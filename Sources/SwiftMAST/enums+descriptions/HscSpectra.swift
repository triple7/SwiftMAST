//
//  HscSpectra.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias HSCSpectra = MASTHscspectraField

public enum MASTHscspectraField:String, CaseIterable, Identifiable {
 case Aperture
case DatasetName
case Dec
case Detector
case ExposureTime
case HSCMatch
case HSLATargetName
case MatchID
case Notes
case ObjID
case ObjectType
case PropID
case RA
case SpectralElement
case SpectrumType
case TargetName
case Wavelength
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .Aperture: return "Aperture"
case .DatasetName: return "Dataset Name"
case .Dec: return "Dec"
case .Detector: return "Detector"
case .ExposureTime: return "Exposure Time"
case .HSCMatch: return "HSC Match?"
case .HSLATargetName: return "HSLA Target Name"
case .MatchID: return "Match ID"
case .Notes: return "Notes"
case .ObjID: return "Object ID"
case .ObjectType: return "Object Type"
case .PropID: return "Proposal ID"
case .RA: return "RA"
case .SpectralElement: return "Spectral Element"
case .SpectrumType: return "Dimensions"
case .TargetName: return "Target Name"
case .Wavelength: return "Wavelength"

}
}
 }

