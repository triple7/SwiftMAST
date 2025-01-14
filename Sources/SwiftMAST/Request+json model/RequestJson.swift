//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
import SwiftQValue


public struct MASTJson:Encodable, CustomStringConvertible {
    /** json representation for a MAST Api json request object
     */
    let service:String
    var data:CrossmatchInput?
    var params:MAJP?
    var format:String?
    var pagesize:Int?
    var page:Int?
    var removecache:Bool?
    var timeout:Int?
    var removenullcolumns:Bool?
    // Custom properties
    
    // Mark: print helper
    public var description:String {
        do {
            let jsonData = try JSONEncoder().encode(self)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                return ""
            }
        } catch {
            print("Failed to encode object to JSON: \(error)")
        return ""
        }
    }
    // Mark: Json request general parameters
    
    public mutating func setGeneralParameters( params: [MAP: Any]) {
        for param in params.keys {
            setGeneralParameter(param: param, value: params[param]!)
        }
    }
    
    public mutating func setGeneralParameter(param: MAP, value: Any) {
        switch param {
        case .pagesize: self.pagesize = value as? Int
        case .page: self.page = value as? Int
        case .removecache: self.removecache = value as? Bool
        case .timeout: self.timeout = value as? Int
        case .removenullcolumns: self.removenullcolumns = value as? Bool
        case .format: self.format = value as? String
        default: break
        }
    }

    // mark: request Json service parameters
    
    public mutating func setParameters(params: [MAP: Any]) {
        for param in params.keys {
            setParameter(param: param, value: params[param]!)
        }
    }

    public mutating func setParameter( param: MAP, value: Any) {
        print("set parameter \(param) value \(value)")
        print("internal params: \(self.params)")
        self.params?.setParameter(parameter: param, value: value)
    }
    
    // Mark: request Json advanced filter parameters
    
    public mutating func setFilterParameters(params: [MASTJsonFilter]) {
        self.setParameters(params: [MAP.filters: params as Any])
    }
    
    public mutating func setFilterParameter( param: MAP, value: Any) {
        
    }
    
    // Mark: RequestJson input data parameters
public mutating func setCrossmatchinput(coordinates: [[String: Float]]) {
        var cmData = [CrossmatchData]()
        for coordinate in coordinates {
            let ra = coordinate["ra"]!
            let dec = coordinate["dec"]!
            if let radius = coordinate["radius"] {
                cmData.append(CrossmatchData(ra: ra, dec: dec, radius: radius))
            } else {
                cmData.append(CrossmatchData(ra: ra, dec: dec))
            }
        }
    self.data = CrossmatchInput(fields: [CrossmatchField(name: "ra", type: "float"), CrossmatchField(name: "dec", type: "float"), CrossmatchField(name: "radius", type: "float")], data: cmData)
    }

}

public typealias MAJP = MASTJsonParams

public struct MASTJsonParams:Encodable {
    /** MAST API request parameters
     */
    var columns:String?
    var filters:[MASTJsonFilter]?
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
    var url:String?
    var maxrecords:Int?
    var format:String?
    
    public init(params: [MAP: Any]) {
        for k in params.keys {
            setParameter(parameter: k, value: params[k]!)
             }
    }
    
    public mutating func setParameter(parameter: MAP, value: Any) {
        print("setParameter: \(parameter) value: \(value)")
        switch parameter {
        case .columns: self.columns = value as? String
        case .filters: self.filters = value as? [MASTJsonFilter]
        case .ra: self.ra = value as? Float
        case .dec: self.dec = value as? Float
        case .radius: self.radius = value as? Float
        case .raColumn: self.raColumn = value as? String
        case .decColumn: self.decColumn = value as? String
        case .exclude_hla: self.exclude_hla = value as? Bool
        case .position: self.position = value as? String
        case .obsid: self.obsid = value as? Int
        case .nr: self.nr = value as? Int
        case .ni: self.ni = value as? Int
        case .magtype: self.magtype = value as? Int
        case .input: self.input = value as? String
        case .url: self.url = value as? String
        case .maxrecords: self.maxrecords = value as? Int
        case .format: self.format = value as? String
        default: break
        }
    }
    
    public mutating func addFilter(paramName: String, values: QObject, separator: String?=nil) {
        if self.filters == nil {
            self.filters = []
        }
        self.filters?.append(MASTJsonFilter(paramName: paramName, values: values, separator: separator, freeText: ""))
    }
}

public struct MASTJsonFilter:Codable {
    let paramName:String
    let values:QObject
    var separator:String?
    var freeText:String?
    
    public init(paramName: String, values: QObject, separator: String? = nil, freeText: String? = nil) {
        self.paramName = paramName
        self.values = values
        self.separator = separator
        self.freeText = freeText
    }
    
    
}


// Mark: CrossMatch input

public struct CrossmatchInput:Codable {
    let fields:[CrossmatchField]
    let data:[CrossmatchData]
}

public struct CrossmatchField:Codable {
    let name:String
    let type:String
}

public struct CrossmatchData:Codable {
    let ra:Float
    let dec:Float
    var radius:Float?
}

