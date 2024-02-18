//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public extension SwiftMAST {
    /** Extends the MAST network requests to the API
     refer to [MAST API](https://mast.stsci.edu/api/v0/md_result_formats.html)
     
     These methods facilitate accessing, requesting and download Json/media which is saved to a MASTTable instance
     and save by target object identification [known or user defined]
     */
    
    
    /** Forms a request object from the given MAST service domain path and given parameters
     Adds a resulting table to the targets dictionary for further processing
     Parameters:
     service: MAST service domain path
     params: pre-formed parameter json object
     returnType: expected response format [json/xml]
     closure: whether request was successful
     */
func queryMast(service: Service, params: MASTJson, returnType: APIReturnType,_ closure: @escaping (Bool) -> Void) {
        
        let json = service.jsonData(json: params)

        let url = MASTRequest(searchType: .apiRequest).getApiUrl(json: json)
        let configuration = URLSessionConfiguration.ephemeral
    let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard error == nil else {
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
                return
            }

            var table:MASTTable!
            switch returnType {
            case .json:
                table = self?.parseJson(data: data!)
            case .xml:
                 table = self?.parseXml(data: data!)
            default:
                self?.sysLog.append(MASTSyslog(log: .RequestError, message: "Return type not recognized or not yet available"))
            closure(false)
                return
            }

            self?.targets[service.id] = table
            self?.sysLog.append(MASTSyslog(log: .Ok, message: "request successful"))
        closure(true)
            return
    }
    task.resume()
    }

    /** Downloads a product bundle from MAST
     Parameters:
     service: MAST service domain path
     params: pre-formed parameter json object
     closure: (Bool, [URL])
     */
    func requestProductBundle(service: Service, coamResults: [CoamResult],_ closure: @escaping (Bool, [URL]) -> Void) {
        print("requestProductBundle: getting \(coamResults.count) URLs in tar.gz bundle")
        let urls = coamResults.map{["uri", $0.dataURL]}
        let jsonData = try! JSONEncoder().encode(urls)
        var request = URLRequest(url: MASTRequest(searchType: .image).getDownloadUrl(service: service))
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let configuration = URLSessionConfiguration.background(withIdentifier: "com.mast.download_bundle")
        let queue = OperationQueue.main
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard error == nil else {
                    self?.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
    closure(false, [])
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    self?.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                    closure(false, [])
                    return
                }
                if response.statusCode != 200 {
                    let error = NSError(domain: "com.error", code: response.statusCode)
                    self?.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                    closure(false, [])
                    return
                }

            // Unzip the data in documents and return
            // The available urls
            self!.unzipResponseData(data!, completion: { urls in
                closure(true, urls)
            })
            
        }
        task.resume()
        }

}
