//
//  File.swift
//  
//
//  Created by Yuma decaux on 11/1/2024.
//

import Foundation

public enum Missions:String, CaseIterable {
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

    public var description:String {
        switch self {
        case .PS1: return "Pan-Stars 1`"
        case .SWIFT: return ""
        case .FUSE: return "Far-UV Spectroscopic Explorer"
        case .IUE: return "International Ultraviolet Explorer"
        case .BEFS: return "Berkeley Extreme and Far-UV Spectrometer"
        case .FIMS_SPEAR: return ""
        case .K2: return "Kepler mission 2"
        case .TESS: return "Transiting Exoplanet Survey Satellite"
        case .K2FFI: return ""
        case .OPO: return ""
        case .WUPPE: return "Wisconsin UV Photo-Polarimeter Explorer"
        case .HUT: return "Hopkins Ultraviolet Telescope"
        case .Kepler: return ""
        case .GALEX: return ""
        case .KeplerFFI: return ""
        case .HLA: return ""
        case .HST: return "Hubble Space Telescope"
        case .EUVE: return "Extreme Ultraviolet Explorer"
        case .TUES: return ""
        case .SPITZER_SHA: return ""
        case .HLSP: return "High Level Science Product"
        }
    }
}
