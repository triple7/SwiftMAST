//
//  Galex.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTGalex:String, CaseIterable, Identifiable {
 case IAUName
case MatchDEC
case MatchID
case MatchRA
case band
case dec
case dec_cent
case distanceArcMin
case distance_arcmin
case e_bv
case fov_radius
case fuv_artifact
case fuv_exptime
case fuv_flux
case fuv_flux_aper_7
case fuv_flux_auto
case fuv_fluxerr
case fuv_mag
case fuv_magerr
case nuv_artifact
case nuv_exptime
case nuv_flux
case nuv_flux_aper_7
case nuv_flux_auto
case nuv_fluxerr
case nuv_mag
case nuv_magerr
case objID
case ra
case ra_cent
case survey
case xCenter
case yCenter
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .IAUName: return "IAU Name"
case .MatchDEC: return "Match Dec"
case .MatchID: return "Match ID"
case .MatchRA: return "Match RA"
case .band: return "Band"
case .dec: return "Dec"
case .dec_cent: return "Dec Center"
case .distanceArcMin: return "Distance (')"
case .distance_arcmin: return "Distance (')"
case .e_bv: return "E(B-V)"
case .fov_radius: return "FOV Radius"
case .fuv_artifact: return "FUV Artifact"
case .fuv_exptime: return "FUV Exposure Time"
case .fuv_flux: return "FUV Flux"
case .fuv_flux_aper_7: return "FUV Flux (aper 7)"
case .fuv_flux_auto: return "FUV Flux (auto)"
case .fuv_fluxerr: return "FUV Flux Error"
case .fuv_mag: return "FUV Magnitude"
case .fuv_magerr: return "FUV Magnitude Error"
case .nuv_artifact: return "NUV Artifact"
case .nuv_exptime: return "NUV Exposure Time"
case .nuv_flux: return "NUV Flux"
case .nuv_flux_aper_7: return "NUV Flux (aper 7)"
case .nuv_flux_auto: return "NUV Flux (auto)"
case .nuv_fluxerr: return "NUV Flux Error"
case .nuv_mag: return "NUV Magnitude"
case .nuv_magerr: return "NUV Magnitude Error"
case .objID: return "Object ID"
case .ra: return "RA"
case .ra_cent: return "RA Center"
case .survey: return "Survey"
case .xCenter: return "X Center"
case .yCenter: return "Y Center"

}
}
 }

