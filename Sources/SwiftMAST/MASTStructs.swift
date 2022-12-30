//
//  File.swift
//  
//
//  Created by Yuma decaux on 28/12/2022.
//

import Foundation

public struct MASTTarget {
    /** Initial key value pair return type
     for all MAST search table requests.
     The dictionary is further processed from the associated search type
     */
    private let header:[String]
    private let data:[[String]]
    
    public init(header: [String], data:[[String]]) {
        self.header = header
        self.data = data
    }
    
    public func headers()->[String] {
        return self.header
    }
}

public struct MASTJson:Encodable {
    /** json representation for a MAST Api json payload
     */
    let service:String
    let params:MASTJsonParams
}

public struct MASTJsonParams:Encodable {
    /** MAST API request payload parameters in json
     note: not all parameters are required
     */
    var columns:String?
    var filters:String?
    var paramName:String?
    var values:String?
    var separator:String?
    var freeText:String?
    var ra:Float?
    var dec:Float?
    var radius:Float?
    var raColumn:String?
    var decColumn:String?
    var exclude_hla:Bool?
    var position:String?
    var obsid:Int?
    var nr:Int?
    var ni:Int?
    var magtype:Int?
    var input:String?
    var format:String
    var url:String?
    var maxrecords:Int?
}

public struct MASTRequest {
    /** MAST archive request formatter
     Creates a request Url from the API and configured parameters,
     */
    private let APIUrl = "https://archive.stsci.edu/dataSet/search.php?action=Search"
    private let scsAPIUrl =  "https://archive.stsci.edu/dataSet/search.php?"
    private let apiRequestUrl = "https://mast.stsci.edu/api/v0/invoke"
    private let apiDownloadUrl = "https://mast.stsci.edu/api/v0.1/Download/"
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
    
    public func getURL(dataSet: MASTDataSet)->URL {
        /** Returns a formatted request Url
         Parameters:
         dataSet: The MAST data set subfolder
         */
        var path = (self.searchType == .mission) ? APIUrl : scsAPIUrl
        path = path.replacingOccurrences(of: "dataSet", with: dataSet.id)
        var url = URLComponents(string: path)
        url!.queryItems = Array(parameters.keys).map {URLQueryItem(name: $0, value: parameters[$0]!)}
            return url!.url!
        }

    func getApiUrl()->URL {
        let path = (self.searchType == .apiRequest) ? apiRequestUrl : apiDownloadUrl
        let url = URLComponents(string: path)
        return url!.url!
    }
}
