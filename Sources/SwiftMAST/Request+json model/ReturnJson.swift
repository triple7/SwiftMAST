//
//  ReturnJson.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

public enum QValue: Hashable, Identifiable {
    /** Quantum value which collapses to a working type
     for codable Json structs
     */
    case int(Int)
    case string(String)
    case float(Float)
    case bool(Bool)
    
    public var id: Self {
        return self
    }
    
    public func type() -> String {
        switch self {
        case .string(_): return "String"
                     case .int(_): return
                     "int"
                     case .float(_): return
                     "float"
                     case .bool(_): return "bool"
        }
    }
}
extension QValue:Codable {

    public init(from decoder: Decoder) throws {
        if let intValue = try? decoder.singleValueContainer().decode(Int.self) {
            self = .int(intValue)
            return
        }
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let floatValue = try? decoder.singleValueContainer().decode(Float.self) {
            self = .float(floatValue)
            return
        }
        if let boolValue = try? decoder.singleValueContainer().decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        
        // This is a NULL value so keep as empty string
        // instead of throwing error
        // The removenullrecord flag in the request
        // will omit these key/value pairs
        self = .string("")
    }

    public init(value: String) {
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
    let data:[[String:QValue]]
    

    enum CodingKeys: String, CodingKey {
        case status, msg, paging, percent_complete, fields, data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        status = try container.decode(String.self, forKey: .status)
        msg = try container.decode(String.self, forKey: .msg)
        paging = try container.decode(MASTJsonPaging.self, forKey: .paging)
        percent_complete = try container.decodeIfPresent(Int.self, forKey: .percent_complete)
        fields = try container.decode([MASTJsonField].self, forKey: .fields)
        
        // Decode data
        var dataContainer = try container.nestedUnkeyedContainer(forKey: .data)
        var dataArray: [[String: QValue]] = []
        
        while !dataContainer.isAtEnd {
            let dictionary = try dataContainer.decodeIfPresent([String: QValue].self)
            if let existingValue = dictionary {
                dataArray.append(existingValue)
            }
        }
        
        data = dataArray
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
    public let ra:Float
    public let cached:Bool
    public let resolverTime:Int
    public let dec:Float
    public let resolver:String
    public let canonicalName:String
    public let radius:Float
    public let objectType:String
    public let searchRadius:Float
    public let searchString:String

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


// Mark: Equatable MAST return Json for time adjustments

public struct CoamResult:Codable, Comparable {
    public let calib_level:Int
    public let dataRights:String
    public let dataURL:String
    public let dataproduct_type:String
    public let distance:Int
    public let em_max:Int
    public let em_min:Int
    public let filters:String
    public let instrument_name:String
    public let intentType:String
    public let jpegURL:String
    public let mtFlag:Bool
    public let objID:Int
    public let obs_collection:String
    public let obs_id:String
    public let obs_title:String
    public let obsid:Int
    public let project:String
    public let proposal_id:String
    public let proposal_pi:String
    public let proposal_type:String
    public let provenance_name:String
    public let s_dec:QValue
    public let s_ra:QValue
    public let s_region:String
    public let sequence_number:Int
    public let srcDen:Int
    public let t_exptime:Float
    public let t_max:Float
    public let t_min:Float
    public let t_obs_release:Float
    public let target_classification:String
    public let target_name:String
    public let wavelength_region:String

    public static func ==(lhs: CoamResult, rhs: CoamResult) -> Bool {
        return lhs.obs_id == rhs.obs_id && lhs.filters == rhs.filters && lhs.instrument_name == rhs.instrument_name && lhs.t_min == rhs.t_min && lhs.t_max == rhs.t_max
    }

    public static func <(lhs: CoamResult, rhs: CoamResult) -> Bool {
        return lhs.t_min < rhs.t_min
    }
    
}

extension CoamResult {
    public init(data: [QValue]) {
        self.calib_level = data[0].value as! Int
        self.dataRights = data[1].value as! String
        self.dataURL = data[2].value as! String
        self.dataproduct_type = data[3].value as! String
        if let distance = data[4].value as? Int {
            self.distance = distance
        } else {
            self.distance = 0
        }
        if let em_max = data[5].value as? Int {
            self.em_max = em_max
        } else {
            self.em_max = 0
        }
        if let em_min = data[6].value as? Int {
            self.em_min = em_min
        } else {
            self.em_min = 0
        }
        self.filters = data[7].value as! String
        self.instrument_name = data[8].value as! String
        self.intentType = data[9].value as! String
        self.jpegURL = data[10].value as! String
        if let mtFlag = data[11].value as? Bool {
                    self.mtFlag = mtFlag
        } else {
            self.mtFlag = false
        }
        if let objID = data[10].value as? Int {
            self.objID = objID
        } else {
            self.objID = 0
        }
        self.obs_collection = data[13].value as! String
        self.obs_id = data[14].value as! String
        self.obs_title = data[15].value as! String
        if let obsid = data[16].value as? Int {
            self.obsid = obsid
        } else {
            self.obsid = 0
        }
        self.project = data[17].value as! String
        self.proposal_id = data[18].value as! String
        self.proposal_pi = data[19].value as! String
        self.proposal_type = data[20].value as! String
        self.provenance_name = data[21].value as! String
        self.s_dec = data[22]
        self.s_ra = data[23]
        self.s_region = data[24].value as! String
        if let sequence_number = data[25].value as? Int {
            self.sequence_number = sequence_number
        } else {
            self.sequence_number = 0
        }
        if let srcDen = data[26].value as? Int {
                    self.srcDen = srcDen
        } else {
            self.srcDen = 0
        }
        if let t_exptime = data[27].value as? Float {
                    self.t_exptime = t_exptime
        } else {
            self.t_exptime = 0
        }
        if let t_max = data[28].value as? Float {
                    self.t_max = t_max
        } else {
            self.t_max = 0
        }
        if let t_min = data[29].value as? Float {
                    self.t_min = t_min
        } else {
            self.t_min = 0
        }
        if let t_obs_release = data[30].value as? Float {
                    self.t_obs_release = t_obs_release
        } else {
            self.t_obs_release = 0
        }
        self.target_classification = data[31].value as! String
        self.target_name = data[32].value as! String
        self.wavelength_region = data[33].value as! String
    }
    
}
