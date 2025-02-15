//
//  MASTDataService.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 15/2/2025.
//


public enum MASTDataService: String, Codable, Identifiable {
    case tic
    case gaiadr3
    case hscv3
    case galexais
    case panstarrsdr2
    case ctlv8
    case diskdetective
    case platoinputcatalog

    public var id: String { return rawValue } // Returns the raw value as the identifier

    public var description: String {
        switch self {
        case .tic:
            return "The TESS Input Catalog (TIC v8) contains stellar parameters for stars observed by TESS, aiding in exoplanet detection."
        case .gaiadr3:
            return "The Gaia Data Release 3 (DR3) provides precise astrometric and photometric measurements of over a billion stars for galactic studies."
        case .hscv3:
            return "The Hubble Source Catalog (HSC v3) combines source lists from Hubble observations into a unified catalog for deep-space research."
        case .galexais:
            return "The GALEX All-Sky Imaging Survey (AIS) provides ultraviolet imaging data to study galaxy evolution and star formation."
        case .panstarrsdr2:
            return "The Pan-STARRS Data Release 2 (DR2) offers wide-field optical imaging data for studying transients and variable stars."
        case .ctlv8:
            return "The TESS Candidate Target List (CTL v8) prioritizes stars optimal for detecting transiting exoplanets, guiding observational campaigns."
        case .diskdetective:
            return "The Disk Detective catalog identifies circumstellar disks, such as debris and protoplanetary disks, which are crucial for planetary formation studies."
        case .platoinputcatalog:
            return "The PLATO Input Catalog supports the PLATO mission by providing stellar data for potential planetary transit observations."
        }
    }
}
