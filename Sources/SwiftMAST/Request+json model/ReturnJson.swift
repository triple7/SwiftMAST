//
//  ReturnJson.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
import SwiftQValue

// Mark: JsonPayload structure hierarchy for the MAST json returns

public typealias ReturnJson = MASTJsonPayload

public struct MASTJsonPayload: Decodable {
    var status: String?
    var msg: String?
    var paging: MASTJsonPaging?
    var percent_complete: Int?
    var fields: [MASTJsonField]?
    var data: [[String: QValue]]?
    var resolvedCoordinate: [LookupSearchResult]?

    enum CodingKeys: String, CodingKey {
        case status, msg, paging, percent_complete, fields, data, resolvedCoordinate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        status = try container.decodeIfPresent(String.self, forKey: .status)
        msg = try container.decodeIfPresent(String.self, forKey: .msg)
        paging = try container.decodeIfPresent(MASTJsonPaging.self, forKey: .paging)
        percent_complete = try container.decodeIfPresent(Int.self, forKey: .percent_complete)
        fields = try container.decodeIfPresent([MASTJsonField].self, forKey: .fields)

        resolvedCoordinate = try container.decodeIfPresent(
            [LookupSearchResult].self, forKey: .resolvedCoordinate)
        // Decode data
        if var dataContainer = try? container.nestedUnkeyedContainer(forKey: .data) {
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

}

public struct MASTJsonPaging: Decodable {
    let page: Int
    let pageSize: Int
    let pagesFiltered: Int
    let rows: Int
    let rowsFiltered: Int
    let rowsTotal: Int
}

public struct MASTJsonField: Decodable {
    let name: String
    let type: String
}

public struct NameLookupJson: Codable {
    public let ra: Float
    public let cached: Bool
    public let resolverTime: Int
    public let dec: Float
    public let resolver: String
    public let canonicalName: String
    public let radius: Float
    public let objectType: String
    public let searchRadius: Float
    public let searchString: String

    public init(data: [QValue], fields: [String]) {
        //        print("fields\n\(fields)")
        //        print("Fields count \(fields.count)")
        //        print("Data count \(data.count)")
        //        print(data)
        if let raIndex = fields.firstIndex(of: "ra"), let raValue = data[raIndex].value as? Float {
            ra = raValue
        } else {
            ra = 0.0
        }

        if let cachedIndex = fields.firstIndex(of: "cached"),
            let cachedValue = data[cachedIndex].value as? Bool
        {
            cached = cachedValue
        } else {
            cached = false
        }

        if let resolverTimeIndex = fields.firstIndex(of: "resolverTime"),
            let resolverTimeValue = data[resolverTimeIndex].value as? Int
        {
            resolverTime = resolverTimeValue
        } else {
            resolverTime = 0
        }

        if let decIndex = fields.firstIndex(of: "decl"),
            let decValue = data[decIndex].value as? Float
        {
            dec = decValue
        } else {
            dec = 0.0
        }

        if let resolverIndex = fields.firstIndex(of: "resolver"),
            let resolverValue = data[resolverIndex].value as? String
        {
            resolver = resolverValue
        } else {
            resolver = ""
        }

        if let canonicalNameIndex = fields.firstIndex(of: "canonicalName"),
            let canonicalNameValue = data[canonicalNameIndex].value as? String
        {
            canonicalName = canonicalNameValue
        } else {
            canonicalName = ""
        }

        if let radiusIndex = fields.firstIndex(of: "radius"),
            let radiusValue = data[radiusIndex].value as? Float
        {
            radius = radiusValue
        } else {
            radius = 0.0
        }

        if let objectTypeIndex = fields.firstIndex(of: "objectType"),
            let objectTypeValue = data[objectTypeIndex].value as? String
        {
            objectType = objectTypeValue
        } else {
            objectType = ""
        }

        if let searchRadiusIndex = fields.firstIndex(of: "searchRadius"),
            let searchRadiusValue = data[searchRadiusIndex].value as? Float
        {
            searchRadius = searchRadiusValue
        } else {
            searchRadius = 0.0
        }

        if let searchStringIndex = fields.firstIndex(of: "searchString"),
            let searchStringValue = data[searchStringIndex].value as? String
        {
            searchString = searchStringValue
        } else {
            searchString = ""
        }
    }
}

// Mark: Equatable MAST return Json for time adjustments

public struct CoamResult: Codable, Comparable, Hashable, CustomStringConvertible {
    public let calib_level: Int
    public let dataRights: String
    public let dataURL: String
    public let dataproduct_type: String
    public let distance: Int
    public let em_max: Int
    public let em_min: Int
    public let filters: String
    public let instrument_name: String
    public let intentType: String
    public let jpegURL: String
    public let mtFlag: Bool
    public let objID: Int
    public let obs_collection: String
    public let obs_id: String
    public let obs_title: String
    public let obsid: Int
    public let project: String
    public let proposal_id: String
    public let proposal_pi: String
    public let proposal_type: String
    public let provenance_name: String
    public let s_dec: QValue
    public let s_ra: QValue
    public let s_region: String
    public let s_region_area: Double?
    public let sequence_number: Int
    public let srcDen: Int
    public let t_exptime: Float
    public let t_max: Float
    public let t_min: Float
    public let t_obs_release: Float
    public let target_classification: String
    public let target_name: String
    public let wavelength_region: String
    /// Artifact filename returned by CAOM TAP, when that query profile selects it.
    public let productFilename: String?
    /// MIME type reported for the selected CAOM artifact.
    public let artifactContentType: String?
    /// Optional image width reported by the CAOM plane (`posdimension1`).
    public let positionDimension1: Int?
    /// Optional image height reported by the CAOM plane (`posdimension2`).
    public let positionDimension2: Int?
    /// Optional median pixel scale reported by the CAOM plane (`possamplesize`).
    public let positionSampleSize: Double?
    public var dataURLSizeBytes: Int64? = nil
    public var jpegURLSizeBytes: Int64? = nil
    public var fitsImageHeaderMetadata: FITSImageHeaderMetadata? = nil
    public var localResources: CoamLocalResources? = nil

    public var preferredDownloadSizeBytes: Int64? {
        dataURLSizeBytes ?? jpegURLSizeBytes
    }

    public var s_region_area_unit: String {
        SpaceRegionArea.unit
    }

    public var dataURLSizeDescription: String? {
        Self.byteCountDescription(dataURLSizeBytes)
    }

    public var jpegURLSizeDescription: String? {
        Self.byteCountDescription(jpegURLSizeBytes)
    }

    public var preferredDownloadSizeDescription: String? {
        Self.byteCountDescription(preferredDownloadSizeBytes)
    }

    public var description: String {
        return """
                    \(target_name)
                    \(target_classification)
                    \(instrument_name)
                    \(wavelength_region)
                    \(filters)
                    \(dataURL)
                    \(jpegURL)
            """

    }

    public static func == (lhs: CoamResult, rhs: CoamResult) -> Bool {
        return lhs.obs_id == rhs.obs_id && lhs.filters == rhs.filters
            && lhs.instrument_name == rhs.instrument_name && lhs.t_min == rhs.t_min
            && lhs.t_max == rhs.t_max
    }

    public static func < (lhs: CoamResult, rhs: CoamResult) -> Bool {
        return lhs.t_min < rhs.t_min
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(obs_id)
        hasher.combine(filters)
        hasher.combine(instrument_name)
        hasher.combine(t_min)
        hasher.combine(t_max)
    }

}

extension CoamResult {
    public init(
        calib_level: Int,
        dataRights: String,
        dataURL: String,
        dataproduct_type: String,
        distance: Int,
        em_max: Int,
        em_min: Int,
        filters: String,
        instrument_name: String,
        intentType: String,
        jpegURL: String,
        mtFlag: Bool,
        objID: Int,
        obs_collection: String,
        obs_id: String,
        obs_title: String,
        obsid: Int,
        project: String,
        proposal_id: String,
        proposal_pi: String,
        proposal_type: String,
        provenance_name: String,
        s_dec: QValue,
        s_ra: QValue,
        s_region: String,
        sequence_number: Int,
        srcDen: Int,
        t_exptime: Float,
        t_max: Float,
        t_min: Float,
        t_obs_release: Float,
        target_classification: String,
        target_name: String,
        wavelength_region: String,
        dataURLSizeBytes: Int64? = nil,
        jpegURLSizeBytes: Int64? = nil,
        fitsImageHeaderMetadata: FITSImageHeaderMetadata? = nil,
        localResources: CoamLocalResources? = nil,
        productFilename: String? = nil,
        artifactContentType: String? = nil,
        positionDimension1: Int? = nil,
        positionDimension2: Int? = nil,
        positionSampleSize: Double? = nil
    ) {
        self.calib_level = calib_level
        self.dataRights = dataRights
        self.dataURL = dataURL
        self.dataproduct_type = dataproduct_type
        self.distance = distance
        self.em_max = em_max
        self.em_min = em_min
        self.filters = filters
        self.instrument_name = instrument_name
        self.intentType = intentType
        self.jpegURL = jpegURL
        self.mtFlag = mtFlag
        self.objID = objID
        self.obs_collection = obs_collection
        self.obs_id = obs_id
        self.obs_title = obs_title
        self.obsid = obsid
        self.project = project
        self.proposal_id = proposal_id
        self.proposal_pi = proposal_pi
        self.proposal_type = proposal_type
        self.provenance_name = provenance_name
        self.s_dec = s_dec
        self.s_ra = s_ra
        self.s_region = s_region
        self.s_region_area = SpaceRegionArea.squareDegrees(from: s_region)
        self.sequence_number = sequence_number
        self.srcDen = srcDen
        self.t_exptime = t_exptime
        self.t_max = t_max
        self.t_min = t_min
        self.t_obs_release = t_obs_release
        self.target_classification = target_classification
        self.target_name = target_name
        self.wavelength_region = wavelength_region
        self.productFilename = productFilename
        self.artifactContentType = artifactContentType
        self.positionDimension1 = positionDimension1
        self.positionDimension2 = positionDimension2
        self.positionSampleSize = positionSampleSize
        self.dataURLSizeBytes = dataURLSizeBytes
        self.jpegURLSizeBytes = jpegURLSizeBytes
        self.fitsImageHeaderMetadata = fitsImageHeaderMetadata
        self.localResources = localResources
    }

    public init(data: [QValue]) {
        self.init(
            calib_level: Self.intValue(data, at: 0),
            dataRights: Self.stringValue(data, at: 1),
            dataURL: Self.stringValue(data, at: 2),
            dataproduct_type: Self.stringValue(data, at: 3),
            distance: Self.intValue(data, at: 4),
            em_max: Self.intValue(data, at: 5),
            em_min: Self.intValue(data, at: 6),
            filters: Self.stringValue(data, at: 7),
            instrument_name: Self.stringValue(data, at: 8),
            intentType: Self.stringValue(data, at: 9),
            jpegURL: Self.stringValue(data, at: 10),
            mtFlag: Self.boolValue(data, at: 11),
            objID: Self.intValue(data, at: 12),
            obs_collection: Self.stringValue(data, at: 13),
            obs_id: Self.stringValue(data, at: 14),
            obs_title: Self.stringValue(data, at: 15),
            obsid: Self.intValue(data, at: 16),
            project: Self.stringValue(data, at: 17),
            proposal_id: Self.stringValue(data, at: 18),
            proposal_pi: Self.stringValue(data, at: 19),
            proposal_type: Self.stringValue(data, at: 20),
            provenance_name: Self.stringValue(data, at: 21),
            s_dec: Self.qValue(data, at: 22),
            s_ra: Self.qValue(data, at: 23),
            s_region: Self.stringValue(data, at: 24),
            sequence_number: Self.intValue(data, at: 25),
            srcDen: Self.intValue(data, at: 26),
            t_exptime: Self.floatValue(data, at: 27),
            t_max: Self.floatValue(data, at: 28),
            t_min: Self.floatValue(data, at: 29),
            t_obs_release: Self.floatValue(data, at: 30),
            target_classification: Self.stringValue(data, at: 31),
            target_name: Self.stringValue(data, at: 32),
            wavelength_region: Self.stringValue(data, at: 33)
        )
    }

    public func withFileSizes(dataURLSizeBytes: Int64?, jpegURLSizeBytes: Int64?) -> CoamResult {
        var copy = self
        copy.dataURLSizeBytes = dataURLSizeBytes
        copy.jpegURLSizeBytes = jpegURLSizeBytes
        return copy
    }

    public func withFITSImageHeaderMetadata(_ metadata: FITSImageHeaderMetadata?) -> CoamResult {
        var copy = self
        copy.fitsImageHeaderMetadata = metadata
        return copy
    }

    private static func byteCountDescription(_ byteCount: Int64?) -> String? {
        guard let byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func qValue(_ data: [QValue], at index: Int) -> QValue {
        guard data.indices.contains(index) else { return QValue(value: "") }
        return data[index]
    }

    private static func stringValue(_ data: [QValue], at index: Int) -> String {
        let value = qValue(data, at: index).value
        if let string = value as? String { return string }
        return String(describing: value)
    }

    private static func intValue(_ data: [QValue], at index: Int) -> Int {
        let value = qValue(data, at: index).value
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let float = value as? Float { return Int(float) }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func floatValue(_ data: [QValue], at index: Int) -> Float {
        let value = qValue(data, at: index).value
        if let float = value as? Float { return float }
        if let double = value as? Double { return Float(double) }
        if let int = value as? Int { return Float(int) }
        if let string = value as? String { return Float(string) ?? 0 }
        return 0
    }

    private static func boolValue(_ data: [QValue], at index: Int) -> Bool {
        let value = qValue(data, at: index).value
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String {
            return ["true", "1", "yes"].contains(string.lowercased())
        }
        return false
    }

}

struct LookupSearchResult: Codable {
    let searchString: String
    let resolver: String
    let cached: Bool
    let resolverTime: Int
    let searchRadius: Double
    let canonicalName: String
    let ra: Double
    let decl: Double
    let radius: Double
    let objectType: String

    enum CodingKeys: String, CodingKey {
        case searchString, resolver, cached, resolverTime, searchRadius, canonicalName, ra, decl,
            radius, objectType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        searchString = try container.decode(String.self, forKey: .searchString)
        resolver = try container.decode(String.self, forKey: .resolver)
        cached = try container.decode(Bool.self, forKey: .cached)
        resolverTime = try container.decode(Int.self, forKey: .resolverTime)
        searchRadius = try container.decode(Double.self, forKey: .searchRadius)
        canonicalName = try container.decode(String.self, forKey: .canonicalName)
        ra = try container.decode(Double.self, forKey: .ra)
        decl = try container.decode(Double.self, forKey: .decl)
        objectType = try container.decode(String.self, forKey: .objectType)

        // Decode optional property
        do {
            radius = try container.decode(Double.self, forKey: .radius)
        } catch let error {
            print("Radius not present: \(error.localizedDescription) Defaulting to 0.02 arcsec")
            radius = 0.02
        }
        //        radius = try container.decodeIfPresent(Double.self, forKey: .radius)
    }

}
