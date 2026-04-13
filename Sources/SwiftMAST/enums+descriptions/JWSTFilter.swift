//
//  JWSTFilter.swift
//
//
//  Created by SwiftMAST on 13/4/2026.
//

import Foundation

public typealias JWSTFilters = JWSTFilter

/// JWST science instrument filters across all four instruments.
///
/// Filter names follow the standard JWST naming convention:
/// - `F` prefix for filters
/// - Number indicating the pivot wavelength (in units of 0.01 μm for NIR, 0.1 μm for MIR)
/// - Suffix indicating bandwidth: `W` (wide), `M` (medium), `N` (narrow),
///   `W2` (extra-wide), `C` (coronagraphic), `LP` (long-pass), `X` (extra-wide bandpass)
///
/// In COAM results, the `filters` field may contain multiple filters
/// separated by a semicolon (`;`), e.g. `"F560W;F1000W"`.
/// Use ``JWSTFilter/parseFilters(_:)`` to convert such strings into `[JWSTFilter]`.
///
/// References:
/// - MIRI: https://jwst-docs.stsci.edu/jwst-mid-infrared-instrument/miri-instrumentation/miri-filters-and-dispersers
/// - NIRCam: https://jwst-docs.stsci.edu/jwst-near-infrared-camera/nircam-instrumentation/nircam-filters
/// - NIRISS: https://jwst-docs.stsci.edu/jwst-near-infrared-imager-and-slitless-spectrograph/niriss-instrumentation/niriss-filters
/// - NIRSpec: https://jwst-docs.stsci.edu/jwst-near-infrared-spectrograph/nirspec-instrumentation/nirspec-dispersers-and-filters
public enum JWSTFilter: String, Codable, CaseIterable, Identifiable {

    // MARK: - MIRI Imaging Filters (4.9–28.8 μm)

    /// MIRI 5.6 μm wide-band imaging filter
    case F560W
    /// MIRI 7.7 μm wide-band imaging filter
    case F770W
    /// MIRI 10.0 μm wide-band imaging filter
    case F1000W
    /// MIRI 11.3 μm wide-band imaging filter
    case F1130W
    /// MIRI 12.8 μm wide-band imaging filter
    case F1280W
    /// MIRI 15.0 μm wide-band imaging filter
    case F1500W
    /// MIRI 18.0 μm wide-band imaging filter
    case F1800W
    /// MIRI 21.0 μm wide-band imaging filter
    case F2100W
    /// MIRI 25.5 μm wide-band imaging filter
    case F2550W

    // MARK: - MIRI Coronagraphic Filters

    /// MIRI 10.65 μm coronagraphic filter
    case F1065C
    /// MIRI 11.40 μm coronagraphic filter
    case F1140C
    /// MIRI 15.50 μm coronagraphic filter
    case F1550C
    /// MIRI 23.00 μm coronagraphic (Lyot) filter
    case F2300C

    // MARK: - NIRCam Short Wavelength Wide Filters (0.6–2.3 μm)

    /// NIRCam 0.70 μm wide-band filter — general purpose
    case F070W
    /// NIRCam 0.90 μm wide-band filter — general purpose
    case F090W
    /// NIRCam 1.15 μm wide-band filter — general purpose
    case F115W
    /// NIRCam 1.50 μm wide-band filter — general purpose
    case F150W
    /// NIRCam 2.00 μm wide-band filter — general purpose
    case F200W

    // MARK: - NIRCam Short Wavelength Medium Filters

    /// NIRCam 1.40 μm medium-band filter — cool stars, H₂O, CH₄
    case F140M
    /// NIRCam 1.63 μm medium-band filter — cool stars, off-band for H₂O
    case F162M
    /// NIRCam 1.85 μm medium-band filter — cool stars, H₂O, CH₄
    case F182M
    /// NIRCam 2.09 μm medium-band filter — H₂O, CH₄
    case F210M

    // MARK: - NIRCam Short Wavelength Narrow Filters

    /// NIRCam 1.64 μm narrow-band filter — [FeII]
    case F164N
    /// NIRCam 1.87 μm narrow-band filter — Pa-alpha
    case F187N
    /// NIRCam 2.12 μm narrow-band filter — H₂
    case F212N

    // MARK: - NIRCam Short Wavelength Extra-Wide Filter

    /// NIRCam 1.67 μm extra-wide filter — blocking filter for F162M, F164N, and DHS
    case F150W2

    // MARK: - NIRCam Long Wavelength Wide Filters (2.4–5.0 μm)

    /// NIRCam 2.78 μm wide-band filter — general purpose
    case F277W
    /// NIRCam 3.57 μm wide-band filter — general purpose
    case F356W
    /// NIRCam 4.40 μm wide-band filter — general purpose; blocking filter for F405N, F466N, F470N
    case F444W

    // MARK: - NIRCam Long Wavelength Extra-Wide Filter

    /// NIRCam 3.25 μm extra-wide filter — background minimum; primarily used with grisms; blocking filter for F323N
    case F322W2

    // MARK: - NIRCam Long Wavelength Medium Filters

    /// NIRCam 2.50 μm medium-band filter — CH₄, continuum
    case F250M
    /// NIRCam 3.00 μm medium-band filter — water ice
    case F300M
    /// NIRCam 3.36 μm medium-band filter — PAH, CH₄
    case F335M
    /// NIRCam 3.62 μm medium-band filter — brown dwarfs, planets, continuum
    case F360M
    /// NIRCam 4.08 μm medium-band filter — brown dwarfs, planets, H₂O, CH₄
    case F410M
    /// NIRCam 4.28 μm medium-band filter — CO₂, N₂
    case F430M
    /// NIRCam 4.63 μm medium-band filter — CO
    case F460M
    /// NIRCam 4.82 μm medium-band filter — brown dwarfs, planets, continuum
    case F480M

    // MARK: - NIRCam Long Wavelength Narrow Filters

    /// NIRCam 3.24 μm narrow-band filter — H₂
    case F323N
    /// NIRCam 4.05 μm narrow-band filter — Br-alpha
    case F405N
    /// NIRCam 4.65 μm narrow-band filter — CO
    case F466N
    /// NIRCam 4.71 μm narrow-band filter — H₂
    case F470N

    // MARK: - NIRISS Filters (unique to NIRISS)

    /// NIRISS 1.58 μm medium-band filter
    case F158M
    /// NIRISS 3.80 μm medium-band filter
    case F380M

    // MARK: - NIRSpec Filters (0.6–5.3 μm)

    /// NIRSpec >0.7 μm long-pass filter — used with G140M/G140H for 0.7–1.27 μm spectra
    case F070LP
    /// NIRSpec >1.0 μm long-pass filter — used with G140M/G140H for 1.0–1.9 μm spectra
    case F100LP
    /// NIRSpec 1.0–1.3 μm bandpass filter — narrow-band target acquisition for brighter targets
    case F110W
    /// NIRSpec 0.8–2.0 μm extra-wide bandpass filter — target acquisition
    case F140X
    /// NIRSpec >1.7 μm long-pass filter — used with G235M/G235H for 1.7–3.2 μm spectra
    case F170LP
    /// NIRSpec >2.9 μm long-pass filter — used with G395M/G395H for 2.9–5.3 μm spectra
    case F290LP
    /// NIRSpec 0.6–5.3 μm open (clear) filter — target acquisition or used with PRISM
    case CLEAR

    // MARK: - Identifiable

    public var id: String {
        return self.rawValue
    }

    // MARK: - Properties

    /// The JWST instrument(s) this filter is available on.
    public var instruments: [String] {
        switch self {
        // MIRI
        case .F560W, .F770W, .F1000W, .F1130W, .F1280W, .F1500W, .F1800W, .F2100W, .F2550W:
            return ["MIRI"]
        case .F1065C, .F1140C, .F1550C, .F2300C:
            return ["MIRI"]

        // NIRCam only
        case .F070W:
            return ["NIRCam"]
        case .F162M, .F182M, .F210M:
            return ["NIRCam"]
        case .F164N, .F187N, .F212N:
            return ["NIRCam"]
        case .F150W2, .F322W2:
            return ["NIRCam"]
        case .F250M, .F300M, .F335M, .F360M, .F410M, .F460M:
            return ["NIRCam"]
        case .F323N, .F405N, .F466N, .F470N:
            return ["NIRCam"]

        // Shared NIRCam + NIRISS
        case .F090W, .F115W, .F150W, .F200W:
            return ["NIRCam", "NIRISS"]
        case .F140M:
            return ["NIRCam", "NIRISS"]
        case .F277W, .F356W, .F444W:
            return ["NIRCam", "NIRISS"]
        case .F430M, .F480M:
            return ["NIRCam", "NIRISS"]

        // NIRISS only
        case .F158M, .F380M:
            return ["NIRISS"]

        // NIRSpec
        case .F070LP, .F100LP, .F110W, .F140X, .F170LP, .F290LP, .CLEAR:
            return ["NIRSpec"]
        }
    }

    /// The pivot (central) wavelength in micrometers (μm).
    public var pivotWavelength: Double {
        switch self {
        // MIRI Imaging
        case .F560W: return 5.6
        case .F770W: return 7.7
        case .F1000W: return 10.0
        case .F1130W: return 11.3
        case .F1280W: return 12.8
        case .F1500W: return 15.0
        case .F1800W: return 18.0
        case .F2100W: return 21.0
        case .F2550W: return 25.5
        // MIRI Coronagraphic
        case .F1065C: return 10.65
        case .F1140C: return 11.40
        case .F1550C: return 15.50
        case .F2300C: return 23.00
        // NIRCam SW Wide
        case .F070W: return 0.704
        case .F090W: return 0.902
        case .F115W: return 1.154
        case .F150W: return 1.501
        case .F200W: return 1.989
        // NIRCam SW Medium
        case .F140M: return 1.405
        case .F162M: return 1.627
        case .F182M: return 1.845
        case .F210M: return 2.096
        // NIRCam SW Narrow
        case .F164N: return 1.645
        case .F187N: return 1.874
        case .F212N: return 2.121
        // NIRCam SW Extra-wide
        case .F150W2: return 1.672
        // NIRCam LW Wide
        case .F277W: return 2.776
        case .F356W: return 3.565
        case .F444W: return 4.402
        // NIRCam LW Extra-wide
        case .F322W2: return 3.247
        // NIRCam LW Medium
        case .F250M: return 2.503
        case .F300M: return 2.996
        case .F335M: return 3.362
        case .F360M: return 3.623
        case .F410M: return 4.083
        case .F430M: return 4.281
        case .F460M: return 4.630
        case .F480M: return 4.817
        // NIRCam LW Narrow
        case .F323N: return 3.237
        case .F405N: return 4.053
        case .F466N: return 4.654
        case .F470N: return 4.708
        // NIRISS only
        case .F158M: return 1.580
        case .F380M: return 3.828
        // NIRSpec
        case .F070LP: return 0.7
        case .F100LP: return 1.0
        case .F110W: return 1.15
        case .F140X: return 1.4
        case .F170LP: return 1.7
        case .F290LP: return 2.9
        case .CLEAR: return 2.95
        }
    }

    /// The bandwidth in micrometers (μm).
    /// For long-pass filters this represents the usable passband width.
    public var bandwidth: Double {
        switch self {
        // MIRI Imaging
        case .F560W: return 1.2
        case .F770W: return 2.2
        case .F1000W: return 2.0
        case .F1130W: return 0.7
        case .F1280W: return 2.4
        case .F1500W: return 3.0
        case .F1800W: return 3.0
        case .F2100W: return 5.0
        case .F2550W: return 4.0
        // MIRI Coronagraphic
        case .F1065C: return 0.53
        case .F1140C: return 0.57
        case .F1550C: return 0.78
        case .F2300C: return 4.60
        // NIRCam SW Wide
        case .F070W: return 0.128
        case .F090W: return 0.194
        case .F115W: return 0.225
        case .F150W: return 0.318
        case .F200W: return 0.461
        // NIRCam SW Medium
        case .F140M: return 0.142
        case .F162M: return 0.168
        case .F182M: return 0.238
        case .F210M: return 0.205
        // NIRCam SW Narrow
        case .F164N: return 0.020
        case .F187N: return 0.024
        case .F212N: return 0.027
        // NIRCam SW Extra-wide
        case .F150W2: return 1.228
        // NIRCam LW Wide
        case .F277W: return 0.672
        case .F356W: return 0.786
        case .F444W: return 1.024
        // NIRCam LW Extra-wide
        case .F322W2: return 1.340
        // NIRCam LW Medium
        case .F250M: return 0.181
        case .F300M: return 0.318
        case .F335M: return 0.348
        case .F360M: return 0.372
        case .F410M: return 0.436
        case .F430M: return 0.228
        case .F460M: return 0.228
        case .F480M: return 0.303
        // NIRCam LW Narrow
        case .F323N: return 0.038
        case .F405N: return 0.046
        case .F466N: return 0.054
        case .F470N: return 0.051
        // NIRISS only
        case .F158M: return 0.165
        case .F380M: return 0.205
        // NIRSpec
        case .F070LP: return 0.6
        case .F100LP: return 0.9
        case .F110W: return 0.3
        case .F140X: return 1.2
        case .F170LP: return 1.5
        case .F290LP: return 2.4
        case .CLEAR: return 4.7
        }
    }

    /// The filter band type classification.
    public var filterType: JWSTFilterType {
        switch self {
        case .F560W, .F770W, .F1000W, .F1130W, .F1280W, .F1500W, .F1800W, .F2100W, .F2550W:
            return .wide
        case .F1065C, .F1140C, .F1550C, .F2300C:
            return .coronagraphic
        case .F070W, .F090W, .F115W, .F150W, .F200W, .F277W, .F356W, .F444W:
            return .wide
        case .F150W2, .F322W2:
            return .extraWide
        case .F140M, .F162M, .F182M, .F210M, .F250M, .F300M, .F335M, .F360M,
            .F410M, .F430M, .F460M, .F480M, .F158M, .F380M:
            return .medium
        case .F164N, .F187N, .F212N, .F323N, .F405N, .F466N, .F470N:
            return .narrow
        case .F070LP, .F100LP, .F170LP, .F290LP:
            return .longPass
        case .F110W:
            return .wide
        case .F140X:
            return .extraWide
        case .CLEAR:
            return .clear
        }
    }

    /// The wavelength regime this filter belongs to.
    public var wavelengthRegime: String {
        switch self {
        case .F560W, .F770W, .F1000W, .F1130W, .F1280W, .F1500W, .F1800W,
            .F2100W, .F2550W, .F1065C, .F1140C, .F1550C, .F2300C:
            return "Mid-Infrared"
        case .F070W, .F090W, .F115W, .F140M, .F150W, .F162M, .F164N, .F150W2,
            .F182M, .F187N, .F200W, .F210M, .F212N, .F158M:
            return "Near-Infrared (short)"
        case .F250M, .F277W, .F300M, .F322W2, .F323N, .F335M, .F356W, .F360M,
            .F380M, .F405N, .F410M, .F430M, .F444W, .F460M, .F466N, .F470N, .F480M:
            return "Near-Infrared (long)"
        case .F070LP, .F100LP, .F110W, .F140X, .F170LP, .F290LP, .CLEAR:
            return "Near-Infrared (spectroscopy)"
        }
    }

    /// A human-readable description of the filter including its properties.
    public var description: String {
        let instStr = instruments.joined(separator: ", ")
        return
            "\(rawValue) — \(instStr) \(filterType.rawValue) filter, λ_pivot = \(pivotWavelength) μm, Δλ = \(bandwidth) μm"
    }

    // MARK: - Parsing

    /// Parse a semicolon-separated filter string (as returned in COAM results) into an array of ``JWSTFilter``.
    ///
    /// Unrecognized filter names are silently skipped.
    ///
    /// - Parameter filterString: A string such as `"F560W;F1000W"` or a single filter name.
    /// - Returns: An array of matched ``JWSTFilter`` values.
    public static func parseFilters(_ filterString: String) -> [JWSTFilter] {
        return
            filterString
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { JWSTFilter(rawValue: $0) }
    }
}

// MARK: - Filter Type

/// Classification of JWST filter bandwidth types.
public enum JWSTFilterType: String, Codable, CaseIterable, Identifiable {
    case wide = "Wide"
    case extraWide = "Extra-Wide"
    case medium = "Medium"
    case narrow = "Narrow"
    case coronagraphic = "Coronagraphic"
    case longPass = "Long-Pass"
    case clear = "Clear"

    public var id: String { rawValue }
}

// MARK: - CoamResult Filter Integration

/// A type alias for an array of JWST filters, used when specifying
/// multiple filters for a COAM query or result.
public typealias JWSTFilterList = [JWSTFilter]

extension Array where Element == JWSTFilter {
    /// Convert this filter array into a semicolon-separated string
    /// matching the COAM result `filters` field format.
    public var filterString: String {
        return self.map(\.rawValue).joined(separator: ";")
    }
}

extension CoamResult {
    /// The parsed JWST filters from this COAM result's `filters` field.
    ///
    /// The `filters` field may contain multiple filter names separated
    /// by semicolons. Any unrecognized filter names are excluded.
    public var jwstFilters: [JWSTFilter] {
        return JWSTFilter.parseFilters(self.filters)
    }
}
