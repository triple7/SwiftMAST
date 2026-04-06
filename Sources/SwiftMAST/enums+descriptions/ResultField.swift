//
//  File.swift
//
//
//  Created by Yuma decaux on 2/1/2023.
//

import Foundation

/// CAOM result field columns
/// https://mast.stsci.edu/api/v0/_c_a_o_mfields.html
public enum ResultField: String, Identifiable, CaseIterable {
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
    case objID

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .intentType: return "Intent Type (science or calibration)"
        case .obs_collection: return "Collection (mission/project name)"
        case .provenance_name: return "Provenance Name"
        case .instrument_name: return "Instrument Name"
        case .project: return "Project"
        case .filters: return "Filters"
        case .wavelength_region: return "Waveband"
        case .target_name: return "Target Name"
        case .target_classification: return "Target Classification"
        case .obs_id: return "Observation ID"
        case .s_ra: return "Right Ascension (degrees)"
        case .s_dec: return "Declination (degrees)"
        case .dataproduct_type: return "Data Product Type"
        case .proposal_pi: return "Principal Investigator"
        case .calib_level: return "Calibration Level"
        case .t_min: return "Start Time (MJD)"
        case .t_max: return "End Time (MJD)"
        case .t_exptime: return "Exposure Time (seconds)"
        case .em_min: return "Min Wavelength (nm)"
        case .em_max: return "Max Wavelength (nm)"
        case .obs_title: return "Observation Title"
        case .t_obs_release: return "Release Date"
        case .proposal_id: return "Proposal ID"
        case .proposal_type: return "Proposal Type"
        case .sequence_number: return "Sequence Number"
        case .s_region: return "Sky Region (footprint)"
        case .jpegURL: return "JPEG Preview URL"
        case .dataURL: return "Data URL"
        case .dataRights: return "Data Rights (public/restricted)"
        case .mtFlag: return "Moving Target Flag"
        case .srcDen: return "Source Density"
        case .obsid: return "Product Group ID"
        case .distance: return "Angular Separation (arcsec)"
        case ._selected_: return "Selected Flag"
        case .objID: return "Object ID"
        }
    }
}
