//
//  Tic.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias Tic = MASTTicField

public enum MASTTicField:String, CaseIterable, Identifiable {
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

}
