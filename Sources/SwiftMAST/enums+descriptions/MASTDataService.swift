//
//  MASTDataService.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 15/2/2025.
//


public enum MASTDataService: String, Codable, Identifiable {
    case tic_v8
    case gaia_dr3
    case hsc_v3
    case galex_ais
    case panstarrs_dr2
    case ctl_v8
    case disk_detective
    case plato_input_catalog

    public var id: String { return rawValue } // Returns the raw value as the identifier

    public var description: String {
        switch self {
        case .tic_v8:
            return "The TESS Input Catalog (TIC v8) contains stellar parameters for stars observed by TESS, aiding in exoplanet detection."
        case .gaia_dr3:
            return "The Gaia Data Release 3 (DR3) provides precise astrometric and photometric measurements of over a billion stars for galactic studies."
        case .hsc_v3:
            return "The Hubble Source Catalog (HSC v3) combines source lists from Hubble observations into a unified catalog for deep-space research."
        case .galex_ais:
            return "The GALEX All-Sky Imaging Survey (AIS) provides ultraviolet imaging data to study galaxy evolution and star formation."
        case .panstarrs_dr2:
            return "The Pan-STARRS Data Release 2 (DR2) offers wide-field optical imaging data for studying transients and variable stars."
        case .ctl_v8:
            return "The TESS Candidate Target List (CTL v8) prioritizes stars optimal for detecting transiting exoplanets, guiding observational campaigns."
        case .disk_detective:
            return "The Disk Detective catalog identifies circumstellar disks, such as debris and protoplanetary disks, which are crucial for planetary formation studies."
        case .plato_input_catalog:
            return "The PLATO Input Catalog supports the PLATO mission by providing stellar data for potential planetary transit observations."
        }
    }
}
