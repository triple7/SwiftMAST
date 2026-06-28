//
//  FITSMetadata.swift
//  SwiftMAST
//
//  Created for FITS file metadata extraction
//

import Foundation
import SwiftQValue

/// Comprehensive FITS file metadata structure
public struct FITSMetadata: Codable, CustomStringConvertible {

    // MARK: - Core Properties

    /// File identifier (filename or URL path)
    public let fileIdentifier: String

    /// Raw metadata dictionary from FITS header
    public let rawMetadata: [String: QValue]

    // MARK: - Image Dimensions

    /// Number of axes (2D, 3D, etc.)
    public let naxis: Int?

    /// Dimensions along each axis [width, height, depth, ...]
    public let axisDimensions: [Int]

    /// Total image dimension description
    public var dimensionDescription: String {
        if axisDimensions.isEmpty {
            return "Unknown dimensions"
        }
        let dims = axisDimensions.map { "\($0)" }.joined(separator: "×")
        return "\(dims) (\(naxis ?? 0)D)"
    }

    // MARK: - Filter & Wavelength

    /// Filter band used for observation
    public let filter: String?

    /// Wavelength region (UV, Optical, IR, etc.)
    public let wavelengthRegion: String?

    /// Central wavelength in Angstroms
    public let centralWavelength: Double?

    // MARK: - Temporal Information

    /// Observation date
    public let observationDate: String?

    /// Exposure start time
    public let exposureStart: String?

    /// Exposure duration in seconds
    public let exposureTime: Double?

    // MARK: - World Coordinate System (WCS)

    /// WCS coordinate reference pixel X
    public let crpix1: Double?

    /// WCS coordinate reference pixel Y
    public let crpix2: Double?

    /// WCS coordinate reference value RA (degrees)
    public let crval1: Double?

    /// WCS coordinate reference value DEC (degrees)
    public let crval2: Double?

    /// WCS coordinate delta per pixel X (degrees)
    public let cdelt1: Double?

    /// WCS coordinate delta per pixel Y (degrees)
    public let cdelt2: Double?

    /// Number of WCS coordinate axes
    public let wcsAxes: Int?

    /// WCS equinox
    public let equinox: Double?

    /// WCS coordinate type 1 (usually RA)
    public let ctype1: String?

    /// WCS coordinate type 2 (usually DEC)
    public let ctype2: String?

    /// WCS coordinate unit 1
    public let cunit1: String?

    /// WCS coordinate unit 2
    public let cunit2: String?

    /// WCS rotation matrix element 1,1
    public let cd1_1: Double?

    /// WCS rotation matrix element 1,2
    public let cd1_2: Double?

    /// WCS rotation matrix element 2,1
    public let cd2_1: Double?

    /// WCS rotation matrix element 2,2
    public let cd2_2: Double?

    /// WCS PC matrix element 1,1
    public let pc1_1: Double?

    /// WCS PC matrix element 1,2
    public let pc1_2: Double?

    /// WCS PC matrix element 2,1
    public let pc2_1: Double?

    /// WCS PC matrix element 2,2
    public let pc2_2: Double?

    // MARK: - Instrument & Mission

    /// Telescope/Observatory name
    public let telescope: String?

    /// Instrument name
    public let instrument: String?

    /// Detector name
    public let detector: String?

    /// Observation ID
    public let observationId: String?

    /// Target name
    public let targetName: String?

    // MARK: - Calibration

    /// Calibration level (RAW, CALIBRATED, etc.)
    public let calibrationLevel: String?

    /// Photometric calibration keyword
    public let photometricCalibration: String?

    /// Astrometric calibration keyword
    public let astrometricCalibration: String?

    /// Processing software/pipeline
    public let processingSoftware: String?

    /// Processing date
    public let processingDate: String?

    // MARK: - Photometry

    /// Photometric zero point
    public let zeroPoint: Double?

    /// Magnitude zero point
    public let magZpt: Double?

    /// Photometric system
    public let photSystem: String?

    // MARK: - Engineering & Quality

    /// Data quality flags
    public let dataQuality: String?

    /// Seeing (arcseconds)
    public let seeing: Double?

    /// Airmass
    public let airmass: Double?

    /// Sky background level
    public let skyBackground: Double?

    /// Read noise (electrons)
    public let readNoise: Double?

    /// Gain (electrons/ADU)
    public let gain: Double?

    // MARK: - Additional Context

    /// FITS extension type (IMAGE, BINTABLE, etc.)
    public let extensionType: String?

    /// FITS version
    public let fitsVersion: String?

    /// Original file format
    public let originalFormat: String?

    // MARK: - Initializer

    public init(fileIdentifier: String, metadata: [String: QValue]) {
        self.fileIdentifier = fileIdentifier
        self.rawMetadata = metadata

        // Extract NAXIS and dimensions
        self.naxis = Self.extractInt(from: metadata, key: "NAXIS")
        var dims: [Int] = []
        if let nax = naxis {
            for i in 1...nax {
                if let dim = Self.extractInt(from: metadata, key: "NAXIS\(i)") {
                    dims.append(dim)
                }
            }
        }
        self.axisDimensions = dims

        // Filter and wavelength
        self.filter = Self.extractString(
            from: metadata, keys: ["FILTER", "FILTER1", "FILTNAM", "FILTNAM1"])
        self.wavelengthRegion = Self.extractString(
            from: metadata, keys: ["WAVEBAND", "WAVELNTH", "SPECBAND"])
        self.centralWavelength = Self.extractDouble(
            from: metadata, keys: ["WAVELEN", "CENTRWV", "PHOTPLAM"])

        // Temporal information
        self.observationDate = Self.extractString(
            from: metadata, keys: ["DATE-OBS", "DATE_OBS", "DATEOBS"])
        self.exposureStart = Self.extractString(
            from: metadata, keys: ["TIME-OBS", "TIME_OBS", "TIMEOBS"])
        self.exposureTime = Self.extractDouble(
            from: metadata, keys: ["EXPTIME", "EXPOSURE", "INTTIME"])

        // WCS
        self.crpix1 = Self.extractDouble(from: metadata, key: "CRPIX1")
        self.crpix2 = Self.extractDouble(from: metadata, key: "CRPIX2")
        self.crval1 = Self.extractDouble(from: metadata, key: "CRVAL1")
        self.crval2 = Self.extractDouble(from: metadata, key: "CRVAL2")
        self.cdelt1 = Self.extractDouble(from: metadata, key: "CDELT1")
        self.cdelt2 = Self.extractDouble(from: metadata, key: "CDELT2")
        self.wcsAxes = Self.extractInt(from: metadata, key: "WCSAXES")
        self.equinox = Self.extractDouble(from: metadata, key: "EQUINOX")
        self.ctype1 = Self.extractString(from: metadata, key: "CTYPE1")
        self.ctype2 = Self.extractString(from: metadata, key: "CTYPE2")
        self.cunit1 = Self.extractString(from: metadata, key: "CUNIT1")
        self.cunit2 = Self.extractString(from: metadata, key: "CUNIT2")
        self.cd1_1 = Self.extractDouble(from: metadata, key: "CD1_1")
        self.cd1_2 = Self.extractDouble(from: metadata, key: "CD1_2")
        self.cd2_1 = Self.extractDouble(from: metadata, key: "CD2_1")
        self.cd2_2 = Self.extractDouble(from: metadata, key: "CD2_2")
        self.pc1_1 = Self.extractDouble(from: metadata, key: "PC1_1")
        self.pc1_2 = Self.extractDouble(from: metadata, key: "PC1_2")
        self.pc2_1 = Self.extractDouble(from: metadata, key: "PC2_1")
        self.pc2_2 = Self.extractDouble(from: metadata, key: "PC2_2")

        // Instrument & Mission
        self.telescope = Self.extractString(from: metadata, keys: ["TELESCOP", "TELESCOPE"])
        self.instrument = Self.extractString(from: metadata, keys: ["INSTRUME", "INSTRUMENT"])
        self.detector = Self.extractString(from: metadata, keys: ["DETECTOR", "DETNAM"])
        self.observationId = Self.extractString(
            from: metadata, keys: ["OBS_ID", "OBSID", "OBSERVID"])
        self.targetName = Self.extractString(
            from: metadata, keys: ["OBJECT", "TARGNAME", "TARGET"])

        // Calibration
        self.calibrationLevel = Self.extractString(
            from: metadata, keys: ["CALIB_LV", "CAL_VER", "CALVER"])
        self.photometricCalibration = Self.extractString(
            from: metadata, keys: ["PHOTCAL", "PHOT_CAL"])
        self.astrometricCalibration = Self.extractString(
            from: metadata, keys: ["ASTRCAL", "ASTR_CAL", "WCS_CAL"])
        self.processingSoftware = Self.extractString(
            from: metadata, keys: ["ORIGIN", "CREATOR", "SOFTWARE"])
        self.processingDate = Self.extractString(from: metadata, keys: ["DATE", "PROCDATE"])

        // Photometry
        self.zeroPoint = Self.extractDouble(from: metadata, keys: ["ZEROPNT", "ZPOINT", "ZP"])
        self.magZpt = Self.extractDouble(from: metadata, keys: ["MAGZPT", "MAGZERO"])
        self.photSystem = Self.extractString(from: metadata, keys: ["PHOTSYS", "PHOTOMET"])

        // Engineering & Quality
        self.dataQuality = Self.extractString(
            from: metadata, keys: ["DATAQUAL", "QUALITY", "DQ_FLAG"])
        self.seeing = Self.extractDouble(from: metadata, keys: ["SEEING", "FWHM"])
        self.airmass = Self.extractDouble(from: metadata, keys: ["AIRMASS", "SECZ"])
        self.skyBackground = Self.extractDouble(
            from: metadata, keys: ["SKYLEVEL", "BACKGRND", "SKY"])
        self.readNoise = Self.extractDouble(from: metadata, keys: ["RDNOISE", "READNOIS"])
        self.gain = Self.extractDouble(from: metadata, keys: ["GAIN", "EGAIN"])

        // Additional
        self.extensionType = Self.extractString(from: metadata, keys: ["XTENSION", "EXTNAME"])
        self.fitsVersion = Self.extractString(from: metadata, keys: ["SIMPLE", "FITS_VER"])
        self.originalFormat = Self.extractString(from: metadata, keys: ["ORIGFMT", "FORMAT"])
    }

    // MARK: - Helper Methods

    private static func extractString(from metadata: [String: QValue], key: String) -> String? {
        guard let qValue = metadata[key] else { return nil }
        // Handle different QValue types
        switch qValue {
        case .string(let str):
            return str.isEmpty ? nil : str
        case .int(let n):
            return String(n)
        case .float(let f):
            return String(f)
        case .bool(let b):
            return String(b)
        }
    }

    private static func extractString(from metadata: [String: QValue], keys: [String]) -> String? {
        for key in keys {
            if let value = extractString(from: metadata, key: key) {
                return value
            }
        }
        return nil
    }

    private static func extractInt(from metadata: [String: QValue], key: String) -> Int? {
        guard let qValue = metadata[key] else { return nil }
        switch qValue {
        case .int(let n):
            return n
        case .string(let str):
            return Int(str)
        case .float(let f):
            return Int(f)
        case .bool(_):
            return nil
        }
    }

    private static func extractDouble(from metadata: [String: QValue], key: String) -> Double? {
        guard let qValue = metadata[key] else { return nil }
        switch qValue {
        case .float(let f):
            return Double(f)
        case .int(let n):
            return Double(n)
        case .string(let str):
            return Double(str)
        case .bool(_):
            return nil
        }
    }

    private static func extractDouble(from metadata: [String: QValue], keys: [String]) -> Double? {
        for key in keys {
            if let value = extractDouble(from: metadata, key: key) {
                return value
            }
        }
        return nil
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var output = "\n=== FITS Metadata: \(fileIdentifier) ===\n"

        output += "\n📐 Dimensions:\n"
        output += "  NAXIS: \(naxis ?? 0) (\(dimensionDescription))\n"

        if let filter = filter {
            output += "\n🔭 Filter & Wavelength:\n"
            output += "  Filter: \(filter)\n"
            if let waveRegion = wavelengthRegion {
                output += "  Wavelength Region: \(waveRegion)\n"
            }
            if let centralWave = centralWavelength {
                output += "  Central Wavelength: \(centralWave) Å\n"
            }
        }

        if let date = observationDate {
            output += "\n📅 Observation Time:\n"
            output += "  Date: \(date)\n"
            if let time = exposureStart {
                output += "  Start Time: \(time)\n"
            }
            if let expTime = exposureTime {
                output += "  Exposure Time: \(expTime) s\n"
            }
        }

        if crval1 != nil || crval2 != nil {
            output += "\n🌍 World Coordinate System:\n"
            if let ra = crval1 {
                output += "  RA (CRVAL1): \(ra)°\n"
            }
            if let dec = crval2 {
                output += "  DEC (CRVAL2): \(dec)°\n"
            }
            if let pixelScaleX = cdelt1 {
                output += "  Pixel Scale X: \(pixelScaleX)°/pixel\n"
            }
            if let pixelScaleY = cdelt2 {
                output += "  Pixel Scale Y: \(pixelScaleY)°/pixel\n"
            }
            if let ct1 = ctype1, let ct2 = ctype2 {
                output += "  Coord Types: \(ct1), \(ct2)\n"
            }
        }

        if let tel = telescope {
            output += "\n🛰️ Instrument:\n"
            output += "  Telescope: \(tel)\n"
            if let inst = instrument {
                output += "  Instrument: \(inst)\n"
            }
            if let det = detector {
                output += "  Detector: \(det)\n"
            }
        }

        if let calLevel = calibrationLevel {
            output += "\n⚙️ Calibration:\n"
            output += "  Level: \(calLevel)\n"
            if let software = processingSoftware {
                output += "  Software: \(software)\n"
            }
            if let photCal = photometricCalibration {
                output += "  Photometric: \(photCal)\n"
            }
        }

        if seeing != nil || airmass != nil {
            output += "\n🔬 Engineering Metrics:\n"
            if let see = seeing {
                output += "  Seeing: \(see) arcsec\n"
            }
            if let air = airmass {
                output += "  Airmass: \(air)\n"
            }
            if let gain_val = gain {
                output += "  Gain: \(gain_val) e-/ADU\n"
            }
            if let rn = readNoise {
                output += "  Read Noise: \(rn) e-\n"
            }
        }

        output += "\n================================\n"
        return output
    }
}
