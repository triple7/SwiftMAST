//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public struct MASTJson:Encodable {
    /** json representation for a MAST Api json request object
     */
    let service:String
    var data:[String: String]?
    var params:MAJP?
    var format:String?
    var pagesize:Int?
    var page:Int?
    var removecache:Bool?
    var timeout:Int?
    var removenullcolumns:Bool?

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
        default: break
        }
    }

    public mutating func setParameter( params: [MAP: Any]) {
        for param in params.keys {
            setParameter(param: param, value: params[param]!)
        }
    }

    public mutating func setParameter( param: MAP, value: Any) {
        self.params?.setParameter(parameter: param, value: value)
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
    
    public init(params: [MAP: Any]) {
        for k in params.keys {
            setParameter(parameter: k, value: params[k]!)
             }
    }
    
    public mutating func setParameter(parameter: MAP, value: Any) {
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
        default: break
        }
    }
}

public struct MASTJsonFilter:Encodable {
    let paramName:String
    let values:[String]
    var separator:String?
    var freeText:String?
}

