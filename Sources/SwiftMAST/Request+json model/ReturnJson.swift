//
//  ReturnJson.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

public enum QValue:Codable {
    /** Quantum value which collapses to a working type
     for codable Json structs
     */
    case int(Int)
    case string(String)
    case float(Float)
    case bool(Bool)
    
    public init(from decoder: Decoder) throws {
        if let int = try? decoder.singleValueContainer().decode(Int.self) {
            self = .int(int)
            return
        }

        if let float = try? decoder.singleValueContainer().decode(Float.self) {
            self = .float(float)
            return
        }
        
        if let bool = try? decoder.singleValueContainer().decode(Bool.self) {
            self = .bool(bool)
            return
        }
        
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self = .string(string)
            return
        }
  
        self = .string("null")
//        throw QuantumError.missingValue
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
    
    enum QuantumError:Error {
        case missingValue
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
    let data:[[String:QValue]]

    private enum CodingKeys:String, CodingKey {
        case status = "status"
        case msg = "msg"
        case paging = "paging"
        case percent_complete = "percent complete"
        case fields = "fields"
        case data = "data"
            }
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
