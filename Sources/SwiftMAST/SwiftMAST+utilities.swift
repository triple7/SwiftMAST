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


extension SwiftMAST {
    
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

    func saveFile(targetName: String, product: CoamResult, urlString: String, data: Data, fitsToJpeg: Bool = true, completion: @escaping ([URL]) -> Void) {
        print("saveFile: \(urlString)")
            // Get the Documents directory
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: "Unable to open Documents folder"))
                completion([])
                return
            }

        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(targetName, isDirectory: true)
        
        MASTDirectory = MASTDirectory.appendingPathComponent(product.obs_collection, isDirectory: true)
        let fileName = urlString.components(separatedBy: "/").last!
        let fileExtension = fileName.components(separatedBy: ".").last!
        MASTDirectory = MASTDirectory.appendingPathComponent(fileExtension, isDirectory: true)


            do {
                try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

                var fileUrl = MASTDirectory.appendingPathComponent(fileName)
                
                try data.write(to: fileUrl)
                print("saveFile:: file added with size(data.count) bytes")

                if fitsToJpeg && !fileName.contains("jpg") {
                    let jpegUrl = MASTDirectory.appendingPathComponent(fileName.replacingOccurrences(of: "fits", with: "jpg"))
                    fileUrl = convertFitsToJpeg(url: fileUrl, writeToUrl: jpegUrl).url
                }
                DispatchQueue.main.async {
                    completion([fileUrl])
                }
            } catch let error {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                DispatchQueue.main.async {
                    completion([])
                }
            }
    }

    func saveFile(targetName: String, tempUrl: URL, fitsToJpeg: Bool = true, completion: @escaping ((URL, [String: QValue])?) -> Void) {
        print("saveFile: \(targetName)")
            // Get the Documents directory
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: "Unable to open Documents folder"))
                completion(nil)
                return
            }

        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(targetName, isDirectory: true)
        
        MASTDirectory = MASTDirectory.appendingPathComponent("PS1", isDirectory: true)

        do {
                try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

            let fileName = tempUrl.lastPathComponent.components(separatedBy: ".").first!
            
                // First get the fits data saved, then get the converted jpg and metadata
            let data = try! Data(contentsOf: tempUrl)
                let fileUrl = MASTDirectory.appendingPathComponent("\(fileName).fits")
                try data.write(to: fileUrl)

                    let jpegUrl = MASTDirectory.appendingPathComponent(fileName.replacingOccurrences(of: "fits", with: "jpg"))
                    let imageBundle = convertFitsToJpeg(url: fileUrl, writeToUrl: jpegUrl)

                DispatchQueue.main.async {
                    completion(imageBundle)
                }
            } catch let error {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
    }

    func saveTempUrlToFile(targetName: String, product: CoamResult, urlString: String, tempUrl: URL, completion: @escaping ([URL]) -> Void) {
        print("saveFile: \(urlString)")
            // Get the Documents directory
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: "Unable to open Documents folder"))
                completion([])
                return
            }

        var MASTDirectory = documentsDirectory.appendingPathComponent("MAST", isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(targetName, isDirectory: true)
        
        MASTDirectory = MASTDirectory.appendingPathComponent(product.obs_collection, isDirectory: true)
        let fileName = urlString.components(separatedBy: "/").last!
        let fileExtension = fileName.components(separatedBy: ".").last!
        MASTDirectory = MASTDirectory.appendingPathComponent(fileExtension, isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

                let saveUrl = MASTDirectory.appendingPathComponent(tempUrl.lastPathComponent)
                

                try FileManager.default.moveItem(at: tempUrl, to: saveUrl)
                                completion([])
                DispatchQueue.main.async {
                    completion([saveUrl])
                }
            } catch let error {
                self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                DispatchQueue.main.async {
                    completion([])
                }
            }
    }

    func saveCGImageToUrl(image: CGImage, toURL: URL, dim: Int=1) -> URL {
        // Create an image destination using the provided URL
        
let destination = CGImageDestinationCreateWithURL(toURL as CFURL, kUTTypeJPEG, dim, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        
        CGImageDestinationFinalize(destination)
            return toURL
        }
    
    func convertFitsToJpeg(url: URL, writeToUrl: URL) -> (url: URL, metadata: [String: QValue]) {
        
        let   fits = FitsFile.read( try! Data(contentsOf: url))!
        
        print(fits.HDUs.count)
        for hdu in fits.HDUs {
            print("HDU \n \(hdu.description)")
        }
                
        let image = try! fits.prime.decode(GrayscaleDecoder.self, ())

        // get the metadata from the hdu primary header unit
        var metadata = [String:QValue]()
        for unit in  fits.prime.headerUnit {
            metadata[unit.keyword.rawValue] = QValue(value: (unit.value != nil) ? unit.value!.toString : "")
        }

        return (url: saveCGImageToUrl(image: image, toURL: writeToUrl), metadata: metadata)
    }
    
}
