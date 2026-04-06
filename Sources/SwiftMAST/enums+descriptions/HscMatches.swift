//
//  HscMatches.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias HSCMatches = MASTHscmatchesField

/// HSC Matches field columns
/// https://mast.stsci.edu/api/v0/_h_s_c__matchesfields.html
public enum MASTHscmatchesField: String, CaseIterable, Identifiable {
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

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .AbsCorr: return "Absolute Correction"
        case .Aperture: return "Aperture Name"
        case .CI: return "Concentration Index"
        case .CatID: return "Catalog ID"
        case .D: return "Distance (arcsec)"
        case .Det: return "Detection Flag"
        case .Detector: return "Detector Name"
        case .Dsigma: return "Distance Sigma"
        case .ExposureTime: return "Exposure Time (seconds)"
        case .Filter: return "Filter Name"
        case .Flags: return "SExtractor Flags"
        case .FluxAper2: return "Flux in Aperture 2"
        case .ImageID: return "Image ID"
        case .ImageName: return "Image Name"
        case .Instrument: return "Instrument Name"
        case .KronRadius: return "Kron Radius"
        case .MagAper2: return "Magnitude in Aperture 2"
        case .MagAuto: return "Auto Magnitude"
        case .MatchDec: return "Match Declination (degrees)"
        case .MatchID: return "Match ID"
        case .MatchRA: return "Match Right Ascension (degrees)"
        case .MemID: return "Member ID"
        case .Mode: return "Observation Mode"
        case .PropID: return "Proposal ID"
        case .SourceDec: return "Source Declination (degrees)"
        case .SourceID: return "Source ID"
        case .SourceRA: return "Source Right Ascension (degrees)"
        case .SpectrumFlag: return "Spectrum Available Flag"
        case .StartMJD: return "Start Time (MJD)"
        case .StartTime: return "Start Time"
        case .StopMJD: return "Stop Time (MJD)"
        case .StopTime: return "Stop Time"
        case .TargetName: return "Target Name"
        case .Wavelength: return "Central Wavelength"
        case .XImage: return "X Image Position"
        case .Ximage: return "X Image Position (alternate)"
        case .YImage: return "Y Image Position"
        case .Yimage: return "Y Image Position (alternate)"
        case .cd_matrix: return "CD Matrix"
        case .crpix: return "Reference Pixel"
        case .crval: return "Reference Value"
        case .naxis: return "Number of Axes"
        }
    }
}
