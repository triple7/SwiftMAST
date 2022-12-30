//
//  DataSets.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation


public enum MASTDataSet:String, CaseIterable, Identifiable {
case hst
case hsc_sum
case hsc
case kepler_data_search
case kepler_fov
case kepler_kic10
case kepler_kgmatch
case kepler_KOI_planets
case kepler_published_planets
case kepler_KOI
case kepler_ffi
case kepler_epic
case k2_data_search
case k2_planets
case k2_ffi
case iue
case hut
case euve
case fuse
case uit
case wuppe
case befs
case tues
case imaps
case hlsp
case pointings
case copernicus
case hpol
case vlafirst
case xmm_om
case swift_uvot

    public var id:String {
        return self.rawValue.replacingOccurrences(of: "_", with: "-")
    }

    public var urlPath:String {
        switch self {
        case .swift_uvot: return self.rawValue
        case .xmm_om: return "xmm-om"
        default: return self.rawValue.replaceFirst(of: "_", with: "/").lowercased()
        }
    }
    
 public var description:String {
switch self {
case .hst: return "Hubble Space Telescope"
case .hsc_sum: return "Hubble Source Catalog Summary table"
case .hsc: return "Hubble Source Catalog Detailed table"
case .kepler_data_search: return "Kepler data search"
case .kepler_fov: return "Target search,replaces kepler_fov_enh (kepler/kepler_fov)"
case .kepler_kic10: return "Kepler Input Catalog (kepler/kic10)"
case .kepler_kgmatch: return "Kepler/Galex Cross match (kepler/kgmatch)"
case .kepler_KOI_planets: return "Kepler Confirmed Planets (with KOI-based data) (kepler/confirmed_planets)"
case .kepler_published_planets: return "Kepler Confirmed Planets (with published data) (kepler/published_planets)"
case .kepler_KOI: return "Kepler Objects of Interest (kepler/koi)"
case .kepler_ffi: return "FFIs (kepler/ffi)"
case .kepler_epic: return "Ecliptic Plane Input Catalog (k2/epic)"
case .k2_data_search: return "Data Search (k2/data_search)"
case .k2_planets: return "K2 planets (k2/published_planets)"
case .k2_ffi: return "FFIs (k2/ffi)"
case .iue: return "International Ultraviolet Explorer"
case .hut: return "Hopkins Ultraviolet Telescope"
case .euve: return "Extreme Ultraviolet Explorer"
case .fuse: return "Far-UV Spectroscopic Explorer"
case .uit: return "Ultraviolet Imageing Telescope"
case .wuppe: return "Wisconsin UV Photo-Polarimeter Explorer"
case .befs: return "Berkeley Extreme and Far-UV"
case .tues: return "Tübingen Echelle Spectrograph"
case .imaps: return "Interstellar Medium Absorption Profile Spectrograph"
case .hlsp: return "High Level Science Products"
case .pointings: return "HST Image Data grouped by position"
case .copernicus: return "Copernicus Satellite"
case .hpol: return "ground based spetropolarimater"
case .vlafirst: return "VLA Faint Images of the Radio Sky (21-cm)"
case .xmm_om: return "X-ray Multi-Mirror Telescope Optical Monitor"
case .swift_uvot: return "Swift UV/optical Telescope"
 }
}
}

