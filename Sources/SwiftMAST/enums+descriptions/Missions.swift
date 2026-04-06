//
//  File.swift
//
//
//  Created by Yuma decaux on 11/1/2024.
//

import Foundation

public enum Missions: String, CaseIterable {
    case PS1
    case SWIFT
    case FUSE
    case IUE
    case BEFS
    case FIMS_SPEAR = "FIMS-SPEAR"
    case K2
    case TESS
    case K2FFI
    case OPO
    case WUPPE
    case HUT
    case Kepler
    case GALEX
    case KeplerFFI
    case HLA
    case HST
    case EUVE
    case TUES
    case SPITZER_SHA
    case HLSP
    case JWST

    public var description: String {
        switch self {
        case .PS1: return "Pan-STARRS 1"
        case .SWIFT: return "Neil Gehrels Swift Observatory"
        case .FUSE: return "Far-UV Spectroscopic Explorer"
        case .IUE: return "International Ultraviolet Explorer"
        case .BEFS: return "Berkeley Extreme and Far-UV Spectrometer"
        case .FIMS_SPEAR:
            return
                "Far-ultraviolet IMaging Spectrograph / Spectroscopy of Plasma Evolution from Astrophysical Radiation"
        case .K2: return "Kepler Mission 2"
        case .TESS: return "Transiting Exoplanet Survey Satellite"
        case .K2FFI: return "K2 Full Frame Images"
        case .OPO: return "Office of Public Outreach"
        case .WUPPE: return "Wisconsin UV Photo-Polarimeter Explorer"
        case .HUT: return "Hopkins Ultraviolet Telescope"
        case .Kepler: return "Kepler Space Telescope"
        case .GALEX: return "Galaxy Evolution Explorer"
        case .KeplerFFI: return "Kepler Full Frame Images"
        case .HLA: return "Hubble Legacy Archive"
        case .HST: return "Hubble Space Telescope"
        case .EUVE: return "Extreme Ultraviolet Explorer"
        case .TUES: return "Tübingen Echelle Spectrograph"
        case .SPITZER_SHA: return "Spitzer Heritage Archive"
        case .HLSP: return "High Level Science Product"
        case .JWST: return "James Webb Space Telescope"
        }
    }
}
