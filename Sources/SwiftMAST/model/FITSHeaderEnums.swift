//
//  FITSHeaderEnums.swift
//  SwiftMAST
//
//  Categorical enums for well-known FITS header keyword values.
//  These represent keywords whose values come from a defined set
//  per the FITS standard (NOST 100-2.0 / NASA/Science Office of Standards and Technology).
//

import Foundation

// MARK: - XTENSION

/// The type of FITS extension.
///
/// Defined in the FITS standard, the XTENSION keyword identifies
/// the format of the data in an extension HDU.
public enum FITSXtension: String, Codable, CaseIterable, Identifiable {
    /// Standard image extension containing n-dimensional array data
    case image = "IMAGE"
    /// Binary table extension with heterogeneous column types
    case bintable = "BINTABLE"
    /// ASCII table extension with character-encoded column data
    case table = "TABLE"
    /// IUE satellite image format (legacy)
    case iueimage = "IUEIMAGE"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .image: return "Standard FITS image extension containing n-dimensional array data"
        case .bintable: return "Binary table extension with heterogeneous column types"
        case .table: return "ASCII table extension with character-encoded column data"
        case .iueimage: return "IUE satellite image format (legacy extension type)"
        }
    }

    /// Attempts to match a raw FITS header string value to this enum
    public init?(fitsValue: String) {
        let cleaned =
            fitsValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        self.init(rawValue: cleaned)
    }
}

// MARK: - BITPIX

/// The data type of pixel values in a FITS image array.
///
/// BITPIX defines the number of bits per pixel and the data format.
/// Positive values indicate unsigned/signed integers; negative values
/// indicate IEEE floating-point.
public enum FITSBitpix: Int, Codable, CaseIterable, Identifiable {
    /// 8-bit unsigned integer (0–255)
    case uint8 = 8
    /// 16-bit two's complement signed integer
    case int16 = 16
    /// 32-bit two's complement signed integer
    case int32 = 32
    /// 64-bit two's complement signed integer
    case int64 = 64
    /// IEEE 754 single-precision floating-point (32-bit)
    case float32 = -32
    /// IEEE 754 double-precision floating-point (64-bit)
    case float64 = -64

    public var id: Int { rawValue }

    public var description: String {
        switch self {
        case .uint8: return "8-bit unsigned integer (0–255)"
        case .int16: return "16-bit two's complement signed integer"
        case .int32: return "32-bit two's complement signed integer"
        case .int64: return "64-bit two's complement signed integer"
        case .float32: return "IEEE 754 single-precision floating-point (32-bit)"
        case .float64: return "IEEE 754 double-precision floating-point (64-bit)"
        }
    }

    /// The byte size of each pixel
    public var byteSize: Int {
        abs(rawValue) / 8
    }

    /// Whether this format is floating-point
    public var isFloatingPoint: Bool {
        rawValue < 0
    }
}

// MARK: - RADESYS

/// The celestial reference frame for coordinate system keywords.
///
/// RADESYS identifies the reference frame used for the celestial coordinates
/// in the WCS (World Coordinate System) keywords of a FITS header.
public enum FITSRaDesys: String, Codable, CaseIterable, Identifiable {
    /// International Celestial Reference System (current IAU standard)
    case icrs = "ICRS"
    /// Fifth fundamental star catalogue (J2000.0 equinox)
    case fk5 = "FK5"
    /// Fourth fundamental star catalogue (B1950.0 equinox)
    case fk4 = "FK4"
    /// FK4 without the E-terms of aberration correction
    case fk4NoE = "FK4-NO-E"
    /// Geocentric apparent place (current epoch)
    case gappt = "GAPPT"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .icrs: return "International Celestial Reference System (current IAU standard)"
        case .fk5: return "Fifth Fundamental Catalogue reference frame (J2000.0 equinox)"
        case .fk4: return "Fourth Fundamental Catalogue reference frame (B1950.0 equinox)"
        case .fk4NoE: return "FK4 without the E-terms of aberration correction"
        case .gappt: return "Geocentric apparent place at the current epoch"
        }
    }

    /// Attempts to match a raw FITS header string value to this enum
    public init?(fitsValue: String) {
        let cleaned =
            fitsValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        self.init(rawValue: cleaned)
    }
}

// MARK: - TIMESYS

/// The time scale used for time-related keywords in a FITS header.
///
/// TIMESYS specifies the time scale for all time-based keywords
/// (DATE-OBS, MJD-OBS, etc.) in the header unless overridden.
public enum FITSTimeSys: String, Codable, CaseIterable, Identifiable {
    /// Coordinated Universal Time
    case utc = "UTC"
    /// Universal Time (based on Earth rotation)
    case ut1 = "UT1"
    /// International Atomic Time
    case tai = "TAI"
    /// Terrestrial Time (successor to Ephemeris Time)
    case tt = "TT"
    /// Barycentric Dynamical Time
    case tdb = "TDB"
    /// Geocentric Coordinate Time
    case tcg = "TCG"
    /// Barycentric Coordinate Time
    case tcb = "TCB"
    /// GPS time scale
    case gps = "GPS"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .utc: return "Coordinated Universal Time"
        case .ut1: return "Universal Time (based on Earth rotation)"
        case .tai: return "International Atomic Time"
        case .tt: return "Terrestrial Time (successor to Ephemeris Time)"
        case .tdb: return "Barycentric Dynamical Time"
        case .tcg: return "Geocentric Coordinate Time"
        case .tcb: return "Barycentric Coordinate Time"
        case .gps: return "GPS time scale"
        }
    }

    /// Attempts to match a raw FITS header string value to this enum
    public init?(fitsValue: String) {
        let cleaned =
            fitsValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        self.init(rawValue: cleaned)
    }
}

// MARK: - HeaderKeywordCategory

/// The category of a FITS header keyword.
///
/// Groups both general FITS structural, scaling, WCS, time, and coordinate keywords
/// as well as JWST-specific keywords from the MAST Instrument Keyword Dictionary at:
/// https://mast.stsci.edu/api/v0/_jwst_inst_keywd.html
///
/// Use ``FITSHeaderKeywords/category(for:)`` or ``FITSHeaderUnit/keywordCategory``
/// to retrieve the category for a given keyword string.
///
/// Example:
/// ```swift
/// let unit = FITSHeaderUnit(keyword: "INSTRUME", value: .string("MIRI"), comment: "")
/// print(unit.keywordCategory)  // instrument
/// ```
public enum HeaderKeywordCategory: String, Codable, CaseIterable, Identifiable {
    /// FITS file and HDU structure (SIMPLE, BITPIX, NAXIS, XTENSION, NEXTEND, etc.)
    case structural = "Structural"
    /// Data value scaling and physical units (BSCALE, BZERO, BUNIT, BTYPE, etc.)
    case dataScaling = "Data Scaling"
    /// Proposal title, principal investigator, and program classification
    case program = "Program"
    /// Observation, visit, and exposure identifier keywords
    case observation = "Observation"
    /// Visit scheduling, execution status, and configuration flags
    case visit = "Visit"
    /// Target coordinates, proper motion, and source classification
    case target = "Target"
    /// Instrument, detector, and optical element configuration
    case instrument = "Instrument"
    /// Exposure duration, readout pattern, and detector parameters
    case exposure = "Exposure"
    /// Date, time, time-scale, and barycentric/heliocentric corrections
    case time = "Time"
    /// World Coordinate System and spatial footprint keywords
    case wcs = "WCS"
    /// Calibration software, reference files, and pipeline provenance
    case calibration = "Calibration"
    /// Detector subarray name, start position, and pixel dimensions
    case subarray = "Subarray"
    /// Dither pattern type, individual offsets, and step parameters
    case dither = "Dither"
    /// Guide star catalog identifier, coordinates, and pointing quality
    case guideStar = "Guide Star"
    /// Sky background level and subtraction status
    case background = "Background"
    /// Science aperture name and configuration
    case aperture = "Aperture"
    /// Pipeline association pool and table file references
    case association = "Association"
    /// Resampled product total exposure time and source catalog filenames
    case resampling = "Resampling"
    /// Instrument mechanism, IFU cube construction, and WFS&C parameters
    case engineering = "Engineering"
    /// Archive product release, access restrictions, and file metadata
    case product = "Product"
    /// FITS comment, history, and blank header cards
    case comments = "Comments"
    /// Keyword not assigned to a specific category
    case unknown = "Unknown"

    public var id: String { rawValue }

    /// Human-readable description of this keyword category.
    public var description: String {
        switch self {
        case .structural: return "FITS file and HDU structural keywords"
        case .dataScaling: return "Data value scaling and physical unit keywords"
        case .program: return "Proposal title, principal investigator, and program classification"
        case .observation: return "Observation, visit, and exposure identifier keywords"
        case .visit: return "Visit scheduling, execution status, and configuration flags"
        case .target: return "Target coordinates, proper motion, and source classification"
        case .instrument: return "Instrument, detector, and optical element configuration"
        case .exposure: return "Exposure duration, readout pattern, and detector parameters"
        case .time: return "Date, time, time-scale, and barycentric/heliocentric corrections"
        case .wcs: return "World Coordinate System and spatial footprint keywords"
        case .calibration: return "Calibration software, reference files, and pipeline provenance"
        case .subarray: return "Detector subarray name, start position, and pixel dimensions"
        case .dither: return "Dither pattern type, individual offsets, and step parameters"
        case .guideStar: return "Guide star catalog identifier, coordinates, and pointing quality"
        case .background: return "Sky background level and subtraction status"
        case .aperture: return "Science aperture name and configuration"
        case .association: return "Pipeline association pool and table file references"
        case .resampling:
            return "Resampled product total exposure time and source catalog filenames"
        case .engineering:
            return "Instrument mechanism, IFU cube construction, and WFS&C parameters"
        case .product: return "Archive product release, access restrictions, and file metadata"
        case .comments: return "FITS comment, history, and blank header cards"
        case .unknown: return "Keyword not assigned to a specific category"
        }
    }
}
