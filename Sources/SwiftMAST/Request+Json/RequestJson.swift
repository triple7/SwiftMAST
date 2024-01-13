//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

enum RequestParam:String, CaseIterable {case intentType
case obs_collection
case provenance_name
case instrument_name
case project
case filters
case wavelength_region
case target_name
case target_classification
case obs_id
case s_ra
case s_dec
case dataproduct_type
case proposal_pi
case calib_level
case t_min
case t_max
case t_exptime
case em_min
case em_max
case obs_title
case t_obs_release
case proposal_id
case proposal_type
case sequence_number
case s_region
case jpegURL
case dataURL
case dataRights
case mtFlag
case srcDen
case obsid
case distance
}

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

    // Mark: Json request general parameters
    
    public mutating func setGeneralParameter( params: [MAP: Any]) {
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

    // mark: request Json service parameters
    
    public mutating func setParameter(params: [MAP: Any]) {
        print("parameters to set \n \(params)")
        for param in params.keys {
            setParameter(param: param, value: params[param]!)
        }
    }

    public mutating func setParameter( param: MAP, value: Any) {
        print("Setting parameter \(param)")
        self.params?.setParameter(parameter: param, value: value)
    }
    
    // Mark: request Json advanced filter parameters
    
    public mutating func setFilterParameters(params: [[MAP: Any]]) {
        print("Setting filter parameters")
        self.setParameter(params: [MAP.filters: params as Any])
    }
    
    public mutating func setFilterParameter( param: MAP, value: Any) {
        
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
    
    public mutating func addFilter(paramName: String, values: [Any], separator: String?=nil) {
        if self.filters == nil {
            self.filters = []
        }
        self.filters?.append(MASTJsonFilter(paramName: paramName, values: values.map{$0 as! String}, separator: separator))
    }
}

public struct MASTJsonFilter:Encodable {
    let paramName:String
    let values:Array<String>
    var separator:String?
    var freeText:String?
}

