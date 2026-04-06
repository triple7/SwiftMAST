//
//  Tic.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias Tic = MASTTicField

/// TIC (TESS Input Catalog) field columns
/// https://mast.stsci.edu/api/v0/_t_i_cfields.html
public enum MASTTicField: String, CaseIterable, Identifiable {
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

    public var id: String {
        return self.rawValue
    }

    public var description: String {
        switch self {
        case .ALLWISE: return "ALLWISE ID"
        case .APASS: return "APASS ID"
        case .Bmag: return "B Magnitude"
        case .GAIA: return "GAIA ID"
        case .GAIAmag: return "GAIA Magnitude"
        case .HIP: return "Hipparcos ID"
        case .Hmag: return "H Magnitude"
        case .ID: return "TIC ID"
        case .Jmag: return "J Magnitude"
        case .KIC: return "Kepler Input Catalog ID"
        case .Kmag: return "K Magnitude"
        case .MH: return "Metallicity [M/H]"
        case .PARflag: return "Parallax Flag"
        case .PMflag: return "Proper Motion Flag"
        case .POSflag: return "Position Flag"
        case .SDSS: return "SDSS ID"
        case .SPFlag: return "Stellar Properties Flag"
        case .TESSflag: return "TESS Flag"
        case .TWOMASS: return "2MASS ID"
        case .TWOMflag: return "2MASS Flag"
        case .TYC: return "Tycho ID"
        case .Teff: return "Effective Temperature (K)"
        case .Tmag: return "TESS Magnitude"
        case .UCAC: return "UCAC ID"
        case .Vmag: return "V Magnitude"
        case .contratio: return "Contamination Ratio"
        case .d: return "Distance (pc)"
        case .dec: return "Declination (degrees)"
        case .disposition: return "Disposition"
        case .duplicate_i: return "Duplicate ID"
        case .e_Bmag: return "B Magnitude Error"
        case .e_GAIAmag: return "GAIA Magnitude Error"
        case .e_Hmag: return "H Magnitude Error"
        case .e_Jmag: return "J Magnitude Error"
        case .e_Kmag: return "K Magnitude Error"
        case .e_MH: return "Metallicity Error"
        case .e_Teff: return "Effective Temperature Error"
        case .e_Tmag: return "TESS Magnitude Error"
        case .e_Vmag: return "V Magnitude Error"
        case .e_d: return "Distance Error"
        case .e_ebv: return "E(B-V) Reddening Error"
        case .e_gmag: return "g Magnitude Error"
        case .e_imag: return "i Magnitude Error"
        case .e_logg: return "Log Surface Gravity Error"
        case .e_lum: return "Luminosity Error"
        case .e_mass: return "Mass Error"
        case .e_plx: return "Parallax Error"
        case .e_pmDEC: return "Proper Motion in Dec Error"
        case .e_pmRA: return "Proper Motion in RA Error"
        case .e_rad: return "Radius Error"
        case .e_rho: return "Density Error"
        case .e_rmag: return "r Magnitude Error"
        case .e_umag: return "u Magnitude Error"
        case .e_w1mag: return "W1 Magnitude Error"
        case .e_w2mag: return "W2 Magnitude Error"
        case .e_w3mag: return "W3 Magnitude Error"
        case .e_w4mag: return "W4 Magnitude Error"
        case .e_zmag: return "z Magnitude Error"
        case .ebv: return "E(B-V) Reddening"
        case .eclat: return "Ecliptic Latitude"
        case .eclong: return "Ecliptic Longitude"
        case .gallat: return "Galactic Latitude"
        case .gallong: return "Galactic Longitude"
        case .gmag: return "g Magnitude"
        case .imag: return "i Magnitude"
        case .logg: return "Log Surface Gravity"
        case .lum: return "Luminosity (solar)"
        case .lumclass: return "Luminosity Class"
        case .mass: return "Mass (solar)"
        case .numcont: return "Number of Contaminants"
        case .objID: return "Object ID"
        case .objType: return "Object Type"
        case .plx: return "Parallax (mas)"
        case .pmDEC: return "Proper Motion in Dec (mas/yr)"
        case .pmRA: return "Proper Motion in RA (mas/yr)"
        case .prox: return "Proximity (arcsec)"
        case .ra: return "Right Ascension (degrees)"
        case .rad: return "Radius (solar)"
        case .rho: return "Density (solar)"
        case .rmag: return "r Magnitude"
        case .typeSrc: return "Stellar Properties Type Source"
        case .umag: return "u Magnitude"
        case .version: return "TIC Version"
        case .w1mag: return "W1 Magnitude"
        case .w2mag: return "W2 Magnitude"
        case .w3mag: return "W3 Magnitude"
        case .w4mag: return "W4 Magnitude"
        case .zmag: return "z Magnitude"
        }
    }
}
