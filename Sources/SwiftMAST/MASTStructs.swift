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

public struct MASTRequest {
    /** MAST archive request formatter
     Creates a request Url from the API and configured parameters,
     */
    private let APIUrl = "https://archive.stsci.edu/dataSet/search.php?action=Search"
    private let scsAPIUrl =  "https://archive.stsci.edu/dataSet/search.php?"
    private(set) var parameters:[String: String]
    let searchType:MASTSearchType
    
    public init(searchType: MASTSearchType, parameters: [MGP: Any]) {
        self.searchType = searchType
        self.parameters = [String:String]()
        for key in parameters.keys {
            self.parameters[key.id] = parameters[key] as? String ?? ""
        }
    }

    public func getURL(dataSet: MASTDataSet)->URL {
        /** Returns a formatted request Url
         Parameters:
         dataSet: The MAST data set subfolder
         */
        var url = URLComponents(string: (self.searchType == .mission) ? APIUrl : scsAPIUrl)
        url!.queryItems = Array(parameters.keys).map {URLQueryItem(name: $0, value: parameters[$0]!)}
            return url!.url!
        }

}
