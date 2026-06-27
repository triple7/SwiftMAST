import Foundation

public struct MASTSyslog: CustomStringConvertible {
    public let log: MASTError
    public let message: String
    public let timecode: String
    public let date: Date

    public init(log: MASTError, message: String) {
        self.date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.timecode = dateFormatter.string(from: self.date)

        self.log = log
        self.message = message
    }

    public var description: String {
        return "MAST: \(log)-\(message) \(timecode)"
    }
}

// MARK: - Log Subscriber Protocol & Types

/// Callback type for log event subscribers
public typealias LogSubscriberCallback = (MASTSyslog) -> Void

/// Wrapper to hold subscriber with identifier for unsubscription
public class LogSubscriber {
    public let id: String
    public let callback: LogSubscriberCallback

    public init(id: String, callback: @escaping LogSubscriberCallback) {
        self.id = id
        self.callback = callback
    }
}

public class SwiftMAST: NSObject {
    /// Default ceiling for concurrent network requests started by batch enrichment.
    public static let defaultMaxConcurrentRequests = 20

    /** Model holding all MAST archive fits network related processes including Url requests and returned data storage
     properties:
     * targets: dictionary of targets with Json style structuring
     * bufferlength: progressive size of download
     * progress: progress in percentage of download for a target
     * expectedContentLength: size in kbytes of data
     */
    internal var currentTargetId: String?
    public var targets: [String: MASTTable]
    internal var targetAssets: [String: TargetAsset]
    // Storage for FITS metadata keyed by targetName
    public var fitsMetadataStore: [String: [FITSMetadata]]
    private var buffer: Int!
    public var progress: Float?
    private var expectedContentLength: Int?
    public var sysLog: [MASTSyslog]!
    public private(set) var logFileURL: URL?
    private let logFileQueue = DispatchQueue(label: "com.swiftmast.logfile")

    /// Maximum concurrent requests used by file-size and FITS metadata enrichment.
    /// Values below one are treated as one when a batch begins.
    public var maxConcurrentRequests: Int = SwiftMAST.defaultMaxConcurrentRequests

    // MARK: - Log Subscribers
    private var logSubscribers: [LogSubscriber] = []
    private let subscriberQueue = DispatchQueue(
        label: "com.swiftmast.logsubscribers", attributes: .concurrent)

    public override init() {
        self.targets = [String: MASTTable]()
        self.targetAssets = [String: TargetAsset]()
        self.fitsMetadataStore = [String: [FITSMetadata]]()
        self.buffer = 0
        self.sysLog = [MASTSyslog]()
        self.logSubscribers = []
    }

    // MARK: - Log Subscription Management

    /// Subscribe to log events with a callback
    /// - Parameters:
    ///   - id: Unique identifier for the subscriber (used for unsubscription)
    ///   - callback: Function to call when a log event occurs
    /// - Returns: The subscriber ID for later unsubscription
    @discardableResult
    public func subscribeToLogs(id: String, callback: @escaping LogSubscriberCallback) -> String {
        let subscriber = LogSubscriber(id: id, callback: callback)
        subscriberQueue.async(flags: .barrier) {
            self.logSubscribers.append(subscriber)
        }
        return id
    }

    /// Unsubscribe from log events
    /// - Parameter id: The subscriber ID to remove
    public func unsubscribeFromLogs(id: String) {
        subscriberQueue.async(flags: .barrier) {
            self.logSubscribers.removeAll { $0.id == id }
        }
    }

    /// Remove all log subscribers
    public func clearLogSubscribers() {
        subscriberQueue.async(flags: .barrier) {
            self.logSubscribers.removeAll()
        }
    }

    /// Enable appending SwiftMAST log entries to a text file.
    ///
    /// If no URL is supplied, the file is created in the user's documents directory
    /// as `SwiftMAST.log`.
    @discardableResult
    public func enableFileLogging(to url: URL? = nil) -> URL? {
        let resolvedURL: URL?
        if let url {
            resolvedURL = url
        } else {
            resolvedURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("SwiftMAST.log")
        }

        guard let resolvedURL else { return nil }

        logFileQueue.sync {
            let directory = resolvedURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                FileManager.default.createFile(atPath: resolvedURL.path, contents: nil)
            }
            self.logFileURL = resolvedURL
        }

        return resolvedURL
    }

    /// Stop appending log entries to a file. In-memory logs and subscribers remain active.
    public func disableFileLogging() {
        logFileQueue.sync {
            self.logFileURL = nil
        }
    }

    /// Log a message and notify all subscribers
    /// - Parameters:
    ///   - log: The log level/type
    ///   - message: The log message
    public func log(_ log: MASTError, message: String) {
        let entry = MASTSyslog(log: log, message: message)
        sysLog.append(entry)
        appendLogEntryToFile(entry)
        notifySubscribers(entry: entry)
    }

    private func appendLogEntryToFile(_ entry: MASTSyslog) {
        logFileQueue.async {
            guard let logFileURL = self.logFileURL else { return }
            let line = entry.description + "\n"
            guard let data = line.data(using: .utf8) else { return }

            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }

    /// Notify all subscribers of a log entry
    private func notifySubscribers(entry: MASTSyslog) {
        subscriberQueue.sync {
            for subscriber in self.logSubscribers {
                subscriber.callback(entry)
            }
        }
    }

    /** Saves the targetID to retrieve during the download sequence
     */
    public func setTargetId(targetId: String) {
        self.currentTargetId = targetId
    }

    /** Saves the target info for retrieval
     */
    public func setTargetAssets(target: String, targetInfo: NameLookupJson) {
        self.targetAssets[target] = TargetAsset(targetInfo: targetInfo)
    }

    /** Save the preview image for the first PS1 cutout
     */
    public func setPreviewImage(target: String, url: URL) {
        guard self.targetAssets[target] != nil else {
            print("setPreviewImage: No target asset for '\(target)', skipping preview")
            return
        }
        self.targetAssets[target]!.setPreview(url: url)
    }

    /** Append new fits data
     */
    public func appendFitsData(target: String, fitsData: FitsData) {
        if self.targetAssets[target] == nil {
            print("appendFitsData: No target asset for '\(target)', storing metadata only")
        } else {
            self.targetAssets[target]!.setFitsData(fitsData: fitsData)
        }

        // Store structured metadata if available
        if let metadata = fitsData.structuredMetadata {
            self.appendFitsMetadata(target: target, metadata: metadata)
        }
    }

    /** Append FITS metadata to the store
     */
    public func appendFitsMetadata(target: String, metadata: FITSMetadata) {
        if self.fitsMetadataStore[target] == nil {
            self.fitsMetadataStore[target] = []
        }
        self.fitsMetadataStore[target]!.append(metadata)
        print("📊 Stored FITS metadata for \(target): \(metadata.fileIdentifier)")
    }

    /** Get all FITS metadata for a target
     */
    public func getFitsMetadata(target: String) -> [FITSMetadata]? {
        return self.fitsMetadataStore[target]
    }

    /** Get FITS metadata for a specific URL
     - Parameter url: The URL of the downloaded FITS file
     - Returns: The FITSMetadata if found, nil otherwise
     */
    public func getFitsMetadata(forUrl url: URL) -> FITSMetadata? {
        let filename = url.lastPathComponent
        for (_, metadataList) in fitsMetadataStore {
            if let metadata = metadataList.first(where: { $0.fileIdentifier == filename }) {
                return metadata
            }
        }
        return nil
    }

    /** Get FITS metadata for a specific URL within a target
     - Parameters:
       - target: The target name
       - url: The URL of the downloaded FITS file
     - Returns: The FITSMetadata if found, nil otherwise
     */
    public func getFitsMetadata(target: String, forUrl url: URL) -> FITSMetadata? {
        let filename = url.lastPathComponent
        return fitsMetadataStore[target]?.first(where: { $0.fileIdentifier == filename })
    }

    /** Get metadata for multiple URLs, returns a dictionary mapping URL to metadata
     - Parameters:
       - target: The target name
       - urls: Array of URLs to get metadata for
     - Returns: Dictionary mapping each URL to its FITSMetadata (if available)
     */
    public func getFitsMetadata(target: String, forUrls urls: [URL]) -> [URL: FITSMetadata] {
        var result: [URL: FITSMetadata] = [:]
        for url in urls {
            if let metadata = getFitsMetadata(target: target, forUrl: url) {
                result[url] = metadata
            }
        }
        return result
    }

    /** Print all FITS metadata for a target
     */
    public func printFitsMetadata(target: String) {
        guard let metadataList = self.fitsMetadataStore[target] else {
            print("No FITS metadata found for target: \(target)")
            return
        }

        print("\n" + String(repeating: "=", count: 80))
        print("FITS METADATA SUMMARY for \(target)")
        print("Total FITS files: \(metadataList.count)")
        print(String(repeating: "=", count: 80))

        for (index, metadata) in metadataList.enumerated() {
            print("\n[\(index + 1)/\(metadataList.count)]")
            print(metadata.description)
        }
    }

}

extension SwiftMAST: URLSessionDelegate {

    public func getTableByMission(
        target: String, mission: MASTDataSet, _ closure: @escaping (Bool) -> Void
    ) {
        /** Requests a mission related table
          Adds a table into the targets dictionary and adds a response type for further processing
          Params:
          target: identifiable target name
          mission: data set path
          closure: whether request was successful
          */
        let request = MASTRequest(target: target, searchType: .mission)
        let configuration = URLSessionConfiguration.ephemeral
        let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request.getURL(dataSet: mission)) {
            [weak self] data, response, error in
            if error != nil {
                self?.log(.RequestError, message: error!.localizedDescription)
                closure(false)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                self?.log(.RequestError, message: "response timed out")
                closure(false)
                return
            }
            if response.statusCode != 200 {
                let error = NSError(domain: "com.error", code: response.statusCode)
                self?.log(.RequestError, message: error.localizedDescription)
                closure(false)
            }

            let table = self?.parseJson(data: data!)
            self?.targets[mission.id] = table
            self?.log(.OK, message: "ephemerus downloaded")
            closure(true)
            return
        }
        task.resume()
    }

    public func getTableByConeSearch(
        ra: Float, dec: Float, radius: Float, mission: MASTDataSet,
        _ closure: @escaping (Bool) -> Void
    ) {
        /** Requests a cone based search
          Adds a table into the targets dictionary and adds a response type for further processing
          Params:
          ra: right ascent [0:360]
          dec: descent [-90:90]
          radius: cone radius in arc degree
          mission: data set path
          closure: whether request was successful
          */
        let request = MASTRequest(ra: ra, dec: dec, radius: radius, searchType: .mission)
        let configuration = URLSessionConfiguration.ephemeral
        let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request.getURL(dataSet: mission)) {
            [weak self] data, response, error in
            if error != nil {
                self?.log(.RequestError, message: error!.localizedDescription)
                closure(false)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                self?.log(.RequestError, message: "response timed out")
                closure(false)
                return
            }
            if response.statusCode != 200 {
                let error = NSError(domain: "com.error", code: response.statusCode)
                self?.log(.RequestError, message: error.localizedDescription)
                closure(false)
            }

            let text = String(decoding: data!, as: UTF8.self)
            let table = self?.parseCsvTable(text: text)
            self?.targets[mission.id] = table
            self?.log(.OK, message: "ephemerus downloaded")
            closure(true)
            return
        }
        task.resume()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        expectedContentLength = Int(response.expectedContentLength)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer += data.count
        let percentageDownloaded = Float(buffer) / Float(expectedContentLength!)
        progress = percentageDownloaded
        print(percentageDownloaded)
    }

}
