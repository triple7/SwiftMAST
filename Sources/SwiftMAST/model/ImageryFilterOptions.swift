//
//  ImageryFilterOptions.swift
//
//
//  Created by SwiftMAST on 21/12/2024.
//

import Foundation
import SwiftQValue

/// Filter options for downloadImagery and getScienceImageProducts
/// Provides a generic way to filter MAST imagery queries by various criteria
public struct ImageryFilterOptions {
    /// Wavelength regions to include (e.g., ["UV", "OPTICAL", "INFRARED", "XRAY", "EUV", "IR"])
    public var wavelengthRegions: [String]?
    /// Missions/collections to include (e.g., ["HST", "JWST", "SWIFT", "TESS", "PS1", "GALEX"])
    public var collections: [String]?
    /// Specific instruments to include (e.g., ["UVOT", "ACS", "WFC3"])
    public var instruments: [String]?
    /// Filter bands to include (e.g., ["NUV", "FUV", "F606W"])
    public var filterBands: [String]?
    /// Calibration levels (default: ["3", "4"] for calibrated data)
    public var calibLevels: [String]
    /// Data product types (default: ["IMAGE"])
    public var dataProductTypes: [String]
    /// Intent type (default: "science")
    public var intentType: String
    /// Data rights (default: "PUBLIC")
    public var dataRights: String

    /// Initialize with default science image settings
    public init(
        wavelengthRegions: [String]? = nil,
        collections: [String]? = nil,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        dataProductTypes: [String] = ["IMAGE"],
        intentType: String = "science",
        dataRights: String = "PUBLIC"
    ) {
        self.wavelengthRegions = wavelengthRegions
        self.collections = collections
        self.instruments = instruments
        self.filterBands = filterBands
        self.calibLevels = calibLevels
        self.dataProductTypes = dataProductTypes
        self.intentType = intentType
        self.dataRights = dataRights
    }

    /// Convert to MASTJsonFilter array for API queries
    public func toMASTFilters() -> [MASTJsonFilter] {
        var filters: [MASTJsonFilter] = []

        // Always include data rights
        filters.append(
            MASTJsonFilter(
                paramName: Coam.dataRights.id,
                values: QObject(values: [QValue(value: dataRights)] as Any)
            ))

        // Calibration levels
        if !calibLevels.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.calib_level.id,
                    values: QObject(values: calibLevels.map { QValue(value: $0) } as Any)
                ))
        }

        // Data product types
        if !dataProductTypes.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.dataproduct_type.id,
                    values: QObject(values: dataProductTypes.map { QValue(value: $0) } as Any)
                ))
        }

        // Intent type
        filters.append(
            MASTJsonFilter(
                paramName: Coam.intentType.id,
                values: QObject(values: [QValue(value: intentType)] as Any)
            ))

        // Optional: Wavelength regions
        if let regions = wavelengthRegions, !regions.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.wavelength_region.id,
                    values: QObject(values: regions.map { QValue(value: $0) } as Any),
                    separator: ";"
                ))
        }

        // Optional: Collections/Missions
        if let cols = collections, !cols.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.obs_collection.id,
                    values: QObject(values: cols.map { QValue(value: $0) } as Any),
                    separator: ";"
                ))
        }

        // Optional: Instruments
        if let insts = instruments, !insts.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.instrument_name.id,
                    values: QObject(values: insts.map { QValue(value: $0) } as Any),
                    separator: ";"
                ))
        }

        // Optional: Filter bands
        if let bands = filterBands, !bands.isEmpty {
            filters.append(
                MASTJsonFilter(
                    paramName: Coam.filters.id,
                    values: QObject(values: bands.map { QValue(value: $0) } as Any),
                    separator: ";"
                ))
        }

        return filters
    }

    // MARK: - Convenience Presets

    /// Default science images (all wavelengths, all missions)
    public static var defaultScience: ImageryFilterOptions {
        ImageryFilterOptions()
    }

    /// UV-only imagery
    public static var uvOnly: ImageryFilterOptions {
        ImageryFilterOptions(wavelengthRegions: ["UV", "EUV"])
    }

    /// Optical-only imagery
    public static var opticalOnly: ImageryFilterOptions {
        ImageryFilterOptions(wavelengthRegions: ["OPTICAL"])
    }

    /// Infrared-only imagery
    public static var infraredOnly: ImageryFilterOptions {
        ImageryFilterOptions(wavelengthRegions: ["INFRARED", "IR"])
    }

    /// X-ray imagery
    public static var xrayOnly: ImageryFilterOptions {
        ImageryFilterOptions(wavelengthRegions: ["XRAY"])
    }

    /// Hubble Space Telescope only
    public static var hubbleOnly: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["HST"])
    }

    /// James Webb Space Telescope only
    public static var jwstOnly: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["JWST"])
    }

    /// GALEX ultraviolet survey
    public static var galexOnly: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["GALEX"])
    }

    /// Swift UVOT
    public static var swiftOnly: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["SWIFT"])
    }

    /// JWST MIRI instrument only
    public static var jwstMIRI: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["JWST"], instruments: ["MIRI/IMAGE"])
    }

    /// JWST NIRCam instrument only
    public static var jwstNIRCam: ImageryFilterOptions {
        ImageryFilterOptions(collections: ["JWST"], instruments: ["NIRCAM/IMAGE"])
    }
}
