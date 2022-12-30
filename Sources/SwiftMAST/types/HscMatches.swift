//
//  HscMatches.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation


public typealias HSCMatches = MASTHscmatchesField

public enum MASTHscmatchesField:String, CaseIterable, Identifiable {
 case AbsCorr
case Aperture
case CI
case CatID
case D
case Det
case Detector
case Dsigma
case ExposureTime
case Filter
case Flags
case FluxAper2
case ImageID
case ImageName
case Instrument
case KronRadius
case MagAper2
case MagAuto
case MatchDec
case MatchID
case MatchRA
case MemID
case Mode
case PropID
case SourceDec
case SourceID
case SourceRA
case SpectrumFlag
case StartMJD
case StartTime
case StopMJD
case StopTime
case TargetName
case Wavelength
case XImage
case Ximage
case YImage
case Yimage
case cd_matrix
case crpix
case crval
case naxis
 
public var id:String {
return self.rawValue
}
 
 }

