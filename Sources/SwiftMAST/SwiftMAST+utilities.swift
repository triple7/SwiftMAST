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

        let fits = FitsFile.read(try! Data(contentsOf: url))!
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

    /// Extract raw image HDU planes from a local FITS file without rendering them to JPEG.
    ///
    /// This is the FITS-aware entry point used by astronomy image pipelines. It preserves
    /// raw scaled pixel values, merged headers, HDU roles, and WCS metadata so the app can
    /// perform histogram stretching, weight masking, color blending, and WCS placement.
    public func extractFITSObservationProduct(
        fitsUrl: URL, coamResult: CoamResult
    ) -> FITSObservationProduct? {
        guard let data = try? Data(contentsOf: fitsUrl),
            let fits = FitsFile.read(data)
        else {
            log(
                .RequestError,
                message: "extractFITSObservationProduct: Unable to read \(fitsUrl.lastPathComponent)"
            )
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
        guard let data = try? Data(contentsOf: fitsUrl),
            let fits = FitsFile.read(data)
        else {
            log(
                .RequestError,
                message:
                    "extractScienceProductsFromFits: Unable to read \(fitsUrl.lastPathComponent)")
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
