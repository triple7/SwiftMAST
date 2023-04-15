//
//  File.swift
//  
//
//  Created by Yuma decaux on 2/1/2023.
//

import Foundation

public enum ResultField:String, Identifiable, CaseIterable {
 case intentType
case obs_collection
case provenance_name
case instrument_name
case project
case filters
case wavelength_region
case target_name
case target_classification
case obs_id
case s_ra
case s_dec
case dataproduct_type
case proposal_pi
case calib_level
case t_min
case t_max
case t_exptime
case em_min
case em_max
case obs_title
case t_obs_release
case proposal_id
case proposal_type
case sequence_number
case s_region
case jpegURL
case dataURL
case dataRights
case mtFlag
case srcDen
case obsid
case distance
case _selected_
    
    public var id:String {
        return self.rawValue
    }
 }
