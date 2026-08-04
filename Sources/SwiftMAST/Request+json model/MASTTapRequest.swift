//
//  MASTTapRequest.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//

import Foundation

public struct MASTTapRequestBody:Codable {
    let query:String
    let request:String
    let lang:String
    let format:String
    
    public init(query: String) {
        self.query = query
        self.request = "doQuery"
        self.lang = "ADQL"
        self.format = "json"
    }
}

public enum MASTTapEndpoint: String, Codable, CaseIterable, Identifiable {
    case tic
    case caom

    public var id: String { rawValue }

    public var url: URL {
        switch self {
        case .tic:
            return URL(string: "https://mast.stsci.edu/vo-tap/api/v0.1/tic/sync")!
        case .caom:
            return URL(string: "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync")!
        }
    }
}

public struct MASTTapRequest {
    /** MAST TAP request formatter
     Creates a request Url from the API and configured parameters, with TAP sql like queries
     */
    private let endpoint: MASTTapEndpoint
    private let table:MASTTap
    private let fields:[String]
    private(set) var parameters:[MASTTapParameter]
    private let format:APIReturnType
    
    public init(
        table: MASTTap,
        fields: [String],
        parameters: [MASTTapParameter],
        format: APIReturnType = .json,
        endpoint: MASTTapEndpoint = .tic
    ) {
        self.endpoint = endpoint
        self.table = table
        self.fields = fields
        self.parameters = parameters
        self.format = format
    }
    

    public init(format: APIReturnType = .json, endpoint: MASTTapEndpoint = .tic) {
        self.endpoint = endpoint
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
        var url = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        let tapQuery = query != nil ? query! : self.getSelectQuery()
        url!.queryItems = [
            URLQueryItem(name: "QUERY", value: tapQuery),
            URLQueryItem(name: "LANG", value: "ADQL"),
            URLQueryItem(name: "responseformat", value: self.format.id)
        ]
        return url!.url!
    }

    public func getBaseUrl() -> URL {
        return endpoint.url
    }

    
}
