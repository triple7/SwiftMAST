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
            print("converted string to int \(value)")
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


// Mark: Equatable MAST return Json for time adjustments

public struct CoamResult:Codable, Comparable {
    let calib_level:QValue
    let dataRights:QValue
    let dataURL:QValue
    let dataproduct_type:QValue
    let distance:QValue
    let em_max:QValue
    let em_min:QValue
    let filters:QValue
    let instrument_name:QValue
    let intentType:QValue
    let jpegURL:QValue
    let mtFlag:QValue
    let objID:QValue
    let obs_collection:QValue
    let obs_id:QValue
    let obs_title:QValue
    let obsid:QValue
    let project:QValue
    let proposal_id:QValue
    let proposal_pi:QValue
    let proposal_type:QValue
    let provenance_name:QValue
    let s_dec:QValue
    let s_ra:QValue
    let s_region:QValue
    let sequence_number:QValue
    let srcDen:QValue
    let t_exptime:QValue
    let t_max:QValue
    let t_min:QValue
    let t_obs_release:QValue
    let target_classification:QValue
    let target_name:QValue
    let wavelength_region:QValue

    public static func ==(lhs: CoamResult, rhs: CoamResult) -> Bool {
        let lObsId = lhs.obs_id.value as! String
        let rObsId = rhs.obs_id.value as! String
        let lFilters = lhs.filters.value as! String
        let rFilters = rhs.filters.value as! String
        let lInstrument = lhs.instrument_name.value as! String
        let rInstrument = rhs.instrument_name.value as! String
        let lTMin = lhs.t_min.value as! Int
        let rTMin = rhs.t_min.value as! Int
        let lTMax = lhs.t_max.value as! Int
        let rtMax = rhs.t_max.value as! Int
        return lObsId == rObsId && lFilters == rFilters && lInstrument == rInstrument && lTMin == rTMin && lTMax == rtMax
    }

    public static func <(lhs: CoamResult, rhs: CoamResult) -> Bool {
        return (lhs.t_min.value as! Int) < (rhs.t_min.value as! Int)
    }
    
}

extension CoamResult {
    public init(data: [QValue]) {
        self.calib_level = data[0]
        self.dataRights = data[1]
        self.dataURL = data[2]
        self.dataproduct_type = data[3]
        self.distance = data[4]
        self.em_max = data[5]
        self.em_min = data[6]
        self.filters = data[7]
        self.instrument_name = data[8]
        self.intentType = data[9]
        self.jpegURL = data[10]
        self.mtFlag = data[11]
        self.objID = data[12]
        self.obs_collection = data[13]
        self.obs_id = data[14]
        self.obs_title = data[15]
        self.obsid = data[16]
        self.project = data[17]
        self.proposal_id = data[18]
        self.proposal_pi = data[19]
        self.proposal_type = data[20]
        self.provenance_name = data[21]
        self.s_dec = data[22]
        self.s_ra = data[23]
        self.s_region = data[24]
        self.sequence_number = data[25]
        self.srcDen = data[26]
        self.t_exptime = data[27]
        self.t_max = data[28]
        self.t_min = data[29]
        self.t_obs_release = data[30]
        self.target_classification = data[31]
        self.target_name = data[32]
        self.wavelength_region = data[33]
    }
    
}
