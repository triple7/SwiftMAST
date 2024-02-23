//
//  File.swift
//  
//
//  Created by Yuma decaux on 12/2/2024.
//

import Foundation
import Zip


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

    func saveFile(targetName: String, product: CoamResult, urlString: String, data: Data, completion: @escaping ([URL]) -> Void) {
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

                let fileUrl = MASTDirectory.appendingPathComponent(fileName)
                
                try data.write(to: fileUrl)
                print("file added")
                print("Data size: \(data.count) bytes")

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

}
