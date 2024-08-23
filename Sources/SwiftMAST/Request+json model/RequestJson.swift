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
    var data:CrossmatchInput?
    var params:MAJP?
    var format:String?
    var pagesize:Int?
    var page:Int?
    var removecache:Bool?
    var timeout:Int?
    var removenullcolumns:Bool?
    // Custom properties
    var targetId:String?

    // Getters
    public func getTargetId() -> String {
        return self.targetId!
    }
    
    // Mark: custom targetId for returning key
    public mutating func setTargetId(targetId: String) {
        self.targetId = targetId
    }
    
    // Mark: Json request general parameters
    
    public mutating func setGeneralParameter( params: [MAP: Any]) {
        for param in params.keys {
            setGeneralParameter(param: param, value: params[param]!)
        }
    }
    
    public mutating func setGeneralParameter(param: MAP, value: Any) {
        print("param \(param) value: \(value)")
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
    
    public mutating func setParameters(params: [MAP: Any]) {
        for param in params.keys {
            setParameter(param: param, value: params[param]!)
        }
    }

    public mutating func setParameter( param: MAP, value: Any) {
        print("set parameter \(param) value \(value)")
        self.params?.setParameter(parameter: param, value: value)
    }
    
    // Mark: request Json advanced filter parameters
    
    public mutating func setFilterParameters(params: [MASTJsonFilter]) {
print("setting filter parameters: \(params) ")
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
    
    public init(params: [MAP: Any]) {
        for k in params.keys {
            setParameter(parameter: k, value: params[k]!)
             }
    }
    
    public mutating func setParameter(parameter: MAP, value: Any) {
        print("setting param \(parameter) \(value)")
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
    
    public mutating func addFilter(paramName: String, values: FilterValues, separator: String?=nil) {
        if self.filters == nil {
            self.filters = []
        }
        self.filters?.append(MASTJsonFilter(paramName: paramName, values: values, separator: separator, freeText: ""))
    }
}

public struct MASTJsonFilter:Codable, CustomStringConvertible {
    let paramName:String
    let values:FilterValues
    var separator:String?
    var freeText:String?
    
    public init(paramName: String, values: FilterValues, separator: String? = nil, freeText: String? = nil) {
        self.paramName = paramName
        self.values = values
        self.separator = separator
        self.freeText = freeText
    }

    public var description: String {
        return self.description
    }
}

public enum FilterValues:Codable {
    case qValue(QValue)
    case qArr([QValue])
    case qDict([[String: QValue]])
    case qDictSingle([String: QValue])
    
    public init(values: Any) {
        print("init values \(values)")
        switch values {
        case let qValue as QValue:
            self = .qValue(qValue)
        case let qArr as [QValue]:
            self = .qArr(qArr)
        case let qDict as [[String: QValue]]:
            self = .qDict(qDict)
        case let qDictSingle as [String: QValue]:
            self = .qDictSingle(qDictSingle)
        default:
            fatalError("Incompatible data structure")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let qValue = try? container.decode(QValue.self) {
            self = .qValue(qValue)
        }
        if let qArr = try? container.decode([QValue].self) {
            self = .qArr(qArr)
        }
        if let qDict = try? container.decode([[String:QValue]].self) {
            self = .qDict(qDict)
        }
        if let qDictSingle = try? container.decode([String:QValue].self) {
            self = .qDictSingle(qDictSingle)
        }
            fatalError("Failed to decode FilterValues")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .qValue(let qValue):
            try container.encode(qValue)
        case .qArr(let qArr):
            try container.encode(qArr)
        case .qDict(let qDict):
            try container.encode(qDict)
        case .qDictSingle(let qDictSingle):
            try container.encode(qDictSingle)
        }
    }

}

extension FilterValues:CustomStringConvertible {
    public var description: String {
        switch self {
        case .qValue(let qValue):
            return qValue.description
        case .qArr(let qArr):
            let strArr = qArr.map{$0.description}.joined(separator: ", ")
            return "[\(strArr)]"
        case .qDict(let qDict):
            var dictArray:[String] = []
            for dict in qDict {
                let inner = dict.keys.map{"\($0): \(dict[$0]!.description)"}.joined(separator: ", ")
                dictArray.append(inner)
            }
            let output = dictArray.joined(separator: ", ")
            return "[\(output)]"
        case .qDictSingle(let qDictSingle):
            let output = qDictSingle.keys.map{"\($0): \(qDictSingle[$0]!.description)"}
            return "{\(output)}"
        }
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

