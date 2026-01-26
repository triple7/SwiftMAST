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

    private func getproductFolder(target: String, collection: String) -> URL {

        // Get the Documents directory
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(target, isDirectory: true)

        MASTDirectory = MASTDirectory.appendingPathComponent(collection, isDirectory: true)
        return MASTDirectory
    }

    func unzipResponseData(_ data: Data, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global().async {
            // Get the Documents directory
            guard
                let documentsDirectory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else {
                self.sysLog.append(
                    MASTSyslog(log: .RequestError, message: "Unable to open Documents folder"))
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
                self.sysLog.append(
                    MASTSyslog(log: .RequestError, message: error.localizedDescription))
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

        var MASTDirectory = getproductFolder(target: targetName, collection: product.obs_collection)

        // We want readable and identifiable URL paths
        let filters = product.filters.replacingOccurrences(of: ";", with: "-")
        MASTDirectory = MASTDirectory.appendingPathComponent(filters, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

            let fileExtension = "_\(product.wavelength_region)_\(product.obs_id).fits"
            let fileUrl = MASTDirectory.appendingPathComponent(fileExtension)

            try data.write(to: fileUrl)
            print("saveAsset: FITS file saved to \(fileUrl)")

            let jpegUrl = MASTDirectory.appendingPathComponent(
                fileExtension.replacingOccurrences(of: "fits", with: "jpg"))
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
            self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    /** Saves jpg/png only
     no fits data
     */
    func saveImageFile(
        target: String, collection: String, filter: String, productType: ProductType = .Jpeg,
        url: URL? = nil, data: Data? = nil
    ) -> URL? {
        print("saveImageFile: \(target)_\(collection)_\(filter).\(productType.id)")

        let MASTDirectory = getproductFolder(target: target, collection: collection)

        let fileExtension = "\(target)_\(collection)_\(filter).\(productType.id)"
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
            self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
            return nil
        }
    }

    func saveTempUrlToFile(
        targetName: String, product: CoamResult, tempUrl: URL, productType: ProductType,
        completion: @escaping (URL?) -> Void
    ) {
        print("saveTempUrlToFile: \(targetName)")

        let MASTDirectory = getproductFolder(target: targetName, collection: product.obs_collection)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

            let filters = product.filters.replacingOccurrences(of: ";", with: "-")
            let fileExtension =
                "\(targetName)_\(product.obs_collection)_\(filters)_\(product.obsid).\(productType.id)"
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
                let jpegUrl = MASTDirectory.appendingPathComponent(
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
            self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
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

}
