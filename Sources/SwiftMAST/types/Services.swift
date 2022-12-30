////  Services.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTServices:String, CaseIterable, Identifiable {
    case Mast_Catalogs_Filtered_Tic
    case Mast_Catalogs_Filtered_Tic_Rows
    case Mast_Catalogs_Filtered_Tic_Position
    case Mast_Catalogs_Filtered_Tic_Position_Rows
    case Mast_Catalogs_Tic_Cone
    case Mast_Tic_Crossmatch
    case Mast_Catalogs_Filtered_Ctl
    case Mast_Catalogs_Filtered_Ctl_Rows
    case Mast_Catalogs_Filtered_Ctl_Position
    case Mast_Catalogs_Filtered_Ctl_Position_Rows
    case Mast_Catalogs_Ctl_Cone
    case Mast_Ctl_Crossmatch
    case Mast_Catalogs_Filtered_Wfc3Psf_Uvis
    case Mast_Catalogs_Filtered_Wfc3Psf_Ir
    case Vo_Hesarc_DatascopeListable
    case Mast_Caom_Cone
    case Mast_Caom_Filtered
    case Mast_Caom_Filtered_Position
    case Mast_Caom_Products
    case Mast_Caom_Crossmatch
    case Mast_Hsc_Db_v2
    case Mast_Hsc_Db_v3
    case Mast_HscMatches_Db_v2
    case Mast_HscMatches_Db_v3
    case Mast_HscSpectra_Db_All
    case Mast_Hsc_Crossmatch_MagAper2v3
    case Mast_Hsc_Crossmatch_MagAutov3
    case Mast_Catalogs_DiskDetective_Cone
    case Mast_Catalogs_Filtered_DiskDetective_Count
    case Mast_Catalogs_Filtered_DiskDetective_Position_Count
    case Mast_Catalogs_Filtered_DiskDetective
    case Mast_Catalogs_Filtered_DiskDetective_Position
    case Mast_GaiaDR1_Crossmatch
    case Mast_GaiaDR2_Crossmatch
    case Mast_GaiaDR3_Crossmatch
    case Mast_Tgas_Crossmatch
    case Mast_Catalogs_GaiaDR1_Cone
    case Mast_Catalogs_GaiaDR2_Cone
    case Mast_Catalogs_GaiaDR3_Cone
    case Mast_Catalogs_Tgas_Cone
    case Mast_Name_Lookup
    case Mast_Missions_List
    case Mast_Galex_Crossmatch
    case Mast_Sdss_Crossmatch
    case Mast_2Mass_Crossmatch
    case Vo_Generic_Table
    case Mast_Galex_Catalog
    case Mast_Jwst_Filtered_Nircam
    case Mast_Jwst_Filtered_Niriss
    case Mast_Jwst_Filtered_Nirspec
    case Mast_Jwst_Filtered_Miri
    case Mast_Jwst_Filtered_Fgs
    case Mast_Jwst_Filtered_GuideStar
    case Mast_Jwst_Filtered_Wss
    
    public var id:String {
        return self.rawValue.replacingOccurrences(of: "_", with: ".")
    }

    public var description:String {
        switch self {
        case .Mast_Catalogs_Filtered_Tic: return """
        Get TESS Input Catalog entries by filtering based on column (as in Advanced Search). Note: It is recommended to use Mast.Catalogs.Filtered.Tic.Rows to download results.
        """
        case .Mast_Catalogs_Filtered_Tic_Rows: return """
        Get TESS Input Catalog entries by filtering based on column (as in Advanced Search). Note: This can only return rows of data, not counts, but is faster than passing c.* as the filters to Mast.Catalogs.Filtered.Tic.
        """
        case .Mast_Catalogs_Filtered_Tic_Position: return """
        Get TESS Input Catalog entries by performing a cone search as well as filtering based on column (as in Advanced Search). Note: It is recommended to use Mast.Catalogs.Filtered.Tic.Position.Rows to download results.
        """
        case .Mast_Catalogs_Filtered_Tic_Position_Rows: return """
        Get TESS Input Catalog entries by performing a cone search as well as filtering based on column (as in Advanced Search). Note: This can only return rows of data, not counts, but is faster than passing c.* as the filters to Mast.Catalogs.Filtered.Tic.Position.
        """
        case .Mast_Catalogs_Tic_Cone: return """
        Perform a TESS Input Catalog cone search. See TIC Field documentation for a description of the returned columns.
        MashupRequest property pagesize rows up to nr will be returned. The MashupRequest property page should be used to get subsequent pages.
        """
        case .Mast_Tic_Crossmatch: return """
        Perform a cross-match with the TESS Input Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Catalogs_Filtered_Ctl: return """
        Get TESS Candidate Target List entries by filtering based on column (as in Advanced Search). Note: It is recommended to use Mast.Catalogs.Filtered.Ctl.Rows to download results.
        """
        case .Mast_Catalogs_Filtered_Ctl_Rows: return """
        Get TESS Candidate Target List entries by filtering based on column (as in Advanced Search). Note: This can only return rows of data, not counts, but is faster than passing c.* as the filters to Mast.Catalogs.Filtered.Ctl.
        """
        case .Mast_Catalogs_Filtered_Ctl_Position: return """
        Get TESS Candidate Target List entries by performing a cone search as well as filtering based on column (as in Advanced Search). Note: It is recommended to use Mast.Catalogs.Filtered.Ctl.Position.Rows to download results.
        """
        case .Mast_Catalogs_Filtered_Ctl_Position_Rows: return """
        Get TESS Candidate Target List entries by performing a cone search as well as filtering based on column (as in Advanced Search). Note: This can only return rows of data, not counts, but is faster than passing c.* as the filters to Mast.Catalogs.Filtered.Ctl.Position.
        """
        case .Mast_Catalogs_Ctl_Cone: return """
        Perform a TESS Candidate Target List cone search. See TIC Field documentation for a description of the returned columns.
        MashupRequest property pagesize rows up to nr will be returned. The MashupRequest property page should be used to get subsequent pages.
        """
        case .Mast_Ctl_Crossmatch: return """
        Perform a cross-match with the TESS Candidate Target List.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Catalogs_Filtered_Wfc3Psf_Uvis: return """
        Get WFC3 PSF UVIS by filtering based on column (as in Advanced Search).
        """
        case .Mast_Catalogs_Filtered_Wfc3Psf_Ir: return """
        Get WFC3 PSF IR by filtering based on column (as in Advanced Search).
        """
        case .Vo_Hesarc_DatascopeListable: return """
        Perform a VO cone search.
        With all return types other than csv the result will include the fields "status" and "percent complete." While the query is still running the status will be "EXECUTING" and the percent complete will reflect what percentage of the results have been returned. Once the query is finished, the status will change to "COMPLETE" and percent complete will be 1. There is a inactivity time out of 10 minutes, which is the maximum time between requests for a query not to be aborted.
        """
        case .Mast_Caom_Cone: return """
        Perform a CAOM cone search. See CAOM Field documentation for the list of columns returned.
        """
        case .Mast_Caom_Filtered: return """
        Get MAST observations by filtering based on column (as in Advanced Search).
        """
        case .Mast_Caom_Filtered_Position: return """
        Get MAST observations by performing a cone search as well as filtering based on column (as in Advanced Search).
        """
        case .Mast_Caom_Products: return """
        Get data products for a specific observation. See Products Field documentation for the list of columns returned.
        obsid: int or str (default 1000033356) One or more product group IDs for which data products will be returned. If supplying more than one obsid the fromat is a comma separated string.
        Note:** When doing a product query for HST data, there will be no indication if that data is in the queue for reprocessing. If this information is crucial, currently, one must go through the MAST Portal.
        """
        case .Mast_Caom_Crossmatch: return """
        Perform a cross-match with all MAST data.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec colums (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Hsc_Db_v2: return """
        Perform a Hubble Source Catalog v2 cone search. See HSC Field documentation for a description of the returned columns.
        MashupRequest property pagesize rows up to nr will be returned. The MashupRequest property page should be used to get subsequent pages.
        """
        case .Mast_Hsc_Db_v3: return """
        Perform a Hubble Source Catalog v3 cone search. See HSC Field documentation for a description of the returned columns.
        MashupRequest property pagesize rows up to nr will be returned. The MashupRequest property page should be used to get subsequent pages.
        """
        case .Mast_HscMatches_Db_v2: return """
        Get detailed results for an HSCv2 match. See HSC_Matches Field documentation for a description of the returned columns.
        """
        case .Mast_HscMatches_Db_v3: return """
        Get detailed results for an HSCv3 match. See HSC_Matches Field documentation for a description of the returned columns.
        """
        case .Mast_HscSpectra_Db_All: return """
        Get all the HSC spectra. See HSC_Spectra Field documentation for a description of the returns columns.
        None, the request simply returns all the HSC spectra
        """
        case .Mast_Hsc_Crossmatch_MagAper2v3: return """
        Perform a cross-match with the Hubble Source Catalog V3.0, MagAper2.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Hsc_Crossmatch_MagAutov3: return """
        Perform a cross-match with the Hubble Source Catalog V3.0, MagAuto.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Catalogs_DiskDetective_Cone: return """
        Perform a Disk Detective cone search. See Disk_Detective Field documentation for a description of the returned columns.
        MashupRequest property pagesize rows up to nr will be returned. The MashupRequest property page should be used to get subsequent pages.
        """
        case .Mast_Catalogs_Filtered_DiskDetective_Count: return """
        Get number of Disk Detective results based on column(s) (as in Advanced Search).
        """
        case .Mast_Catalogs_Filtered_DiskDetective_Position_Count: return """
        Get number of Disk Detective results by performing a cone search as well as filtering based on column (as in Advanced Search).
        """
        case .Mast_Catalogs_Filtered_DiskDetective: return """
        Get Disk Detective results by filtering based on column (as in Advanced Search).
        """
        case .Mast_Catalogs_Filtered_DiskDetective_Position: return """
        Get Disk Detective results by performing a cone search as well as filtering based on column (as in Advanced Search).
        """
        case .Mast_GaiaDR1_Crossmatch: return """
        Perform a cross-match with the Gaia (DR1) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_GaiaDR2_Crossmatch: return """
        Perform a cross-match with the Gaia (DR2) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_GaiaDR3_Crossmatch: return """
        Perform a cross-match with the Gaia (DR3) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Tgas_Crossmatch: return """
        Perform a cross-match with the TGAS (DR1) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Catalogs_GaiaDR1_Cone: return """
        Perform GAIA (DR1) catalog cone search. See Gaia Field documentation for a description of the returned columns.
        """
        case .Mast_Catalogs_GaiaDR2_Cone: return """
        Perform GAIA (DR2) catalog cone search. See Gaia Field documentation for a description of the returned columns.
        """
        case .Mast_Catalogs_GaiaDR3_Cone: return """
        Perform GAIA (DR3) catalog cone search. See Gaia Field documentation for a description of the returned columns.
        """
        case .Mast_Catalogs_Tgas_Cone: return """
        Perform TGAS (DR1) catalog cone search. See Gaia Field documentation for a description of the returned columns.
        """
        case .Mast_Name_Lookup: return """
        Resolves an object name into a position on the sky.
        """
        case .Mast_Missions_List: return """
        Lists the missions available in CAOM.
        None, the request simple returns all CAOM missions.
        """
        case .Mast_Galex_Crossmatch: return """
        Perform a cross-match with the GALEX Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_Sdss_Crossmatch: return """
        Perform a cross-match with the Sloan Digital Sky Surveys (SDSS) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Mast_2Mass_Crossmatch: return """
        Perform a cross-match with the Two Micron All Sky Survey (2MASS) Catalog.
        When using this service, a json object must be provided in the MashupRequest property "data" that at minimum contains ra and dec columns (see the python example for a minimal example of this object). If using the json result from a CAOM cone search as crossmatch input the ra/dec columns will usually be 's_ra' and s_dec.'
        """
        case .Vo_Generic_Table: return """
        Get VO data given a url.
        """
        case .Mast_Galex_Catalog: return """
        Perform a GALEX catalog cone search. See GALEX Field documentation for a description of the returned columns.
        """
        case .Mast_Jwst_Filtered_Nircam: return """
        Get JWST Science Instrument Keyword entries for NIRCAM by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_Niriss: return """
        Get JWST Science Instrument Keyword entries for NIRISS by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_Nirspec: return """
        Get JWST Science Instrument Keyword entries for NIRSPEC by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_Miri: return """
        Get JWST Science Instrument Keyword entries for MIRI by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_Fgs: return """
        Get JWST Science Instrument Keyword entries for FGS by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_GuideStar: return """
        Get JWST Science Instrument Keyword entries for GuideStar by filtering based on column (as in Advanced Search).
        """
        case .Mast_Jwst_Filtered_Wss: return """
        Get JWST Science Instrument Keyword entries for WSS by filtering based on column (as in Advanced Search).

        """
        }
    }
    
    public func json(parameters: [MAP: Any])->MASTJson {
        return MASTJson(service: self.id, params: MAJP(params: parameters))
    }
}

