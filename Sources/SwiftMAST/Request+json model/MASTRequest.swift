//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum PS1Filter:String, Codable, Identifiable {
    case grizy

    public var id:String {
        return self.rawValue
    }
    
}

public enum PS1ImageType: String, Codable, Identifiable {
    case stack        // Default is stack (standard image stack)
    case warp         // warp (single-epoch images)
    case stack_wt     // stack.wt (weight image)
    case stack_mask   // stack.mask (mask image)
    case stack_exp    // stack.exp (exposure time)
    case stack_num    // stack.num (number of exposures)
    case warp_wt      // warp.wt (weight image for warp)
    
    public var id:String {
        if self.rawValue.contains("_") {
            return self.rawValue.replacingOccurrences(of: "_", with: ".")
        }
        return self.rawValue
    }
    
}

public struct MASTRequest {
    /** MAST archive request formatter
     Creates a request Url from the API and configured parameters,
     */
    private let APIUrl = "https://archive.stsci.edu/dataSet/search.php?action=Search"
    private let scsAPIUrl =  "https://archive.stsci.edu/dataSet/search.php?"
    private let apiRequestUrl = "https://mast.stsci.edu/api/v0/invoke"
    private let apiDownloadUrl = "https://mast.stsci.edu/api/v0.1/"
    private(set) var parameters:[String: String]
    let searchType:MASTSearchType
    
    public init(target: String, searchType: MASTSearchType) {
        self.searchType = searchType
        var parameters = searchType.defaultParameters
        parameters[MGP.target] = target
        self.parameters = [String:String]()
        for key in parameters.keys {
            self.parameters[key.id] = parameters[key]
        }
    }

    public init(ra: Float, dec: Float, radius: Float, searchType: MASTSearchType) {
        self.searchType = searchType
        var parameters = searchType.defaultParameters
        parameters[MGP.ra] = "\(ra)"
                   parameters[MGP.dec] = "\(dec)"
                   parameters[MGP.SR] = "\(radius)"
        self.parameters = [String:String]()
        for key in parameters.keys {
            self.parameters[key.id] = parameters[key]
        }
    }

    public init(searchType: MASTSearchType) {
        self.searchType = searchType
        self.parameters = [String:String]()
    }
    
    
    /** Returns a formatted request Url
     Parameters:
     dataSet: The MAST data set subfolder
     */
    public func getURL(dataSet: MASTDataSet)->URL {
        var path = (self.searchType == .mission) ? APIUrl : scsAPIUrl
        path = path.replacingOccurrences(of: "dataSet", with: dataSet.id)
        var url = URLComponents(string: path)
        url!.queryItems = Array(parameters.keys).map {URLQueryItem(name: $0, value: parameters[$0]!)}
            return url!.url!
        }

    func getBundleDownloadUrl(service: Service) -> URL {
        return URL(string: "\(apiDownloadUrl)\(service.id).tar.gz")!
    }
    
    func getFileDownloadUrl(service: Service, parameters: [String: String]) -> URL {
        let baseUrl = "\(apiDownloadUrl)\(service.id)?"
        var urlComponents = URLComponents(string: baseUrl)
        let queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        urlComponents!.queryItems = queryItems
        return urlComponents!.url!
    }
    
    func getApiUrl(json: Data)->URL {

        let text = String(decoding: json, as: UTF8.self)
        let path = (self.searchType == .apiRequest) ? apiRequestUrl : apiDownloadUrl
        var url = URLComponents(string: path)
        url?.queryItems = [URLQueryItem(name: "request", value: text)]
        return url!.url!
    }
    
    private func removeQValueString(text: String) -> String {
        let strQ = "{\"string\":{\"_0\":"
        let intQ = "{\"int\":{\"_0\":"
            let floatQ = "{\"float\":{\"_0\":"
        let endQ = "}}"
        var output = text.replacingOccurrences(of: strQ, with: "", options: .literal)
        output = output.replacingOccurrences(of: "separator", with: "", options: .literal)
        output = text.replacingOccurrences(of: intQ, with: "", options: .literal)
        output = text.replacingOccurrences(of: floatQ, with: "", options: .literal)
        output = text.replacingOccurrences(of: endQ, with: "", options: .literal)
        return output
    }
    
}


public struct PS1Request {
    /** PS1 panstarr archive request formatter
     Creates a request Url from the API and configured parameters,
     */
    private let fileListUrl = "http://ps1images.stsci.edu/cgi-bin/ps1filenames.py"
    private let downloadFileUrl = ""
    private let fitsCutRequestUrl = "http://ps1images.stsci.edu/cgi-bin/fitscut.cgi"
    private(set) var parameters:[String: Any]
    private let size:Int
    private let format:String
    
    public init(ra: Float, dec: Float, size: Int = 900, filters:PS1Filter = .grizy, format: PS1FileType = .fits, imageTypes: [PS1ImageType] = [.stack]) {
        self.parameters = [:]
        parameters["filters"] = filters.id as Any
        parameters["type"] = imageTypes.map{$0.id}.joined(separator: ",") as Any
                           parameters["position"] = "\(ra) \(dec)" as Any
        parameters["ra"] = ra as Any
        parameters["dec"] = dec as Any
        self.format = format.id
        self.size = size
    }

    func getFileListRequest()->URLRequest {
        let ra = self.parameters["ra"]! as! Float
        let dec = self.parameters["dec"]! as! Float
        var request = URLRequest(url: Foundation.URL(string: "\(self.fileListUrl)?ra=\(ra)&dec=\(dec)&size=\(size)")!)
        request.httpMethod = "POST"
        return request
    }
    
    
    func getFitsCutUrlBase() -> String {
        return "\(self.fitsCutRequestUrl)?size=\(self.size)&format=\(self.format)"
    }

    
    func getFitsColorImageUrl(fileNames: [String], outputSize: Int? = nil, format: String = "jpg") -> URL {
        let urlBase = "\(self.fitsCutRequestUrl)?size=\(self.size)&format=\(format)"
        let ra = self.parameters["ra"]! as! Float
        let dec = self.parameters["dec"]! as! Float
        var url = "\(urlBase)&ra=\(ra)&dec=\(dec)"
        if let outputSize = outputSize {
            url += "&output_size=\(outputSize)"
        }
        for (i, param) in ["red", "green", "blue"].enumerated() {
            url += "&\(param)=\(fileNames[i])"
        }
        print("getFitsColorImageUrl: \(url)")
return URL(string:url.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!)!
    }
    
}
