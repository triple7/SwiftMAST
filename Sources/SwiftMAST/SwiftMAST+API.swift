//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

extension SwiftMAST {
    
    public func resolveName(target: String, mission: MASTDataSet, _ closure: @escaping (Bool)-> Void) {
        /** Requests a mission related table
         Adds a table into the targets dictionary and adds a response type for further processing
         Params:
         target: identifiable target name
         mission: data set path
         closure: whether request was successful
         */
        let request = MASTRequest(target: target, searchType: .mission)
        print(request.getURL(dataSet: mission).absoluteString)
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
            self?.sysLog.append(MASTSyslog(log: .Ok, message: "ephemerus downloaded"))
        closure(true)
            return
    }
    task.resume()
    }


    
}
