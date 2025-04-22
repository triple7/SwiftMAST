//
//  File.swift
//  
//
//  Created by Yuma decaux on 12/2/2024.
//

import Foundation
import Zip
import FITS
import FITSKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftQValue


extension SwiftMAST {
    
    private func getproductFolder(target: String, collection: String) -> URL {
        
        // Get the Documents directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(target, isDirectory: true)
        
        MASTDirectory = MASTDirectory.appendingPathComponent(collection, isDirectory: true)
        return MASTDirectory
    }
    
    
    func unzipResponseData(_ data: Data, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global().async {
            // Get the Documents directory
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: "Unable to open Documents folder"))
                completion([])
                return
            }
            
            let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                
                let temporaryZipFileURL = temporaryDirectory.appendingPathComponent("temp.tar.gz")
                
                let tempDoc = documentsDirectory.appendingPathComponent("temp.tar.gz")
                try data.write(to: temporaryZipFileURL)
                try data.write(to: tempDoc)
                print("tar temporarily added")
                print("Data size: \(data.count) bytes")
                
                try FileManager.default.createFilesAndDirectories(path: temporaryDirectory.path, tarPath: temporaryZipFileURL.path)
                
                //                let unzipDirectory = try Zip.quickUnzipFile(temporaryZipFileURL)
                let unzippedFiles = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
                
                // Clean up: remove the temporary directory and file
                try FileManager.default.removeItem(at: temporaryZipFileURL)
                try FileManager.default.removeItem(at: temporaryDirectory)
                
                print("unzipResponseData: Unzipped files to: \(documentsDirectory)")
                DispatchQueue.main.async {
                    completion(unzippedFiles.map{Foundation.URL(fileURLWithPath: $0)})
                }
            } catch let error {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    
    /** Saves MAST returned assets to local directory
     */
    func saveAsset(targetName: String, product: CoamResult, urlString: String, data: Data, completion: @escaping (FitsData?) -> Void) {
        print("saveAsset: \(urlString)")
        
        var MASTDirectory = getproductFolder(target: targetName, collection: product.obs_collection)
        
        // We want readable and identifiable URL paths
        let filters = product.filters.replacingOccurrences(of: ";", with: "-")
        MASTDirectory = MASTDirectory.appendingPathComponent(filters, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let fileExtension = "_\(product.wavelength_region)_\(product.obs_id).fits"
            let fileUrl = MASTDirectory.appendingPathComponent(fileExtension)
            
            try data.write(to: fileUrl)
            
            let jpegUrl = MASTDirectory.appendingPathComponent(fileExtension.replacingOccurrences(of: "fits", with: "jpg"))
            let fitsData = convertFitsToJpeg(url: fileUrl, writeToUrl: jpegUrl)
            
            DispatchQueue.main.async {
                completion(fitsData)
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
    func saveImageFile(target: String, collection: String, filter: String, productType: ProductType = .Jpeg, url: URL? = nil, data: Data? = nil) -> URL? {
        print("saveImageFile: \(target)_\(collection)_\(filter).\(productType.id)")
        
        let MASTDirectory = getproductFolder(target: target, collection: collection)
        
        let fileExtension = "\(target)_\(collection)_\(filter).\(productType.id)"
        let imageUrl = MASTDirectory.appendingPathComponent(fileExtension)
        
        do {
            try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)
            
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
    
    
    
    func saveTempUrlToFile(targetName: String, product: CoamResult, tempUrl: URL, productType: ProductType, completion: @escaping (URL?) -> Void) {
        print("saveTempUrlToFile: \(targetName)")
        
        let MASTDirectory = getproductFolder(target: targetName, collection: product.obs_collection)
        
        do {
            try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let filters = product.filters.replacingOccurrences(of: ";", with: "-")
            let fileExtension = "\(targetName)_\(product.obs_collection)_\(filters)_\(product.obsid).\(productType.id)"
            let saveUrl = MASTDirectory.appendingPathComponent(fileExtension)
            
            
            try FileManager.default.moveItem(at: tempUrl, to: saveUrl)
            
            // Add the fits or jpeg data to the target
            if productType == .Fits {
                let fits = FitsFile.read( try! Data(contentsOf: saveUrl))!
                let fitsData = FitsData(metadata: getFitsMetaData(fits: fits), url: saveUrl)
                self.appendFitsData(target: targetName, fitsData: fitsData)
            }
            DispatchQueue.main.async {
                completion(saveUrl)
            }
        } catch let error {
            self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
    
    func saveCGImageToUrl(image: CGImage, toURL: URL, dim: Int=1) -> URL {
        // Create an image destination using the provided URL
        
        let destination = CGImageDestinationCreateWithURL(toURL as CFURL, UTType.jpeg.identifier as CFString, dim, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        
        CGImageDestinationFinalize(destination)
        return toURL
    }
    
    private func getFitsMetaData(fits: FitsFile) -> [String: QValue] {
        print("getFitsMetaData: HDU count \(fits.HDUs.count)")
        for hdu in fits.HDUs {
            print("HDU: \n \(hdu.description)")
            for header in hdu.headerUnit {
                print("\(header.keyword): \(header.value)")
            }
        }
        
        // get the metadata from the hdu primary header unit
        var metadata = [String:QValue]()
        for hdu in fits.HDUs {
            for unit in  hdu.headerUnit {
                metadata[unit.keyword.rawValue] = QValue(value: (unit.value != nil) ? unit.value!.toString : "")
            }
        }
        return metadata
    }
    
    
    private func convertFitsToJpeg(url: URL, writeToUrl: URL) -> FitsData {
        
        let fits = FitsFile.read( try! Data(contentsOf: url))!
        let metadata = getFitsMetaData(fits: fits)
        for key in metadata.keys {
            print("key: \(key)")
        }
        let hduExtension = metadata["XTENSION"]!
        let numAxis = metadata["NAXIS"]!
        
        if hduExtension.string.lowercased() == "image" {
            if Int(numAxis.string)! == 3 {
                let image = try! fits.prime.decode(GrayscaleDecoder.self, ())
                return FitsData(metadata: metadata, url: saveCGImageToUrl(image: image, toURL: writeToUrl))
            } else {

                let image = try! fits.prime.decode(RGB_Decoder<RGB>.self, ())
                return FitsData(metadata: metadata, url: saveCGImageToUrl(image: image, toURL: writeToUrl))
            }
        } else {
// TODO: handle conversions for all fits data types
            return FitsData(metadata: metadata, url: nil)
        }
    }
    
    // Mark: Debug helper
    internal func printUniqueSets(table: MASTTable) {
        let fieldss:[Coam] = [.dataproduct_type, .filters, .instrument_name, .obs_collection, .wavelength_region]
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
//    internal func pruneProductsByFilterBand(results: [CoamResult]) -> [CoamResult] {
//        var firstFilter = [String: [CoamResult]]()
//        for product in results {
//            for key in FILTER_BANDS.keys {
//                let band = FILTER_BANDS[key]!
//                if band.contains(product.filters) {
//                    if firstFilter[key] == nil {
//                        firstFilter[key] = [product]
//                    } else {
//                        firstFilter[key]!.append(product)
//                    }
//                }
//            }
//        }
//        
//        // Get unique filter and obs_collection combinations
//    }

    
}
