//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation


public struct MASTJson:Encodable {
    /** json representation for a MAST Api json payload
     */
    let service:String
    let params:MASTJsonParams
}

public typealias MAJP = MASTJsonParams
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
    
    public init(params: [MAP: Any]) {
        self.format = params[MAP.format] as! String
        for k in params.keys {
            switch k {
            case .columns: self.columns = params[k] as? String
            case .filters: self.filters = params[k] as? String
            case .paramName: self.paramName = params[k] as? String
            case .values: self.values = params[k] as? String
            case .separator: self.separator = params[k] as? String
            case .freeText: self.freeText = params[k] as? String
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
            case .format: break
            case .url: self.url = params[k] as? String
            case .maxrecords: self.maxrecords = params[k] as? Int
            }
             }
    }
}

