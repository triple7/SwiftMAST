//
//  Siap.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

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
