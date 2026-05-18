//
//  JWSTObservationGroup.swift
//  SwiftMAST
//
//  Created by SwiftMAST on 12/4/2026.
//

import Foundation

/// Which mission collections to include when querying observation groups.
public enum ObservationMission: String, Codable, CaseIterable, Identifiable {
    case jwst = "JWST"
    case hst = "HST"

    public var id: String { rawValue }

    public var collectionNames: [String] {
        switch self {
        case .jwst:
            return ["JWST"]
        case .hst:
            return ["HST", "HLA"]
        }
    }

    public static var jwstOnly: [ObservationMission] { [.jwst] }
    public static var hstOnly: [ObservationMission] { [.hst] }
    public static var jwstAndHST: [ObservationMission] { [.jwst, .hst] }
}

/// How products within an ``ObservationGroup`` are sorted.
public enum ObservationProductSortOrder {
    /// Sort by filter wavelength ascending (e.g. F200W before F1000W).
    /// Products with equal wavelength are further sorted by observation start time.
    case filter

    /// Sort by observation start time ascending.
    /// Products with equal start time are further sorted by filter wavelength.
    case time
}

public typealias JWSTProductSortOrder = ObservationProductSortOrder

/// A group of products from the same observation session, sharing a mission,
/// observation key, and instrument.
///
/// Products are sorted according to the ``ObservationProductSortOrder`` used when
/// building the group.
public struct ObservationGroup: CustomStringConvertible {
    /// The mission collection for this group (e.g. "JWST", "HST")
    public let mission: String

    /// The observation group key (e.g. "jw02666-o007_t004_miri", "hst_10775_62_wfc3")
    public let observationKey: String

    /// The instrument used in this observation (e.g. "MIRI/IMAGE", "WFC3/UVIS")
    public let instrument: String

    /// Products sorted according to the sort order used when building this group.
    public let products: [CoamResult]

    /// Unique filter names in wavelength order
    public var filterNames: [String] {
        products.map { $0.filters }
    }

    /// Display color tags for each filter string in this group.
    public var filterColors: [ObservationFilterColor] {
        products.flatMap(\.filterColors)
    }

    public var description: String {
        let filters = filterNames.joined(separator: ", ")
        return "\(observationKey) [\(mission)/\(instrument)] — \(products.count) filters: \(filters)"
    }
}

public typealias JWSTObservationGroup = ObservationGroup

/// Display color metadata for a filter attached to a ``CoamResult``.
public struct ObservationFilterColor: Codable, Hashable {
    public let filterName: String
    public let mission: String
    public let colorName: String
    public let hexColor: String

    public init(filterName: String, mission: String, colorName: String, hexColor: String) {
        self.filterName = filterName
        self.mission = mission
        self.colorName = colorName
        self.hexColor = hexColor
    }
}

/// Extract the numeric wavelength from a JWST filter name for sorting.
///
/// Examples:
/// - `"F200W"` → 200
/// - `"F1000W"` → 1000
/// - `"F150W2"` → 150
/// - `"F444W;F405N"` → 444 (uses first filter in compound name)
/// - `"CLEAR"` → `Int.max` (non-standard names sort last)
public func jwstFilterWavelength(_ filterName: String) -> Int {
    observationFilterWavelength(filterName)
}

/// Extract the numeric wavelength from a filter name for sorting.
public func observationFilterWavelength(_ filterName: String) -> Int {
    // For compound filters like "F444W;F405N", use the first component
    let primary = filterName.split(separator: ";").first.map(String.init) ?? filterName
    // Match the leading F followed by digits
    guard let regex = try? NSRegularExpression(pattern: "^[Ff](\\d+)", options: []),
        let match = regex.firstMatch(
            in: primary, options: [], range: NSRange(primary.startIndex..., in: primary)),
        let digitRange = Range(match.range(at: 1), in: primary)
    else {
        return Int.max
    }
    return Int(primary[digitRange]) ?? Int.max
}

/// Compare two JWST filter names by wavelength (ascending).
/// Filters with the same wavelength are further sorted alphabetically.
public func compareJWSTFilters(_ a: String, _ b: String) -> Bool {
    compareObservationFilters(a, b)
}

/// Compare two filter names by wavelength (ascending).
/// Filters with the same wavelength are further sorted alphabetically.
public func compareObservationFilters(_ a: String, _ b: String) -> Bool {
    let wa = observationFilterWavelength(a)
    let wb = observationFilterWavelength(b)
    if wa != wb { return wa < wb }
    return a < b
}

/// Returns the effective observation time for a product.
///
/// Priority:
/// 1. `t_min` (exposure start time), if > 0
/// 2. `t_max` (exposure end time), if > 0
/// 3. `t_obs_release` (product release date)
public func jwstEffectiveTime(_ coam: CoamResult) -> Float {
    observationEffectiveTime(coam)
}

/// Returns the effective observation time for a product.
public func observationEffectiveTime(_ coam: CoamResult) -> Float {
    if coam.t_min > 0 { return coam.t_min }
    if coam.t_max > 0 { return coam.t_max }
    return coam.t_obs_release
}

/// Compare two products according to the given ``ObservationProductSortOrder``.
///
/// - `.filter`: sort by filter wavelength ascending; tiebreak by effective time then filter name
/// - `.time`: sort by effective time ascending; tiebreak by filter wavelength then filter name
public func compareObservationProducts(
    _ a: CoamResult, _ b: CoamResult, by sortOrder: ObservationProductSortOrder
) -> Bool {
    switch sortOrder {
    case .filter:
        let wa = observationFilterWavelength(a.filters)
        let wb = observationFilterWavelength(b.filters)
        if wa != wb { return wa < wb }
        let ta = observationEffectiveTime(a)
        let tb = observationEffectiveTime(b)
        if ta != tb { return ta < tb }
        return a.filters < b.filters
    case .time:
        let ta = observationEffectiveTime(a)
        let tb = observationEffectiveTime(b)
        if ta != tb { return ta < tb }
        let wa = observationFilterWavelength(a.filters)
        let wb = observationFilterWavelength(b.filters)
        if wa != wb { return wa < wb }
        return a.filters < b.filters
    }
}

public func compareJWSTProducts(
    _ a: CoamResult, _ b: CoamResult, by sortOrder: JWSTProductSortOrder
) -> Bool {
    compareObservationProducts(a, b, by: sortOrder)
}

/// Extract the observation group key from a `CoamResult`.
public func observationGroupKey(_ coam: CoamResult) -> String {
    let collection = coam.obs_collection.uppercased()
    if collection == ObservationMission.jwst.rawValue {
        return jwstObservationGroupKey(coam.obs_id)
    }
    if collection == ObservationMission.hst.rawValue || coam.obs_id.lowercased().hasPrefix("hst_") {
        return hstObservationGroupKey(coam.obs_id)
    }
    return coam.obs_id
}

/// Extract the observation group key from a JWST `obs_id`.
///
/// The key is the first 3 underscore-delimited segments:
/// `"jw02666-o007_t004_miri_f1000w"` → `"jw02666-o007_t004_miri"`
public func jwstObservationGroupKey(_ obsId: String) -> String {
    let parts = obsId.split(separator: "_", maxSplits: 3)
    if parts.count >= 3 {
        return parts[0..<3].joined(separator: "_")
    }
    return obsId
}

/// Extract the observation group key from an HST/HLA-style `obs_id`.
///
/// HST product IDs commonly include one or more filter tokens after the visit
/// and instrument pieces. This keeps the prefix before the first filter token:
/// `"hst_10775_62_wfc3_f606w"` → `"hst_10775_62_wfc3"`.
public func hstObservationGroupKey(_ obsId: String) -> String {
    let parts = obsId.split(separator: "_").map(String.init)
    guard !parts.isEmpty else { return obsId }

    var keyParts: [String] = []
    for part in parts {
        if isFilterToken(part), !keyParts.isEmpty {
            break
        }
        keyParts.append(part)
    }
    return keyParts.isEmpty ? obsId : keyParts.joined(separator: "_")
}

private func isFilterToken(_ value: String) -> Bool {
    let upper = value.uppercased()
    if upper == "CLEAR" { return true }
    guard let regex = try? NSRegularExpression(pattern: "^(FQ?|G)\\d{2,4}[A-Z0-9]*$", options: [])
    else {
        return false
    }
    return regex.firstMatch(in: upper, options: [], range: NSRange(upper.startIndex..., in: upper)) != nil
}

extension CoamResult {
    /// The broad observation mission represented by this result.
    public var observationMission: ObservationMission? {
        let collection = obs_collection.uppercased()
        if collection == "JWST" { return .jwst }
        if collection == "HST" || collection == "HLA" { return .hst }
        return nil
    }

    /// Filter display colors derived from recognized HST or JWST filter metadata.
    public var filterColors: [ObservationFilterColor] {
        var colors: [ObservationFilterColor] = []

        for filter in jwstFilters {
            colors.append(
                ObservationFilterColor(
                    filterName: filter.rawValue,
                    mission: ObservationMission.jwst.rawValue,
                    colorName: filter.likelySpaceColor.rawValue,
                    hexColor: filter.likelySpaceColorHex
                ))
        }

        for filter in hstFilters {
            colors.append(
                ObservationFilterColor(
                    filterName: filter.rawValue,
                    mission: ObservationMission.hst.rawValue,
                    colorName: filter.likelySpaceColor.rawValue,
                    hexColor: filter.likelySpaceColorHex
                ))
        }

        return colors
    }

    /// A filter-name → color map for UI chips, legends, and quick lookup.
    public var filterColorMap: [String: ObservationFilterColor] {
        Dictionary(uniqueKeysWithValues: filterColors.map { ($0.filterName, $0) })
    }
}
