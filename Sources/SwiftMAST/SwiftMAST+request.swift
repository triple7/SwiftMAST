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
func queryMast(service: Service, params: MASTJson, returnType: APIReturnType, _ closure: @escaping (Bool) -> Void) {
        
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

            self?.targets[self!.currentTargetId!] = table
            self?.sysLog.append(MASTSyslog(log: .OK, message: "request successful"))
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

    
    func getDataproducts( targetName: String, service: Service,  products: [CoamResult], productType: ProductType, token: String?, completion: @escaping (Bool, [URL])->Void ) {
        let serialQueue = DispatchQueue(label: "MASTDataproductsQueue")
        
        var remainingProducts = products.filter { (productType == .Fits ?  $0.dataURL : $0.jpegURL) != ""}
        var urls = [URL]()
        
        
        // Create a recursive function to handle the download
        func downloadNextproduct() {
            guard !remainingProducts.isEmpty else {
                // All products have been downloaded, call the completion handler
                completion(true, urls)
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
                var gotError = false
                if error != nil {
                    print(error!.localizedDescription)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
                    gotError = true
                }
                if (response as? HTTPURLResponse) == nil {
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                    gotError = true
                }
                let urlResponse = (response as! HTTPURLResponse)
                if urlResponse.statusCode != 200 {
                    let error = NSError(domain: "com.error", code: urlResponse.statusCode)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                    gotError = true
                }
                
                if !gotError {
                    self.sysLog.append(MASTSyslog(log: .OK, message: "\(productUrl) downloaded"))
                    
                    self.saveFile(targetName: targetName, product: product, urlString: productUrl, data: data!, completion: { url in
                        urls += url
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
        

    func getDirectDataproducts( targetName: String, service: Service,  products: [CoamResult], productType: ProductType, token: String?, completion: @escaping (Bool, [URL])->Void ) {
        let serialQueue = DispatchQueue(label: "DirectDownloadDataproductsQueue")
        
        var remainingProducts = products.filter { (productType == .Fits ?  $0.dataURL : $0.jpegURL) != ""}
        var urls = [URL]()
        
        
        // Create a recursive function to handle the download
        func downloadNextproduct() {
            guard !remainingProducts.isEmpty else {
                // All products have been downloaded, call the completion handler
                completion(true, urls)
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
                var gotError = false
                if error != nil {
                    print(error!.localizedDescription)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
                    gotError = true
                }
                if (response as? HTTPURLResponse) == nil {
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                    gotError = true
                }
                let urlResponse = (response as! HTTPURLResponse)
                if urlResponse.statusCode != 200 {
                    print(urlResponse.statusCode)
                    print(urlResponse)
                    let error = NSError(domain: "com.error", code: urlResponse.statusCode)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                    gotError = true
                }
                
                if !gotError {
                    self.sysLog.append(MASTSyslog(log: .OK, message: "\(productUrl) downloaded"))
                    
                    self.saveTempUrlToFile(targetName: targetName, product: product, urlString: productUrl, tempUrl: tempUrl!, productType: productType, completion: { url in
                        urls.append(contentsOf: url)
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

    func downloadPS1Cutouts( targetName: String, urls: [URL], completion: @escaping (Bool, [URL])->Void ) {
        let serialQueue = DispatchQueue(label: "downloadUrlsQueue")
        
        
        var remainingUrls = urls
        var jpgUrls:[URL] = []
        // Create a recursive function to handle the download
        func downloadNextUrl() {
            guard !remainingUrls.isEmpty else {
                // All urls have been downloaded, call the completion handler
                completion(true, jpgUrls)
                return
            }
            
            let url = remainingUrls.removeFirst()
            let request = URLRequest(url: url)
            
            let operation = MASTDirectDownloadOperation(session: URLSession.shared, request: request, completionHandler: { (tempUrl, response, error) in
                var gotError = false
                if error != nil {
                    print(error!.localizedDescription)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error!.localizedDescription))
                    gotError = true
                }
                if (response as? HTTPURLResponse) == nil {
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: "response timed out"))
                    gotError = true
                }
                let urlResponse = (response as! HTTPURLResponse)
                if urlResponse.statusCode != 200 {
                    print(urlResponse.statusCode)
                    let error = NSError(domain: "com.error", code: urlResponse.statusCode)
                    self.sysLog.append(MASTSyslog(log: .RequestError, message: error.localizedDescription))
                    gotError = true
                }
                
                if !gotError {
                    self.sysLog.append(MASTSyslog(log: .OK, message: "\(url) downloaded"))
                    
                    self.saveFile(fileName: targetName, tempUrl: tempUrl!, completion: { fitsData in
                        if let fitsData
                            = fitsData {
                            jpgUrls.append(fitsData.url)
                            self.savePreview(target: targetName, fitsData: fitsData)
                        }
                        // Call the recursive function to download the next object
                        serialQueue.async {
                            downloadNextUrl()
                        }
                    })
                } else {
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
        print("queryPS1: \(request.url!.absoluteString)")
        let configuration = URLSessionConfiguration.ephemeral
    let queue = OperationQueue.main
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
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

            let table = self?.parsePS1table(text: String(data: data!, encoding: .ascii)!, baseUrl: ps1Request.getFitsCutUrlBase())
            self?.targets[self!.currentTargetId!] = table
            self?.sysLog.append(MASTSyslog(log: .OK, message: "request successful"))
        closure(true)
            return
    }
    task.resume()
    }

}
