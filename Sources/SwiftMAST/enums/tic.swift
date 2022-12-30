//
//  Tic.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTTic:String, CaseIterable, Identifiable {
 case ALLWISE
case APASS
case Bmag
case GAIA
case GAIAmag
case HIP
case Hmag
case ID
case Jmag
case KIC
case Kmag
case MH
case PARflag
case PMflag
case POSflag
case SDSS
case SPFlag
case TESSflag
case TWOMASS
case TWOMflag
case TYC
case Teff
case Tmag
case UCAC
case Vmag
case contratio
case d
case dec
case disposition
case duplicate_i
case e_Bmag
case e_GAIAmag
case e_Hmag
case e_Jmag
case e_Kmag
case e_MH
case e_Teff
case e_Tmag
case e_Vmag
case e_d
case e_ebv
case e_gmag
case e_imag
case e_logg
case e_lum
case e_mass
case e_plx
case e_pmDEC
case e_pmRA
case e_rad
case e_rho
case e_rmag
case e_umag
case e_w1mag
case e_w2mag
case e_w3mag
case e_w4mag
case e_zmag
case ebv
case eclat
case eclong
case gallat
case gallong
case gmag
case imag
case logg
case lum
case lumclass
case mass
case numcont
case objID
case objType
case plx
case pmDEC
case pmRA
case prox
case ra
case rad
case rho
case rmag
case typeSrc
case umag
case version
case w1mag
case w2mag
case w3mag
case w4mag
case zmag
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .ALLWISE: return "ALLWISE ID"
case .APASS: return "APASS ID"
case .Bmag: return "B Mag."
case .GAIA: return "GAIA ID"
case .GAIAmag: return "GAIA G Mag."
case .HIP: return "HIP"
case .Hmag: return "H Mag."
case .ID: return "TIC ID"
case .Jmag: return "J Mag."
case .KIC: return "KIC ID"
case .Kmag: return "K Mag."
case .MH: return "Metallicity"
case .PARflag: return "Source of Parallax"
case .PMflag: return "PM Flag"
case .POSflag: return "Source of Position"
case .SDSS: return "SDSS ID"
case .SPFlag: return "Stellar Properties Flag"
case .TESSflag: return "TESS Flag"
case .TWOMASS: return "2MASS ID"
case .TWOMflag: return "TWOMflag"
case .TYC: return "TYC ID"
case .Teff: return "T_eff"
case .Tmag: return "TESS Mag."
case .UCAC: return "UCAC ID"
case .Vmag: return "V Mag."
case .contratio: return "Contam. Ratio"
case .d: return "Distance"
case .dec: return "Dec"
case .disposition: return "Disposition"
case .duplicate_i: return "Duplicate ID"
case .e_Bmag: return "B Mag. Err."
case .e_GAIAmag: return "GAIA G Mag. Err."
case .e_Hmag: return "H Mag. Err."
case .e_Jmag: return "J Mag. Err."
case .e_Kmag: return "K Mag. Err."
case .e_MH: return "Metallicity Err."
case .e_Teff: return "T_eff Err."
case .e_Tmag: return "TESS Mag. Err."
case .e_Vmag: return "V Mag. Err."
case .e_d: return "Distance Err."
case .e_ebv: return "E(B-V) Err."
case .e_gmag: return "g Mag. Err."
case .e_imag: return "i Mag. Err."
case .e_logg: return "log(g) Err."
case .e_lum: return "Stellar Luminosity Err."
case .e_mass: return "Stellar Mass Err."
case .e_plx: return "Parallax Err."
case .e_pmDEC: return "pmDec Err."
case .e_pmRA: return "pmRA Err."
case .e_rad: return "Stellar Radius Err."
case .e_rho: return "Stellar Density Err."
case .e_rmag: return "r Mag. Err."
case .e_umag: return "u Mag. Err."
case .e_w1mag: return "W1 Mag. Err."
case .e_w2mag: return "W2 Mag. Err."
case .e_w3mag: return "W3 Mag. Err."
case .e_w4mag: return "W4 Mag. Err."
case .e_zmag: return "z Mag. Err."
case .ebv: return "E(B-V)"
case .eclat: return "Ecl. Lat."
case .eclong: return "Ecl. Long."
case .gallat: return "Gal. Lat."
case .gallong: return "Gal. Long."
case .gmag: return "g Mag."
case .imag: return "i Mag."
case .logg: return "log(g)"
case .lum: return "Stellar Luminosity"
case .lumclass: return "Luminosity Class from RPM"
case .mass: return "Stellar Mass"
case .numcont: return "Num. Sources in Aper."
case .objID: return "MAST Object ID"
case .objType: return "Object Type"
case .plx: return "Parallax"
case .pmDEC: return "pmDEC"
case .pmRA: return "pmRA"
case .prox: return "prox"
case .ra: return "RA"
case .rad: return "Stellar Radius"
case .rho: return "Stellar Density"
case .rmag: return "r Mag."
case .typeSrc: return "Source of Type"
case .umag: return "u Mag."
case .version: return "Version"
case .w1mag: return "W1 Mag."
case .w2mag: return "W2 Mag."
case .w3mag: return "W3 Mag."
case .w4mag: return "W4 Mag."
case .zmag: return "z Mag."

}
}
 }

