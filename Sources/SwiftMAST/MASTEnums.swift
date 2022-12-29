//
//  File.swift
//  
//
//  Created by Yuma decaux on 28/12/2022.
//

import Foundation

public typealias MGP = MASTGeneralParameter

public enum MASTGeneralParameter:String, CaseIterable, Identifiable {
    /** MAST general parameters
     reference [general parameters](https://archive.stsci.edu/vo/help/search_help.html)
     */
    case target /* target name as identifiable string"*/
 case  resolver /* Character :
  "NED",
  "SIMBAD",
  "CFA" = SIMBAD at CFA,
  "Don't Resolve" = search on target name without resolving to coordinates*/
case  radius /* Float : Range: 0.0 - ?*/
case  ra /* Float : Range: 0.0 - 360.0*/
case  dec /* Float : Range: -90.0 - 90.0*/
    case SR /* search radius in degrees*/
case  equinox /* Character :  J2000, B1900, B1950*/
case  selectedColumnsCsv /* Character : Example: hut_target_name,hut_data_id*/
case  ordercolumn1 /* Character : Example: ang_sep*/
case  descending1 /* Character : on*/
case  ordercolumn2 /* Character : Example: ra*/
case  descending2 /* Character : on*/
case  ordercolumn3 /* Character : Example: dec*/
case  descending3 /* Character : on*/
case  outputformat /* Character :
    "HTML_Table" = Table in HTML format,
    "VOTable" = VOTable format,
    "CSV" = comma-separated values,
    "SSV" = space-separated values,
    "PSV" = pipe-separated values,
    "COSV" = semicolon-separated values,
    "JSON" = JSON format,
    "Excel_Spreadsheet" = Excel Spreadsheet format
     Other formats available.
    */
case  showquery /* Character :  on, off*/
case  makedistinct /* Character :  on, off*/
case  coordformat /* Character :
 "sex" = Sexigesimal notation,
 "dec" = decimal degrees,
 "dechr" = decimal hours for RA and decimal degrees for Dec */
case  max_records /* Integer :  1 to ?*/
case  max_rpp /* Integer :  1 to ?*/
case  verb /* Integer :  1 to 3*/
case nonull /*Character: on,off*/
case skipformat /*Character: on,off*/
    
    public var id:String {
        return self.rawValue
    }
}

public enum MASTDataSet:String, CaseIterable, Identifiable {
case hst
case hsc_sum
case hsc
case kepler_data_search
case kepler_fov
case kepler_kic10
case kepler_kgmatch
case kepler_KOI_planets
case kepler_published_planets
case kepler_KOI
case kepler_ffi
case kepler_epic
case k2_data_search
case k2_planets
case k2_ffi
case iue
case hut
case euve
case fuse
case uit
case wuppe
case befs
case tues
case imaps
case hlsp
case pointings
case copernicus
case hpol
case vlafirst
case xmm_om
case swift_uvot

    public var id:String {
        return self.rawValue.replacingOccurrences(of: "_", with: "-")
    }

    public var urlPath:String {
        switch self {
        case .swift_uvot: return self.rawValue
        case .xmm_om: return "xmm-om"
        default: return self.rawValue.replaceFirst(of: "_", with: "/").lowercased()
        }
    }
    
 public var description:String {
switch self {
case .hst: return "Hubble Space Telescope"
case .hsc_sum: return "Hubble Source Catalog Summary table"
case .hsc: return "Hubble Source Catalog Detailed table"
case .kepler_data_search: return "Kepler data search"
case .kepler_fov: return "Target search,replaces kepler_fov_enh (kepler/kepler_fov)"
case .kepler_kic10: return "Kepler Input Catalog (kepler/kic10)"
case .kepler_kgmatch: return "Kepler/Galex Cross match (kepler/kgmatch)"
case .kepler_KOI_planets: return "Kepler Confirmed Planets (with KOI-based data) (kepler/confirmed_planets)"
case .kepler_published_planets: return "Kepler Confirmed Planets (with published data) (kepler/published_planets)"
case .kepler_KOI: return "Kepler Objects of Interest (kepler/koi)"
case .kepler_ffi: return "FFIs (kepler/ffi)"
case .kepler_epic: return "Ecliptic Plane Input Catalog (k2/epic)"
case .k2_data_search: return "Data Search (k2/data_search)"
case .k2_planets: return "K2 planets (k2/published_planets)"
case .k2_ffi: return "FFIs (k2/ffi)"
case .iue: return "International Ultraviolet Explorer"
case .hut: return "Hopkins Ultraviolet Telescope"
case .euve: return "Extreme Ultraviolet Explorer"
case .fuse: return "Far-UV Spectroscopic Explorer"
case .uit: return "Ultraviolet Imageing Telescope"
case .wuppe: return "Wisconsin UV Photo-Polarimeter Explorer"
case .befs: return "Berkeley Extreme and Far-UV"
case .tues: return "Tübingen Echelle Spectrograph"
case .imaps: return "Interstellar Medium Absorption Profile Spectrograph"
case .hlsp: return "High Level Science Products"
case .pointings: return "HST Image Data grouped by position"
case .copernicus: return "Copernicus Satellite"
case .hpol: return "ground based spetropolarimater"
case .vlafirst: return "VLA Faint Images of the Radio Sky (21-cm)"
case .xmm_om: return "X-ray Multi-Mirror Telescope Optical Monitor"
case .swift_uvot: return "Swift UV/optical Telescope"
 }
}
}

public enum MASTSIAP:String, CaseIterable, Identifiable {
 case WFPC2
case NICMOS
case STIS
case FOC
case ACS
case UIT
case VLA_FIRST
case AL218
case UDF
case UDFUV
case HDF
case HDF_SOUTH
case GOODS
case TNO
case HELIX
case MAOZ_ATLAS
case CANDELS
case STPR
case ANGRRR
case ACSGGCT
case ANDROMEDA
case HIPPIES
case CLASH
case COMA
case APPP
case s3CR
case ANGST
case SGAL
case M51
case M82
case GALEX_ATLAS
case HERITAGE
case COSMOS
case GEMS
case PHAT
case HUDF09

public var id:String {
    switch self {
    case .s3CR: return "3CR"
    case .VLA_FIRST: return "VLA-FIRST"
    default: return self.rawValue
    }
}
    
public var description:String {
switch self {
 case .WFPC2: return "HST Wide Field Planetary Camera 2"
case .NICMOS: return "HST Near Infrared Camera and Multi Object Spectrometer "
case .STIS: return "Space Telescope Imaging Spectrograph"
case .FOC: return "HST Faint Object Camera"
case .ACS: return "HST Advance Camera Survey"
case .UIT: return "Ultraviolet Imageing Telescope "
case .VLA_FIRST: return "VLA Faint Images of the Radio Sky at 20 cm"
case .AL218: return "VLA Array AL218 Texas Survey Source Snapshots"
case .UDF: return "HLSP Ultra Deep Field"
case .UDFUV: return "HLSP Ultraviolet Images of Ultra Deep Field"
case .HDF: return "HLSP Hubble Deep Field"
case .HDF_SOUTH: return "HLSP Hubble Deep Field South"
case .GOODS: return "HLSP The Great Observatories Origins Deep Survey "
case .TNO: return "HLSP trans-Neptunian objects"
case .HELIX: return "HLSP HST Helix Observations"
case .MAOZ_ATLAS: return "HLSP HST Atlas of Ultraviolet Images of Nearby Galaxies"
case .CANDELS: return "Cosmic Assembly Near-IR Deep Extragalactic Legacy Survey"
case .STPR: return " HST Press Release Images 2008"
case .ANGRRR: return " Archive of Nearby Galaxies: Reduce, Reuse, Recycle (ANGRRR)"
case .ACSGGCT: return " ACS Galactic Globular Cluster Survey (ACSGGCT)"
case .ANDROMEDA: return "Deep Optical Photometry of Six Fields in the Andromeda Galaxy"
case .HIPPIES: return "Hubble Infrared Pure Parallel Imaging Extragalactic Survey (HIPPIES) "
case .CLASH: return "Cluster Lensing And Supernova survey with Hubble (CLASH)"
case .COMA: return "HST ACS Coma Cluster Treasury Survey"
case .APPP: return "HST Archive Pure Parallels"
case .s3CR: return "The revised 3C catalogue (3CR, Bennett 1962) "
case .ANGST: return "HST ACS Nearby Galaxy Survey (ANGST) "
case .SGAL: return "HST WFPC2 Spiral Galaxies"
case .M51: return "HST ACS mosaic images of M51"
case .M82: return "HST multicolor ACS mosaic images of M82"
case .GALEX_ATLAS: return "GALEX atlas of Nearby Galaxies  "
case .HERITAGE: return "HST Heritage Press Release Images"
case .COSMOS: return "HST Cosmic Evolution Survey"
case .GEMS: return "HST Galaxy Evolution from Morphology and SEDs"
case .PHAT: return "Panchromatic Hubble Andromeda Treasury (PHAT)"
case .HUDF09: return "Hubble Ultra Deep Field 2009 (HUDF09)"
}
}
}

public enum MASTSSAP:String, CaseIterable, Identifiable {
    case fos
    case ghrs
    case stis
    case hst //(to include all instruments)
    case iue
    case hut
    case euve
    case fuse
    case wuppe
    case befs
    case tues
    case hpol

public var id:String {
return self.rawValue
}
    
public var description:String {
switch self {
case .fos: return ""
case .ghrs: return "Goddard high resolution spectrograph"
case .stis: return "Space telescope imaging spectrograph"
case .hst: return "hubble space telescope"
case .iue: return "International Ultraviolet Explorer"
case .hut: return "Hopkins Ultraviolet Telescope"
case .euve: return "Extreme Ultraviolet Explorer"
case .fuse: return "Far-UV Spectroscopic Explorer"
case .wuppe: return "Wisconsin UV Photo-Polarimeter Explorer"
case .befs: return "Berkeley Extreme and Far-UV"
case .tues: return "Tübingen Echelle Spectrograph"
case .hpol: return "ground based spetropolarimater"
}
}
}

public enum MASTSearchType:String, CaseIterable, Identifiable {
    case mission
    case simpleCone
    case image
    case spectra
    
    public var id:String {
        return self.rawValue
    }
    
    public var description:String {
        switch self {
        case .mission: return "Mission search"
        case .simpleCone: return "Simple cone search"
        case .image: return "Simple image access protocol"
        case .spectra: return "Simple spectra Access protocol"
        }
    }
    
    var defaultParameters:[MGP: String] {
        switch self {
        case .mission:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .simpleCone:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .image:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .spectra:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        }
    }
}

