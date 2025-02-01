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
    

    /** request returned data check
     */
    private func requestIsValid(error: Error?, response: URLResponse?, url: URL? = nil) -> Bool {
        var gotError = false
        if error != nil {
            print("requestIsValid: \(error!.localizedDescription)")
            self.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
            gotError = true
        }
        if (response as? HTTPURLResponse) == nil {
            self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
            gotError = true
        }
        if let response = response {
            let urlResponse = (response as! HTTPURLResponse)
            if urlResponse.statusCode != 200 {
                let error = NSError(domain: "com.error", code: urlResponse.statusCode)
                self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                gotError = true
            }
        } else {

            self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out or no connection"))
            gotError = true
        }
        if !gotError {
            let message = url != nil ? url!.absoluteString : "data"
            self.sysLog.append(MASTSyslog(log: .OK, message: "\(message) downloaded"))
        }
        for log in self.sysLog {
            print(log)
        }
        return !gotError
    }
    
    
    /** Forms a request object from the given MAST service domain path and given parameters
     Adds a resulting table to the targets dictionary for further processing
     Parameters:
     service: MAST service domain path
     params: pre-formed parameter json object
     returnType: expected response format [json/xml]
     closure: whether request was successful
     */
func queryMast(service: Service, params: MASTJson, returnType: APIReturnType, _ closure: @escaping (Bool) -> Void) {
        
    var extendedParams = params
    extendedParams.setParameter(param: MAP.format, value: returnType.id as Any)
    let json = service.jsonData(json: extendedParams)

        let url = MASTRequest(searchType: .apiRequest).getApiUrl(json: json)

        let configuration = URLSessionConfiguration.ephemeral
    let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            
            if self!.requestIsValid(error: error, response: response) {
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
                
                self?.targets[self!.currentTargetId!] = table
                closure(true)
                return
            }
            closure(false)
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
        let urls = coamResults.map{["uri", $0.dataURL]}.filter {$0[1] != ""}
        let jsonData = try! JSONEncoder().encode(urls)
        var request = URLRequest(url: MASTRequest(searchType: .image).getBundleDownloadUrl(service: service))
        request.httpMethod = "POST"
        request.httpBody = jsonData

            let configuration = URLSessionConfiguration.default
        let queue = OperationQueue.main
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request) { data, response, error in
                guard error == nil else {
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
    closure(false, [])
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                    closure(false, [])
                    return
                }
                if response.statusCode != 200 {
                    let error = NSError(domain: "com.error", code: response.statusCode)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                    closure(false, [])
                    return
                }

            // Unzip the data in documents and return
            // The available urls
            self.unzipResponseData(data!, completion: { urls in
                closure(true, urls)
            })
            
        }
        task.resume()
        }

    
    func getDataproducts( targetName: String, service: Service,  products: [CoamResult], productType: ProductType, token: String?, completion: @escaping ([FitsData])->Void ) {
        let serialQueue = DispatchQueue(label: "MASTDataproductsQueue")
        
        var remainingProducts = products.filter { (productType == .Fits ?  $0.dataURL : $0.jpegURL) != ""}
        print("Remaining products: \(remainingProducts)")
        var fitsData = [FitsData]()
        
        
        // Create a recursive function to handle the download
        func downloadNextproduct() {
            guard !remainingProducts.isEmpty else {
                // All products have been downloaded, call the completion handler
                completion(fitsData)
                return
            }
            
            let product = remainingProducts.removeFirst()
            let productUrl = productType == .Fits ? product.dataURL : product.jpegURL
            var request = URLRequest(url: MASTRequest(searchType: .image).getFileDownloadUrl(service: service, parameters: ["uri": productUrl]))
            request.httpMethod = "GET"
            if let token = token {
                request.allHTTPHeaderFields = [
                    "Authorization":"token \(token)"
                ]
            }
            
            let operation = MASTDownloadOperation(session: URLSession.shared, request: request, completionHandler: { (data, response, error) in
                
                if self.requestIsValid(error: error, response: response) {
                    self.saveAsset(targetName: targetName, product: product, urlString: productUrl, data: data!, completion: { fits in
                        if let fits = fits {
                            fitsData.append(fits)
                        }
                        // Call the recursive function to download the next object
                        serialQueue.async {
                            downloadNextproduct()
                        }
                    })
                } else {
                    serialQueue.async {
                        downloadNextproduct()
                    }
                }
                
            })
            
            // Add the operation to the serial queue to execute it serially
            serialQueue.async {
                operation.start()
            }
        }

            // Start the download process by calling the recursive function
            serialQueue.async {
                downloadNextproduct()
            }
        }
        

    func getDirectDataproducts( targetName: String, service: Service,  products: [CoamResult], productType: ProductType, token: String?, completion: @escaping ([URL])->Void ) {
        let serialQueue = DispatchQueue(label: "DirectDownloadDataproductsQueue")
        
        var remainingProducts = products.filter { (productType == .Fits ?  $0.dataURL : $0.jpegURL) != ""}
        var urls = [URL]()
        
        
        // Create a recursive function to handle the download
        func downloadNextproduct() {
            guard !remainingProducts.isEmpty else {
                // All products have been downloaded, call the completion handler
                completion(urls)
                return
            }
            
            let product = remainingProducts.removeFirst()
            var productUrl = productType == .Fits ? product.dataURL : product.jpegURL
            if !productUrl.contains("https") {
                productUrl = productUrl.replacingOccurrences(of: "http", with: "https")
            }
            var request = URLRequest(url: URL(string: productUrl)!)
            if let token = token {
                request.allHTTPHeaderFields = [
                    "Authorization":"token \(token)"
                ]
            }
            
            let operation = MASTDirectDownloadOperation(session: URLSession.shared, request: request, completionHandler: { (tempUrl, response, error) in
                if self.requestIsValid(error: error, response: response, url: tempUrl) {
                    self.saveTempUrlToFile(targetName: targetName, product: product, tempUrl: tempUrl!, productType: productType, completion: { url in
                        if let url = url {
                            urls.append(url)
                        }
                        // Call the recursive function to download the next object
                        serialQueue.async {
                            downloadNextproduct()
                        }
                    })
                } else {
                    serialQueue.async {
                        downloadNextproduct()
                    }
                }
                
            })
            
            // Add the operation to the serial queue to execute it serially
            serialQueue.async {
                operation.start()
            }
        }

            // Start the download process by calling the recursive function
            serialQueue.async {
                downloadNextproduct()
            }
        }

    /** Get the fits cutout from PS1, get the color jpeg and save all
     metadata files from all filters
     */
    func downloadPS1Cutouts( targetName: String, urls: [URL], colored: Bool = true, completion: @escaping ([URL])->Void ) {
        print("downloadPS1Cutouts: \(targetName)")
        let serialQueue = DispatchQueue(label: "downloadUrlsQueue")
        
        
        var remainingUrls = urls
        var urls:[URL] = []
        // Create a recursive function to handle the download
        func downloadNextUrl() {
            guard !remainingUrls.isEmpty else {
                // All urls have been downloaded, call the completion handler
                print("All URLS downloaded")
                completion(urls)
                return
            }
            
            let url = remainingUrls.removeFirst()
            let request = URLRequest(url: url)
            
            let operation = MASTDirectDownloadOperation(session: URLSession.shared, request: request, completionHandler: { (tempUrl, response, error) in
                if self.requestIsValid(error: error, response: response, url: tempUrl) {
                    print("downloadFitsCutout: \(tempUrl)")
                    let url = self.saveImageFile(target: targetName, collection: "PS1", filter: "OPTICAL", productType: .Jpeg, url: tempUrl!)
                    if let url = url {
                        urls.append(url)
                    }
                    serialQueue.async {
                        downloadNextUrl()
                    }
                }
            })
            
            // Add the operation to the serial queue to execute it serially
            serialQueue.async {
                operation.start()
            }
        }
        
            // Start the download process by calling the recursive function
            serialQueue.async {
                downloadNextUrl()
            }
        }
        
        
        /** Forms a request object from the given PS1 request URL and given parameters
         Adds a resulting table to the targets dictionary for further processing
         Parameters:
         ps1Request: PS1 request generator
         closure: whether request was successful
         */
        func queryPS1(ps1Request: PS1Request, _ closure: @escaping (Bool) -> Void) {
            
            
            let request = ps1Request.getFileListRequest()
            let configuration = URLSessionConfiguration.ephemeral
            let queue = OperationQueue.main
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                if self!.requestIsValid(error: error, response: response) {
                    let table = self!.parsePS1table(text: String(data: data!, encoding: .ascii)!, baseUrl: ps1Request.getFitsCutUrlBase())
                    self!.targets[self!.currentTargetId!] = table
                    closure(true)
                    return
                }
            }
            task.resume()
        }

    
    func getNedResolver(target: String, completion: @escaping (NedResult?) -> Void) {
        let requestBuilder = NedResolverRequest()
        
        let request = requestBuilder.getRequest(target: target)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if self.requestIsValid(error: error, response: response) {
                // Decode JSON into NedResolver
                do {
                    let decoder = JSONDecoder()
                    let nedResolver = try decoder.decode(NedResult.self, from: data!)
//                    let text = String(data: data!, encoding: .utf8)
                    completion(nedResolver)
                } catch let error  {
                    print("issue with resolver: \(error)")
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))

                    completion(nil)
                }
            }
            completion(nil)
        }.resume()
    }

    func queryMASTTap(selectQuery: String? = nil, table: MASTTap, fields: [String], parameters: [MASTTapParameter], format: APIReturnType = .json, token: String? = nil, closure: @escaping (MASTTAPResponse)-> Void) {
        /** Gets a TAP (Table Access protocol) result
         Params:
         table: the table to query
         fields: which fields to use
         params: the WHERe clause elements
         format: what format to return
         token: the ADS API token
         closure: the resulting json data
         */
        var mASTTapRequest:MASTTapRequest
        if let _ = selectQuery {
            mASTTapRequest = MASTTapRequest()
        } else {
            mASTTapRequest = MASTTapRequest(table: table, fields: fields, parameters: parameters, format: format)
        }
        let configuration = URLSessionConfiguration.ephemeral
        let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: mASTTapRequest.getUrl(selectQuery))
        request.httpMethod = "POST"
        if token != nil {
            request.addValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        }

        print(mASTTapRequest.getUrl(selectQuery).absoluteString)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            
            if self!.requestIsValid(error: error, response: response) {
//                print(String(data: data!, encoding: .utf8))
                let result = try! JSONDecoder().decode(MASTTAPResponse.self, from: data!)

                self?.sysLog.append(MASTSyslog(log: .OK, message: "query \(mASTTapRequest.getSelectQuery()) result downloaded"))
                closure(result)
                return

            }
        }
        task.resume()
    }

}

