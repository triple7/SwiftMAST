//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

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

