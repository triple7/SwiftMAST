//
//  JWSTObservationGroup.swift
//  SwiftMAST
//
//  Created by SwiftMAST on 12/4/2026.
//

import Foundation

/// A group of JWST products from the same observation session, sharing
/// the same program, observation number, target, and instrument.
///
/// Products within a group are sorted by filter wavelength (ascending).
/// The group key is derived from the `obs_id` prefix:
/// `jw{program}-{obs}_t{target}_{instrument}` (first 3 underscore-delimited segments).
public struct JWSTObservationGroup: CustomStringConvertible {
    /// The observation group key (e.g. "jw02666-o007_t004_miri")
    public let observationKey: String

    /// The instrument used in this observation (e.g. "MIRI/IMAGE", "NIRCAM/IMAGE")
    public let instrument: String

    /// Products sorted by filter wavelength (ascending: F200W before F1000W)
    public let products: [CoamResult]

    /// Unique filter names in wavelength order
    public var filterNames: [String] {
        products.map { $0.filters }
    }

    public var description: String {
        let filters = filterNames.joined(separator: ", ")
        return "\(observationKey) [\(instrument)] — \(products.count) filters: \(filters)"
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
    let wa = jwstFilterWavelength(a)
    let wb = jwstFilterWavelength(b)
    if wa != wb { return wa < wb }
    return a < b
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
