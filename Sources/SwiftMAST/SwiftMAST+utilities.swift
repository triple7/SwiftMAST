//
//  File.swift
//
//
//  Created by Yuma decaux on 12/2/2024.
//

import CoreGraphics
import FITS
import FITSKit
import Foundation
import ImageIO
import SwiftQValue
import UniformTypeIdentifiers
import Zip

extension SwiftMAST {

    internal func storageSafePathComponent(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = source.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars).replacingOccurrences(
            of: "__+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_")).isEmpty
            ? fallback
            : collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    internal func productStorageFolder(
        target: String,
        mission: String,
        observationId: String,
        filter: String,
        contentType: ObservationProductContentType
    ) -> URL {

        // Get the Documents directory
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(target, fallback: "unknown-target"), isDirectory: true)

        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(mission, fallback: "unknown-mission"), isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(observationId, fallback: "unknown-observation"),
            isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(
                filter.replacingOccurrences(of: ";", with: "-"),
                fallback: "unknown-filter"),
            isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(contentType.rawValue, isDirectory: true)
        return MASTDirectory
    }

    internal func productStorageFolder(
        target: String,
        product: CoamResult,
        contentType: ObservationProductContentType
    ) -> URL {
        productStorageFolder(
            target: target,
            mission: product.observationMission?.rawValue ?? product.obs_collection,
            observationId: product.obs_id,
            filter: product.filters,
            contentType: contentType
        )
    }

    internal func productFileName(
        target: String,
        product: CoamResult,
        productType: ProductType
    ) -> String {
        let targetName = storageSafePathComponent(target, fallback: "unknown-target")
        let mission = storageSafePathComponent(
            product.observationMission?.rawValue ?? product.obs_collection,
            fallback: "unknown-mission")
        let observationId = storageSafePathComponent(product.obs_id, fallback: "unknown-observation")
        let filter = storageSafePathComponent(
            product.filters.replacingOccurrences(of: ";", with: "-"),
            fallback: "unknown-filter")
        return "\(targetName)_\(mission)_\(observationId)_\(filter).\(productType.id)"
    }

    func unzipResponseData(_ data: Data, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global().async {
            // Get the Documents directory
            guard
                let documentsDirectory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else {
                self.log(.RequestError, message: "Unable to open Documents folder")
                completion([])
                return
            }

            let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)

            do {
                try FileManager.default.createDirectory(
                    at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)

                let temporaryZipFileURL = temporaryDirectory.appendingPathComponent("temp.tar.gz")

                let tempDoc = documentsDirectory.appendingPathComponent("temp.tar.gz")
                try data.write(to: temporaryZipFileURL)
                try data.write(to: tempDoc)
                print("tar temporarily added")
                print("Data size: \(data.count) bytes")

                try FileManager.default.createFilesAndDirectories(
                    path: temporaryDirectory.path, tarPath: temporaryZipFileURL.path)

                //                let unzipDirectory = try Zip.quickUnzipFile(temporaryZipFileURL)
                let unzippedFiles = try FileManager.default.contentsOfDirectory(
                    atPath: temporaryDirectory.path)

                // Clean up: remove the temporary directory and file
                try FileManager.default.removeItem(at: temporaryZipFileURL)
                try FileManager.default.removeItem(at: temporaryDirectory)

                print("unzipResponseData: Unzipped files to: \(documentsDirectory)")
                DispatchQueue.main.async {
                    completion(unzippedFiles.map { Foundation.URL(fileURLWithPath: $0) })
                }
            } catch let error {
                self.log(.RequestError, message: error.localizedDescription)
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    /** Saves MAST returned assets to local directory
     */
    func saveAsset(
        targetName: String, product: CoamResult, urlString: String, data: Data,
        completion: @escaping (FitsData?) -> Void
    ) {
        print("saveAsset: \(urlString)")

        let fitsDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .fit)
        let imageDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .image)

        do {
            try FileManager.default.createDirectory(
                at: fitsDirectory, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(
                at: imageDirectory, withIntermediateDirectories: true, attributes: nil)

            let fileName = productFileName(target: targetName, product: product, productType: .Fits)
            let fileUrl = fitsDirectory.appendingPathComponent(fileName)

            try data.write(to: fileUrl)
            print("saveAsset: FITS file saved to \(fileUrl)")

            let jpegUrl = imageDirectory.appendingPathComponent(
                fileName.replacingOccurrences(of: ".fits", with: ".jpg"))
            let fitsData = convertFitsToJpeg(url: fileUrl, writeToUrl: jpegUrl)

            // Store the FITS metadata
            self.appendFitsData(target: targetName, fitsData: fitsData)

            // If JPEG conversion succeeded, use the JPEG URL; otherwise use the FITS file URL
            let resultUrl = fitsData.url ?? fileUrl
            let resultFitsData = FitsData(
                metadata: fitsData.metadata, url: resultUrl,
                structuredMetadata: fitsData.structuredMetadata)

            if fitsData.url != nil {
                print("saveAsset: JPEG image saved to \(jpegUrl)")
            } else {
                print("saveAsset: JPEG conversion failed, returning FITS URL instead")
            }

            DispatchQueue.main.async {
                completion(resultFitsData)
            }
        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    /** Saves jpg/png only
     no fits data
     */
    func saveImageFile(
        target: String, collection: String, filter: String, observationId: String? = nil,
        productType: ProductType = .Jpeg, url: URL? = nil, data: Data? = nil
    ) -> URL? {
        print("saveImageFile: \(target)_\(collection)_\(filter).\(productType.id)")

        let MASTDirectory = productStorageFolder(
            target: target,
            mission: collection,
            observationId: observationId ?? "unknown-observation",
            filter: filter,
            contentType: .image
        )

        let safeTarget = storageSafePathComponent(target, fallback: "unknown-target")
        let safeCollection = storageSafePathComponent(collection, fallback: "unknown-mission")
        let safeObservationId = storageSafePathComponent(
            observationId ?? "unknown-observation",
            fallback: "unknown-observation")
        let safeFilter = storageSafePathComponent(
            filter.replacingOccurrences(of: ";", with: "-"),
            fallback: "unknown-filter")
        let fileExtension =
            "\(safeTarget)_\(safeCollection)_\(safeObservationId)_\(safeFilter).\(productType.id)"
        let imageUrl = MASTDirectory.appendingPathComponent(fileExtension)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

            if let url = url {
                let data = try Data(contentsOf: url)
                try data.write(to: imageUrl)
            } else if let data = data {
                try data.write(to: imageUrl)
            } else {
                assertionFailure("No url or data specified.")
            }
            // Set the preview image if it's not set

            return imageUrl

        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            return nil
        }
    }

    func saveTempUrlToFile(
        targetName: String, product: CoamResult, tempUrl: URL, productType: ProductType,
        completion: @escaping (URL?) -> Void
    ) {
        print("saveTempUrlToFile: \(targetName)")

        let contentType: ObservationProductContentType = productType == .Fits ? .fit : .image
        let MASTDirectory = productStorageFolder(
            target: targetName, product: product, contentType: contentType)
        let imageDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .image)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)
            if productType == .Fits {
                try FileManager.default.createDirectory(
                    at: imageDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            let fileExtension = productFileName(
                target: targetName, product: product, productType: productType)
            let saveUrl = MASTDirectory.appendingPathComponent(fileExtension)

            // Remove existing file if it exists to avoid "item already exists" error
            if FileManager.default.fileExists(atPath: saveUrl.path) {
                try FileManager.default.removeItem(at: saveUrl)
            }

            try FileManager.default.moveItem(at: tempUrl, to: saveUrl)

            // Add the fits or jpeg data to the target
            if productType == .Fits {
                print("saveTempUrlToFile: FITS file saved to \(saveUrl)")

                // Convert FITS to JPEG for viewing
                let jpegUrl = imageDirectory.appendingPathComponent(
                    fileExtension.replacingOccurrences(of: ".fits", with: ".jpg"))
                let fitsData = convertFitsToJpeg(url: saveUrl, writeToUrl: jpegUrl)

                // Store the FITS metadata
                self.appendFitsData(target: targetName, fitsData: fitsData)

                // Return the JPEG URL if conversion succeeded, otherwise return the FITS file URL
                let resultUrl = fitsData.url ?? saveUrl

                if fitsData.url != nil {
                    print("saveTempUrlToFile: JPEG image saved to \(jpegUrl)")
                } else {
                    print("saveTempUrlToFile: JPEG conversion failed, returning FITS URL instead")
                }

                DispatchQueue.main.async {
                    completion(resultUrl)
                }
            } else {
                DispatchQueue.main.async {
                    completion(saveUrl)
                }
            }
        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    func saveCGImageToUrl(image: CGImage, toURL: URL, dim: Int = 1) -> URL {
        // Create an image destination using the provided URL

        let destination = CGImageDestinationCreateWithURL(
            toURL as CFURL, UTType.jpeg.identifier as CFString, dim, nil)!
        CGImageDestinationAddImage(destination, image, nil)

        CGImageDestinationFinalize(destination)
        return toURL
    }

    private func getFitsMetaData(fits: FitsFile) -> [String: QValue] {
        print("getFitsMetaData: HDU count \(fits.HDUs.count)")
        for hdu in fits.HDUs {
            print("HDU: \n \(hdu.description)")
        }

        // get the metadata from the hdu primary header unit
        var metadata = [String: QValue]()
        for hdu in fits.HDUs {
            for unit in hdu.headerUnit {
                metadata[unit.keyword.rawValue] = QValue(
                    value: (unit.value != nil) ? unit.value!.toString : "")
            }
        }
        return metadata
    }

    private func convertFitsToJpeg(url: URL, writeToUrl: URL) -> FitsData {

        guard let fits = readFITSFileSafely(at: url, context: "convertFitsToJpeg") else {
            return FitsData(metadata: [:], url: nil)
        }
        let metadata = getFitsMetaData(fits: fits)
        let structuredMetadata = FITSMetadata(
            fileIdentifier: url.lastPathComponent, metadata: metadata)

        // Check if this FITS file contains actual image data
        // NAXIS > 0 with NAXIS1 and NAXIS2 indicates image data in the primary HDU
        // XTENSION = 'IMAGE' indicates an image extension

        // Helper function to get string value from QValue safely
        func getStringValue(_ qvalue: QValue?) -> String {
            guard let qv = qvalue else { return "" }
            return String(describing: qv.value)
        }

        // First check if primary HDU has image data
        let naxis = getStringValue(metadata["NAXIS"])
        let naxisValue = Int(naxis) ?? 0
        let naxis1 = getStringValue(metadata["NAXIS1"])
        let naxis1Value = Int(naxis1) ?? 0
        let naxis2 = getStringValue(metadata["NAXIS2"])
        let naxis2Value = Int(naxis2) ?? 0

        // Also check if the primary HDU has actual data (not just headers)
        // If primary HDU data size is 0, it's likely metadata-only with tables in extensions
        let primeHasData = fits.prime.dataUnit?.count ?? 0 > 0
        let primaryHasImageData =
            naxisValue >= 2 && naxis1Value > 0 && naxis2Value > 0 && primeHasData

        print(
            "convertFitsToJpeg: Primary HDU - NAXIS=\(naxisValue), NAXIS1=\(naxis1Value), NAXIS2=\(naxis2Value), primeHasData=\(primeHasData)"
        )

        // Try to decode from primary HDU first if it has image data
        if primaryHasImageData {
            do {
                if naxisValue == 3 {
                    let image = try fits.prime.decode(GrayscaleDecoder.self, ())
                    return FitsData(
                        metadata: metadata, url: saveCGImageToUrl(image: image, toURL: writeToUrl),
                        structuredMetadata: structuredMetadata)
                } else {
                    let image = try fits.prime.decode(RGB_Decoder<RGB>.self, ())
                    return FitsData(
                        metadata: metadata, url: saveCGImageToUrl(image: image, toURL: writeToUrl),
                        structuredMetadata: structuredMetadata)
                }
            } catch {
                print("convertFitsToJpeg: Failed to decode primary HDU image: \(error)")
            }
        }

        // If primary HDU has no image data or decoding failed, try extension HDUs
        // Look for ImageHDU extensions which contain actual image data
        print("convertFitsToJpeg: Checking \(fits.HDUs.count) extension HDUs for image data")

        for (index, hdu) in fits.HDUs.enumerated() {
            // Check if this is an ImageHDU (not a table)
            if let imageHDU = hdu as? ImageHDU {
                let extNaxis = imageHDU.naxis ?? 0
                let extNaxis1 = imageHDU.naxis(1) ?? 0
                let extNaxis2 = imageHDU.naxis(2) ?? 0
                let extHasData = imageHDU.dataUnit?.count ?? 0 > 0

                print(
                    "convertFitsToJpeg: Extension[\(index)] ImageHDU - NAXIS=\(extNaxis), NAXIS1=\(extNaxis1), NAXIS2=\(extNaxis2), hasData=\(extHasData)"
                )

                if extNaxis >= 2 && extNaxis1 > 0 && extNaxis2 > 0 && extHasData {
                    do {
                        // Try to decode using GrayscaleDecoder for 2D data, RGB for 3D
                        let image: CGImage
                        if extNaxis == 3 {
                            image = try imageHDU.decode(RGB_Decoder<RGB>.self, ())
                        } else {
                            image = try imageHDU.decode(GrayscaleDecoder.self, ())
                        }
                        print("convertFitsToJpeg: Successfully decoded Extension[\(index)]")
                        return FitsData(
                            metadata: metadata,
                            url: saveCGImageToUrl(image: image, toURL: writeToUrl),
                            structuredMetadata: structuredMetadata)
                    } catch {
                        print("convertFitsToJpeg: Failed to decode Extension[\(index)]: \(error)")
                        // Continue to try next extension
                    }
                }
            }
        }

        // No renderable image data found in any HDU
        print("convertFitsToJpeg: No renderable image data found in primary or extension HDUs")
        return FitsData(metadata: metadata, url: nil, structuredMetadata: structuredMetadata)
    }

    // Mark: Debug helper
    internal func printUniqueSets(table: MASTTable) {
        let fieldss: [Coam] = [
            .dataproduct_type, .filters, .instrument_name, .obs_collection, .wavelength_region,
        ]
        for field in fieldss {
            let uniqueFields = table.getUniqueString(for: field.id)
            print("\(field.id) has \(uniqueFields.count)")
            for u in uniqueFields {
                print(u)
            }
        }

    }

    internal func printUrls(table: MASTTable) {
        let results = table.getCoamResults()
        for c in results {
            print(c.instrument_name)
            print(c.dataURL)
            print(c.jpegURL)
        }
    }

    /** Mark: optimise what products get downloaded
     Using combined frequency ranges
     FILTER_BANDS models a range of frequencies
     per filter band
    */
    internal func pruneProductsByFilterBand(results: [CoamResult]) {
        var firstFilter = [String: [CoamResult]]()
        for product in results {
            for key in FILTER_BANDS.keys {
                let band = FILTER_BANDS[key]!
                if band.contains(product.filters) {
                    if firstFilter[key] == nil {
                        firstFilter[key] = [product]
                    } else {
                        firstFilter[key]!.append(product)
                    }
                }
            }
        }

        // Get unique filter and obs_collection combinations
        for key in firstFilter.keys {
            print("Band \(key) has \(firstFilter[key]!.count)")
        }
    }

    // MARK: - FITS HDU Extraction for ScienceProduct

    /// Convert a raw FITS HeaderUnit into an array of structured ``FITSHeaderUnit`` entries.
    ///
    /// Each ``HeaderBlock`` in the HDU is converted to a ``FITSHeaderUnit`` with:
    /// - The keyword name
    /// - A typed ``FITSHeaderValue`` (parsed from the raw string)
    /// - The FITS comment field
    ///
    /// - Parameter headerUnit: The raw `HeaderUnit` from fitscore
    /// - Returns: Array of structured header units
    internal func extractHeaderUnits(_ headerUnit: HeaderUnit) -> [FITSHeaderUnit] {
        var units = [FITSHeaderUnit]()
        for block in headerUnit {
            let keyword = block.keyword.rawValue
            let rawString = block.value?.toString ?? ""
            let value = Self.parseFITSValue(rawString)
            let comment = block.comment ?? ""
            units.append(
                FITSHeaderUnit(
                    keyword: keyword, value: value, comment: comment
                ))
        }
        return units
    }

    /// Merge primary HDU headers with extension HDU headers.
    /// Extension headers override primary headers when keywords conflict.
    /// Keywords that appear multiple times (COMMENT, HISTORY) are kept from both.
    ///
    /// - Parameters:
    ///   - primary: Headers from the primary HDU
    ///   - hdu: Headers from an extension HDU
    /// - Returns: Merged array of header units
    internal func mergeHeaderUnits(
        primary: [FITSHeaderUnit], hdu: [FITSHeaderUnit]
    ) -> [FITSHeaderUnit] {
        let multiKeys: Set<String> = ["COMMENT", "HISTORY", ""]
        var merged = [String: FITSHeaderUnit]()
        var orderedKeys = [String]()
        var multiEntries = [FITSHeaderUnit]()

        // Add primary headers as base
        for unit in primary {
            if multiKeys.contains(unit.keyword) {
                multiEntries.append(unit)
            } else if merged[unit.keyword] == nil {
                merged[unit.keyword] = unit
                orderedKeys.append(unit.keyword)
            }
        }

        // Override with extension HDU headers
        for unit in hdu {
            if multiKeys.contains(unit.keyword) {
                multiEntries.append(unit)
            } else {
                if merged[unit.keyword] == nil {
                    orderedKeys.append(unit.keyword)
                }
                merged[unit.keyword] = unit
            }
        }

        var result = orderedKeys.compactMap { merged[$0] }
        result.append(contentsOf: multiEntries)
        return result
    }

    /// Parse a raw FITS value string into a typed ``FITSHeaderValue``.
    internal static func parseFITSValue(_ raw: String) -> FITSHeaderValue {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Boolean: FITS uses T and F
        if trimmed == "T" || trimmed == "true" { return .bool(true) }
        if trimmed == "F" || trimmed == "false" { return .bool(false) }

        // Integer
        if let intVal = Int(trimmed) {
            return .integer(intVal)
        }

        // Double (floating-point, including scientific notation)
        if let dblVal = Double(trimmed) {
            return .double(dblVal)
        }

        // String value (strip FITS quoting)
        let unquoted =
            trimmed
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        return .string(unquoted.isEmpty ? trimmed : unquoted)
    }

    /// Look up a header value by keyword from an array of header units.
    private func headerValue(_ keyword: String, in headers: [FITSHeaderUnit]) -> FITSHeaderValue? {
        headers.first { $0.keyword == keyword }?.value
    }

    /// Convenience: get an integer value from headers, returning 0 if missing or non-integer.
    private func headerInt(_ keyword: String, in headers: [FITSHeaderUnit]) -> Int {
        headerValue(keyword, in: headers)?.intValue ?? 0
    }

    /// Convenience: get a floating-point value from headers.
    private func headerDouble(_ keyword: String, in headers: [FITSHeaderUnit]) -> Double? {
        headerValue(keyword, in: headers)?.doubleValue
    }

    /// Determine whether an HDU contains renderable image data based on its headers and data size.
    private func hduContainsImage(headers: [FITSHeaderUnit], dataSize: Int) -> Bool {
        let naxis = headerInt("NAXIS", in: headers)
        let naxis1 = headerInt("NAXIS1", in: headers)
        let naxis2 = headerInt("NAXIS2", in: headers)
        return naxis >= 2 && naxis1 > 0 && naxis2 > 0 && dataSize > 0
    }

    /// Fetch and parse remote FITS headers using HTTP byte-range requests.
    ///
    /// This avoids downloading large FITS payloads. The parser reads FITS 80-byte
    /// header cards and computes HDU data offsets from structural keywords, so it
    /// can return image dimensions and WCS metadata even when image bytes are absent.
    public func fetchFITSHeaderSummary(
        from productURL: String,
        initialByteCount: Int = 262_144,
        maxByteCount: Int = 2_097_152,
        session: URLSession = .shared,
        completion: @escaping (FITSHeaderSummary?) -> Void
    ) {
        guard let url = fitsHeaderDownloadURL(for: productURL) else {
            completion(nil)
            return
        }

        fetchFITSHeaderSummary(
            from: url,
            initialByteCount: initialByteCount,
            maxByteCount: maxByteCount,
            session: session,
            completion: completion
        )
    }

    /// Fetch only enough remote FITS bytes to identify the preferred image HDU and
    /// return its key image metadata.
    ///
    /// The request uses HTTP byte ranges and skips image payloads by computing HDU
    /// data sizes from FITS structural keywords. The returned metadata describes
    /// the primary image if the primary HDU contains image data, otherwise the
    /// preferred science image extension when available.
    public func fetchPreferredFITSImageHeaderMetadata(
        from productURL: String,
        initialByteCount: Int = 2_880,
        maxByteCount: Int = 262_144,
        fetchMode: FITSImageMetadataFetchMode = .stream,
        session: URLSession = .shared,
        completion: @escaping (FITSImageHeaderMetadata?) -> Void
    ) {
        guard let url = fitsHeaderDownloadURL(for: productURL) else {
            completion(nil)
            return
        }

        fetchPreferredFITSImageHeaderMetadata(
            from: url,
            initialByteCount: initialByteCount,
            maxByteCount: maxByteCount,
            fetchMode: fetchMode,
            session: session
        ) { metadata in
            completion(metadata)
        }
    }

    /// Fetch only enough remote FITS bytes to identify the preferred image HDU and
    /// return its key image metadata.
    public func fetchPreferredFITSImageHeaderMetadata(
        from url: URL,
        initialByteCount: Int = 2_880,
        maxByteCount: Int = 262_144,
        fetchMode: FITSImageMetadataFetchMode = .stream,
        session: URLSession = .shared,
        completion: @escaping (FITSImageHeaderMetadata?) -> Void
    ) {
        if fetchMode == .stream {
            streamPreferredFITSImageHeaderMetadata(
                from: url,
                maxByteCount: maxByteCount,
                completion: completion
            )
            return
        }

        fetchFITSHeaderSummary(
            from: url,
            initialByteCount: initialByteCount,
            maxByteCount: maxByteCount,
            session: session,
            stopAfterFirstImageHDU: true
        ) { summary in
            completion(summary?.preferredImageMetadata)
        }
    }

    /// Fetch key image metadata from a ``CoamResult`` data URL without downloading
    /// the FITS image payload.
    public func fetchPreferredFITSImageHeaderMetadata(
        for coamResult: CoamResult,
        initialByteCount: Int = 2_880,
        maxByteCount: Int = 262_144,
        fetchMode: FITSImageMetadataFetchMode = .stream,
        session: URLSession = .shared,
        completion: @escaping (FITSImageHeaderMetadata?) -> Void
    ) {
        guard !coamResult.dataURL.isEmpty else {
            completion(nil)
            return
        }

        fetchPreferredFITSImageHeaderMetadata(
            from: coamResult.dataURL,
            initialByteCount: initialByteCount,
            maxByteCount: maxByteCount,
            fetchMode: fetchMode,
            session: session,
            completion: completion
        )
    }

    internal func streamPreferredFITSImageHeaderMetadata(
        from url: URL,
        maxByteCount: Int = 262_144,
        configuration: URLSessionConfiguration = .ephemeral,
        completion: @escaping (FITSImageHeaderMetadata?) -> Void
    ) {
        let fetcher = FITSImageHeaderMetadataStreamFetcher(
            url: url,
            maxByteCount: max(maxByteCount, 2_880),
            configuration: configuration
        ) { data, remoteFileSize in
            self.parseFITSHeaderSummary(
                data: data,
                sourceURL: url,
                remoteFileSizeBytes: remoteFileSize
            )?.preferredImageMetadata
        } completion: { metadata in
            completion(metadata)
        }
        fetcher.start()
    }

    internal func enrichCoamResultsWithFITSImageMetadata(
        _ results: [CoamResult],
        fetchMode: FITSImageMetadataFetchMode = .stream,
        session: URLSession = .shared,
        maxConcurrentRequests: Int? = nil,
        completion: @escaping ([CoamResult]) -> Void
    ) {
        guard !results.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var enriched = results
        let candidates = results.enumerated().filter {
            shouldFetchFITSImageMetadata(for: $0.element.dataURL)
        }
        var nextIndex = 0

        guard !candidates.isEmpty else {
            completion(results)
            return
        }

        func nextCandidate() -> (offset: Int, element: CoamResult)? {
            lock.lock()
            defer { lock.unlock() }
            guard nextIndex < candidates.count else { return nil }
            let candidate = candidates[nextIndex]
            nextIndex += 1
            return candidate
        }

        func startWorker() {
            group.enter()
            func fetchNext() {
                guard let (index, coam) = nextCandidate() else {
                    group.leave()
                    return
                }
                fetchPreferredFITSImageHeaderMetadata(
                    for: coam,
                    fetchMode: fetchMode,
                    session: session
                ) { metadata in
                    if let metadata {
                        lock.lock()
                        enriched[index] = coam.withFITSImageHeaderMetadata(metadata)
                        lock.unlock()
                    }
                    fetchNext()
                }
            }
            fetchNext()
        }

        let requestLimit = max(maxConcurrentRequests ?? self.maxConcurrentRequests, 1)
        let workerCount = min(requestLimit, candidates.count)
        for _ in 0..<workerCount {
            startWorker()
        }

        group.notify(queue: .main) {
            completion(enriched)
        }
    }

    private func shouldFetchFITSImageMetadata(for dataURL: String) -> Bool {
        let lowercased = dataURL.lowercased()
        guard !lowercased.isEmpty else { return false }
        if lowercased.hasPrefix("mast:") { return true }
        return lowercased.contains(".fits") || lowercased.contains(".fit")
    }

    /// Fetch and parse remote FITS headers using HTTP byte-range requests.
    public func fetchFITSHeaderSummary(
        from url: URL,
        initialByteCount: Int = 262_144,
        maxByteCount: Int = 2_097_152,
        session: URLSession = .shared,
        completion: @escaping (FITSHeaderSummary?) -> Void
    ) {
        fetchFITSHeaderSummary(
            from: url,
            initialByteCount: initialByteCount,
            maxByteCount: maxByteCount,
            session: session,
            stopAfterFirstImageHDU: false,
            completion: completion
        )
    }

    private func fetchFITSHeaderSummary(
        from url: URL,
        initialByteCount: Int,
        maxByteCount: Int,
        session: URLSession,
        stopAfterFirstImageHDU: Bool,
        completion: @escaping (FITSHeaderSummary?) -> Void
    ) {
        let initial = max(initialByteCount, 2_880)
        let maximum = max(maxByteCount, initial)
        let maxHeaderCount = 64
        var bytesFetched = 0
        var remoteFileSize: Int64?
        var primaryHeaders = [FITSHeaderUnit]()
        var imageHDUs = [FITSHeaderHDUSummary]()
        var parsedHeaderCount = 0

        func finish(reachedEnd: Bool) {
            guard !primaryHeaders.isEmpty else {
                completion(nil)
                return
            }

            completion(
                FITSHeaderSummary(
                    sourceURL: url,
                    bytesFetched: bytesFetched,
                    remoteFileSizeBytes: remoteFileSize,
                    primaryHeaders: primaryHeaders,
                    imageHDUs: imageHDUs,
                    parsedHeaderCount: parsedHeaderCount,
                    reachedEndOfAvailableHeaders: reachedEnd
                ))
        }

        func fetchHeader(at headerOffset: Int, hduIndex: Int, byteCount: Int) {
            var request = URLRequest(url: url)
            let rangeEnd = headerOffset + byteCount - 1
            request.setValue("bytes=\(headerOffset)-\(rangeEnd)", forHTTPHeaderField: "Range")
            request.timeoutInterval = 30

            session.dataTask(with: request) { data, response, error in
                guard
                    error == nil,
                    let data,
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode)
                else {
                    completion(nil)
                    return
                }

                bytesFetched += data.count
                remoteFileSize = remoteFileSize ?? self.remoteFileSize(from: httpResponse)

                guard let header = self.parseFITSHeaderBlock(data: data, offset: 0, hduIndex: hduIndex)
                else {
                    let nextByteCount = min(byteCount * 2, maximum)
                    if nextByteCount > byteCount {
                        fetchHeader(at: headerOffset, hduIndex: hduIndex, byteCount: nextByteCount)
                    } else {
                        finish(reachedEnd: false)
                    }
                    return
                }

                parsedHeaderCount += 1
                if hduIndex == 0 {
                    primaryHeaders = header.units
                }

                let dataOffset = headerOffset + self.paddedOffset(header.endOffset, blockLength: 2_880)
                let dataSize = self.fitsDataSize(from: header.rawValues)
                guard dataSize >= 0, let nextDataOffset = self.safeAdd(dataOffset, dataSize) else {
                    completion(nil)
                    return
                }

                let axisCount = self.headerUnitInt("NAXIS", in: header.units)
                let width = self.headerUnitInt("NAXIS1", in: header.units)
                let height = self.headerUnitInt("NAXIS2", in: header.units)
                let bitpix = self.headerUnitInt("BITPIX", in: header.units)
                let isImageHDU = axisCount >= 2 && width > 0 && height > 0 && dataSize > 0

                if isImageHDU {
                    let mergedHeaders =
                        hduIndex == 0
                        ? header.units
                        : self.mergeHeaderUnits(primary: primaryHeaders, hdu: header.units)
                    let extName = self.headerUnitString("EXTNAME", in: header.units)
                    imageHDUs.append(
                        FITSHeaderHDUSummary(
                            extIndex: hduIndex,
                            extName: extName,
                            role: FITSHDURoleClassifier.classify(headers: mergedHeaders),
                            width: width,
                            height: height,
                            axisCount: axisCount,
                            bitpix: bitpix,
                            dataSizeBytes: dataSize,
                            headerOffset: headerOffset,
                            dataOffset: dataOffset,
                            headers: mergedHeaders,
                            wcs: FITSWCS(headers: mergedHeaders)
                        ))
                }

                if stopAfterFirstImageHDU, !imageHDUs.isEmpty {
                    finish(reachedEnd: false)
                    return
                }

                let nextHeaderOffset = self.paddedOffset(nextDataOffset, blockLength: 2_880)
                if parsedHeaderCount >= maxHeaderCount {
                    finish(reachedEnd: false)
                    return
                }
                if let remoteFileSize, Int64(nextHeaderOffset) >= remoteFileSize {
                    finish(reachedEnd: true)
                    return
                }
                guard nextHeaderOffset > headerOffset else {
                    finish(reachedEnd: false)
                    return
                }

                fetchHeader(at: nextHeaderOffset, hduIndex: hduIndex + 1, byteCount: initial)
            }.resume()
        }

        fetchHeader(at: 0, hduIndex: 0, byteCount: initial)
    }

    internal func parseFITSHeaderSummary(
        data: Data,
        sourceURL: URL,
        remoteFileSizeBytes: Int64? = nil
    ) -> FITSHeaderSummary? {
        let blockLength = 2_880
        guard data.count >= blockLength else { return nil }

        var offset = 0
        var hduIndex = 0
        var primaryHeaders = [FITSHeaderUnit]()
        var imageHDUs = [FITSHeaderHDUSummary]()
        var parsedHeaderCount = 0
        var reachedEndOfAvailableHeaders = true

        while offset < data.count {
            guard let header = parseFITSHeaderBlock(data: data, offset: offset, hduIndex: hduIndex)
            else {
                reachedEndOfAvailableHeaders = false
                break
            }

            parsedHeaderCount += 1
            if hduIndex == 0 {
                primaryHeaders = header.units
            }

            let dataOffset = paddedOffset(header.endOffset, blockLength: blockLength)
            let dataSize = fitsDataSize(from: header.rawValues)
            guard dataSize >= 0 else { return nil }

            let axisCount = headerUnitInt("NAXIS", in: header.units)
            let width = headerUnitInt("NAXIS1", in: header.units)
            let height = headerUnitInt("NAXIS2", in: header.units)
            let bitpix = headerUnitInt("BITPIX", in: header.units)
            let isImageHDU = axisCount >= 2 && width > 0 && height > 0 && dataSize > 0

            if isImageHDU {
                let mergedHeaders =
                    hduIndex == 0
                    ? header.units
                    : mergeHeaderUnits(primary: primaryHeaders, hdu: header.units)
                let extName = headerUnitString("EXTNAME", in: header.units)
                imageHDUs.append(
                    FITSHeaderHDUSummary(
                        extIndex: hduIndex,
                        extName: extName,
                        role: FITSHDURoleClassifier.classify(headers: mergedHeaders),
                        width: width,
                        height: height,
                        axisCount: axisCount,
                        bitpix: bitpix,
                        dataSizeBytes: dataSize,
                        headerOffset: offset,
                        dataOffset: dataOffset,
                        headers: mergedHeaders,
                        wcs: FITSWCS(headers: mergedHeaders)
                    ))
            }

            guard let nextOffset = safeAdd(dataOffset, dataSize) else { return nil }
            let paddedNextOffset = paddedOffset(nextOffset, blockLength: blockLength)
            if paddedNextOffset >= data.count {
                reachedEndOfAvailableHeaders = paddedNextOffset == data.count
                break
            }

            offset = paddedNextOffset
            hduIndex += 1
        }

        guard !primaryHeaders.isEmpty else { return nil }
        return FITSHeaderSummary(
            sourceURL: sourceURL,
            bytesFetched: data.count,
            remoteFileSizeBytes: remoteFileSizeBytes,
            primaryHeaders: primaryHeaders,
            imageHDUs: imageHDUs,
            parsedHeaderCount: parsedHeaderCount,
            reachedEndOfAvailableHeaders: reachedEndOfAvailableHeaders
        )
    }

    private func parseFITSHeaderBlock(
        data: Data,
        offset startOffset: Int,
        hduIndex: Int
    ) -> (units: [FITSHeaderUnit], rawValues: [String: String], endOffset: Int)? {
        let cardLength = 80
        var offset = startOffset
        var cardIndex = 0
        var units = [FITSHeaderUnit]()
        var rawValues = [String: String]()

        while offset + cardLength <= data.count {
            guard
                let card = String(data: data[offset..<offset + cardLength], encoding: .ascii)
            else {
                return nil
            }

            let keyword = card.prefix(8).trimmingCharacters(in: .whitespaces)
            if cardIndex == 0 {
                if hduIndex == 0 {
                    guard keyword == "SIMPLE" else { return nil }
                } else {
                    guard keyword == "XTENSION" else { return nil }
                }
            }

            if keyword == "END" {
                return (units, rawValues, offset + cardLength)
            }

            if !keyword.isEmpty, let parsed = parseFITSHeaderCard(card) {
                units.append(
                    FITSHeaderUnit(
                        keyword: keyword,
                        value: Self.parseFITSValue(parsed.value),
                        comment: parsed.comment
                    ))
                rawValues[keyword] = parsed.value
            }

            offset += cardLength
            cardIndex += 1
        }

        return nil
    }

    private func parseFITSHeaderCard(_ card: String) -> (value: String, comment: String)? {
        guard let equals = card.firstIndex(of: "=") else { return nil }

        let valueAndComment = card[card.index(after: equals)...]
        var inString = false
        var commentIndex: String.Index?
        var index = valueAndComment.startIndex

        while index < valueAndComment.endIndex {
            let character = valueAndComment[index]
            if character == "'" {
                inString.toggle()
            } else if character == "/", !inString {
                commentIndex = index
                break
            }
            index = valueAndComment.index(after: index)
        }

        let valuePart: Substring
        let commentPart: Substring
        if let commentIndex {
            valuePart = valueAndComment[..<commentIndex]
            commentPart = valueAndComment[valueAndComment.index(after: commentIndex)...]
        } else {
            valuePart = valueAndComment[...]
            commentPart = ""
        }

        return (
            value: String(valuePart).trimmingCharacters(in: .whitespacesAndNewlines),
            comment: String(commentPart).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func fitsHeaderDownloadURL(for productURL: String) -> URL? {
        if productURL.lowercased().hasPrefix("http") {
            let unescaped = productURL.replacingOccurrences(of: "&amp;", with: "&")
            let secureURL = unescaped.replacingOccurrences(of: "http://", with: "https://")
            return URL(string: secureURL)
        }

        return MASTRequest(searchType: .image).getFileDownloadUrl(
            service: .Download_file,
            parameters: ["uri": productURL]
        )
    }

    private func remoteFileSize(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
            let total = contentRange.split(separator: "/").last,
            let size = Int64(total)
        {
            return size
        }
        if let contentLength = response.value(forHTTPHeaderField: "Content-Length") {
            return Int64(contentLength)
        }
        let expected = response.expectedContentLength
        return expected > 0 ? expected : nil
    }

    private func headerUnitInt(_ keyword: String, in headers: [FITSHeaderUnit]) -> Int {
        headers.first { $0.keyword == keyword }?.value.intValue ?? 0
    }

    private func headerUnitString(_ keyword: String, in headers: [FITSHeaderUnit]) -> String? {
        headers.first { $0.keyword == keyword }?.value.rawString
    }

    private func readFITSFileSafely(at url: URL, context: String) -> FitsFile? {
        guard let data = try? Data(contentsOf: url) else {
            log(.RequestError, message: "\(context): Unable to read \(url.lastPathComponent)")
            return nil
        }

        guard validateFITSBuffer(data) else {
            log(
                .RequestError,
                message: "\(context): \(url.lastPathComponent) is not a complete uncompressed FITS file"
            )
            return nil
        }

        guard let fits = FitsFile.read(data) else {
            log(.RequestError, message: "\(context): FITSCore could not parse \(url.lastPathComponent)")
            return nil
        }

        return fits
    }

    private func validateFITSBuffer(_ data: Data) -> Bool {
        let cardLength = 80
        let blockLength = 2880
        guard data.count >= blockLength else { return false }

        return data.withUnsafeBytes { rawBuffer in
            guard rawBuffer.count >= cardLength else { return false }

            var offset = 0
            var hduIndex = 0
            while offset < rawBuffer.count {
                var headers: [String: String] = [:]
                var cardIndex = 0
                var foundEnd = false

                while offset < rawBuffer.count {
                    guard offset + cardLength <= rawBuffer.count else { return false }
                    guard
                        let card = String(
                            bytes: rawBuffer[offset..<offset + cardLength],
                            encoding: .ascii
                        )
                    else {
                        return false
                    }

                    let keyword = card.prefix(8).trimmingCharacters(in: .whitespaces)
                    if cardIndex == 0 {
                        if hduIndex == 0 {
                            guard keyword == "SIMPLE" else { return false }
                        } else {
                            guard keyword == "XTENSION" else { return false }
                        }
                    }

                    if keyword == "END" {
                        offset += cardLength
                        foundEnd = true
                        break
                    }

                    if let equals = card.firstIndex(of: "=") {
                        let rawValue = card[card.index(after: equals)...]
                            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                            .first
                            .map(String.init)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        headers[keyword] = rawValue
                    }

                    offset += cardLength
                    cardIndex += 1
                }

                guard foundEnd else { return false }
                offset = paddedOffset(offset, blockLength: blockLength)
                guard offset <= rawBuffer.count else { return false }

                let dataSize = fitsDataSize(from: headers)
                guard dataSize >= 0 else { return false }
                guard offset + dataSize <= rawBuffer.count else { return false }

                let nextOffset = paddedOffset(offset + dataSize, blockLength: blockLength)
                if nextOffset >= rawBuffer.count { return true }
                offset = nextOffset
                hduIndex += 1
            }

            return true
        }
    }

    private func fitsDataSize(from headers: [String: String]) -> Int {
        let axis = fitsHeaderInt("NAXIS", in: headers) ?? 0
        let bitpix = fitsHeaderInt("BITPIX", in: headers) ?? 0
        let bytesPerPixel: Int
        switch bitpix {
        case 8: bytesPerPixel = 1
        case 16: bytesPerPixel = 2
        case 32, -32: bytesPerPixel = 4
        case 64, -64: bytesPerPixel = 8
        default: return -1
        }
        let pcount = fitsHeaderInt("PCOUNT", in: headers) ?? 0
        let gcount = fitsHeaderInt("GCOUNT", in: headers) ?? 1
        let groups = fitsHeaderBool("GROUPS", in: headers) ?? false

        guard axis >= 0, pcount >= 0, gcount >= 0 else {
            return -1
        }

        var elementCount = 0
        if axis > 0 {
            elementCount = 1
            let startAxis = groups ? 2 : 1
            if startAxis <= axis {
                for index in startAxis...axis {
                    guard let dimension = fitsHeaderInt("NAXIS\(index)", in: headers),
                          dimension >= 0
                    else {
                        return -1
                    }
                    guard let nextElementCount = safeMultiply(elementCount, dimension) else {
                        return -1
                    }
                    elementCount = nextElementCount
                }
            }
        }

        guard
            let payloadElements = safeAdd(elementCount, pcount),
            let groupedElements = safeMultiply(payloadElements, gcount),
            let byteCount = safeMultiply(groupedElements, bytesPerPixel)
        else {
            return -1
        }

        return byteCount
    }

    private func fitsHeaderInt(_ keyword: String, in headers: [String: String]) -> Int? {
        guard let raw = headers[keyword] else { return nil }
        return Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "' ")))
    }

    private func fitsHeaderBool(_ keyword: String, in headers: [String: String]) -> Bool? {
        guard let raw = headers[keyword]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        if raw == "T" { return true }
        if raw == "F" { return false }
        return nil
    }

    private func paddedOffset(_ offset: Int, blockLength: Int) -> Int {
        guard offset > 0 else { return 0 }
        let remainder = offset % blockLength
        return remainder == 0 ? offset : offset + (blockLength - remainder)
    }

    private func safeAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private func safeMultiply(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    /// Extract raw image HDU planes from a local FITS file without rendering them to JPEG.
    ///
    /// This is the FITS-aware entry point used by astronomy image pipelines. It preserves
    /// raw scaled pixel values, merged headers, HDU roles, and WCS metadata so the app can
    /// perform histogram stretching, weight masking, color blending, and WCS placement.
    public func extractFITSObservationProduct(
        fitsUrl: URL, coamResult: CoamResult
    ) -> FITSObservationProduct? {
        guard let fits = readFITSFileSafely(
            at: fitsUrl,
            context: "extractFITSObservationProduct"
        )
        else {
            return nil
        }

        let primaryHeaders = extractHeaderUnits(fits.prime.headerUnit)
        let sourceFilename = fitsUrl.lastPathComponent
        var planes = [FITSImagePlane]()

        if let primaryPlane = extractImagePlane(
            from: fits.prime,
            extIndex: 0,
            headers: primaryHeaders,
            sourceFilename: sourceFilename
        ) {
            planes.append(primaryPlane)
        }

        for (index, hdu) in fits.HDUs.enumerated() {
            guard let imageHDU = hdu as? ImageHDU else { continue }

            let hduHeaders = extractHeaderUnits(imageHDU.headerUnit)
            let xtension = (headerValue("XTENSION", in: hduHeaders)?.rawString ?? "").lowercased()
            guard xtension == "image" else { continue }

            let mergedHeaders = mergeHeaderUnits(primary: primaryHeaders, hdu: hduHeaders)
            if let plane = extractImagePlane(
                from: imageHDU,
                extIndex: index + 1,
                headers: mergedHeaders,
                sourceFilename: sourceFilename
            ) {
                planes.append(plane)
            }
        }

        return FITSObservationProduct(
            coamResult: coamResult,
            sourceFileLocation: fitsUrl,
            primaryHeaders: primaryHeaders,
            planes: planes
        )
    }

    private func extractImagePlane(
        from hdu: AnyImageHDU,
        extIndex: Int,
        headers: [FITSHeaderUnit],
        sourceFilename: String
    ) -> FITSImagePlane? {
        let dataSize = hdu.dataUnit?.count ?? 0
        guard hduContainsImage(headers: headers, dataSize: dataSize) else { return nil }

        let width = headerInt("NAXIS1", in: headers)
        let height = headerInt("NAXIS2", in: headers)
        guard let pixels = decodeRawPixelBuffer(from: hdu, headers: headers) else { return nil }

        let extName = headerValue("EXTNAME", in: headers)?.rawString
        let role = FITSHDURoleClassifier.classify(headers: headers, sourceFilename: sourceFilename)

        return FITSImagePlane(
            role: role,
            extName: extName?.isEmpty == true ? nil : extName,
            extIndex: extIndex,
            width: width,
            height: height,
            headers: headers,
            pixels: pixels,
            wcs: FITSWCS(headers: headers)
        )
    }

    private func decodeRawPixelBuffer(
        from hdu: AnyImageHDU,
        headers: [FITSHeaderUnit]
    ) -> FITSPixelBuffer? {
        guard let dataUnit = hdu.dataUnit else { return nil }

        let width = headerInt("NAXIS1", in: headers)
        let height = headerInt("NAXIS2", in: headers)
        let axisCount = max(headerInt("NAXIS", in: headers), 0)
        let channelCount = max(headerInt("NAXIS3", in: headers), 1)
        let expectedValueCount = width * height * channelCount
        let bscale = Float(headerDouble("BSCALE", in: headers) ?? 1)
        let bzero = Float(headerDouble("BZERO", in: headers) ?? 0)
        let bitpix = headerInt("BITPIX", in: headers)

        let decoded: ([Float], Int)?
        switch hdu.bitpix {
        case .UINT8:
            decoded = decodeIntegerPixels(dataUnit, as: UInt8.self, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .INT16:
            decoded = decodeIntegerPixels(dataUnit, as: Int16.self, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .INT32:
            decoded = decodeIntegerPixels(dataUnit, as: Int32.self, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .INT64:
            decoded = decodeIntegerPixels(dataUnit, as: Int64.self, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .FLOAT32:
            decoded = decodeFloatPixels(dataUnit, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .FLOAT64:
            decoded = decodeDoublePixels(dataUnit, expectedCount: expectedValueCount, bscale: bscale, bzero: bzero)
        case .none:
            decoded = nil
        }

        guard let decoded else { return nil }

        return FITSPixelBuffer(
            width: width,
            height: height,
            axisCount: axisCount,
            channelCount: channelCount,
            bitpix: bitpix,
            values: decoded.0,
            invalidValueCount: decoded.1
        )
    }

    private func decodeIntegerPixels<Integer: FixedWidthInteger>(
        _ dataUnit: DataUnit,
        as type: Integer.Type,
        expectedCount: Int,
        bscale: Float,
        bzero: Float
    ) -> ([Float], Int) {
        dataUnit.withUnsafeBytes { rawBuffer in
            let byteCount = MemoryLayout<Integer>.size
            let count = min(expectedCount, rawBuffer.count / byteCount)
            var values = [Float]()
            values.reserveCapacity(count)

            for index in 0..<count {
                let rawValue = readBigEndianInteger(
                    Integer.self,
                    from: rawBuffer,
                    byteOffset: index * byteCount
                )
                values.append(Float(rawValue) * bscale + bzero)
            }

            return (values, max(expectedCount - count, 0))
        }
    }

    private func decodeFloatPixels(
        _ dataUnit: DataUnit,
        expectedCount: Int,
        bscale: Float,
        bzero: Float
    ) -> ([Float], Int) {
        dataUnit.withUnsafeBytes { rawBuffer in
            let byteCount = MemoryLayout<UInt32>.size
            let count = min(expectedCount, rawBuffer.count / byteCount)
            var values = [Float]()
            values.reserveCapacity(count)
            var invalidCount = max(expectedCount - count, 0)

            for index in 0..<count {
                let bits = readBigEndianUnsignedInteger(
                    UInt32.self,
                    from: rawBuffer,
                    byteOffset: index * byteCount
                )
                let rawValue = Float(bitPattern: bits)
                let value = rawValue * bscale + bzero
                if !value.isFinite { invalidCount += 1 }
                values.append(value)
            }

            return (values, invalidCount)
        }
    }

    private func decodeDoublePixels(
        _ dataUnit: DataUnit,
        expectedCount: Int,
        bscale: Float,
        bzero: Float
    ) -> ([Float], Int) {
        dataUnit.withUnsafeBytes { rawBuffer in
            let byteCount = MemoryLayout<UInt64>.size
            let count = min(expectedCount, rawBuffer.count / byteCount)
            var values = [Float]()
            values.reserveCapacity(count)
            var invalidCount = max(expectedCount - count, 0)

            for index in 0..<count {
                let bits = readBigEndianUnsignedInteger(
                    UInt64.self,
                    from: rawBuffer,
                    byteOffset: index * byteCount
                )
                let rawValue = Double(bitPattern: bits)
                let scaledValue = rawValue * Double(bscale) + Double(bzero)
                let value = Float(scaledValue)
                if !scaledValue.isFinite || !value.isFinite { invalidCount += 1 }
                values.append(value)
            }

            return (values, invalidCount)
        }
    }

    private func readBigEndianInteger<Integer: FixedWidthInteger>(
        _ type: Integer.Type,
        from rawBuffer: UnsafeRawBufferPointer,
        byteOffset: Int
    ) -> Integer {
        let unsigned = readBigEndianUnsignedInteger(
            UInt64.self,
            from: rawBuffer,
            byteOffset: byteOffset,
            byteCount: MemoryLayout<Integer>.size
        )
        return Integer(truncatingIfNeeded: unsigned)
    }

    private func readBigEndianUnsignedInteger<Integer: FixedWidthInteger & UnsignedInteger>(
        _ type: Integer.Type,
        from rawBuffer: UnsafeRawBufferPointer,
        byteOffset: Int,
        byteCount: Int = MemoryLayout<Integer>.size
    ) -> Integer {
        var value: Integer = 0
        for offset in 0..<byteCount {
            value <<= 8
            value |= Integer(rawBuffer[byteOffset + offset])
        }
        return value
    }

    /// Extract science products from a local FITS file.
    /// Each image HDU becomes a `ScienceProduct` with the image saved as JPEG
    /// and structured ``FITSHeaderUnit`` headers.
    /// - Parameters:
    ///   - fitsUrl: Local URL of the FITS file
    ///   - outputDirectory: Directory in which to save converted images
    ///   - coamResult: The originating CoamResult
    /// - Returns: Array of `ScienceProduct` for each image found in the FITS file
    internal func extractScienceProductsFromFits(
        fitsUrl: URL, outputDirectory: URL, coamResult: CoamResult
    ) -> [ScienceProduct] {
        guard let fits = readFITSFileSafely(
            at: fitsUrl,
            context: "extractScienceProductsFromFits"
        )
        else {
            return []
        }

        let baseName = fitsUrl.deletingPathExtension().lastPathComponent
        let primaryHeaders = extractHeaderUnits(fits.prime.headerUnit)
        var products = [ScienceProduct]()

        // Check Primary HDU for image data
        let primeDataSize = fits.prime.dataUnit?.count ?? 0
        if hduContainsImage(headers: primaryHeaders, dataSize: primeDataSize) {
            let naxis = headerInt("NAXIS", in: primaryHeaders)
            let naxis3 = headerInt("NAXIS3", in: primaryHeaders)
            let name = "\(baseName)_primary"
            let jpegUrl = outputDirectory.appendingPathComponent("\(name).jpg")

            do {
                let image: CGImage
                if naxis == 3 && naxis3 == 3 {
                    image = try fits.prime.decode(RGB_Decoder<RGB>.self, ())
                } else {
                    image = try fits.prime.decode(GrayscaleDecoder.self, ())
                }
                let savedUrl = saveCGImageToUrl(image: image, toURL: jpegUrl)
                products.append(
                    ScienceProduct(
                        name: name,
                        imageLocation: savedUrl,
                        sourceFileLocation: fitsUrl,
                        headers: primaryHeaders,
                        coamResult: coamResult
                    ))
            } catch {
                log(
                    .RequestError,
                    message:
                        "extractScienceProductsFromFits: Failed to decode primary HDU: \(error)")
            }
        }

        // Check Extension HDUs for image data
        for (index, hdu) in fits.HDUs.enumerated() {
            let hduHeaders = extractHeaderUnits(hdu.headerUnit)
            let xtension = (headerValue("XTENSION", in: hduHeaders)?.rawString ?? "").lowercased()

            guard xtension == "image", let imageHDU = hdu as? ImageHDU else { continue }

            let hduDataSize = imageHDU.dataUnit?.count ?? 0
            guard hduContainsImage(headers: hduHeaders, dataSize: hduDataSize) else { continue }

            let naxis = headerInt("NAXIS", in: hduHeaders)
            let naxis3 = headerInt("NAXIS3", in: hduHeaders)
            let extName = headerValue("EXTNAME", in: hduHeaders)?.rawString ?? ""
            let suffix = extName.isEmpty ? "ext\(index)" : extName
            let name = "\(baseName)_\(suffix)"
            let jpegUrl = outputDirectory.appendingPathComponent("\(name).jpg")
            let mergedHeaders = mergeHeaderUnits(primary: primaryHeaders, hdu: hduHeaders)

            do {
                let image: CGImage
                if naxis == 3 && naxis3 == 3 {
                    image = try imageHDU.decode(RGB_Decoder<RGB>.self, ())
                } else {
                    image = try imageHDU.decode(GrayscaleDecoder.self, ())
                }
                let savedUrl = saveCGImageToUrl(image: image, toURL: jpegUrl)
                products.append(
                    ScienceProduct(
                        name: name,
                        imageLocation: savedUrl,
                        sourceFileLocation: fitsUrl,
                        headers: mergedHeaders,
                        coamResult: coamResult
                    ))
            } catch {
                log(
                    .RequestError,
                    message:
                        "extractScienceProductsFromFits: Failed to decode Extension[\(index)]: \(error)"
                )
            }
        }

        // If no images were extracted, still return a product with headers only
        if products.isEmpty {
            products.append(
                ScienceProduct(
                    name: baseName,
                    imageLocation: nil,
                    sourceFileLocation: fitsUrl,
                    headers: primaryHeaders,
                    coamResult: coamResult
                ))
        }

        return products
    }

}

private final class FITSImageHeaderMetadataStreamFetcher: NSObject, URLSessionDataDelegate {
    private let url: URL
    private let maxByteCount: Int
    private let configuration: URLSessionConfiguration
    private let parse: (Data, Int64?) -> FITSImageHeaderMetadata?
    private let completion: (FITSImageHeaderMetadata?) -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var remoteFileSize: Int64?
    private var didComplete = false

    init(
        url: URL,
        maxByteCount: Int,
        configuration: URLSessionConfiguration,
        parse: @escaping (Data, Int64?) -> FITSImageHeaderMetadata?,
        completion: @escaping (FITSImageHeaderMetadata?) -> Void
    ) {
        self.url = url
        self.maxByteCount = maxByteCount
        self.configuration = configuration
        self.parse = parse
        self.completion = completion
    }

    func start() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        task = session.dataTask(with: request)
        task?.resume()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            remoteFileSize = remoteFileSize(from: httpResponse)
        } else {
            let expected = response.expectedContentLength
            remoteFileSize = expected > 0 ? expected : nil
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !didComplete else { return }
        data.append(chunk)

        if let metadata = parse(data, remoteFileSize) {
            finish(metadata)
            return
        }

        if data.count >= maxByteCount {
            finish(nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didComplete else { return }
        finish(parse(data, remoteFileSize))
    }

    private func finish(_ metadata: FITSImageHeaderMetadata?) {
        guard !didComplete else { return }
        didComplete = true
        task?.cancel()
        session?.invalidateAndCancel()
        completion(metadata)
    }

    private func remoteFileSize(from response: HTTPURLResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
            let total = contentRange.split(separator: "/").last,
            let size = Int64(total)
        {
            return size
        }
        if let contentLength = response.value(forHTTPHeaderField: "Content-Length") {
            return Int64(contentLength)
        }
        let expected = response.expectedContentLength
        return expected > 0 ? expected : nil
    }
}
