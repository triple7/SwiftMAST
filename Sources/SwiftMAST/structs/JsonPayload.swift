//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

enum QValue: Decodable {
    /** Quantum value which collapses to a working type
     for decodable Json returns of any type
     */
    case int(Int)
    case string(String)
    case float(Float)
    case bool(Bool)
    
    init(from decoder: Decoder) throws {
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
        
        throw QuantumError.missingValue
    }
    
    enum QuantumError:Error {
        case missingValue
    }
}

// Mark: JsonPayload structure hierarchy for the MAST json returns

public typealias JsonPayload = MASTJsonPayload

public struct MASTJsonPayload:Decodable {
    let status:String
    let msg:String
    let paging:MASTJsonPaging
    let percent_complete:String
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
    let page:QValue
let pageSize:QValue
    let pagesFiltered:QValue
    let rows:QValue
    let rowsFiltered:QValue
    let rowsTotal:QValue
}

public struct MASTJsonField:Decodable {
    let name:String
    let type:String
}

