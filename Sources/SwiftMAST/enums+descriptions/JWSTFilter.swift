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

    /// Detailed tabular metadata for the filter.
    public var metadata: JWSTFilterMetadata {
        Self.metadataByFilter[self]!
    }

    /// The JWST instrument(s) this filter is available on.
    public var instruments: [String] {
        metadata.instruments
    }

    /// The pivot (central) wavelength in micrometers (μm).
    public var pivotWavelength: Double {
        metadata.pivotWavelength
    }

    /// The bandwidth in micrometers (μm).
    /// For long-pass filters this represents the usable passband width.
    public var bandwidth: Double {
        metadata.bandwidth
    }

    /// The filter band type classification.
    public var filterType: JWSTFilterType {
        metadata.filterType
    }

    /// The wavelength regime this filter belongs to.
    public var wavelengthRegime: String {
        metadata.wavelengthRegime
    }

    /// A display-oriented color tag for false-color astronomy imagery.
    public var likelySpaceColor: JWSTFilterColorTag {
        switch pivotWavelength {
        case ..<1.2:
            return .blue
        case ..<2.0:
            return .cyan
        case ..<3.0:
            return .green
        case ..<5.0:
            return .yellow
        case ..<10.0:
            return .orange
        case ..<18.0:
            return .red
        default:
            return .deepRed
        }
    }

    /// Hex color suitable for legends, previews, and filter chips.
    public var likelySpaceColorHex: String {
        likelySpaceColor.hex
    }

    /// What this filter is designed to detect or measure.
    ///
    /// Based on the science use cases documented in the JWST instrument handbooks.
    public var scienceUse: String {
        metadata.scienceUse
    }

    /// A human-readable description of the filter including its properties.
    public var description: String {
        let instStr = instruments.joined(separator: ", ")
        return
            "\(rawValue) — \(instStr) \(filterType.rawValue) filter, λ_pivot = \(pivotWavelength) μm, Δλ = \(bandwidth) μm, color = \(likelySpaceColor.rawValue) [\(scienceUse)]"
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

// MARK: - Supporting Types

public struct JWSTFilterMetadata: Codable, Hashable {
    public let instruments: [String]
    public let pivotWavelength: Double
    public let bandwidth: Double
    public let filterType: JWSTFilterType
    public let wavelengthRegime: String
    public let scienceUse: String

    public init(
        instruments: [String],
        pivotWavelength: Double,
        bandwidth: Double,
        filterType: JWSTFilterType,
        wavelengthRegime: String,
        scienceUse: String
    ) {
        self.instruments = instruments
        self.pivotWavelength = pivotWavelength
        self.bandwidth = bandwidth
        self.filterType = filterType
        self.wavelengthRegime = wavelengthRegime
        self.scienceUse = scienceUse
    }
}

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

public enum JWSTFilterColorTag: String, Codable, CaseIterable, Identifiable {
    case blue = "Blue"
    case cyan = "Cyan"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case red = "Red"
    case deepRed = "Deep Red / Far-IR"

    public var id: String { rawValue }

    public var hex: String {
        switch self {
        case .blue: return "#3B82F6"
        case .cyan: return "#22D3EE"
        case .green: return "#22C55E"
        case .yellow: return "#FACC15"
        case .orange: return "#FB923C"
        case .red: return "#EF4444"
        case .deepRed: return "#B91C1C"
        }
    }
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

// MARK: - Metadata Table

extension JWSTFilter {
    private static let miri = ["MIRI"]
    private static let nircam = ["NIRCam"]
    private static let niriss = ["NIRISS"]
    private static let nirspec = ["NIRSpec"]
    private static let nircamNiriss = ["NIRCam", "NIRISS"]

    private static let metadataByFilter: [JWSTFilter: JWSTFilterMetadata] = [
        .F560W: .init(instruments: miri, pivotWavelength: 5.6, bandwidth: 1.2, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Stellar photospheres, warm dust continuum"),
        .F770W: .init(instruments: miri, pivotWavelength: 7.7, bandwidth: 2.2, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "PAH emission (7.7 μm feature), warm dust"),
        .F1000W: .init(instruments: miri, pivotWavelength: 10.0, bandwidth: 2.0, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Silicate absorption/emission, warm dust continuum"),
        .F1130W: .init(instruments: miri, pivotWavelength: 11.3, bandwidth: 0.7, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "PAH emission (11.3 μm feature)"),
        .F1280W: .init(instruments: miri, pivotWavelength: 12.8, bandwidth: 2.4, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Dust continuum, star-forming regions"),
        .F1500W: .init(instruments: miri, pivotWavelength: 15.0, bandwidth: 3.0, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Dust continuum, cool dust emission"),
        .F1800W: .init(instruments: miri, pivotWavelength: 18.0, bandwidth: 3.0, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Silicate emission, cool dust continuum"),
        .F2100W: .init(instruments: miri, pivotWavelength: 21.0, bandwidth: 5.0, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Cool dust emission, debris disks"),
        .F2550W: .init(instruments: miri, pivotWavelength: 25.5, bandwidth: 4.0, filterType: .wide, wavelengthRegime: "Mid-Infrared", scienceUse: "Cold dust emission, asteroid thermal emission"),
        .F1065C: .init(instruments: miri, pivotWavelength: 10.65, bandwidth: 0.53, filterType: .coronagraphic, wavelengthRegime: "Mid-Infrared", scienceUse: "NH₃ feature, exoplanet atmospheres"),
        .F1140C: .init(instruments: miri, pivotWavelength: 11.40, bandwidth: 0.57, filterType: .coronagraphic, wavelengthRegime: "Mid-Infrared", scienceUse: "CO₂ feature, exoplanet atmospheres"),
        .F1550C: .init(instruments: miri, pivotWavelength: 15.50, bandwidth: 0.78, filterType: .coronagraphic, wavelengthRegime: "Mid-Infrared", scienceUse: "Exoplanet direct imaging, circumstellar disks"),
        .F2300C: .init(instruments: miri, pivotWavelength: 23.00, bandwidth: 4.60, filterType: .coronagraphic, wavelengthRegime: "Mid-Infrared", scienceUse: "Exoplanet direct imaging, debris disks (Lyot coronagraph)"),
        .F070W: .init(instruments: nircam, pivotWavelength: 0.704, bandwidth: 0.128, filterType: .wide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "General purpose imaging"),
        .F090W: .init(instruments: nircamNiriss, pivotWavelength: 0.902, bandwidth: 0.194, filterType: .wide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "General purpose imaging"),
        .F115W: .init(instruments: nircamNiriss, pivotWavelength: 1.154, bandwidth: 0.225, filterType: .wide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "General purpose imaging"),
        .F150W: .init(instruments: nircamNiriss, pivotWavelength: 1.501, bandwidth: 0.318, filterType: .wide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "General purpose imaging"),
        .F200W: .init(instruments: nircamNiriss, pivotWavelength: 1.989, bandwidth: 0.461, filterType: .wide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "General purpose imaging"),
        .F140M: .init(instruments: nircamNiriss, pivotWavelength: 1.405, bandwidth: 0.142, filterType: .medium, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Cool stars, H₂O, CH₄"),
        .F162M: .init(instruments: nircam, pivotWavelength: 1.627, bandwidth: 0.168, filterType: .medium, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Cool stars, off-band for H₂O"),
        .F182M: .init(instruments: nircam, pivotWavelength: 1.845, bandwidth: 0.238, filterType: .medium, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Cool stars, H₂O, CH₄"),
        .F210M: .init(instruments: nircam, pivotWavelength: 2.096, bandwidth: 0.205, filterType: .medium, wavelengthRegime: "Near-Infrared (short)", scienceUse: "H₂O, CH₄"),
        .F164N: .init(instruments: nircam, pivotWavelength: 1.645, bandwidth: 0.020, filterType: .narrow, wavelengthRegime: "Near-Infrared (short)", scienceUse: "[FeII] emission (1.644 μm)"),
        .F187N: .init(instruments: nircam, pivotWavelength: 1.874, bandwidth: 0.024, filterType: .narrow, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Paschen-alpha (Pa-α) hydrogen emission"),
        .F212N: .init(instruments: nircam, pivotWavelength: 2.121, bandwidth: 0.027, filterType: .narrow, wavelengthRegime: "Near-Infrared (short)", scienceUse: "H₂ molecular emission (2.12 μm)"),
        .F150W2: .init(instruments: nircam, pivotWavelength: 1.672, bandwidth: 1.228, filterType: .extraWide, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Blocking filter for F162M, F164N, and DHS"),
        .F277W: .init(instruments: nircamNiriss, pivotWavelength: 2.776, bandwidth: 0.672, filterType: .wide, wavelengthRegime: "Near-Infrared (long)", scienceUse: "General purpose imaging"),
        .F356W: .init(instruments: nircamNiriss, pivotWavelength: 3.565, bandwidth: 0.786, filterType: .wide, wavelengthRegime: "Near-Infrared (long)", scienceUse: "General purpose imaging"),
        .F444W: .init(instruments: nircamNiriss, pivotWavelength: 4.402, bandwidth: 1.024, filterType: .wide, wavelengthRegime: "Near-Infrared (long)", scienceUse: "General purpose imaging; blocking filter for F405N, F466N, F470N"),
        .F322W2: .init(instruments: nircam, pivotWavelength: 3.247, bandwidth: 1.340, filterType: .extraWide, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Background minimum, primarily used with grisms; blocking filter for F323N"),
        .F250M: .init(instruments: nircam, pivotWavelength: 2.503, bandwidth: 0.181, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "CH₄, continuum"),
        .F300M: .init(instruments: nircam, pivotWavelength: 2.996, bandwidth: 0.318, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Water ice (3.0 μm feature)"),
        .F335M: .init(instruments: nircam, pivotWavelength: 3.362, bandwidth: 0.348, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "PAH emission (3.3 μm feature), CH₄"),
        .F360M: .init(instruments: nircam, pivotWavelength: 3.623, bandwidth: 0.372, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Brown dwarfs, planets, continuum"),
        .F410M: .init(instruments: nircam, pivotWavelength: 4.083, bandwidth: 0.436, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Brown dwarfs, planets, H₂O, CH₄"),
        .F430M: .init(instruments: nircamNiriss, pivotWavelength: 4.281, bandwidth: 0.228, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "CO₂, N₂"),
        .F460M: .init(instruments: nircam, pivotWavelength: 4.630, bandwidth: 0.228, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "CO"),
        .F480M: .init(instruments: nircamNiriss, pivotWavelength: 4.817, bandwidth: 0.303, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Brown dwarfs, planets, continuum"),
        .F323N: .init(instruments: nircam, pivotWavelength: 3.237, bandwidth: 0.038, filterType: .narrow, wavelengthRegime: "Near-Infrared (long)", scienceUse: "H₂ molecular emission (3.23 μm)"),
        .F405N: .init(instruments: nircam, pivotWavelength: 4.053, bandwidth: 0.046, filterType: .narrow, wavelengthRegime: "Near-Infrared (long)", scienceUse: "Brackett-alpha (Br-α) hydrogen emission"),
        .F466N: .init(instruments: nircam, pivotWavelength: 4.654, bandwidth: 0.054, filterType: .narrow, wavelengthRegime: "Near-Infrared (long)", scienceUse: "CO fundamental band emission"),
        .F470N: .init(instruments: nircam, pivotWavelength: 4.708, bandwidth: 0.051, filterType: .narrow, wavelengthRegime: "Near-Infrared (long)", scienceUse: "H₂ molecular emission (4.69 μm)"),
        .F158M: .init(instruments: niriss, pivotWavelength: 1.580, bandwidth: 0.165, filterType: .medium, wavelengthRegime: "Near-Infrared (short)", scienceUse: "Continuum, stellar characterization"),
        .F380M: .init(instruments: niriss, pivotWavelength: 3.828, bandwidth: 0.205, filterType: .medium, wavelengthRegime: "Near-Infrared (long)", scienceUse: "CH₄, continuum, exoplanet transit spectroscopy"),
        .F070LP: .init(instruments: nirspec, pivotWavelength: 0.7, bandwidth: 0.6, filterType: .longPass, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Spectroscopy 0.7–1.27 μm (paired with G140M/G140H)"),
        .F100LP: .init(instruments: nirspec, pivotWavelength: 1.0, bandwidth: 0.9, filterType: .longPass, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Spectroscopy 1.0–1.9 μm (paired with G140M/G140H)"),
        .F110W: .init(instruments: nirspec, pivotWavelength: 1.15, bandwidth: 0.3, filterType: .wide, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Narrow-band target acquisition for brighter targets"),
        .F140X: .init(instruments: nirspec, pivotWavelength: 1.4, bandwidth: 1.2, filterType: .extraWide, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Target acquisition"),
        .F170LP: .init(instruments: nirspec, pivotWavelength: 1.7, bandwidth: 1.5, filterType: .longPass, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Spectroscopy 1.7–3.2 μm (paired with G235M/G235H)"),
        .F290LP: .init(instruments: nirspec, pivotWavelength: 2.9, bandwidth: 2.4, filterType: .longPass, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Spectroscopy 2.9–5.3 μm (paired with G395M/G395H)"),
        .CLEAR: .init(instruments: nirspec, pivotWavelength: 2.95, bandwidth: 4.7, filterType: .clear, wavelengthRegime: "Near-Infrared (spectroscopy)", scienceUse: "Target acquisition or full-range spectroscopy with PRISM (0.6–5.3 μm)"),
    ]
}
