//
//  ReturnJson.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

public enum QValue {
    /** Quantum value which collapses to a working type
     for codable Json structs
     */
    case int(Int)
    case string(String)
    case float(Float)
    case bool(Bool)
}

extension QValue:Codable {
    private enum CodingKeys:String, CodingKey {
        case values = "values"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleContainer = try decoder.singleValueContainer()
        
        let values = try container.decode(String.self, forKey: .values)
        switch values {
        case "int":
            let int = try singleContainer.decode(Int.self)
            self = .int(int)
        case "string":
            let string = try singleContainer.decode(String.self)
            self = .string(string)
        case "float":
            let float = try singleContainer.decode(Float.self)
            self = .float(float)
        case "bool":
            let bool = try singleContainer.decode(Bool.self)
            self = .bool(bool)
        default:
            fatalError("Unavailable data type")
        }
    }

    init(value: String) {
        if let int = Int(value) {
            self = .int(int)
            return
        }
        if let float = Float(value) {
            self = .float(float)
            return
        }
        if let bool = Bool(value) {
            self = .bool(bool)
            return
        }
            self = .string(value)
    }

    public func encode(to encoder: Encoder) throws {
        var singleContainer = encoder.singleValueContainer()
        
        switch self {
        case .int(let int):
            try singleContainer.encode(int)
        case .string(let string):
            try singleContainer.encode(string)
        case .float(let float):
            try singleContainer.encode(float)
        case .bool(let bool):
            try singleContainer.encode(bool)
        }
    }

    public var value:Any {
        switch self {
        case .string(let str):
            return str
        case .float(let ft):
            return ft
        case .bool(let b):
            return b
        case .int(let n):
            return n
        }
    }
    
}

// Mark: JsonPayload structure hierarchy for the MAST json returns

public typealias ReturnJson = MASTJsonPayload

public struct MASTJsonPayload:Decodable {
    let status:String
    let msg:String
    let paging:MASTJsonPaging
    var percent_complete:Int?
    let fields:[MASTJsonField]
    let data:[FilterValues]
    
}

public struct MASTJsonPaging:Decodable {
    let page:Int
let pageSize:Int
    let pagesFiltered:Int
    let rows:Int
    let rowsFiltered:Int
    let rowsTotal:Int
}

public struct MASTJsonField:Decodable {
    let name:String
    let type:String
}

public struct NameLookupJson:Codable {
    let ra:Float
    let cached:Bool
    let resolverTime:Int
    let dec:Float
    let resolver:String
    let canonicalName:String
    let radius:Float
    let objectType:String
    let searchRadius:Float
    let searchString:String

    public init(data: [QValue], fields: [String]) {
        ra = data[fields.firstIndex(of: "ra")!].value as! Float
        cached = data[fields.firstIndex(of: "cached")!].value as! Bool
        resolverTime = data[fields.firstIndex(of: "resolverTime")!].value as! Int
        dec = data[fields.firstIndex(of: "dec")!].value as! Float
        resolver = data[fields.firstIndex(of: "resolver")!].value as! String
        canonicalName = data[fields.firstIndex(of: "canonicalName")!].value as! String
        radius = data[fields.firstIndex(of: "radius")!].value as! Float
        objectType = data[fields.firstIndex(of: "objectType")!].value as! String
        searchRadius = data[fields.firstIndex(of: "searchRadius")!].value as! Float
        searchString = data[fields.firstIndex(of: "searchString")!].value as! String
    }
    
}
