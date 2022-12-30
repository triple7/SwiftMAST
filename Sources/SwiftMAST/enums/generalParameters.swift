//
//  GeneralParameters.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias MGP = MASTGeneralParameter

public enum MASTGeneralParameter:String, CaseIterable, Identifiable {
    /** MAST general parameters
     reference [general parameters](https://archive.stsci.edu/vo/help/search_help.html)
     */
    case target /* target name as identifiable string"*/
 case  resolver /* Character :
  "NED",
  "SIMBAD",
  "CFA" = SIMBAD at CFA,
  "Don't Resolve" = search on target name without resolving to coordinates*/
case  radius /* Float : Range: 0.0 - ?*/
case  ra /* Float : Range: 0.0 - 360.0*/
case  dec /* Float : Range: -90.0 - 90.0*/
    case SR /* search radius in degrees*/
case  equinox /* Character :  J2000, B1900, B1950*/
case  selectedColumnsCsv /* Character : Example: hut_target_name,hut_data_id*/
case  ordercolumn1 /* Character : Example: ang_sep*/
case  descending1 /* Character : on*/
case  ordercolumn2 /* Character : Example: ra*/
case  descending2 /* Character : on*/
case  ordercolumn3 /* Character : Example: dec*/
case  descending3 /* Character : on*/
case  outputformat /* Character :
    "HTML_Table" = Table in HTML format,
    "VOTable" = VOTable format,
    "CSV" = comma-separated values,
    "SSV" = space-separated values,
    "PSV" = pipe-separated values,
    "COSV" = semicolon-separated values,
    "JSON" = JSON format,
    "Excel_Spreadsheet" = Excel Spreadsheet format
     Other formats available.
    */
case  showquery /* Character :  on, off*/
case  makedistinct /* Character :  on, off*/
case  coordformat /* Character :
 "sex" = Sexigesimal notation,
 "dec" = decimal degrees,
 "dechr" = decimal hours for RA and decimal degrees for Dec */
case  max_records /* Integer :  1 to ?*/
case  max_rpp /* Integer :  1 to ?*/
case  verb /* Integer :  1 to 3*/
case nonull /*Character: on,off*/
case skipformat /*Character: on,off*/
    
    public var id:String {
        return self.rawValue
    }
}

