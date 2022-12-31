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
            switch k {
            case .columns: self.columns = params[k] as? String
            case .filters: self.filters = params[k] as? [MASTJsonFilter]
            case .ra: self.ra = params[k] as? Float
            case .dec: self.dec = params[k] as? Float
            case .radius: self.radius = params[k] as? Float
            case .raColumn: self.raColumn = params[k] as? String
            case .decColumn: self.decColumn = params[k] as? String
            case .exclude_hla: self.exclude_hla = params[k] as? Bool
            case .position: self.position = params[k] as? String
            case .obsid: self.obsid = params[k] as? Int
            case .nr: self.nr = params[k] as? Int
            case .ni: self.ni = params[k] as? Int
            case .magtype: self.magtype = params[k] as? Int
            case .input: self.input = params[k] as? String
            case .url: self.url = params[k] as? String
            case .maxrecords: self.maxrecords = params[k] as? Int
            default: break
            }
             }
    }
}

public struct MASTJsonFilter:Encodable {
    let paramName:String
    let values:[String]
    var separator:String?
    var freeText:String?
}

