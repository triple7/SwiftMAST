//
//  MASTTapRequest.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//

import Foundation


public struct MASTTapRequest {
    /** MAST TAP request formatter
     Creates a request Url from the API and configured parameters, with TAP sql like queries
     */
private let APIUrl = "https://mast.stsci.edu/vo-tap/api/v0.1/tic/sync"
    private let table:MASTTap
    private let fields:[String]
    private(set) var parameters:[MASTTapParameter]
    private let format:APIReturnType
    
    public init(table: MASTTap, fields: [String], parameters: [MASTTapParameter], format: APIReturnType = .json) {
        self.table = table
        self.fields = fields
        self.parameters = parameters
        self.format = format
    }
    

    public init(format: APIReturnType = .json) {
        self.table = .dbo_catalog_record
        self.fields = []
        self.parameters = []
        self.format = format
    }

    
    public func getSelectQuery() -> String {
        let selectFields = fields.joined(separator: ",")
        let conditions = parameters.map{$0.getPredicate()}.joined(separator: " ")
        return "select \(selectFields) from \(table) where \(conditions)"
        }
    
    
    public func getUrl(_ query: String? = nil) -> URL {
        var url = URLComponents(string: APIUrl)
        let tapQuery = query != nil ? query! : self.getSelectQuery()
        url!.queryItems = [
            URLQueryItem(name: "query", value: tapQuery),
            URLQueryItem(name: "request", value: "doQuery"),
            URLQueryItem(name: "lang", value: "ADQL-2.0"),
            URLQueryItem(name: "format", value: self.format.id)
        ]
        return url!.url!
    }
    
    
}

