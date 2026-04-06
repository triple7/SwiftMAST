//
//  DiskDetected.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias DiskDetected = MASTDiskdetectedField

/// Disk Detective catalog field columns
/// https://mast.stsci.edu/api/v0/_disk__detectivefields.html
public enum MASTDiskdetectedField: String, CaseIterable, Identifiable {
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

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .A_contamination: return "A Contamination Flag"
        case .G_contamination: return "G Contamination Flag"
        case .P_contamination: return "P Contamination Flag"
        case .P_nDetections: return "Number of P Detections"
        case .T_contamination: return "T Contamination Flag"
        case .ZooniverseURL: return "Zooniverse URL"
        case .classifiers: return "Number of Classifiers"
        case .dec: return "Declination (degrees)"
        case .dstArcSec: return "Distance (arcsec)"
        case .empty: return "Empty Flag"
        case .extended: return "Extended Source Flag"
        case .glat: return "Galactic Latitude"
        case .glon: return "Galactic Longitude"
        case .good: return "Good Classification Count"
        case .h_m_2mass: return "2MASS H Magnitude"
        case .h_msig_2mass: return "2MASS H Magnitude Error"
        case .j_m_2mass: return "2MASS J Magnitude"
        case .j_msig_2mass: return "2MASS J Magnitude Error"
        case .k_m_2mass: return "2MASS K Magnitude"
        case .k_msig_2mass: return "2MASS K Magnitude Error"
        case .multi: return "Multiple Source Flag"
        case .oval: return "Oval Classification Count"
        case .previewURL: return "Preview Image URL"
        case .ra: return "Right Ascension (degrees)"
        case .sedURL: return "SED Plot URL"
        case .shift: return "Shift Classification Count"
        case .state: return "Classification State"
        case .w1mpro: return "WISE W1 Magnitude"
        case .w1sigmpro: return "WISE W1 Magnitude Error"
        case .w2mpro: return "WISE W2 Magnitude"
        case .w2sigmpro: return "WISE W2 Magnitude Error"
        case .w3mpro: return "WISE W3 Magnitude"
        case .w3sigmpro: return "WISE W3 Magnitude Error"
        case .w4mpro: return "WISE W4 Magnitude"
        case .w4sigmpro: return "WISE W4 Magnitude Error"
        }
    }
}
