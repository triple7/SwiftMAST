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

    /// Returns the header keyword category for a given FITS keyword.
    ///
    /// Covers both general FITS structural, scaling, WCS, and time keywords as well as
    /// JWST-specific keywords from the MAST Instrument Keyword Dictionary at
    /// https://mast.stsci.edu/api/v0/_jwst_inst_keywd.html
    /// Returns `.unknown` for keywords not in the category map.
    public static func category(for keyword: String) -> HeaderKeywordCategory {
        keywordCategories[keyword] ?? .unknown
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

        // --- JWST: Standard parameters ---
        d["NEXTEND"] = "Number of file extensions"

        // --- JWST: Basic parameters ---
        d["OSS_VER"] = "Version number of the OSS software"
        d["CAL_VCS"] = "Calibration software repository version"
        d["HGA_MOVE"] = "High Gain Antenna moved during data collection"
        d["PWFSEET"] = "Exposure end time from the previous WFS exposure (MJD)"
        d["NWFSEST"] = "Exposure start time from the next WFS exposure (MJD)"

        // --- JWST: IFU cube parameters ---
        d["ERRTYPE"] = "Type of values in the error array (ERR, IERR, VAR, IVAR)"
        d["ROIS"] = "Radius of the region of interest in spatial dimensions (arcsec)"
        d["ROIW"] = "Radius of the region of interest in wavelength dimension (arcsec)"
        d["WTYPE"] = "Type of weighting used when combining IFU point cloud fluxes"
        d["WPOWER"] = "Weighting power controlling distance weighting for IFU spaxels"

        // --- JWST: Programmatic information ---
        d["SUBCAT"] = "Program sub-category (FGS, MIRI, NIRCAM, NIRISS, NIRSPEC, SC)"
        d["CONT_ID"] = "Continuation of the specified previous program number"

        // --- JWST: Observation identifiers ---
        d["VISIT"] = "Visit number within the observation"
        d["OBSLABEL"] = "Proposer-defined label for the observation"
        d["OBSFOLDR"] = "APT observation folder name containing this observation"
        d["VISITGRP"] = "Visit group identifier for parallel synchronization"
        d["SEQ_ID"] = "Parallel sequence identifier within a group"
        d["ACT_ID"] = "Activity identifier (base-36) within a sequence"
        d["BKGDTARG"] = "Exposure is flagged as a background target"
        d["ENG_QUAL"] = "Engineering database quality flag (OK or SUSPECT)"
        d["ENGQLPTG"] = "Source and quality of spacecraft pointing keywords"
        d["IS_PSF"] = "Exposure intended as a PSF reference observation"
        d["SELFREF"] = "Coronagraphic observation is a self-referencing PSF survey"

        // --- JWST: Visit information ---
        d["VSTSTART"] = "Observatory UTC time when the visit started"
        d["VISITSTA"] = "Status of the visit (e.g. DATALOSS)"
        d["NEXPOSUR"] = "Total number of planned exposures in the visit"
        d["INTARGET"] = "At least one exposure in the visit is internally targeted"
        d["TARGOOPP"] = "Visit scheduled as a target of opportunity"
        d["TSOVISIT"] = "Visit uses Time Series Observation special requirement"
        d["EXP_ONLY"] = "Exposure taken through special commanding without SI configuration"
        d["CROWDFLD"] = "FGSes operating in a crowded star field"

        // --- JWST: Target information ---
        d["TARGPROP"] = "Proposer-preferred name for the target (2–31 characters)"
        d["TARGTYPE"] = "Target type: FIXED, MOVING, or GENERIC"
        d["TARGURA"] = "Target right ascension uncertainty at mid-exposure (arcsec)"
        d["TARGUDEC"] = "Target declination uncertainty at mid-exposure (arcsec)"
        d["MU_RA"] = "Proper motion of the target in RA from APT (arcsec/year)"
        d["MU_DEC"] = "Proper motion of the target in Dec from APT (arcsec/year)"
        d["MU_EPOCH"] = "Epoch of the proper motion values"
        d["SRCTYAPT"] = "APT source type for spectroscopy: POINT, EXTENDED, or UNKNOWN"

        // --- JWST: Instrument configuration ---
        d["LAMP"] = "Internal lamp state for all science instruments"
        d["MODULE"] = "NIRCam module used (A, B, or MULTIPLE)"
        d["CCCSTATE"] = "MIRI contamination control cover state (OPEN, CLOSED, LOCKED)"
        d["MIRNGRPS"] = "MIRI flight system number of groups"
        d["MIRNFRMS"] = "MIRI flight system number of frames"
        d["CORONMSK"] = "MIRI coronagraph mask in use"
        d["DETMODE"] = "Detector mode: FLUSH_MODE, TEST_PATTERN, CLOCKING, or EXPOSURE"
        d["CMD_TSEL"] = "SCE test pattern: COLUMNS, ROWS, FRAMES, or ALL"
        d["OPMODE"] = "NIRSpec lamp operating mode (MSASPEC, IFU, IMAGE, FIXEDSLIT, etc.)"
        d["PILIN"] = "Pupil imaging lens in use (T or F)"
        d["FOCUSPOS"] = "FGS focus mechanism position in millimeters (-4.0 to 4.0)"
        d["FWCPOS"] = "NIRISS filter wheel encoder position (millimeters)"
        d["PWCPOS"] = "NIRISS pupil wheel encoder position (millimeters)"
        d["GWA_XTIL"] = "NIRSpec grating wheel averaged X-tilt sensor value"
        d["GWA_YTIL"] = "NIRSpec grating wheel averaged Y-tilt sensor value"
        d["GWA_XP_V"] = "NIRSpec grating wheel X-position tilt sensor calibrated value"
        d["GWA_YP_V"] = "NIRSpec grating wheel Y-position tilt sensor calibrated value"
        d["GWA_PXAV"] = "NIRSpec grating wheel REC-averaged calibrated X-tilt value"
        d["GWA_PYAV"] = "NIRSpec grating wheel REC-averaged calibrated Y-tilt value"
        d["GWA_TILT"] = "NIRSpec grating wheel temperature sensor calibrated value"
        d["NRS_NORM"] = "Number of normal pixels per block in NIRSpec IRS2 readout"
        d["NRS_REF"] = "Number of interleaved reference pixels per block in NIRSpec IRS2 readout"
        d["MSASTATE"] = "NIRSpec MSA state: ALLOPEN, ALLCLOSED, or CONFIGURED"
        d["MSAMETFL"] = "NIRSpec MSA metadata file name"
        d["MSAMETID"] = "Unique identifier within a visit for MSA configuration collection"
        d["MSACONID"] = "Unique identifier of all MSA configurations within a visit"
        d["PREIMAGE"] = "Name of reference image used to measure position for this source"
        d["IS_IMPRT"] = "Exposure flagged as a leakcal or imprint exposure"
        d["FXD_SLIT"] = "NIRSpec fixed slit aperture name (S200A1, S200A2, S200B1, S400A1, S1600A1)"

        // --- JWST: Exposure parameters ---
        d["EFFEXPTM"] = "Effective exposure time corrected for dead time (seconds)"
        d["DURATION"] = "Total duration of exposure: integration time × number of integrations (seconds)"
        d["GAINFACT"] = "Data scaling factor ratio between gain=2 and nominal gain=1"
        d["SCTARATE"] = "Spacecraft clock time adjustment rate (milliseconds/second)"
        d["EXPCOUNT"] = "Monotonically increasing exposure count within a visit"
        d["EXPRIPAR"] = "Exposure is PRIME, PARALLEL_COORDINATED, or PARALLEL_PURE"
        d["EXPMID"] = "Exposure mid time (Modified Julian Date)"
        d["EXPSTENG"] = "UTC exposure start time from engineering data stream"
        d["OSF_FILE"] = "Observatory Status File name for this exposure"
        d["READPATT"] = "Readout pattern name (pre-defined NFRAMES, GROUPGAP, NRESETS combination)"
        d["NINTS"] = "Number of integrations within the exposure"
        d["EXSEGTOT"] = "Total number of segments in a TSO single exposure"
        d["EXSEGNUM"] = "Sequential segment number within a TSO single exposure"
        d["INTSTART"] = "Number of the first integration in a segmented exposure product"
        d["INTEND"] = "Number of the last integration in a segmented exposure product"
        d["NGROUPS"] = "Number of groups per integration"
        d["NFRAMES"] = "Number of frames in a group"
        d["GROUPGAP"] = "Number of frames skipped between groups"
        d["NSAMPLES"] = "Number of A/D samples per pixel read"
        d["TSAMPLE"] = "Time between samples (microseconds)"
        d["TFRAME"] = "Time between start of successive frames (seconds)"
        d["TGROUP"] = "Time between start of successive groups (seconds)"
        d["EFFINTTM"] = "Effective integration time (seconds)"
        d["NRSTSTRT"] = "Number of resets at the start of exposure"
        d["NRESETS"] = "Number of resets separating integrations within an exposure"
        d["ZEROFRAM"] = "Zero frame was read separately (T or F)"
        d["DATAPROB"] = "Science telemetry indicated data problems (T or F)"
        d["SCA_NUM"] = "Sensor Chip Assembly number (1–18)"
        d["DATAMODE"] = "Post-processing method used in FPAP; maps to readout pattern (0–86)"
        d["FRMDIVSR"] = "Frame divisor used on-board when averaging multiple frames into a group"
        d["DRPFRMS1"] = "Number of frames dropped prior to first integration"
        d["DRPFRMS3"] = "Number of frames dropped between integrations"
        d["NOUTPUTS"] = "Number of detector amplifier outputs used (1, 4, or 5)"

        // --- JWST: Association parameters ---
        d["ASNPOOL"] = "Name of the association pool file used as pipeline input"
        d["ASNTABLE"] = "Name of the association table from which this product was created"

        // --- JWST: Subarray parameters ---
        d["SUBARRAY"] = "Subarray name (FULL or named subarray up to 9 characters)"
        d["SUBSTRT1"] = "Starting pixel in the full science frame axis 1 direction"
        d["SUBSTRT2"] = "Starting pixel in the full science frame axis 2 direction"
        d["SUBSIZE1"] = "Number of pixels in the full science frame axis 1 direction"
        d["SUBSIZE2"] = "Number of pixels in the full science frame axis 2 direction"
        d["FASTAXIS"] = "Axis and direction of fast detector readout (±1 or ±2)"
        d["SLOWAXIS"] = "Axis and direction of slow detector readout (±1 or ±2)"

        // --- JWST: Dither information ---
        d["NUMDTHPT"] = "Total number of points in the entire dither pattern"
        d["PATT_NUM"] = "Position number within dither pattern"
        d["XOFFSET"] = "X offset from pattern starting position in SI ideal frame (arcsec)"
        d["YOFFSET"] = "Y offset from pattern starting position in SI ideal frame (arcsec)"
        d["PATTTYPE"] = "Dither pattern type (FULL, INTRAMODULE, INTRASCA, NONE, etc.)"
        d["PRIDTPTS"] = "Number of points in FGS primary dither pattern"
        d["SUBPXPTS"] = "Number of points in FGS subpixel dither pattern"
        d["NRIMDTPT"] = "NIRISS direct image dither number of points"
        d["PATTSIZE"] = "NIRCam/NIRISS dither pattern size (NONE, SMALL, MEDIUM, LARGE)"
        d["PRIDTYPE"] = "NIRCam primary dither specification with number of points"
        d["SUBPXPAT"] = "NIRCam subpixel dither pattern type (STANDARD, SMALL-GRID-DITHER, NONE)"
        d["SMGRDPAT"] = "NIRCam small grid dither pattern name"
        d["PATTSTRT"] = "MIRI imaging starting point in the dither cycling pattern (1–311)"
        d["PATTNPTS"] = "MIRI imaging number of points in CYCLING dither pattern (≥3)"
        d["NUMDSETS"] = "Total number of 4-point dither sets (1–10)"
        d["DITHPNTS"] = "Sparse cycling dither positions list"
        d["NOD_TYPE"] = "NIRSpec MSA nod pattern type (NONE, 2-, 3-, or 5-SHUTTER-SLITLET)"
        d["MRSPRCHN"] = "MIRI MRS channel for which dither is optimized"
        d["DSETSTRT"] = "Starting set number of the 4-point dither sets (1–10)"
        d["DITHOPFR"] = "Dither optimization type: POINT-SOURCE or EXTENDED-SOURCE"
        d["DITHDIRC"] = "Dither direction: POSITIVE or NEGATIVE"
        d["SPECNSTP"] = "MIRI LRS number of steps in the spectral direction"
        d["SPECSTEP"] = "MIRI LRS distance between steps in the spectral direction (arcsec)"
        d["SPCOFFST"] = "MIRI LRS spectral offset from pattern starting position (arcsec)"
        d["SPATNSTP"] = "MIRI LRS number of steps in the spatial direction"
        d["SPATSTEP"] = "MIRI LRS distance between steps in the spatial direction (arcsec)"
        d["SPTOFFST"] = "MIRI LRS spatial offset from pattern starting position (arcsec)"
        d["SPEC_NUM"] = "MIRI LRS position number within spectral steps"
        d["SPAT_NUM"] = "MIRI LRS position number within spatial steps"

        // --- JWST: NIRSpec WFS&C engineering ---
        d["RMA_POS"] = "NIRSpec Refocus Mechanism Assembly latest hall-position sensor value"
        d["FCSRLPOS"] = "NIRSpec RMA relative position in motor steps (-18400 to +18400)"

        // --- JWST: Focus Adjust Mechanism ---
        d["FAM_LA1"] = "FAM primary sensor measured position of linear actuator 1 (steps)"
        d["FASTEP1"] = "Requested focus actuator 1 starting steps per exposure specification"
        d["FAUNIT1"] = "Requested focus actuator 1 starting units per exposure specification"
        d["FAPHASE1"] = "Requested focus actuator 1 starting phase per exposure specification"
        d["FA1VALUE"] = "Requested focus actuator 1 absolute position value"
        d["FAM_LA2"] = "FAM primary sensor measured position of linear actuator 2 (steps)"
        d["FASTEP2"] = "Requested focus actuator 2 starting steps per exposure specification"
        d["FAUNIT2"] = "Requested focus actuator 2 starting units per exposure specification"
        d["FAPHASE2"] = "Requested focus actuator 2 starting phase per exposure specification"
        d["FA2VALUE"] = "Requested focus actuator 2 absolute position value"
        d["FAM_LA3"] = "FAM primary sensor measured position of linear actuator 3 (steps)"
        d["FASTEP3"] = "Requested focus actuator 3 starting steps per exposure specification"
        d["FAUNIT3"] = "Requested focus actuator 3 starting units per exposure specification"
        d["FAPHASE3"] = "Requested focus actuator 3 starting phase per exposure specification"
        d["FA3VALUE"] = "Requested focus actuator 3 absolute position value"

        // --- JWST: Aperture information ---
        d["APERNAME"] = "S&OC PRD aperture name used for telescope pointing"
        d["PPS_APER"] = "Original aperture name as supplied by PPS in the PPS_DB"

        // --- JWST: Time information ---
        d["BARTDELT"] = "Calculated barycentric time correction from UTC (seconds)"
        d["BSTRTIME"] = "Barycentric-corrected exposure start time (MJD)"
        d["BMIDTIME"] = "Barycentric-corrected exposure mid time (MJD)"
        d["BENDTIME"] = "Barycentric-corrected exposure end time (MJD)"
        d["HELIDELT"] = "Calculated heliocentric time correction from UTC (seconds)"
        d["HSTRTIME"] = "Heliocentric exposure start time (MJD)"
        d["HMIDTIME"] = "Heliocentric exposure mid time (MJD)"
        d["HENDTIME"] = "Heliocentric exposure end time (MJD)"

        // --- JWST: Reference file information ---
        d["CRDS_VER"] = "Version of the CRDS client software used for reference file selection"
        d["CRDS_CTX"] = "Version of the CRDS context (PMAP) controlling reference file selection"

        // --- JWST: Resampling parameter information ---
        d["TEXPTIME"] = "Total exposure time of all pointings in a resampled product (seconds)"
        d["TCATFILE"] = "Tweakreg catalog filename used for image alignment"
        d["SCATFILE"] = "Source catalog filename generated by the source_catalog pipeline step"

        // --- JWST: Guide star information ---
        d["GS_ORDER"] = "Index of this guide star within the list of selected guide stars"
        d["GSSTRTTM"] = "Observatory UTC time when guide star activity started"
        d["GSENDTIM"] = "UTC end time of guide star acquisition activity"
        d["GDSTARID"] = "Guide Star Catalog 2 identifier (10 character, base-36)"
        d["GS_RA"] = "ICRS right ascension of the guide star (degrees)"
        d["GS_DEC"] = "ICRS declination of the guide star (degrees)"
        d["GS_URA"] = "ICRS right ascension uncertainty of the guide star (arcsec)"
        d["GS_UDEC"] = "ICRS declination uncertainty of the guide star (arcsec)"
        d["GS_MAG"] = "Guide star magnitude in FGS detector"
        d["GS_UMAG"] = "Guide star magnitude uncertainty"
        d["GS_V3_PA"] = "V3 position angle of the guide star at the guide star location (degrees)"
        d["PCS_MODE"] = "Pointing Control System mode (FINEGUIDE, COARSE, TRACK, MOVING, NONE)"
        d["VISITEND"] = "Observatory UTC time when the visit completed"

        // --- JWST: Background information ---
        d["BKGLEVEL"] = "Overall background signal level computed by the skymatch pipeline step"
        d["BKGSUB"] = "Background signal from BKGLEVEL has been subtracted (T or F)"
        d["MASTERBG"] = "Name of the 1-D master background spectrum file used in pipeline"

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

    // MARK: - Keyword Categories

    /// Header keyword → category mapping.
    ///
    /// Covers general FITS structural, scaling, WCS, and time keywords as well as
    /// JWST-specific keywords from the MAST JWST Instrument Keyword Dictionary.
    private static let keywordCategories: [String: HeaderKeywordCategory] = {
        var c = [String: HeaderKeywordCategory]()

        // Structural — FITS file and HDU structure
        c["SIMPLE"]   = .structural
        c["BITPIX"]   = .structural
        c["NAXIS"]    = .structural
        c["NAXIS1"]   = .structural
        c["NAXIS2"]   = .structural
        c["NAXIS3"]   = .structural
        c["NAXIS4"]   = .structural
        c["EXTEND"]   = .structural
        c["XTENSION"]  = .structural
        c["PCOUNT"]   = .structural
        c["GCOUNT"]   = .structural
        c["EXTNAME"]  = .structural
        c["EXTVER"]   = .structural
        c["EXTLEVEL"] = .structural
        c["NEXTEND"]  = .structural

        // Data Scaling — value transformation and physical units
        c["BSCALE"]   = .dataScaling
        c["BZERO"]    = .dataScaling
        c["BUNIT"]    = .dataScaling
        c["BTYPE"]    = .dataScaling
        c["BLANK"]    = .dataScaling
        c["DATAMAX"]  = .dataScaling
        c["DATAMIN"]  = .dataScaling

        // WCS — World Coordinate System
        c["WCSAXES"]  = .wcs
        c["RADESYS"]  = .wcs
        c["EQUINOX"]  = .wcs
        c["CTYPE1"]   = .wcs
        c["CTYPE2"]   = .wcs
        c["CUNIT1"]   = .wcs
        c["CUNIT2"]   = .wcs
        c["CRPIX1"]   = .wcs
        c["CRPIX2"]   = .wcs
        c["CRVAL1"]   = .wcs
        c["CRVAL2"]   = .wcs
        c["CDELT1"]   = .wcs
        c["CDELT2"]   = .wcs
        c["CD1_1"]    = .wcs
        c["CD1_2"]    = .wcs
        c["CD2_1"]    = .wcs
        c["CD2_2"]    = .wcs
        c["PC1_1"]    = .wcs
        c["PC1_2"]    = .wcs
        c["PC2_1"]    = .wcs
        c["PC2_2"]    = .wcs
        c["LONPOLE"]  = .wcs
        c["LATPOLE"]  = .wcs
        c["S_REGION"] = .wcs

        // Time — dates, time-scales, and temporal corrections
        c["DATE"]     = .time
        c["DATE-OBS"] = .time
        c["DATE-BEG"] = .time
        c["DATE-END"] = .time
        c["TIME-OBS"] = .time
        c["MJD-OBS"]  = .time
        c["MJD-BEG"]  = .time
        c["MJD-MID"]  = .time
        c["MJD-AVG"]  = .time
        c["MJD-END"]  = .time
        c["TIMESYS"]  = .time
        c["TIMEUNIT"] = .time
        c["BARTDELT"] = .time
        c["BSTRTIME"] = .time
        c["BMIDTIME"] = .time
        c["BENDTIME"] = .time
        c["HELIDELT"] = .time
        c["HSTRTIME"] = .time
        c["HMIDTIME"] = .time
        c["HENDTIME"] = .time

        // Program — proposal and principal investigator metadata
        c["TITLE"]    = .program
        c["PI_NAME"]  = .program
        c["CATEGORY"] = .program
        c["SUBCAT"]   = .program
        c["SCICAT"]   = .program
        c["CONT_ID"]  = .program
        c["ORIGIN"]   = .program

        // Observation — identifiers and observation-level flags
        c["OBS_ID"]   = .observation
        c["VISIT_ID"] = .observation
        c["PROGRAM"]  = .observation
        c["OBSERVTN"] = .observation
        c["VISIT"]    = .observation
        c["OBSLABEL"] = .observation
        c["OBSFOLDR"] = .observation
        c["VISITGRP"] = .observation
        c["SEQ_ID"]   = .observation
        c["ACT_ID"]   = .observation
        c["EXPOSURE"] = .observation
        c["BKGDTARG"] = .observation
        c["TEMPLATE"] = .observation
        c["ENG_QUAL"] = .observation
        c["ENGQLPTG"] = .observation
        c["IS_PSF"]   = .observation
        c["SELFREF"]  = .observation
        c["OBJECT"]   = .observation
        c["OBSMODE"]  = .observation
        c["OBSTYPE"]  = .observation

        // Visit — scheduling, execution status, and configuration
        c["VISITYPE"] = .visit
        c["VSTSTART"] = .visit
        c["VISITSTA"] = .visit
        c["NEXPOSUR"] = .visit
        c["INTARGET"] = .visit
        c["TARGOOPP"] = .visit
        c["TSOVISIT"] = .visit
        c["EXP_ONLY"] = .visit
        c["CROWDFLD"] = .visit

        // Target — coordinates, proper motion, and source classification
        c["TARGPROP"] = .target
        c["TARGNAME"] = .target
        c["TARGTYPE"] = .target
        c["TARG_RA"]  = .target
        c["TARG_DEC"] = .target
        c["TARGURA"]  = .target
        c["TARGUDEC"] = .target
        c["MU_RA"]    = .target
        c["MU_DEC"]   = .target
        c["MU_EPOCH"] = .target
        c["PROP_RA"]  = .target
        c["PROP_DEC"] = .target
        c["SRCTYAPT"] = .target
        c["RA_TARG"]  = .target
        c["DEC_TARG"] = .target
        c["RA_V1"]    = .target
        c["DEC_V1"]   = .target
        c["PA_V3"]    = .target
        c["PA_APER"]  = .target

        // Instrument — telescope, detector, and optical element
        c["TELESCOP"]  = .instrument
        c["INSTRUME"]  = .instrument
        c["DETECTOR"]  = .instrument
        c["DATAMODL"]  = .instrument
        c["FILTER"]    = .instrument
        c["FILTER1"]   = .instrument
        c["FILTER2"]   = .instrument
        c["GRATING"]   = .instrument
        c["PUPIL"]     = .instrument
        c["CHANNEL"]   = .instrument
        c["BAND"]      = .instrument
        c["LAMP"]      = .instrument
        c["MODULE"]    = .instrument
        c["CCCSTATE"]  = .instrument
        c["MIRNGRPS"]  = .instrument
        c["MIRNFRMS"]  = .instrument
        c["CORONMSK"]  = .instrument
        c["DETMODE"]   = .instrument
        c["CMD_TSEL"]  = .instrument
        c["OPMODE"]    = .instrument
        c["PILIN"]     = .instrument
        c["FOCUSPOS"]  = .instrument
        c["FWCPOS"]    = .instrument
        c["PWCPOS"]    = .instrument
        c["GWA_XTIL"]  = .instrument
        c["GWA_YTIL"]  = .instrument
        c["GWA_XP_V"]  = .instrument
        c["GWA_YP_V"]  = .instrument
        c["GWA_PXAV"]  = .instrument
        c["GWA_PYAV"]  = .instrument
        c["GWA_TILT"]  = .instrument
        c["NRS_NORM"]  = .instrument
        c["NRS_REF"]   = .instrument
        c["MSASTATE"]  = .instrument
        c["MSAMETFL"]  = .instrument
        c["MSAMETID"]  = .instrument
        c["MSACONID"]  = .instrument
        c["PREIMAGE"]  = .instrument
        c["IS_IMPRT"]  = .instrument
        c["FXD_SLIT"]  = .instrument
        c["APERTURE"]  = .instrument
        c["PROPAPER"]  = .instrument

        // Exposure — readout parameters, integrations, groups
        c["EXPTIME"]   = .exposure
        c["XPOSURE"]   = .exposure
        c["TELAPSE"]   = .exposure
        c["EXPSTART"]  = .exposure
        c["EXPMID"]    = .exposure
        c["EXPEND"]    = .exposure
        c["EFFEXPTM"]  = .exposure
        c["DURATION"]  = .exposure
        c["GAINFACT"]  = .exposure
        c["SCTARATE"]  = .exposure
        c["EXPCOUNT"]  = .exposure
        c["EXPRIPAR"]  = .exposure
        c["EXPSTENG"]  = .exposure
        c["OSF_FILE"]  = .exposure
        c["EXP_TYPE"]  = .exposure
        c["READPATT"]  = .exposure
        c["NINTS"]     = .exposure
        c["EXSEGTOT"]  = .exposure
        c["EXSEGNUM"]  = .exposure
        c["INTSTART"]  = .exposure
        c["INTEND"]    = .exposure
        c["NGROUPS"]   = .exposure
        c["NFRAMES"]   = .exposure
        c["GROUPGAP"]  = .exposure
        c["NSAMPLES"]  = .exposure
        c["TSAMPLE"]   = .exposure
        c["TFRAME"]    = .exposure
        c["TGROUP"]    = .exposure
        c["EFFINTTM"]  = .exposure
        c["NRSTSTRT"]  = .exposure
        c["NRESETS"]   = .exposure
        c["ZEROFRAM"]  = .exposure
        c["DATAPROB"]  = .exposure
        c["SCA_NUM"]   = .exposure
        c["DATAMODE"]  = .exposure
        c["FRMDIVSR"]  = .exposure
        c["DRPFRMS1"]  = .exposure
        c["DRPFRMS3"]  = .exposure
        c["NOUTPUTS"]  = .exposure

        // Calibration — software versions, reference files, pipeline provenance
        c["FILENAME"]  = .calibration
        c["FILETYPE"]  = .calibration
        c["CAL_VER"]   = .calibration
        c["SDP_VER"]   = .calibration
        c["PRD_VER"]   = .calibration
        c["OSS_VER"]   = .calibration
        c["CAL_VCS"]   = .calibration
        c["CRDS_VER"]  = .calibration
        c["CRDS_CTX"]  = .calibration
        c["LINENUM"]   = .calibration
        c["ROOTNAME"]  = .calibration
        c["VA_SCALE"]  = .calibration
        c["IMAGETYP"]  = .calibration
        c["POSTARG1"]  = .calibration
        c["POSTARG2"]  = .calibration

        // Subarray — detector subarray selection and geometry
        c["SUBARRAY"]  = .subarray
        c["SUBSTRT1"]  = .subarray
        c["SUBSTRT2"]  = .subarray
        c["SUBSIZE1"]  = .subarray
        c["SUBSIZE2"]  = .subarray
        c["FASTAXIS"]  = .subarray
        c["SLOWAXIS"]  = .subarray

        // Dither — pattern type, offsets, and step parameters
        c["NUMDTHPT"]  = .dither
        c["PATT_NUM"]  = .dither
        c["XOFFSET"]   = .dither
        c["YOFFSET"]   = .dither
        c["PATTTYPE"]  = .dither
        c["PRIDTPTS"]  = .dither
        c["SUBPXPTS"]  = .dither
        c["NRIMDTPT"]  = .dither
        c["PATTSIZE"]  = .dither
        c["PRIDTYPE"]  = .dither
        c["SUBPXPAT"]  = .dither
        c["SMGRDPAT"]  = .dither
        c["PATTSTRT"]  = .dither
        c["PATTNPTS"]  = .dither
        c["NUMDSETS"]  = .dither
        c["DITHPNTS"]  = .dither
        c["NOD_TYPE"]  = .dither
        c["MRSPRCHN"]  = .dither
        c["DSETSTRT"]  = .dither
        c["DITHOPFR"]  = .dither
        c["DITHDIRC"]  = .dither
        c["SPECNSTP"]  = .dither
        c["SPECSTEP"]  = .dither
        c["SPCOFFST"]  = .dither
        c["SPATNSTP"]  = .dither
        c["SPATSTEP"]  = .dither
        c["SPTOFFST"]  = .dither
        c["SPEC_NUM"]  = .dither
        c["SPAT_NUM"]  = .dither

        // Guide Star — identification, coordinates, and pointing quality
        c["GS_ORDER"]  = .guideStar
        c["GSSTRTTM"]  = .guideStar
        c["GSENDTIM"]  = .guideStar
        c["GDSTARID"]  = .guideStar
        c["GS_RA"]     = .guideStar
        c["GS_DEC"]    = .guideStar
        c["GS_URA"]    = .guideStar
        c["GS_UDEC"]   = .guideStar
        c["GS_MAG"]    = .guideStar
        c["GS_UMAG"]   = .guideStar
        c["GS_V3_PA"]  = .guideStar
        c["PCS_MODE"]  = .guideStar
        c["VISITEND"]  = .guideStar

        // Background — sky background level and subtraction
        c["BKGLEVEL"]  = .background
        c["BKGSUB"]    = .background
        c["MASTERBG"]  = .background

        // Aperture — science aperture name and configuration
        c["APERNAME"]  = .aperture
        c["PPS_APER"]  = .aperture

        // Association — pipeline association pool and table
        c["ASNPOOL"]   = .association
        c["ASNTABLE"]  = .association

        // Resampling — combined product exposure time and catalog filenames
        c["TEXPTIME"]  = .resampling
        c["TCATFILE"]  = .resampling
        c["SCATFILE"]  = .resampling

        // Engineering — instrument mechanism, IFU cube, WFS&C
        c["ERRTYPE"]   = .engineering
        c["ROIS"]      = .engineering
        c["ROIW"]      = .engineering
        c["WTYPE"]     = .engineering
        c["WPOWER"]    = .engineering
        c["HGA_MOVE"]  = .engineering
        c["PWFSEET"]   = .engineering
        c["NWFSEST"]   = .engineering
        c["RMA_POS"]   = .engineering
        c["FCSRLPOS"]  = .engineering
        c["FAM_LA1"]   = .engineering
        c["FASTEP1"]   = .engineering
        c["FAUNIT1"]   = .engineering
        c["FAPHASE1"]  = .engineering
        c["FA1VALUE"]  = .engineering
        c["FAM_LA2"]   = .engineering
        c["FASTEP2"]   = .engineering
        c["FAUNIT2"]   = .engineering
        c["FAPHASE2"]  = .engineering
        c["FA2VALUE"]  = .engineering
        c["FAM_LA3"]   = .engineering
        c["FASTEP3"]   = .engineering
        c["FAUNIT3"]   = .engineering
        c["FAPHASE3"]  = .engineering
        c["FA3VALUE"]  = .engineering

        // Comments — FITS comment, history, and blank header cards
        c["COMMENT"]   = .comments
        c["HISTORY"]   = .comments
        c[""]          = .comments

        return c
    }()
}
