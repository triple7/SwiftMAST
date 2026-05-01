//
//  JWSTObservationGroup.swift
//  SwiftMAST
//
//  Created by SwiftMAST on 12/4/2026.
//

import Foundation

/// How products within a ``JWSTObservationGroup`` are sorted.
public enum JWSTProductSortOrder {
    /// Sort by filter wavelength ascending (e.g. F200W before F1000W).
    /// Products with equal wavelength are further sorted by observation start time.
    case filter

    /// Sort by observation start time ascending.
    /// Products with equal start time are further sorted by filter wavelength.
    case time
}

/// A group of JWST products from the same observation session, sharing
/// the same program, observation number, target, and instrument.
///
/// Products are sorted according to the ``JWSTProductSortOrder`` used when building
/// the group. The group key is derived from the `obs_id` prefix:
/// `jw{program}-{obs}_t{target}_{instrument}` (first 3 underscore-delimited segments).
public struct JWSTObservationGroup: CustomStringConvertible {
    /// The observation group key (e.g. "jw02666-o007_t004_miri")
    public let observationKey: String

    /// The instrument used in this observation (e.g. "MIRI/IMAGE", "NIRCAM/IMAGE")
    public let instrument: String

    /// Products sorted according to the sort order used when building this group.
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

/// Returns the effective observation time for a product.
///
/// Priority:
/// 1. `t_min` (exposure start time), if > 0
/// 2. `t_max` (exposure end time), if > 0
/// 3. `t_obs_release` (product release date)
public func jwstEffectiveTime(_ coam: CoamResult) -> Float {
    if coam.t_min > 0 { return coam.t_min }
    if coam.t_max > 0 { return coam.t_max }
    return coam.t_obs_release
}

/// Compare two JWST products according to the given ``JWSTProductSortOrder``.
///
/// - `.filter`: sort by filter wavelength ascending; tiebreak by effective time then filter name
/// - `.time`: sort by effective time ascending; tiebreak by filter wavelength then filter name
public func compareJWSTProducts(
    _ a: CoamResult, _ b: CoamResult, by sortOrder: JWSTProductSortOrder
) -> Bool {
    switch sortOrder {
    case .filter:
        let wa = jwstFilterWavelength(a.filters)
        let wb = jwstFilterWavelength(b.filters)
        if wa != wb { return wa < wb }
        let ta = jwstEffectiveTime(a)
        let tb = jwstEffectiveTime(b)
        if ta != tb { return ta < tb }
        return a.filters < b.filters
    case .time:
        let ta = jwstEffectiveTime(a)
        let tb = jwstEffectiveTime(b)
        if ta != tb { return ta < tb }
        let wa = jwstFilterWavelength(a.filters)
        let wb = jwstFilterWavelength(b.filters)
        if wa != wb { return wa < wb }
        return a.filters < b.filters
    }
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
