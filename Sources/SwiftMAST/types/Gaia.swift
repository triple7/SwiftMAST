//
//  Gaia.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
typealias Gaia = MASTGaiaField


public enum MASTGaiaField:String, CaseIterable, Identifiable {
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
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .astrometric_primary_flag: return "astrometric_primary_flag"
case .b: return "b"
case .dec: return "dec"
case .dec_error: return "dec_error"
case .duplicated_source: return "duplicated_source"
case .hip: return "hip"
case .l: return "l"
case .matched_observations: return "matched_observations"
case .parallax: return "parallax"
case .parallax_error: return "parallax error"
case .phot_g_mean_flux: return "phot_g_mean_flux"
case .phot_g_mean_flux_error: return "phot_g_mean_flux_error"
case .phot_g_mean_mag: return "phot_g_mean_mag"
case .phot_g_n_obs: return "phot_g_n_obs"
case .phot_variable_flag: return "phot_variable_flag"
case .pmdec: return "pmdec"
case .pmdec_error: return "pmdec_error"
case .pmra: return "pmra"
case .pmra_error: return "pmra_error"
case .ra: return "ra"
case .ra_error: return "ra error"
case .random_index: return "random_index"
case .ref_epoch: return "ref_epoch"
case .solution_id: return "solution_id"
case .source_id: return "source_id"
case .tycho2_id: return "tycho2_id"

}
}
 }

