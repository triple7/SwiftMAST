//
//  Ssap.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation


public enum MASTSSAP:String, CaseIterable, Identifiable {
    case fos
    case ghrs
    case stis
    case hst //(to include all instruments)
    case iue
    case hut
    case euve
    case fuse
    case wuppe
    case befs
    case tues
    case hpol

public var id:String {
return self.rawValue
}
    
public var description:String {
switch self {
case .fos: return ""
case .ghrs: return "Goddard high resolution spectrograph"
case .stis: return "Space telescope imaging spectrograph"
case .hst: return "hubble space telescope"
case .iue: return "International Ultraviolet Explorer"
case .hut: return "Hopkins Ultraviolet Telescope"
case .euve: return "Extreme Ultraviolet Explorer"
case .fuse: return "Far-UV Spectroscopic Explorer"
case .wuppe: return "Wisconsin UV Photo-Polarimeter Explorer"
case .befs: return "Berkeley Extreme and Far-UV"
case .tues: return "Tübingen Echelle Spectrograph"
case .hpol: return "ground based spetropolarimater"
}
}
}
