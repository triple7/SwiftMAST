////  JwstInstrument.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias JWSTInstruments = MASTJwstInstrumentField

/// JWST Science Instrument Keyword fields
/// https://mast.stsci.edu/api/v0/_jwst_inst_keywd.html
public enum MASTJwstInstrumentField: String, CaseIterable, Identifiable {
    // MARK: Standard parameters
    case nextend

    // MARK: Basic parameters
    case date
    case date_mjd
    case origin
    case timesys
    case filename
    case sdp_ver
    case prd_ver
    case oss_ver
    case cal_ver
    case cal_vcs
    case telescop
    case hga_move
    case datamodl
    case pwfseet
    case nwfsest

    // MARK: IFU cube parameters
    case errtype
    case rois
    case roiw
    case wtype
    case wpower

    // MARK: Programmatic information
    case title
    case pi_name
    case category
    case subcat
    case scicat
    case cont_id

    // MARK: Observation identifiers
    case obs_id
    case visit_id
    case program
    case observtn
    case visit
    case obslabel
    case obsfoldr
    case date_obs
    case date_obs_mjd
    case date_beg
    case date_beg_mjd
    case date_end
    case date_end_mjd
    case visitgrp
    case seq_id
    case act_id
    case exposure
    case bkgdtarg
    case template
    case eng_qual
    case engqlptg
    case is_psf
    case selfref

    // MARK: Visit information
    case visitype
    case vststart
    case vststart_mjd
    case visitsta
    case nexposur
    case intarget
    case targoopp
    case tsovisit
    case exp_only
    case crowdfld

    // MARK: Target information
    case targprop
    case targname
    case targtype
    case targ_ra
    case targ_dec
    case targura
    case targudec
    case mu_ra
    case mu_dec
    case mu_epoch
    case mu_epoch_mjd
    case prop_ra
    case prop_dec
    case srctyapt

    // MARK: Instrument configuration information
    case instrume
    case detector
    case lamp
    case module
    case cccstate
    case mirngrps
    case mirnfrms
    case coronmsk
    case detmode
    case cmd_tsel
    case channel
    case band
    case opmode
    case filter
    case grating
    case pupil
    case pilin
    case focuspos
    case fwcpos
    case pwcpos
    case gwa_xtil
    case gwa_ytil
    case gwa_xp_v
    case gwa_yp_v
    case gwa_pxav
    case gwa_pyav
    case gwa_tilt
    case nrs_norm
    case nrs_ref
    case msastate
    case msametfl
    case msametid
    case msaconid
    case preimage
    case is_imprt
    case fxd_slit

    // MARK: Exposure parameters
    case effexptm
    case duration
    case gainfact
    case sctarate
    case expcount
    case expripar
    case expstart
    case expmid
    case expend
    case expsteng
    case expsteng_mjd
    case osf_file
    case exp_type
    case readpatt
    case nints
    case exsegtot
    case exsegnum
    case intstart
    case intend
    case ngroups
    case nframes
    case groupgap
    case nsamples
    case tsample
    case tframe
    case tgroup
    case effinttm
    case nrststrt
    case nresets
    case zerofram
    case dataprob
    case sca_num
    case datamode
    case frmdivsr
    case drpfrms1
    case drpfrms3
    case noutputs

    // MARK: Association parameters
    case asnpool
    case asntable

    // MARK: Subarray parameters
    case subarray
    case substrt1
    case substrt2
    case subsize1
    case subsize2
    case fastaxis
    case slowaxis

    // MARK: Dither information
    case numdthpt
    case patt_num
    case xoffset
    case yoffset
    case patttype
    case pridtpts
    case subpxpts
    case nrimdtpt
    case pattsize
    case pridtype
    case subpxpat
    case smgrdpat
    case pattstrt
    case pattnpts
    case numdsets
    case dithpnts
    case nod_type
    case mrsprchn
    case dsetstrt
    case dithopfr
    case dithdirc
    case specnstp
    case specstep
    case spcoffst
    case spatnstp
    case spatstep
    case sptoffst
    case spec_num
    case spat_num

    // MARK: NIRSPEC WFS&C engineering keywords
    case rma_pos
    case fcsrlpos

    // MARK: Focus Adjust Mechanism parameters
    case fam_la1
    case fastep1
    case faunit1
    case faphase1
    case fa1value
    case fam_la2
    case fastep2
    case faunit2
    case faphase2
    case fa2value
    case fam_la3
    case fastep3
    case faunit3
    case faphase3
    case fa3value

    // MARK: Aperture information
    case apername
    case pps_aper

    // MARK: Time information
    case bartdelt
    case bstrtime
    case bmidtime
    case bendtime
    case helidelt
    case hstrtime
    case hmidtime
    case hendtime

    // MARK: Reference file information
    case crds_ver
    case crds_ctx

    // MARK: Resampling parameter information
    case texptime
    case tcatfile
    case scatfile

    // MARK: WCS parameters
    case s_region

    // MARK: Guide star information
    case gs_order
    case gsstrttm
    case gsstrttm_mjd
    case gsendtim
    case gsendtim_mjd
    case gdstarid
    case gs_ra
    case gs_dec
    case gs_ura
    case gs_udec
    case gs_mag
    case gs_umag
    case gs_v3_pa
    case pcs_mode
    case visitend
    case visitend_mjd

    // MARK: Background information
    case bkglevel
    case bkgsub
    case masterbg

    // MARK: Product Information
    case productLevel
    case publicReleaseDate
    case publicReleaseDate_mjd
    case isItar
    case isRestricted
    case isStale
    case fileSize
    case checksum

    // MARK: Internal Information
    case ArchiveFileID
    case fileSetName
    case FileSetId
    case FileTypeID
    case ingestCompletionDate
    case ingestCompletionDate_mjd
    case ingestStartDate
    case ingestStartDate_mjd
    case dva_ra
    case dva_dec

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        // Standard parameters
        case .nextend: return "Number of file extensions"
        // Basic parameters
        case .date: return "File Creation Date UTC"
        case .date_mjd: return "File Creation Date MJD"
        case .origin: return "Institution responsible for creating the FITS file"
        case .timesys: return "Principal time system (UTC)"
        case .filename: return "Name of the file"
        case .sdp_ver: return "Data Processing Software Version"
        case .prd_ver: return "Project Reference Database Version"
        case .oss_ver: return "OSS Software Version"
        case .cal_ver: return "Calibration Software Version"
        case .cal_vcs: return "Calibration Software Repository Version"
        case .telescop: return "Telescope used to acquire the data (JWST)"
        case .hga_move: return "High Gain Antenna moved during data collection"
        case .datamodl: return "JWST DataModel class name"
        case .pwfseet: return "Previous WFS exposure end time (MJD)"
        case .nwfsest: return "Next WFS exposure start time (MJD)"
        // IFU cube parameters
        case .errtype: return "Error array type (ERR, IERR, VAR, IVAR)"
        case .rois: return "Region of interest size in spatial dimensions"
        case .roiw: return "Region of interest size in wavelength dimension"
        case .wtype: return "Weighting type for IFU cube combination"
        case .wpower: return "Weighting power for IFU cube distances"
        // Programmatic information
        case .title: return "Proposal title"
        case .pi_name: return "Principal Investigator name"
        case .category: return "Program category (AR, CAL, DD, ENG, GO, GTO, NASA)"
        case .subcat: return "Program sub-category (FGS, MIRI, NIRCAM, NIRISS, NIRSPEC, SC)"
        case .scicat: return "Science category assigned during TAC process"
        case .cont_id: return "Continuation ID of previous program"
        // Observation identifiers
        case .obs_id: return "Programmatic observation identifier"
        case .visit_id: return "Visit identifier (PPPPPOOOVVV)"
        case .program: return "Program number"
        case .observtn: return "Observation number"
        case .visit: return "Visit number"
        case .obslabel: return "Proposer-defined observation label"
        case .obsfoldr: return "APT observation folder name"
        case .date_obs: return "UTC date of observation start (yyyy-mm-dd)"
        case .date_obs_mjd: return "Observation start date in MJD format"
        case .date_beg: return "Exposure start datetime (ISO-8601)"
        case .date_beg_mjd: return "Exposure start in MJD format"
        case .date_end: return "Exposure end datetime (ISO-8601)"
        case .date_end_mjd: return "Exposure end in MJD format"
        case .visitgrp: return "Visit group identifier"
        case .seq_id: return "Parallel sequence identifier"
        case .act_id: return "Activity identifier"
        case .exposure: return "Exposure request number"
        case .bkgdtarg: return "Background target indicator"
        case .template: return "Observation template name"
        case .eng_qual: return "Engineering database quality indicator"
        case .engqlptg: return "Pointing source quality indicator"
        case .is_psf: return "PSF reference observation indicator"
        case .selfref: return "Self-referencing PSF indicator"
        // Visit information
        case .visitype: return "Specific type of visit"
        case .vststart: return "Visit start time (UTC)"
        case .vststart_mjd: return "Visit start time in MJD format"
        case .visitsta: return "Visit status"
        case .nexposur: return "Total number of planned exposures in visit"
        case .intarget: return "Internally targeted indicator"
        case .targoopp: return "Target of opportunity indicator"
        case .tsovisit: return "Time Series Observation visit indicator"
        case .exp_only: return "Special exposure command indicator"
        case .crowdfld: return "FGS crowded field indicator"
        // Target information
        case .targprop: return "Proposer's preferred target name"
        case .targname: return "Standard astronomical catalog target name"
        case .targtype: return "Target type (FIXED, MOVING, GENERIC)"
        case .targ_ra: return "Target RA at mid-exposure (degrees)"
        case .targ_dec: return "Target Dec at mid-exposure (degrees)"
        case .targura: return "Target RA uncertainty (arcsec)"
        case .targudec: return "Target Dec uncertainty (arcsec)"
        case .mu_ra: return "Proper motion in RA (arcsec/year)"
        case .mu_dec: return "Proper motion in Dec (arcsec/year)"
        case .mu_epoch: return "Epoch of proper motion values"
        case .mu_epoch_mjd: return "Proper motion epoch in MJD format"
        case .prop_ra: return "Proposer's target RA (degrees)"
        case .prop_dec: return "Proposer's target Dec (degrees)"
        case .srctyapt: return "APT source type (POINT, EXTENDED, UNKNOWN)"
        // Instrument configuration information
        case .instrume: return "Instrument (NIRCAM, NIRSPEC, MIRI, NIRISS, FGS)"
        case .detector: return "Detector name"
        case .lamp: return "Internal lamp state"
        case .module: return "NIRCam module (A, B, MULTIPLE)"
        case .cccstate: return "MIRI contamination control cover state"
        case .mirngrps: return "MIRI flight system number of groups"
        case .mirnfrms: return "MIRI flight system number of frames"
        case .coronmsk: return "MIRI coronagraph mask"
        case .detmode: return "Detector mode (FLUSH_MODE, TEST_PATTERN, CLOCKING, EXPOSURE)"
        case .cmd_tsel: return "Test pattern generated by SCE"
        case .channel: return "IFU data channels (12, 34)"
        case .band: return "Wavelength band (SHORT, MEDIUM, LONG)"
        case .opmode: return "Lamp operating mode"
        case .filter: return "Filter element used"
        case .grating: return "NIRSpec grating element"
        case .pupil: return "Pupil wheel element"
        case .pilin: return "Pupil imaging lens indicator"
        case .focuspos: return "FGS focus mechanism position (mm)"
        case .fwcpos: return "NIRISS filter wheel position"
        case .pwcpos: return "NIRISS pupil wheel position"
        case .gwa_xtil: return "Grating wheel tilt X"
        case .gwa_ytil: return "Grating wheel tilt Y"
        case .gwa_xp_v: return "Grating wheel X-position sensor value"
        case .gwa_yp_v: return "Grating wheel Y-position sensor value"
        case .gwa_pxav: return "Grating wheel REC X-position sensor"
        case .gwa_pyav: return "Grating wheel REC Y-position sensor"
        case .gwa_tilt: return "Grating wheel temperature sensor"
        case .nrs_norm: return "Number of normal pixels per IRS2 block"
        case .nrs_ref: return "Number of interleaved reference pixels per IRS2 block"
        case .msastate: return "NIRSpec MSA state"
        case .msametfl: return "NIRSpec MSA metadata file name"
        case .msametid: return "MSA metadata ID"
        case .msaconid: return "MSA configuration ID"
        case .preimage: return "Reference image for source position"
        case .is_imprt: return "Imprint/leakcal exposure indicator"
        case .fxd_slit: return "NIRSpec fixed slit aperture"
        // Exposure parameters
        case .effexptm: return "Effective exposure time (seconds)"
        case .duration: return "Total exposure duration (seconds)"
        case .gainfact: return "Gain scale factor"
        case .sctarate: return "Spacecraft clock time adjustment rate"
        case .expcount: return "Exposure count within visit"
        case .expripar: return "Prime or parallel exposure"
        case .expstart: return "Exposure start time (MJD)"
        case .expmid: return "Exposure midpoint time (MJD)"
        case .expend: return "Exposure end time (MJD)"
        case .expsteng: return "Engineering exposure start time (UTC)"
        case .expsteng_mjd: return "Engineering exposure start time (MJD)"
        case .osf_file: return "Observatory Status File name"
        case .exp_type: return "Exposure type"
        case .readpatt: return "Readout pattern"
        case .nints: return "Number of integrations in exposure"
        case .exsegtot: return "Total segments in TSO exposure"
        case .exsegnum: return "Sequential segment number in TSO"
        case .intstart: return "Starting integration number"
        case .intend: return "Ending integration number"
        case .ngroups: return "Number of groups in integration"
        case .nframes: return "Number of frames in a group"
        case .groupgap: return "Frames dropped between groups"
        case .nsamples: return "Number of A/D samples per pixel read"
        case .tsample: return "Time between samples (microseconds)"
        case .tframe: return "Time between frames (seconds)"
        case .tgroup: return "Time between groups (seconds)"
        case .effinttm: return "Effective integration time (seconds)"
        case .nrststrt: return "Number of resets at start of exposure"
        case .nresets: return "Number of resets between integrations"
        case .zerofram: return "Zero frame read indicator"
        case .dataprob: return "Science telemetry data problem indicator"
        case .sca_num: return "Sensor Chip Assembly number (1-18)"
        case .datamode: return "Post-processing method for FPAP"
        case .frmdivsr: return "Frame divisor for on-board averaging"
        case .drpfrms1: return "Frames dropped prior to first integration"
        case .drpfrms3: return "Frames dropped between integrations"
        case .noutputs: return "Number of detector amplifier outputs"
        // Association parameters
        case .asnpool: return "Association pool file name"
        case .asntable: return "Association table name"
        // Subarray parameters
        case .subarray: return "Subarray name"
        case .substrt1: return "Starting pixel in axis 1"
        case .substrt2: return "Starting pixel in axis 2"
        case .subsize1: return "Number of pixels in axis 1"
        case .subsize2: return "Number of pixels in axis 2"
        case .fastaxis: return "Fast readout axis direction"
        case .slowaxis: return "Slow readout axis direction"
        // Dither information
        case .numdthpt: return "Total number of dither points"
        case .patt_num: return "Position number within dither pattern"
        case .xoffset: return "X offset from pattern start (arcsec)"
        case .yoffset: return "Y offset from pattern start (arcsec)"
        case .patttype: return "Dither pattern type"
        case .pridtpts: return "Number of primary dither points"
        case .subpxpts: return "Number of subpixel dither points"
        case .nrimdtpt: return "NIRISS direct image dither points"
        case .pattsize: return "Dither pattern size (NONE, SMALL, MEDIUM, LARGE)"
        case .pridtype: return "Primary dither specification"
        case .subpxpat: return "Subpixel dither pattern type"
        case .smgrdpat: return "Small grid dither pattern name"
        case .pattstrt: return "MIRI imaging dither start point"
        case .pattnpts: return "MIRI imaging CYCLING dither points"
        case .numdsets: return "Number of 4-point dither sets"
        case .dithpnts: return "Sparse cycling dither point list"
        case .nod_type: return "NIRSpec MSA nod pattern type"
        case .mrsprchn: return "MRS channel for dither optimization"
        case .dsetstrt: return "Starting dither set number"
        case .dithopfr: return "Dither optimization (point/extended source)"
        case .dithdirc: return "Dither direction (POSITIVE, NEGATIVE)"
        case .specnstp: return "MIRI LRS spectral direction steps"
        case .specstep: return "MIRI LRS spectral step size (arcsec)"
        case .spcoffst: return "MIRI LRS spectral offset (arcsec)"
        case .spatnstp: return "MIRI LRS spatial direction steps"
        case .spatstep: return "MIRI LRS spatial step size (arcsec)"
        case .sptoffst: return "MIRI LRS spatial offset (arcsec)"
        case .spec_num: return "MIRI LRS spectral step position"
        case .spat_num: return "MIRI LRS spatial step position"
        // NIRSPEC WFS&C engineering keywords
        case .rma_pos: return "NIRSpec RMA hall-position sensor value"
        case .fcsrlpos: return "NIRSpec RMA relative position (steps)"
        // Focus Adjust Mechanism parameters
        case .fam_la1: return "FAM linear actuator 1 position (steps)"
        case .fastep1: return "Requested focus actuator 1 steps"
        case .faunit1: return "Focus actuator 1 units"
        case .faphase1: return "Focus actuator 1 phase"
        case .fa1value: return "Focus actuator 1 absolute position"
        case .fam_la2: return "FAM linear actuator 2 position (steps)"
        case .fastep2: return "Requested focus actuator 2 steps"
        case .faunit2: return "Focus actuator 2 units"
        case .faphase2: return "Focus actuator 2 phase"
        case .fa2value: return "Focus actuator 2 absolute position"
        case .fam_la3: return "FAM linear actuator 3 position (steps)"
        case .fastep3: return "Requested focus actuator 3 steps"
        case .faunit3: return "Focus actuator 3 units"
        case .faphase3: return "Focus actuator 3 phase"
        case .fa3value: return "Focus actuator 3 absolute position"
        // Aperture information
        case .apername: return "PRD aperture name used"
        case .pps_aper: return "Original aperture name from PPS"
        // Time information
        case .bartdelt: return "Barycentric time correction from UTC (seconds)"
        case .bstrtime: return "Barycentric exposure start (MJD)"
        case .bmidtime: return "Barycentric exposure midpoint (MJD)"
        case .bendtime: return "Barycentric exposure end (MJD)"
        case .helidelt: return "Heliocentric time correction from UTC (seconds)"
        case .hstrtime: return "Heliocentric exposure start (MJD)"
        case .hmidtime: return "Heliocentric exposure midpoint (MJD)"
        case .hendtime: return "Heliocentric exposure end (MJD)"
        // Reference file information
        case .crds_ver: return "CRDS client software version"
        case .crds_ctx: return "CRDS context (PMAP file) version"
        // Resampling parameter information
        case .texptime: return "Total exposure time of combined product (seconds)"
        case .tcatfile: return "Tweakreg catalog filename"
        case .scatfile: return "Source catalog filename"
        // WCS parameters
        case .s_region: return "Sky footprint (ICRS circle or polygon)"
        // Guide star information
        case .gs_order: return "Guide star index"
        case .gsstrttm: return "Guide star activity start time (UTC)"
        case .gsstrttm_mjd: return "Guiding start time (MJD)"
        case .gsendtim: return "Guide star activity end time (UTC)"
        case .gsendtim_mjd: return "Guiding end time (MJD)"
        case .gdstarid: return "Guide star identifier"
        case .gs_ra: return "Guide star ICRS right ascension (degrees)"
        case .gs_dec: return "Guide star ICRS declination (degrees)"
        case .gs_ura: return "Guide star RA uncertainty (arcsec)"
        case .gs_udec: return "Guide star Dec uncertainty (arcsec)"
        case .gs_mag: return "Guide star magnitude in FGS"
        case .gs_umag: return "Guide star magnitude uncertainty"
        case .gs_v3_pa: return "Guide star V3 position angle (degrees)"
        case .pcs_mode: return "Pointing Control System mode"
        case .visitend: return "Visit end time (UTC)"
        case .visitend_mjd: return "Visit end time (MJD)"
        // Background information
        case .bkglevel: return "Background signal level from skymatch"
        case .bkgsub: return "Background subtracted indicator"
        case .masterbg: return "Master background spectrum filename"
        // Product Information
        case .productLevel: return "Product level"
        case .publicReleaseDate: return "Public release datetime"
        case .publicReleaseDate_mjd: return "Public release date (MJD)"
        case .isItar: return "ITAR restricted indicator"
        case .isRestricted: return "Restricted data indicator"
        case .isStale: return "Stale data indicator"
        case .fileSize: return "File size"
        case .checksum: return "Valid checksum"
        // Internal Information
        case .ArchiveFileID: return "Archive file ID"
        case .fileSetName: return "FileSet name"
        case .FileSetId: return "FileSet ID"
        case .FileTypeID: return "FileType ID"
        case .ingestCompletionDate: return "Ingest completion datetime"
        case .ingestCompletionDate_mjd: return "Ingest completion date (MJD)"
        case .ingestStartDate: return "Ingest start datetime"
        case .ingestStartDate_mjd: return "Ingest start date (MJD)"
        case .dva_ra: return "Velocity aberrated RA (degrees)"
        case .dva_dec: return "Velocity aberrated Dec (degrees)"
        }
    }
}
