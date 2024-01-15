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
 
 }

