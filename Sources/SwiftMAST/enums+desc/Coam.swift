//
//  Coam.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
public typealias Coam = MASTCoamField

/** COAM search fields
 https://mast.stsci.edu/api/v0/_c_a_o_mfields.html
 */
public enum MASTCoamField:String, CaseIterable, Identifiable {
 case calib_level
case dataRights
case dataURL
case dataproduct_type
case distance
case em_max
case em_min
case filters
case instrument_name
case intentType
case jpegURL
case mtFlag
case objID
case obs_collection
case obs_id
case obs_title
case obsid
case project
case proposal_id
case proposal_pi
case proposal_type
case provenance_name
case s_dec
case s_ra
case s_region
case sequence_number
case srcDen
case t_exptime
case t_max
case t_min
case t_obs_release
case target_classification
case target_name
case wavelength_region
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .calib_level: return "Calibration Level"
case .dataRights: return "Data Rights"
case .dataURL: return "Data URL"
case .dataproduct_type: return "Product Type"
case .distance: return "Distance"
case .em_max: return "Max. Wavelength"
case .em_min: return "Min. Wavelength"
case .filters: return "Filters"
case .instrument_name: return "Instrument"
case .intentType: return "Observation Type"
case .jpegURL: return "jpegURL"
case .mtFlag: return "Moving Target"
case .objID: return "Object ID"
case .obs_collection: return "Mission"
case .obs_id: return "Observation ID"
case .obs_title: return "Observation Title"
case .obsid: return "Product Group ID"
case .project: return "Project"
case .proposal_id: return "Proposal ID"
case .proposal_pi: return "Principal Investigator"
case .proposal_type: return "Proposal Type"
case .provenance_name: return "Provenance Name"
case .s_dec: return "Dec"
case .s_ra: return "RA"
case .s_region: return "s_region"
case .sequence_number: return "Sequence Number"
case .srcDen: return "Number of Catalog Objects"
case .t_exptime: return "Exposure Length"
case .t_max: return "End Time"
case .t_min: return "Start Time"
case .t_obs_release: return "Release Date"
case .target_classification: return "Target Classification"
case .target_name: return "Target Name"
case .wavelength_region: return "Waveband"
}
}
    
    public func scienceImageFilters() -> [[MAP: Any]] {
        return [
            [MAP.paramName: MAP.filters as Any,
             MAP.values: ["NUV" , "FUV"] as Any],
            [MAP.paramName: Coam.calib_level as Any,
             MAP.values: [3, 4] as Any],
            [MAP.paramName: Coam.dataRights as Any,
             MAP.values: ["public"] as Any],
            [MAP.paramName: Coam.dataproduct_type as Any,
             MAP.values: ["IMAGE"] as Any],
            [MAP.paramName: Coam.intentType as Any,
             MAP.values: ["science"] as Any]
        ]
    }
    
 }

