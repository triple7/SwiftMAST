//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

extension SwiftMAST {
    /** Extends the MAST network requests to the API
     refer to [MAST API](https://mast.stsci.edu/api/v0/md_result_formats.html)
     
     These methods facilitate accessing, requesting and download Json/media and are composed of all the available MAST service queries, with a swift flavour.
     */
    
    public func createRequest(url: URL)->URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain",forHTTPHeaderField: "Accept")
        request.httpMethod = "POST"
        print(request.allHTTPHeaderFields)
        return request
    }
    
    public func resolveName(target: String, _ closure: @escaping (Bool)-> Void) {
        /** Requests a lookup on a given identifiable name
         Params:
         target: identifiable target name
         closure: whether request was successful
         */
        
        let service = Service.Mast_Name_Lookup
        let json = service.json(parameters: [MAP.input: target, MAP.format: "json"])

        let url = MASTRequest(searchType: .apiRequest).getApiUrl(json: json)
        
        let request = createRequest(url: url)
        print(request.url!)
        let configuration = URLSessionConfiguration.ephemeral
    let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
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
                return
            }

            let table = self?.parseJson(data: data!)
            self?.targets["lookup-\(target)"] = table
            self?.sysLog.append(MASTSyslog(log: .Ok, message: "lookup \(target) successful"))
        closure(true)
            return
    }
    task.resume()
    }

}
