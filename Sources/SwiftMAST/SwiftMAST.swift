import Foundation

public struct MASTSyslog:CustomStringConvertible {
    let log:MASTError
    let message:String
    let timecode:String
    
    init( log: MASTError, message: String) {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy--MM-dd hh:mm:ss"
        self.timecode = dateFormatter.string(from: date)

        self.log = log
                  self.message = message
    }
    
    public var description:String {
        return "MAST: \(log)-\(message) \(timecode)"
    }
}

public class SwiftMAST:NSObject {
    /** Model holding all MAST archive fits network related processes including Url requests and returned data storage
     properties:
     * targets: dictionary of targets with Json style structuring
     * bufferlength: progressive size of download
     * progress: progress in percentage of download for a target
     * expectedContentLength: size in kbytes of data
     */
    internal var currentTargetId:String?
    public var targets:[String: MASTTable]
    private var targetAssets:[String:TargetAsset]
    private var buffer:Int!
    public var progress:Float?
    private var expectedContentLength:Int?
    public var sysLog:[MASTSyslog]!
    
    public override init() {
        self.targets = [String: MASTTable]()
        self.targetAssets = [String:TargetAsset]()
        self.buffer = 0
        self.sysLog = [MASTSyslog]()
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
        self.targetAssets[target]!.setPreview(url: url)
    }
    
    
    /** Append new fits data
     */
    public func appendFitsData(target: String, fitsData: FitsData) {
        self.targetAssets[target]!.setFitsData(fitsData: fitsData)
    }
    
}

 extension SwiftMAST: URLSessionDelegate {

     public func getTableByMission(target: String, mission: MASTDataSet, _ closure: @escaping (Bool)-> Void) {
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
         
         let task = session.dataTask(with: request.getURL(dataSet: mission)) { [weak self] data, response, error in
             if error != nil {
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
                 closure(false)
                 return
             }
             guard let response = response as? HTTPURLResponse else {
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                 closure(false)
                 return
             }
             if response.statusCode != 200 {
                 let error = NSError(domain: "com.error", code: response.statusCode)
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                 closure(false)
             }

             let table = self?.parseJson(data: data!)
             self?.targets[mission.id] = table
             self?.sysLog.append(MASTSyslog(log: .OK, message: "ephemerus downloaded"))
         closure(true)
             return
     }
     task.resume()
     }

     public func getTableByConeSearch(ra: Float, dec: Float, radius: Float, mission: MASTDataSet, _ closure: @escaping (Bool)-> Void) {
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
         
         let task = session.dataTask(with: request.getURL(dataSet: mission)) { [weak self] data, response, error in
             if error != nil {
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
                 closure(false)
                 return
             }
             guard let response = response as? HTTPURLResponse else {
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                 closure(false)
                 return
             }
             if response.statusCode != 200 {
                 let error = NSError(domain: "com.error", code: response.statusCode)
                 self?.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                 closure(false)
             }

             let text = String(decoding: data!, as: UTF8.self)
             let table = self?.parseCsvTable(text: text)
             self?.targets[mission.id] = table
             self?.sysLog.append(MASTSyslog(log: .OK, message: "ephemerus downloaded"))
         closure(true)
             return
     }
     task.resume()
     }

     func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
         expectedContentLength = Int(response.expectedContentLength)
     }
     
     func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
         buffer += data.count
         let percentageDownloaded = Float(buffer) / Float(expectedContentLength!)
            progress =  percentageDownloaded
         print(percentageDownloaded)
     }

}
