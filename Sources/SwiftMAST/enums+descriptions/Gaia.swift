//
//  Gaia.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias Gaia = MASTGaiaField

/// Gaia catalog field columns
/// https://mast.stsci.edu/api/v0/_gaiafields.html
public enum MASTGaiaField: String, CaseIterable, Identifiable {
    case astrometric_primary_flag
    case b
    case dec
    case dec_error
    case duplicated_source
    case hip
    case l
    case matched_observations
    case parallax
    case parallax_error
    case phot_g_mean_flux
    case phot_g_mean_flux_error
    case phot_g_mean_mag
    case phot_g_n_obs
    case phot_variable_flag
    case pmdec
    case pmdec_error
    case pmra
    case pmra_error
    case ra
    case ra_error
    case random_index
    case ref_epoch
    case solution_id
    case source_id
    case tycho2_id

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .astrometric_primary_flag: return "Astrometric Primary Flag"
        case .b: return "Galactic Latitude (degrees)"
        case .dec: return "Declination (degrees)"
        case .dec_error: return "Declination Error (mas)"
        case .duplicated_source: return "Duplicated Source Flag"
        case .hip: return "Hipparcos ID"
        case .l: return "Galactic Longitude (degrees)"
        case .matched_observations: return "Matched Observations"
        case .parallax: return "Parallax (mas)"
        case .parallax_error: return "Parallax Error (mas)"
        case .phot_g_mean_flux: return "G-band Mean Flux (e-/s)"
        case .phot_g_mean_flux_error: return "G-band Mean Flux Error (e-/s)"
        case .phot_g_mean_mag: return "G-band Mean Magnitude"
        case .phot_g_n_obs: return "G-band Number of Observations"
        case .phot_variable_flag: return "Photometric Variability Flag"
        case .pmdec: return "Proper Motion in Dec (mas/yr)"
        case .pmdec_error: return "Proper Motion in Dec Error (mas/yr)"
        case .pmra: return "Proper Motion in RA (mas/yr)"
        case .pmra_error: return "Proper Motion in RA Error (mas/yr)"
        case .ra: return "Right Ascension (degrees)"
        case .ra_error: return "Right Ascension Error (mas)"
        case .random_index: return "Random Index"
        case .ref_epoch: return "Reference Epoch (Julian Year)"
        case .solution_id: return "Solution ID"
        case .source_id: return "Source ID"
        case .tycho2_id: return "Tycho-2 ID"
        }
    }
}
