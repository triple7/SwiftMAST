//
//  products.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTProducts:String, CaseIterable, Identifiable {
 case calib_level
case dataURI
case dataproduct_type
case description
case obsID
case obs_collection
case obs_id
case parent_obsid
case productDocumentationURL
case productFilename
case productGroupDescription
case productSubGroupDescription
case productType
case project
case proposal_id
case prvversion
case size
case type
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .calib_level: return "Calibration Level"
case .dataURI: return "URI"
case .dataproduct_type: return "Product Type"
case .description: return "Description"
case .obsID: return "Product Group ID"
case .obs_collection: return "Mission"
case .obs_id: return "Observation ID"
case .parent_obsid: return "Parent Product Group ID"
case .productDocumentationURL: return "Product Documentation"
case .productFilename: return "Filename"
case .productGroupDescription: return "Product Group"
case .productSubGroupDescription: return "Product Subgroup"
case .productType: return "Product Category"
case .project: return "Project"
case .proposal_id: return "Proposal ID"
case .prvversion: return "Calibration Version"
case .size: return "File Size"
case .type: return "Type"

}
}
 }

