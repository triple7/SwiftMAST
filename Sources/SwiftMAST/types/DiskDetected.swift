//
//  DiskDetected.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
public typealias DiskDetected = MASTDiskdetectedField

public enum MASTDiskdetectedField:String, CaseIterable, Identifiable {
 case A_contamination
case G_contamination
case P_contamination
case P_nDetections
case T_contamination
case ZooniverseURL
case classifiers
case dec
case dstArcSec
case empty
case extended
case glat
case glon
case good
case h_m_2mass
case h_msig_2mass
case j_m_2mass
case j_msig_2mass
case k_m_2mass
case k_msig_2mass
case multi
case oval
case previewURL
case ra
case sedURL
case shift
case state
case w1mpro
case w1sigmpro
case w2mpro
case w2sigmpro
case w3mpro
case w3sigmpro
case w4mpro
case w4sigmpro
 
public var id:String {
return self.rawValue
}
 
 }

