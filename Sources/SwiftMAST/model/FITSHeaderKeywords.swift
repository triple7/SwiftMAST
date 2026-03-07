//
//  FITSHeaderKeywords.swift
//  SwiftMAST
//
//  Lookup tables for FITS header keyword descriptions and
//  categorical value metadata. Based on the FITS Standard
//  (NOST 100-2.0) and HEASARC FITS keyword dictionary.
//

import Foundation

/// Provides descriptions and categorical metadata for FITS header keywords.
///
/// Use the static methods to query keyword meanings:
/// ```swift
/// let desc = FITSHeaderKeywords.description(for: "BITPIX")
/// // "Number of bits per data pixel"
///
/// let options = FITSHeaderKeywords.categoricalOptions(for: "XTENSION")
/// // [CategoricalOption(value: "IMAGE", ...), ...]
/// ```
public enum FITSHeaderKeywords {

    // MARK: - Public API

    /// Returns the human-readable description for a FITS keyword.
    /// Falls back to a generic message for unknown keywords.
    public static func description(for keyword: String) -> String {
        keywordDescriptions[keyword] ?? "FITS header keyword"
    }

    /// Returns whether the keyword has a well-known set of categorical values.
    public static func isCategorical(keyword: String) -> Bool {
        categoricalKeywords.keys.contains(keyword)
    }

    /// Returns all valid values with descriptions for a categorical keyword.
    public static func categoricalOptions(for keyword: String) -> [CategoricalOption]? {
        categoricalKeywords[keyword]
    }

    /// Returns the description of a specific value for a categorical keyword.
    public static func valueDescription(
        for keyword: String, value: FITSHeaderValue
    ) -> String? {
        guard let options = categoricalKeywords[keyword] else { return nil }
        let raw = value.rawString.uppercased()
        return options.first { $0.value.uppercased() == raw }?.description
    }

    // MARK: - Keyword Descriptions

    /// Descriptions for the most common FITS header keywords, organized by category.
    private static let keywordDescriptions: [String: String] = {
        var d = [String: String]()

        // --- Mandatory / Structural ---
        d["SIMPLE"] = "File conforms to the FITS standard"
        d["BITPIX"] = "Number of bits per data pixel"
        d["NAXIS"] = "Number of data array dimensions"
        d["NAXIS1"] = "Length of data axis 1 (columns)"
        d["NAXIS2"] = "Length of data axis 2 (rows)"
        d["NAXIS3"] = "Length of data axis 3 (planes/channels)"
        d["NAXIS4"] = "Length of data axis 4"
        d["EXTEND"] = "File may contain standard extensions"
        d["XTENSION"] = "Type of extension (IMAGE, BINTABLE, TABLE)"
        d["PCOUNT"] = "Number of bytes of supplemental data (parameter count)"
        d["GCOUNT"] = "Number of data groups"
        d["EXTNAME"] = "Name of the extension"
        d["EXTVER"] = "Version number of the extension"
        d["EXTLEVEL"] = "Hierarchical level of the extension"

        // --- Scaling / Data Interpretation ---
        d["BSCALE"] = "Linear scaling factor for data values"
        d["BZERO"] = "Zero point offset for data values"
        d["BUNIT"] = "Physical unit of the data array values"
        d["BTYPE"] = "Type of data (e.g. surface brightness)"
        d["BLANK"] = "Value representing undefined pixels (integer arrays)"
        d["DATAMAX"] = "Maximum data value"
        d["DATAMIN"] = "Minimum data value"

        // --- Observation / Target ---
        d["OBJECT"] = "Name of the observed object"
        d["TARGNAME"] = "Target name as specified in the proposal"
        d["TELESCOP"] = "Telescope used to acquire the data"
        d["INSTRUME"] = "Instrument used to acquire the data"
        d["DETECTOR"] = "Detector used to acquire the data"
        d["FILTER"] = "Filter used during observation"
        d["FILTER1"] = "First filter element"
        d["FILTER2"] = "Second filter element"
        d["PUPIL"] = "Pupil wheel element"
        d["GRATING"] = "Grating used during observation"
        d["CHANNEL"] = "Instrument channel"
        d["BAND"] = "Wavelength band"
        d["OBSMODE"] = "Observation mode"
        d["OBSTYPE"] = "Observation type"

        // --- Time ---
        d["DATE"] = "File creation date (UTC)"
        d["DATE-OBS"] = "Date of observation start (UTC)"
        d["DATE-BEG"] = "Date-time of observation start"
        d["DATE-END"] = "Date-time of observation end"
        d["TIME-OBS"] = "Time of observation start (UTC)"
        d["MJD-OBS"] = "Modified Julian Date of observation start"
        d["MJD-BEG"] = "Modified Julian Date of exposure start"
        d["MJD-MID"] = "Modified Julian Date of exposure midpoint"
        d["MJD-AVG"] = "Modified Julian Date of exposure midpoint"
        d["MJD-END"] = "Modified Julian Date of exposure end"
        d["EXPTIME"] = "Exposure time in seconds"
        d["XPOSURE"] = "Effective exposure time in seconds"
        d["TELAPSE"] = "Total elapsed exposure time in seconds"
        d["EXPSTART"] = "Exposure start time in MJD"
        d["EXPEND"] = "Exposure end time in MJD"
        d["TIMESYS"] = "Principal time system for time-related keywords"
        d["TIMEUNIT"] = "Default unit for time values"

        // --- World Coordinate System (WCS) ---
        d["WCSAXES"] = "Number of World Coordinate System axes"
        d["RADESYS"] = "Celestial coordinate reference frame"
        d["EQUINOX"] = "Equinox of celestial coordinate system"
        d["CTYPE1"] = "Coordinate type for axis 1"
        d["CTYPE2"] = "Coordinate type for axis 2"
        d["CUNIT1"] = "Physical unit for axis 1 coordinate"
        d["CUNIT2"] = "Physical unit for axis 2 coordinate"
        d["CRPIX1"] = "Reference pixel on axis 1"
        d["CRPIX2"] = "Reference pixel on axis 2"
        d["CRVAL1"] = "Coordinate value at reference pixel on axis 1"
        d["CRVAL2"] = "Coordinate value at reference pixel on axis 2"
        d["CDELT1"] = "Coordinate increment along axis 1"
        d["CDELT2"] = "Coordinate increment along axis 2"
        d["CD1_1"] = "Coordinate transformation matrix element (1,1)"
        d["CD1_2"] = "Coordinate transformation matrix element (1,2)"
        d["CD2_1"] = "Coordinate transformation matrix element (2,1)"
        d["CD2_2"] = "Coordinate transformation matrix element (2,2)"
        d["PC1_1"] = "Linear transformation matrix element (1,1)"
        d["PC1_2"] = "Linear transformation matrix element (1,2)"
        d["PC2_1"] = "Linear transformation matrix element (2,1)"
        d["PC2_2"] = "Linear transformation matrix element (2,2)"
        d["LONPOLE"] = "Native longitude of the celestial pole"
        d["LATPOLE"] = "Native latitude of the celestial pole"

        // --- Target Coordinates ---
        d["RA_TARG"] = "Right ascension of the target (degrees)"
        d["DEC_TARG"] = "Declination of the target (degrees)"
        d["TARG_RA"] = "Right ascension of the target (degrees)"
        d["TARG_DEC"] = "Declination of the target (degrees)"
        d["RA_V1"] = "Right ascension of the V1 axis (degrees)"
        d["DEC_V1"] = "Declination of the V1 axis (degrees)"
        d["PA_V3"] = "Position angle of the V3 axis (degrees)"
        d["PA_APER"] = "Position angle of the aperture (degrees)"
        d["PROP_RA"] = "Proposed right ascension (degrees)"
        d["PROP_DEC"] = "Proposed declination (degrees)"

        // --- Proposal / Program ---
        d["TITLE"] = "Proposal title"
        d["PI_NAME"] = "Principal investigator name"
        d["PROGRAM"] = "Program number"
        d["CATEGORY"] = "Program category"
        d["SCICAT"] = "Science category"
        d["ORIGIN"] = "Institution that created the file"
        d["AUTHOR"] = "Author of the data"

        // --- JWST Specific ---
        d["DATAMODL"] = "Type of data model"
        d["EXP_TYPE"] = "Exposure type"
        d["TEMPLATE"] = "Observation template used"
        d["VISIT_ID"] = "Visit identifier"
        d["OBSERVTN"] = "Observation number"
        d["OBS_ID"] = "Programmatic observation identifier"
        d["EXPOSURE"] = "Exposure request number"
        d["VISITYPE"] = "Visit type"
        d["PHOTMJSR"] = "Flux density producing 1 count/sec (MJy/sr)"
        d["PIXAR_SR"] = "Nominal pixel area in steradians"
        d["PIXAR_A2"] = "Nominal pixel area in arcsec squared"
        d["VA_SCALE"] = "Velocity aberration scale factor"

        // --- HST Specific ---
        d["LINENUM"] = "Proposal log-sheet line number"
        d["ROOTNAME"] = "Root name of the observation set"
        d["IMAGETYP"] = "Type of exposure identifier"
        d["POSTARG1"] = "POSTARG in axis 1 direction"
        d["POSTARG2"] = "POSTARG in axis 2 direction"
        d["APERTURE"] = "Aperture name"
        d["PROPAPER"] = "Proposed aperture name"

        // --- Calibration / Processing ---
        d["FILENAME"] = "Name of the file"
        d["FILETYPE"] = "Type of data in the file"
        d["CAL_VER"] = "Calibration software version"
        d["SDP_VER"] = "Data processing software version"
        d["PRD_VER"] = "Project Reference Database version"
        d["S_REGION"] = "Spatial footprint (STC-S format)"

        // --- Standard Comment Keywords ---
        d["COMMENT"] = "Comment"
        d["HISTORY"] = "Processing history entry"
        d[""] = "Blank keyword (headline or padding)"

        return d
    }()

    // MARK: - Categorical Keywords

    /// Keywords whose values come from a well-defined set per the FITS standard.
    private static let categoricalKeywords: [String: [CategoricalOption]] = [
        "XTENSION": FITSXtension.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
        "BITPIX": FITSBitpix.allCases.map {
            CategoricalOption(value: String($0.rawValue), description: $0.description)
        },
        "RADESYS": FITSRaDesys.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
        "TIMESYS": FITSTimeSys.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
    ]
}
