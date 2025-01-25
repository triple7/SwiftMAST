//
//  MASTTap.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//


public enum MASTTap: String, Codable, CaseIterable {
    case tap_schema_schemas = "tap_schema.schemas"
    case tap_schema_tables = "tap_schema.tables"
    case tap_schema_columns = "tap_schema.columns"
    case tap_schema_keys = "tap_schema.keys"
    case tap_schema_key_columns = "tap_schema.key_columns"
    case dbo_catalog_record = "dbo.catalogrecord"

    private enum CodingKeys: String, CodingKey {
        case tap_schema_schemas = "tap_schema.schemas"
        case tap_schema_tables = "tap_schema.tables"
        case tap_schema_columns = "tap_schema.columns"
        case tap_schema_keys = "tap_schema.keys"
        case tap_schema_key_columns = "tap_schema.key_columns"
        case dbo_catalog_record = "dbo.catalogrecord"
    }
}


public enum MASTTICRecord_columns: String, Codable, Identifiable, CaseIterable {
    case id
    case version
    case hip
    case tyc
    case ucac
    case twomass
    case sdss
    case allwise
    case gaia
    case apass
    case kic
    case objtype
    case typesrc
    case ra
    case dec
    case posflag
    case pmra
    case e_pmra
    case pmdec
    case e_pmdec
    case pmflag
    case plx
    case e_plx
    case parflag
    case gallong
    case gallat
    case eclong
    case eclat
    case bmag
    case e_bmag
    case vmag
    case e_vmag
    case umag
    case e_umag
    case gmag
    case e_gmag
    case rmag
    case e_rmag
    case imag
    case e_imag
    case zmag
    case e_zmag
    case jmag
    case e_jmag
    case hmag
    case e_hmag
    case kmag
    case e_kmag
    case twomflag
    case prox
    case w1mag
    case e_w1mag
    case w2mag
    case e_w2mag
    case w3mag
    case e_w3mag
    case w4mag
    case e_w4mag
    case gaiamag
    case e_gaiamag
    case tmag
    case e_tmag
    case tessflag
    case spflag
    case teff
    case e_teff
    case logg
    case e_logg
    case mh
    case e_mh
    case rad
    case e_rad
    case mass
    case e_mass
    case rho
    case e_rho
    case lumclass
    case lum
    case e_lum
    case d
    case e_d
    case ebv
    case e_ebv
    case numcont
    case contratio
    case disposition
    case duplicate_id
    case priority
    case eneg_ebv
    case epos_ebv
    case ebvflag
    case eneg_mass
    case epos_mass
    case eneg_rad
    case epos_rad
    case eneg_rho
    case epos_rho
    case eneg_logg
    case epos_logg
    case eneg_lum
    case epos_lum
    case eneg_dist
    case epos_dist
    case distflag
    case eneg_teff
    case epos_teff
    case teffflag
    case gaiabp
    case e_gaiabp
    case gaiarp
    case e_gaiarp
    case gaiaqflag
    case starchareflag
    case vmagflag
    case bmagflag
    case splists
    case e_ra
    case e_dec
    case ra_orig
    case dec_orig
    case e_ra_orig
    case e_dec_orig
    case raddflag
    case wdflag
    case objid
    
    public var id:String {
        return self.rawValue
    }
    
    public var description: String {
        switch self {
        case .id: return "TESS input catalog identifier"
        case .version: return "Catalog version"
        case .hip: return "Hipparcos identifier"
        case .tyc: return "Tycho2 identifier"
        case .ucac: return "UCAC4 identifier"
        case .twomass: return "2MASS identifier (hhmmssss+ddmmsss J2000)"
        case .sdss: return "SDSS DR9 object ID identifier"
        case .allwise: return "ALLWISE identifier (jhhmmss.ss+ddmmss.s)"
        case .gaia: return "Gaia DR2 identifier"
        case .apass: return "APASS DR9 identifier"
        case .kic: return "Kepler Input Catalog identifier"
        case .objtype: return "Object type (star or extended)"
        case .typesrc: return "Source of the object in the TIC"
        case .ra: return "Right ascension (J2000)"
        case .dec: return "Declination (J2000)"
        case .posflag: return "Source of position data"
        case .pmra: return "Proper motion in right ascension"
        case .e_pmra: return "Uncertainty in PMRA"
        case .pmdec: return "Proper motion in declination"
        case .e_pmdec: return "Uncertainty in PMDEC"
        case .pmflag: return "Source of proper motion data"
        case .plx: return "Parallax"
        case .e_plx: return "Uncertainty in parallax"
        case .parflag: return "Source of the parallax"
        case .gallong: return "Galactic longitude"
        case .gallat: return "Galactic latitude"
        case .eclong: return "Ecliptic longitude"
        case .eclat: return "Ecliptic latitude"
        case .bmag: return "Johnson B-band magnitude"
        case .e_bmag: return "Uncertainty in B magnitude"
        case .vmag: return "Johnson V-band magnitude"
        case .e_vmag: return "Uncertainty in V magnitude"
        case .umag: return "SDSS U-band (AB) magnitude"
        case .e_umag: return "Uncertainty in U magnitude"
        case .gmag: return "SDSS G-band (AB) magnitude"
        case .e_gmag: return "Uncertainty in G magnitude"
        case .rmag: return "SDSS R-band (AB) magnitude"
        case .e_rmag: return "Uncertainty in R magnitude"
        case .imag: return "SDSS I-band (AB) magnitude"
        case .e_imag: return "Uncertainty in I magnitude"
        case .zmag: return "SDSS Z-band (AB) magnitude"
        case .e_zmag: return "Uncertainty in Z magnitude"
        case .jmag: return "2MASS Johnson J-band magnitude"
        case .e_jmag: return "Uncertainty in J magnitude"
        case .hmag: return "2MASS Johnson H-band magnitude"
        case .e_hmag: return "Uncertainty in H magnitude"
        case .kmag: return "2MASS Johnson K-band magnitude"
        case .e_kmag: return "Uncertainty in K magnitude"
        case .twomflag: return "Quality flags for 2MASS"
        case .prox: return "Object proximity in arcseconds"
        case .w1mag: return "AllWISE W1 (3.4µm) magnitude"
        case .e_w1mag: return "Uncertainty in W1 magnitude"
        case .w2mag: return "AllWISE W2 (4.6µm) magnitude"
        case .e_w2mag: return "Uncertainty in W2 magnitude"
        case .w3mag: return "AllWISE W3 (12µm) magnitude"
        case .e_w3mag: return "Uncertainty in W3 magnitude"
        case .w4mag: return "AllWISE W4 (22µm) magnitude"
        case .e_w4mag: return "Uncertainty in W4 magnitude"
        case .gaiamag: return "Gaia DR2 G-band magnitude"
        case .e_gaiamag: return "Uncertainty in G-band magnitude"
        case .tmag: return "TESS magnitude"
        case .e_tmag: return "Uncertainty in TESS magnitude"
        case .tessflag: return "TESS magnitude flag"
        case .spflag: return "Stellar properties flag"
        case .teff: return "Effective temperature in Kelvin"
        case .e_teff: return "Uncertainty in effective temperature"
        case .logg: return "Log of the surface gravity (cm/s²)"
        case .e_logg: return "Uncertainty in surface gravity"
        case .mh: return "Metallicity [M/H]"
        case .e_mh: return "Uncertainty in metallicity"
        case .rad: return "Radius in solar radii"
        case .e_rad: return "Uncertainty in radius"
        case .mass: return "Mass in solar masses"
        case .e_mass: return "Uncertainty in mass"
        case .rho: return "Stellar density in solar units"
        case .e_rho: return "Uncertainty in density"
        case .lumclass: return "Luminosity class"
        case .lum: return "Stellar luminosity in solar units"
        case .e_lum: return "Uncertainty in luminosity"
        case .d: return "Distance in parsecs"
        case .e_d: return "Uncertainty in distance"
        case .ebv: return "Applied color excess (E(B-V))"
        case .e_ebv: return "Uncertainty in E(B-V)"
        case .numcont: return "Number of contaminants within 10 arcseconds"
        case .contratio: return "Contamination ratio"
        case .disposition: return "Disposition type"
        case .duplicate_id: return "Duplicate TIC ID in set of stars"
        case .priority: return "Priority (0 to 1, highest priority)"
        case .eneg_ebv: return "Negative error for E(B-V)"
        case .epos_ebv: return "Positive error for E(B-V)"
        case .ebvflag: return "Source of E(B-V)"
        case .eneg_mass: return "Negative error for mass"
        case .epos_mass: return "Positive error for mass"
        case .eneg_rad: return "Negative error for radius"
        case .epos_rad: return "Positive error for radius"
        case .eneg_rho: return "Negative error for stellar density"
        case .epos_rho: return "Positive error for stellar density"
        case .eneg_logg: return "Negative error for surface gravity"
        case .epos_logg: return "Positive error for surface gravity"
        case .eneg_lum: return "Negative error for luminosity"
        case .epos_lum: return "Positive error for luminosity"
        case .eneg_dist: return "Negative error for distance"
        case .epos_dist: return "Positive error for distance"
        case .distflag: return "Source for distance"
        case .eneg_teff: return "Negative error for effective temperature"
        case .epos_teff: return "Positive error for effective temperature"
        case .teffflag: return "Source for effective temperature"
        case .gaiabp: return "Gaia DR2 BP magnitude"
        case .e_gaiabp: return "Uncertainty in BP magnitude"
        case .gaiarp: return "Gaia DR2 RP magnitude"
        case .e_gaiarp: return "Uncertainty in RP magnitude"
        case .gaiaqflag: return "Quality flags for Gaia information"
        case .starchareflag: return "Asymmetric error flag"
        case .vmagflag: return "Source of V magnitude"
        case .bmagflag: return "Source of B"
            default: return "Unknown case"
        }
    }
    
}
