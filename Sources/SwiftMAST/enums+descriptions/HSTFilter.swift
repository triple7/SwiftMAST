//
//  HSTFilter.swift
//
//
//  Created by SwiftMAST on 16/5/2026.
//

import Foundation

public typealias HSTFilters = HSTFilter

/// HST WFC3/UVIS filters.
///
/// Values are based on the WFC3 Instrument Handbook table for UVIS spectral
/// elements. Pivot wavelengths, widths, cumulative throughput widths, and peak
/// system throughput are listed for UVIS chip 1, except for quad filters.
public enum HSTFilter: String, Codable, CaseIterable, Identifiable {

    // MARK: - UVIS Long-Pass and Extremely Wide Filters

    case F200LP
    case F300X
    case F350LP
    case F475X
    case F600LP
    case F850LP

    // MARK: - UVIS Wide-Band Filters

    case F218W
    case F225W
    case F275W
    case F336W
    case F390W
    case F438W
    case F475W
    case F555W
    case F606W
    case F625W
    case F775W
    case F814W

    // MARK: - UVIS Medium-Band Filters

    case F390M
    case F410M
    case FQ422M
    case F467M
    case F547M
    case F621M
    case F689M
    case F763M
    case F845M

    // MARK: - UVIS Narrow-Band Filters

    case FQ232N
    case FQ243N
    case F280N
    case F343N
    case F373N
    case FQ378N
    case FQ387N
    case F395N
    case FQ436N
    case FQ437N
    case F469N
    case F487N
    case FQ492N
    case F502N
    case FQ508N
    case FQ575N
    case FQ619N
    case F631N
    case FQ634N
    case F645N
    case F656N
    case F657N
    case F658N
    case F665N
    case FQ672N
    case F673N
    case FQ674N
    case F680N
    case FQ727N
    case FQ750N
    case FQ889N
    case FQ906N
    case FQ924N
    case FQ937N
    case F953N

    public var id: String {
        rawValue
    }

    /// The HST instrument/channel this spectral element belongs to.
    public var instruments: [String] {
        ["WFC3/UVIS"]
    }

    /// Detailed tabular metadata for the filter.
    public var metadata: HSTFilterMetadata {
        Self.metadataByFilter[self]!
    }

    /// The pivot wavelength in Angstroms.
    public var pivotWavelengthAngstroms: Double {
        metadata.pivotWavelengthAngstroms
    }

    /// The pivot wavelength in micrometers.
    public var pivotWavelength: Double {
        pivotWavelengthAngstroms / 10_000
    }

    /// The passband rectangular width in Angstroms.
    public var bandwidthAngstroms: Double? {
        metadata.bandwidthAngstroms
    }

    /// The passband rectangular width in micrometers.
    public var bandwidth: Double? {
        bandwidthAngstroms.map { $0 / 10_000 }
    }

    /// The wavelength range containing 95% of the cumulative throughput.
    public var cumulativeThroughputWidthAngstroms: Double? {
        metadata.cumulativeThroughputWidthAngstroms
    }

    /// The peak system throughput from the WFC3 UVIS table.
    public var peakSystemThroughput: Double {
        metadata.peakSystemThroughput
    }

    /// The filter band type classification.
    public var filterType: HSTFilterType {
        metadata.filterType
    }

    /// The wavelength regime this spectral element belongs to.
    public var wavelengthRegime: String {
        switch pivotWavelengthAngstroms {
        case ..<3200:
            return "Ultraviolet"
        case ..<4000:
            return "Near-Ultraviolet / Violet"
        case ..<5000:
            return "Blue"
        case ..<5900:
            return "Green / Visual"
        case ..<7000:
            return "Red"
        default:
            return "Near-Infrared"
        }
    }

    /// A display-oriented color tag for false-color astronomy imagery.
    public var likelySpaceColor: HSTFilterColorTag {
        switch pivotWavelengthAngstroms {
        case ..<3200:
            return .ultraviolet
        case ..<4500:
            return .blue
        case ..<5000:
            return .cyan
        case ..<5700:
            return .green
        case ..<6200:
            return .yellow
        case ..<7000:
            return .red
        default:
            return .deepRed
        }
    }

    /// Hex color suitable for legends, previews, and filter chips.
    public var likelySpaceColorHex: String {
        likelySpaceColor.hex
    }

    /// What this filter is designed to detect or approximate.
    public var scienceUse: String {
        metadata.scienceUse
    }

    /// A human-readable description of the spectral element and its properties.
    public var description: String {
        let width = bandwidthAngstroms.map { ", width = \($0) A" } ?? ""
        return
            "\(rawValue) - WFC3/UVIS \(filterType.rawValue), pivot = \(pivotWavelengthAngstroms) A\(width), color = \(likelySpaceColor.rawValue) [\(scienceUse)]"
    }

    /// Parse a semicolon-separated filter string as returned in COAM results.
    ///
    /// Unrecognized filter names are silently skipped.
    public static func parseFilters(_ filterString: String) -> [HSTFilter] {
        filterString
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .compactMap { HSTFilter(rawValue: $0) }
    }
}

// MARK: - Supporting Types

public struct HSTFilterMetadata: Codable, Hashable {
    public let scienceUse: String
    public let pivotWavelengthAngstroms: Double
    public let bandwidthAngstroms: Double?
    public let cumulativeThroughputWidthAngstroms: Double?
    public let peakSystemThroughput: Double
    public let filterType: HSTFilterType

    public init(
        scienceUse: String,
        pivotWavelengthAngstroms: Double,
        bandwidthAngstroms: Double?,
        cumulativeThroughputWidthAngstroms: Double?,
        peakSystemThroughput: Double,
        filterType: HSTFilterType
    ) {
        self.scienceUse = scienceUse
        self.pivotWavelengthAngstroms = pivotWavelengthAngstroms
        self.bandwidthAngstroms = bandwidthAngstroms
        self.cumulativeThroughputWidthAngstroms = cumulativeThroughputWidthAngstroms
        self.peakSystemThroughput = peakSystemThroughput
        self.filterType = filterType
    }
}

public enum HSTFilterType: String, Codable, CaseIterable, Identifiable {
    case longPass = "Long-Pass"
    case extremelyWide = "Extremely Wide"
    case wide = "Wide"
    case medium = "Medium"
    case narrow = "Narrow"
    public var id: String { rawValue }
}

public enum HSTFilterColorTag: String, Codable, CaseIterable, Identifiable {
    case ultraviolet = "Ultraviolet"
    case blue = "Blue"
    case cyan = "Cyan"
    case green = "Green"
    case yellow = "Yellow"
    case red = "Red"
    case deepRed = "Deep Red / Near-IR"

    public var id: String { rawValue }

    public var hex: String {
        switch self {
        case .ultraviolet: return "#8A5CFF"
        case .blue: return "#3B82F6"
        case .cyan: return "#22D3EE"
        case .green: return "#22C55E"
        case .yellow: return "#FACC15"
        case .red: return "#EF4444"
        case .deepRed: return "#B91C1C"
        }
    }
}

// MARK: - CoamResult Filter Integration

public typealias HSTFilterList = [HSTFilter]

extension Array where Element == HSTFilter {
    /// Convert this filter array into a semicolon-separated string matching
    /// the COAM result `filters` field format.
    public var filterString: String {
        map(\.rawValue).joined(separator: ";")
    }
}

extension CoamResult {
    /// The parsed HST WFC3/UVIS filters from this COAM result's `filters` field.
    public var hstFilters: [HSTFilter] {
        HSTFilter.parseFilters(self.filters)
    }
}

// MARK: - Metadata Table

extension HSTFilter {
    private static let metadataByFilter: [HSTFilter: HSTFilterMetadata] = [
        .F200LP: .init(scienceUse: "Clear fused silica; UVIS full spectral range", pivotWavelengthAngstroms: 4971.9, bandwidthAngstroms: 5881.1, cumulativeThroughputWidthAngstroms: 7015, peakSystemThroughput: 0.28, filterType: .longPass),
        .F300X: .init(scienceUse: "Extremely wide UV; grism reference", pivotWavelengthAngstroms: 2820.5, bandwidthAngstroms: 707.3, cumulativeThroughputWidthAngstroms: 1270, peakSystemThroughput: 0.16, filterType: .extremelyWide),
        .F350LP: .init(scienceUse: "Long-pass visual reference", pivotWavelengthAngstroms: 5873.9, bandwidthAngstroms: 4803.7, cumulativeThroughputWidthAngstroms: 5889, peakSystemThroughput: 0.29, filterType: .longPass),
        .F475X: .init(scienceUse: "Extremely wide blue", pivotWavelengthAngstroms: 4940.7, bandwidthAngstroms: 2057.2, cumulativeThroughputWidthAngstroms: 2420, peakSystemThroughput: 0.28, filterType: .extremelyWide),
        .F600LP: .init(scienceUse: "Long-pass red / near-IR", pivotWavelengthAngstroms: 7468.1, bandwidthAngstroms: 2340.1, cumulativeThroughputWidthAngstroms: 3617, peakSystemThroughput: 0.29, filterType: .longPass),
        .F850LP: .init(scienceUse: "SDSS z prime", pivotWavelengthAngstroms: 9176.1, bandwidthAngstroms: 1192.5, cumulativeThroughputWidthAngstroms: 1786, peakSystemThroughput: 0.11, filterType: .longPass),
        .F218W: .init(scienceUse: "ISM feature", pivotWavelengthAngstroms: 2228, bandwidthAngstroms: 330.7, cumulativeThroughputWidthAngstroms: 460.2, peakSystemThroughput: 0.04, filterType: .wide),
        .F225W: .init(scienceUse: "UV wide", pivotWavelengthAngstroms: 2372.1, bandwidthAngstroms: 467.1, cumulativeThroughputWidthAngstroms: 681, peakSystemThroughput: 0.09, filterType: .wide),
        .F275W: .init(scienceUse: "UV wide", pivotWavelengthAngstroms: 2709.7, bandwidthAngstroms: 405.3, cumulativeThroughputWidthAngstroms: 590.1, peakSystemThroughput: 0.12, filterType: .wide),
        .F336W: .init(scienceUse: "U, Stromgren u", pivotWavelengthAngstroms: 3354.5, bandwidthAngstroms: 511.6, cumulativeThroughputWidthAngstroms: 544.3, peakSystemThroughput: 0.2, filterType: .wide),
        .F390W: .init(scienceUse: "Washington C", pivotWavelengthAngstroms: 3923.7, bandwidthAngstroms: 894, cumulativeThroughputWidthAngstroms: 983.3, peakSystemThroughput: 0.25, filterType: .wide),
        .F438W: .init(scienceUse: "WFPC2 B", pivotWavelengthAngstroms: 4326.2, bandwidthAngstroms: 614.7, cumulativeThroughputWidthAngstroms: 653.7, peakSystemThroughput: 0.24, filterType: .wide),
        .F475W: .init(scienceUse: "SDSS g prime", pivotWavelengthAngstroms: 4773.1, bandwidthAngstroms: 1343.5, cumulativeThroughputWidthAngstroms: 1420.5, peakSystemThroughput: 0.27, filterType: .wide),
        .F555W: .init(scienceUse: "WFPC2 V", pivotWavelengthAngstroms: 5308.4, bandwidthAngstroms: 1565.4, cumulativeThroughputWidthAngstroms: 1946, peakSystemThroughput: 0.29, filterType: .wide),
        .F606W: .init(scienceUse: "WFPC2 wide V", pivotWavelengthAngstroms: 5889.2, bandwidthAngstroms: 2189.2, cumulativeThroughputWidthAngstroms: 2193, peakSystemThroughput: 0.29, filterType: .wide),
        .F625W: .init(scienceUse: "SDSS r prime", pivotWavelengthAngstroms: 6242.6, bandwidthAngstroms: 1464.6, cumulativeThroughputWidthAngstroms: 1501, peakSystemThroughput: 0.28, filterType: .wide),
        .F775W: .init(scienceUse: "SDSS i prime", pivotWavelengthAngstroms: 7651.4, bandwidthAngstroms: 1179.1, cumulativeThroughputWidthAngstroms: 1422, peakSystemThroughput: 0.23, filterType: .wide),
        .F814W: .init(scienceUse: "WFPC2 wide I", pivotWavelengthAngstroms: 8039.1, bandwidthAngstroms: 1565.2, cumulativeThroughputWidthAngstroms: 2351, peakSystemThroughput: 0.23, filterType: .wide),
        .F390M: .init(scienceUse: "Ca II continuum", pivotWavelengthAngstroms: 3897.2, bandwidthAngstroms: 204.3, cumulativeThroughputWidthAngstroms: 225.9, peakSystemThroughput: 0.22, filterType: .medium),
        .F410M: .init(scienceUse: "Stromgren v", pivotWavelengthAngstroms: 4109, bandwidthAngstroms: 172, cumulativeThroughputWidthAngstroms: 184.3, peakSystemThroughput: 0.26, filterType: .medium),
        .FQ422M: .init(scienceUse: "Blue continuum", pivotWavelengthAngstroms: 4219.2, bandwidthAngstroms: 111.7, cumulativeThroughputWidthAngstroms: 130.4, peakSystemThroughput: 0.18, filterType: .medium),
        .F467M: .init(scienceUse: "Stromgren b", pivotWavelengthAngstroms: 4682.6, bandwidthAngstroms: 200.9, cumulativeThroughputWidthAngstroms: 213.1, peakSystemThroughput: 0.28, filterType: .medium),
        .F547M: .init(scienceUse: "Stromgren y", pivotWavelengthAngstroms: 5447.5, bandwidthAngstroms: 650, cumulativeThroughputWidthAngstroms: 700.6, peakSystemThroughput: 0.27, filterType: .medium),
        .F621M: .init(scienceUse: "11 percent passband", pivotWavelengthAngstroms: 6218.9, bandwidthAngstroms: 609.5, cumulativeThroughputWidthAngstroms: 613.4, peakSystemThroughput: 0.29, filterType: .medium),
        .F689M: .init(scienceUse: "11 percent passband", pivotWavelengthAngstroms: 6876.8, bandwidthAngstroms: 684.2, cumulativeThroughputWidthAngstroms: 689.7, peakSystemThroughput: 0.25, filterType: .medium),
        .F763M: .init(scienceUse: "11 percent passband", pivotWavelengthAngstroms: 7614.4, bandwidthAngstroms: 708.6, cumulativeThroughputWidthAngstroms: 768.6, peakSystemThroughput: 0.21, filterType: .medium),
        .F845M: .init(scienceUse: "11 percent passband", pivotWavelengthAngstroms: 8439.1, bandwidthAngstroms: 794.3, cumulativeThroughputWidthAngstroms: 869.2, peakSystemThroughput: 0.14, filterType: .medium),
        .FQ232N: .init(scienceUse: "[C II] 2326", pivotWavelengthAngstroms: 2432.2, bandwidthAngstroms: 34.2, cumulativeThroughputWidthAngstroms: 42.1, peakSystemThroughput: 0.04, filterType: .narrow),
        .FQ243N: .init(scienceUse: "[Ne IV] 2425", pivotWavelengthAngstroms: 2476.3, bandwidthAngstroms: 36.7, cumulativeThroughputWidthAngstroms: 40.7, peakSystemThroughput: 0.05, filterType: .narrow),
        .F280N: .init(scienceUse: "Mg II 2795/2802", pivotWavelengthAngstroms: 2832.9, bandwidthAngstroms: 42.5, cumulativeThroughputWidthAngstroms: 52, peakSystemThroughput: 0.06, filterType: .narrow),
        .F343N: .init(scienceUse: "[Ne V] 3426", pivotWavelengthAngstroms: 3435.1, bandwidthAngstroms: 249.1, cumulativeThroughputWidthAngstroms: 287.2, peakSystemThroughput: 0.2, filterType: .narrow),
        .F373N: .init(scienceUse: "[O II] 3726/3728", pivotWavelengthAngstroms: 3730.2, bandwidthAngstroms: 49.6, cumulativeThroughputWidthAngstroms: 52.9, peakSystemThroughput: 0.18, filterType: .narrow),
        .FQ378N: .init(scienceUse: "Redshifted [O II] 3726", pivotWavelengthAngstroms: 3792.4, bandwidthAngstroms: 99.3, cumulativeThroughputWidthAngstroms: 106.5, peakSystemThroughput: 0.19, filterType: .narrow),
        .FQ387N: .init(scienceUse: "[Ne III] 3868", pivotWavelengthAngstroms: 3873.7, bandwidthAngstroms: 33.6, cumulativeThroughputWidthAngstroms: 35.4, peakSystemThroughput: 0.16, filterType: .narrow),
        .F395N: .init(scienceUse: "Ca II 3933/3968", pivotWavelengthAngstroms: 3955.2, bandwidthAngstroms: 85.2, cumulativeThroughputWidthAngstroms: 87.2, peakSystemThroughput: 0.22, filterType: .narrow),
        .FQ436N: .init(scienceUse: "H-gamma 4340 + [O III] 4363", pivotWavelengthAngstroms: 4367.2, bandwidthAngstroms: 43.4, cumulativeThroughputWidthAngstroms: 45.9, peakSystemThroughput: 0.18, filterType: .narrow),
        .FQ437N: .init(scienceUse: "[O III] 4363", pivotWavelengthAngstroms: 4371, bandwidthAngstroms: 30, cumulativeThroughputWidthAngstroms: 31.7, peakSystemThroughput: 0.19, filterType: .narrow),
        .F469N: .init(scienceUse: "He II 4686", pivotWavelengthAngstroms: 4688.1, bandwidthAngstroms: 49.7, cumulativeThroughputWidthAngstroms: 51.2, peakSystemThroughput: 0.2, filterType: .narrow),
        .F487N: .init(scienceUse: "H-beta 4861", pivotWavelengthAngstroms: 4871.4, bandwidthAngstroms: 60.4, cumulativeThroughputWidthAngstroms: 62.9, peakSystemThroughput: 0.25, filterType: .narrow),
        .FQ492N: .init(scienceUse: "Redshifted H-beta", pivotWavelengthAngstroms: 4933.4, bandwidthAngstroms: 113.5, cumulativeThroughputWidthAngstroms: 112.9, peakSystemThroughput: 0.25, filterType: .narrow),
        .F502N: .init(scienceUse: "[O III] 5007", pivotWavelengthAngstroms: 5009.6, bandwidthAngstroms: 65.3, cumulativeThroughputWidthAngstroms: 67.6, peakSystemThroughput: 0.26, filterType: .narrow),
        .FQ508N: .init(scienceUse: "Redshifted [O III] 5007", pivotWavelengthAngstroms: 5091, bandwidthAngstroms: 130.6, cumulativeThroughputWidthAngstroms: 130.8, peakSystemThroughput: 0.22, filterType: .narrow),
        .FQ575N: .init(scienceUse: "[N II] 5754", pivotWavelengthAngstroms: 5757.7, bandwidthAngstroms: 18.4, cumulativeThroughputWidthAngstroms: 20.1, peakSystemThroughput: 0.21, filterType: .narrow),
        .FQ619N: .init(scienceUse: "CH4 6194", pivotWavelengthAngstroms: 6198.5, bandwidthAngstroms: 60.9, cumulativeThroughputWidthAngstroms: 69.4, peakSystemThroughput: 0.25, filterType: .narrow),
        .F631N: .init(scienceUse: "[O I] 6300", pivotWavelengthAngstroms: 6304.3, bandwidthAngstroms: 58.3, cumulativeThroughputWidthAngstroms: 61.7, peakSystemThroughput: 0.25, filterType: .narrow),
        .FQ634N: .init(scienceUse: "6194 continuum", pivotWavelengthAngstroms: 6349.2, bandwidthAngstroms: 64.1, cumulativeThroughputWidthAngstroms: 74.6, peakSystemThroughput: 0.24, filterType: .narrow),
        .F645N: .init(scienceUse: "Continuum", pivotWavelengthAngstroms: 6453.6, bandwidthAngstroms: 84.2, cumulativeThroughputWidthAngstroms: 98.8, peakSystemThroughput: 0.24, filterType: .narrow),
        .F656N: .init(scienceUse: "H-alpha 6562", pivotWavelengthAngstroms: 6561.4, bandwidthAngstroms: 17.6, cumulativeThroughputWidthAngstroms: 18.6, peakSystemThroughput: 0.23, filterType: .narrow),
        .F657N: .init(scienceUse: "Wide H-alpha + [N II]", pivotWavelengthAngstroms: 6566.6, bandwidthAngstroms: 121, cumulativeThroughputWidthAngstroms: 136.9, peakSystemThroughput: 0.25, filterType: .narrow),
        .F658N: .init(scienceUse: "[N II] 6583", pivotWavelengthAngstroms: 6584, bandwidthAngstroms: 27.6, cumulativeThroughputWidthAngstroms: 28.6, peakSystemThroughput: 0.25, filterType: .narrow),
        .F665N: .init(scienceUse: "Redshifted H-alpha + [N II]", pivotWavelengthAngstroms: 6655.9, bandwidthAngstroms: 131.3, cumulativeThroughputWidthAngstroms: 138.7, peakSystemThroughput: 0.25, filterType: .narrow),
        .FQ672N: .init(scienceUse: "[S II] 6717", pivotWavelengthAngstroms: 6716.4, bandwidthAngstroms: 19.4, cumulativeThroughputWidthAngstroms: 20.6, peakSystemThroughput: 0.21, filterType: .narrow),
        .F673N: .init(scienceUse: "[S II] 6717/6731", pivotWavelengthAngstroms: 6765.9, bandwidthAngstroms: 117.8, cumulativeThroughputWidthAngstroms: 125.1, peakSystemThroughput: 0.25, filterType: .narrow),
        .FQ674N: .init(scienceUse: "[S II] 6731", pivotWavelengthAngstroms: 6730.7, bandwidthAngstroms: 17.6, cumulativeThroughputWidthAngstroms: 19.9, peakSystemThroughput: 0.23, filterType: .narrow),
        .F680N: .init(scienceUse: "Redshifted H-alpha + [N II]", pivotWavelengthAngstroms: 6877.6, bandwidthAngstroms: 370.5, cumulativeThroughputWidthAngstroms: 374.1, peakSystemThroughput: 0.25, filterType: .narrow),
        .FQ727N: .init(scienceUse: "CH4 7270", pivotWavelengthAngstroms: 7275.2, bandwidthAngstroms: 63.9, cumulativeThroughputWidthAngstroms: 74.1, peakSystemThroughput: 0.2, filterType: .narrow),
        .FQ750N: .init(scienceUse: "7270 continuum", pivotWavelengthAngstroms: 7502.5, bandwidthAngstroms: 70.4, cumulativeThroughputWidthAngstroms: 81.5, peakSystemThroughput: 0.18, filterType: .narrow),
        .FQ889N: .init(scienceUse: "CH4 25 km-amagat", pivotWavelengthAngstroms: 8892.2, bandwidthAngstroms: 98.5, cumulativeThroughputWidthAngstroms: 107.7, peakSystemThroughput: 0.1, filterType: .narrow),
        .FQ906N: .init(scienceUse: "CH4 2.5 km-amagat", pivotWavelengthAngstroms: 9057.8, bandwidthAngstroms: 98.6, cumulativeThroughputWidthAngstroms: 108.5, peakSystemThroughput: 0.09, filterType: .narrow),
        .FQ924N: .init(scienceUse: "CH4 0.25 km-amagat", pivotWavelengthAngstroms: 9247.6, bandwidthAngstroms: 91.6, cumulativeThroughputWidthAngstroms: 104.6, peakSystemThroughput: 0.08, filterType: .narrow),
        .FQ937N: .init(scienceUse: "CH4 0.025 km-amagat", pivotWavelengthAngstroms: 9372.4, bandwidthAngstroms: 93.3, cumulativeThroughputWidthAngstroms: 107.9, peakSystemThroughput: 0.07, filterType: .narrow),
        .F953N: .init(scienceUse: "[S III] 9532", pivotWavelengthAngstroms: 9530.6, bandwidthAngstroms: 96.8, cumulativeThroughputWidthAngstroms: 95.8, peakSystemThroughput: 0.05, filterType: .narrow),
    ]
}
