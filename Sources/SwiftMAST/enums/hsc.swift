//
//  Hsc.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTHsc:String, CaseIterable, Identifiable {
 case A_F435W
case A_F435W_MAD
case A_F435W_N
case A_F435W_Sigma
case A_F475W
case A_F475W_MAD
case A_F475W_N
case A_F475W_Sigma
case A_F502N
case A_F502N_MAD
case A_F502N_N
case A_F502N_Sigma
case A_F550M
case A_F550M_MAD
case A_F550M_N
case A_F550M_Sigma
case A_F555W
case A_F555W_MAD
case A_F555W_N
case A_F555W_Sigma
case A_F606W
case A_F606W_MAD
case A_F606W_N
case A_F606W_Sigma
case A_F625W
case A_F625W_MAD
case A_F625W_N
case A_F625W_Sigma
case A_F658N
case A_F658N_MAD
case A_F658N_N
case A_F658N_Sigma
case A_F660N
case A_F660N_MAD
case A_F660N_N
case A_F660N_Sigma
case A_F775W
case A_F775W_MAD
case A_F775W_N
case A_F775W_Sigma
case A_F814W
case A_F814W_MAD
case A_F814W_N
case A_F814W_Sigma
case A_F850LP
case A_F850LP_MAD
case A_F850LP_N
case A_F850LP_Sigma
case AbsCorr
case CI
case CI_Sigma
case DSigma
case Distance
case Extinction
case KronRadius
case KronRadius_Sigma
case MatchDec
case MatchID
case MatchRA
case NumFilters
case NumImages
case NumVisits
case StartMJD
case StartTime
case StopMJD
case StopTime
case TargetName
case W2_F1042M
case W2_F1042M_MAD
case W2_F1042M_N
case W2_F1042M_Sigma
case W2_F122M
case W2_F122M_MAD
case W2_F122M_N
case W2_F122M_Sigma
case W2_F160BN15
case W2_F160BN15_MAD
case W2_F160BN15_N
case W2_F160BN15_Sigma
case W2_F160BW
case W2_F160BW_MAD
case W2_F160BW_N
case W2_F160BW_Sigma
case W2_F170W
case W2_F170W_MAD
case W2_F170W_N
case W2_F170W_Sigma
case W2_F185W
case W2_F185W_MAD
case W2_F185W_N
case W2_F185W_Sigma
case W2_F218W
case W2_F218W_MAD
case W2_F218W_N
case W2_F218W_Sigma
case W2_F255W
case W2_F255W_MAD
case W2_F255W_N
case W2_F255W_Sigma
case W2_F300W
case W2_F300W_MAD
case W2_F300W_N
case W2_F300W_Sigma
case W2_F336W
case W2_F336W_MAD
case W2_F336W_N
case W2_F336W_Sigma
case W2_F343N
case W2_F343N_MAD
case W2_F343N_N
case W2_F343N_Sigma
case W2_F375N
case W2_F375N_MAD
case W2_F375N_N
case W2_F375N_Sigma
case W2_F380W
case W2_F380W_MAD
case W2_F380W_N
case W2_F380W_Sigma
case W2_F390N
case W2_F390N_MAD
case W2_F390N_N
case W2_F390N_Sigma
case W2_F410M
case W2_F410M_MAD
case W2_F410M_N
case W2_F410M_Sigma
case W2_F437N
case W2_F437N_MAD
case W2_F437N_N
case W2_F437N_Sigma
case W2_F439W
case W2_F439W_MAD
case W2_F439W_N
case W2_F439W_Sigma
case W2_F450W
case W2_F450W_MAD
case W2_F450W_N
case W2_F450W_Sigma
case W2_F467M
case W2_F467M_MAD
case W2_F467M_N
case W2_F467M_Sigma
case W2_F469N
case W2_F469N_MAD
case W2_F469N_N
case W2_F469N_Sigma
case W2_F487N
case W2_F487N_MAD
case W2_F487N_N
case W2_F487N_Sigma
case W2_F502N
case W2_F502N_MAD
case W2_F502N_N
case W2_F502N_Sigma
case W2_F547M
case W2_F547M_MAD
case W2_F547M_N
case W2_F547M_Sigma
case W2_F555W
case W2_F555W_MAD
case W2_F555W_N
case W2_F555W_Sigma
case W2_F569W
case W2_F569W_MAD
case W2_F569W_N
case W2_F569W_Sigma
case W2_F588N
case W2_F588N_MAD
case W2_F588N_N
case W2_F588N_Sigma
case W2_F606W
case W2_F606W_MAD
case W2_F606W_N
case W2_F606W_Sigma
case W2_F622W
case W2_F622W_MAD
case W2_F622W_N
case W2_F622W_Sigma
case W2_F631N
case W2_F631N_MAD
case W2_F631N_N
case W2_F631N_Sigma
case W2_F656N
case W2_F656N_MAD
case W2_F656N_N
case W2_F656N_N_MAD
case W2_F656N_Sigma
case W2_F656N_Sigma_MAD
case W2_F658N
case W2_F658N_MAD
case W2_F658N_N
case W2_F658N_Sigma
case W2_F673N
case W2_F673N_MAD
case W2_F673N_N
case W2_F673N_Sigma
case W2_F675W
case W2_F675W_MAD
case W2_F675W_N
case W2_F675W_Sigma
case W2_F702W
case W2_F702W_MAD
case W2_F702W_N
case W2_F702W_Sigma
case W2_F785LP
case W2_F785LP_MAD
case W2_F785LP_N
case W2_F785LP_Sigma
case W2_F791W
case W2_F791W_MAD
case W2_F791W_N
case W2_F791W_Sigma
case W2_F814W
case W2_F814W_MAD
case W2_F814W_N
case W2_F814W_Sigma
case W2_F850LP
case W2_F850LP_MAD
case W2_F850LP_N
case W2_F850LP_Sigma
case W2_F953N
case W2_F953N_MAD
case W2_F953N_N
case W2_F953N_Sigma
case W3_BLANK
case W3_BLANK_MAD
case W3_BLANK_N
case W3_BLANK_Sigma
case W3_F098M
case W3_F098M_MAD
case W3_F098M_N
case W3_F098M_Sigma
case W3_F105W
case W3_F105W_MAD
case W3_F105W_N
case W3_F105W_Sigma
case W3_F110W
case W3_F110W_MAD
case W3_F110W_N
case W3_F110W_Sigma
case W3_F125W
case W3_F125W_MAD
case W3_F125W_N
case W3_F125W_Sigma
case W3_F126N
case W3_F126N_MAD
case W3_F126N_N
case W3_F126N_Sigma
case W3_F127M
case W3_F127M_MAD
case W3_F127M_N
case W3_F127M_Sigma
case W3_F128N
case W3_F128N_MAD
case W3_F128N_N
case W3_F128N_Sigma
case W3_F130N
case W3_F130N_MAD
case W3_F130N_N
case W3_F130N_Sigma
case W3_F132N
case W3_F132N_MAD
case W3_F132N_N
case W3_F132N_Sigma
case W3_F139M
case W3_F139M_MAD
case W3_F139M_N
case W3_F139M_Sigma
case W3_F140W
case W3_F140W_MAD
case W3_F140W_N
case W3_F140W_Sigma
case W3_F153M
case W3_F153M_MAD
case W3_F153M_N
case W3_F153M_Sigma
case W3_F160W
case W3_F160W_MAD
case W3_F160W_N
case W3_F160W_Sigma
case W3_F164N
case W3_F164N_MAD
case W3_F164N_N
case W3_F164N_Sigma
case W3_F167N
case W3_F167N_MAD
case W3_F167N_N
case W3_F167N_Sigma
case W3_F200LP
case W3_F200LP_MAD
case W3_F200LP_N
case W3_F200LP_Sigma
case W3_F218W
case W3_F218W_MAD
case W3_F218W_N
case W3_F218W_Sigma
case W3_F225W
case W3_F225W_MAD
case W3_F225W_N
case W3_F225W_Sigma
case W3_F275W
case W3_F275W_MAD
case W3_F275W_N
case W3_F275W_Sigma
case W3_F280N
case W3_F280N_MAD
case W3_F280N_N
case W3_F280N_Sigma
case W3_F300X
case W3_F300X_MAD
case W3_F300X_N
case W3_F300X_Sigma
case W3_F336W
case W3_F336W_MAD
case W3_F336W_N
case W3_F336W_Sigma
case W3_F343N
case W3_F343N_MAD
case W3_F343N_N
case W3_F343N_Sigma
case W3_F350LP
case W3_F350LP_MAD
case W3_F350LP_N
case W3_F350LP_Sigma
case W3_F373N
case W3_F373N_MAD
case W3_F373N_N
case W3_F373N_Sigma
case W3_F390M
case W3_F390M_MAD
case W3_F390M_N
case W3_F390M_Sigma
case W3_F390W
case W3_F390W_MAD
case W3_F390W_N
case W3_F390W_Sigma
case W3_F395N
case W3_F395N_MAD
case W3_F395N_N
case W3_F395N_Sigma
case W3_F410M
case W3_F410M_MAD
case W3_F410M_N
case W3_F410M_Sigma
case W3_F438W
case W3_F438W_MAD
case W3_F438W_N
case W3_F438W_Sigma
case W3_F467M
case W3_F467M_MAD
case W3_F467M_N
case W3_F467M_Sigma
case W3_F469N
case W3_F469N_MAD
case W3_F469N_N
case W3_F469N_Sigma
case W3_F475W
case W3_F475W_MAD
case W3_F475W_N
case W3_F475W_Sigma
case W3_F475X
case W3_F475X_MAD
case W3_F475X_N
case W3_F475X_Sigma
case W3_F487N
case W3_F487N_MAD
case W3_F487N_N
case W3_F487N_Sigma
case W3_F502N
case W3_F502N_MAD
case W3_F502N_N
case W3_F502N_Sigma
case W3_F547M
case W3_F547M_MAD
case W3_F547M_N
case W3_F547M_Sigma
case W3_F555W
case W3_F555W_MAD
case W3_F555W_N
case W3_F555W_Sigma
case W3_F600LP
case W3_F600LP_MAD
case W3_F600LP_N
case W3_F600LP_Sigma
case W3_F606W
case W3_F606W_MAD
case W3_F606W_N
case W3_F606W_Sigma
case W3_F621M
case W3_F621M_MAD
case W3_F621M_N
case W3_F621M_Sigma
case W3_F625W
case W3_F625W_MAD
case W3_F625W_N
case W3_F625W_Sigma
case W3_F631N
case W3_F631N_MAD
case W3_F631N_N
case W3_F631N_Sigma
case W3_F645N
case W3_F645N_MAD
case W3_F645N_N
case W3_F645N_Sigma
case W3_F656N
case W3_F656N_MAD
case W3_F656N_N
case W3_F656N_Sigma
case W3_F657N
case W3_F657N_MAD
case W3_F657N_N
case W3_F657N_Sigma
case W3_F658N
case W3_F658N_MAD
case W3_F658N_N
case W3_F658N_Sigma
case W3_F665N
case W3_F665N_F6
case W3_F665N_F6_MAD
case W3_F665N_F6_N
case W3_F665N_F6_Sigma
case W3_F665N_MAD
case W3_F665N_N
case W3_F665N_Sigma
case W3_F673N
case W3_F673N_MAD
case W3_F673N_N
case W3_F673N_Sigma
case W3_F680N
case W3_F680N_MAD
case W3_F680N_N
case W3_F680N_Sigma
case W3_F689M
case W3_F689M_MAD
case W3_F689M_N
case W3_F689M_Sigma
case W3_F763M
case W3_F763M_MAD
case W3_F763M_N
case W3_F763M_Sigma
case W3_F775W
case W3_F775W_MAD
case W3_F775W_N
case W3_F775W_Sigma
case W3_F814W
case W3_F814W_MAD
case W3_F814W_N
case W3_F814W_Sigma
case W3_F845M
case W3_F845M_MAD
case W3_F845M_N
case W3_F845M_Sigma
case W3_F850LP
case W3_F850LP_MAD
case W3_F850LP_N
case W3_F850LP_Sigma
case W3_F953N
case W3_F953N_MAD
case W3_F953N_N
case W3_F953N_Sigma
case W3_FQ232N
case W3_FQ232N_MAD
case W3_FQ232N_N
case W3_FQ232N_Sigma
case W3_FQ243N
case W3_FQ243N_MAD
case W3_FQ243N_N
case W3_FQ243N_Sigma
case W3_FQ378N
case W3_FQ378N_MAD
case W3_FQ378N_N
case W3_FQ378N_Sigma
case W3_FQ387N
case W3_FQ387N_MAD
case W3_FQ387N_N
case W3_FQ387N_Sigma
case W3_FQ422M
case W3_FQ422M_MAD
case W3_FQ422M_N
case W3_FQ422M_Sigma
case W3_FQ436N
case W3_FQ436N_MAD
case W3_FQ436N_N
case W3_FQ436N_Sigma
case W3_FQ437N
case W3_FQ437N_MAD
case W3_FQ437N_N
case W3_FQ437N_Sigma
case W3_FQ492N
case W3_FQ492N_MAD
case W3_FQ492N_N
case W3_FQ492N_Sigma
case W3_FQ508N
case W3_FQ508N_MAD
case W3_FQ508N_N
case W3_FQ508N_Sigma
case W3_FQ575N
case W3_FQ575N_MAD
case W3_FQ575N_N
case W3_FQ575N_Sigma
case W3_FQ619N
case W3_FQ619N_MAD
case W3_FQ619N_N
case W3_FQ619N_Sigma
case W3_FQ634N
case W3_FQ634N_MAD
case W3_FQ634N_N
case W3_FQ634N_Sigma
case W3_FQ672N
case W3_FQ672N_MAD
case W3_FQ672N_N
case W3_FQ672N_Sigma
case W3_FQ674N
case W3_FQ674N_MAD
case W3_FQ674N_N
case W3_FQ674N_Sigma
case W3_FQ727N
case W3_FQ727N_MAD
case W3_FQ727N_N
case W3_FQ727N_Sigma
case W3_FQ750N
case W3_FQ750N_MAD
case W3_FQ750N_N
case W3_FQ750N_Sigma
case W3_FQ889N
case W3_FQ889N_MAD
case W3_FQ889N_N
case W3_FQ889N_Sigma
case W3_FQ906N
case W3_FQ906N_MAD
case W3_FQ906N_N
case W3_FQ906N_Sigma
case W3_FQ924N
case W3_FQ924N_MAD
case W3_FQ924N_N
case W3_FQ924N_Sigma
case W3_FQ937N
case W3_FQ937N_MAD
case W3_FQ937N_N
case W3_FQ937N_Sigma
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .A_F435W: return "A_F435W"
case .A_F435W_MAD: return "A_F435W_MAD"
case .A_F435W_N: return "A_F435W_N"
case .A_F435W_Sigma: return "A_F435W_Sigma"
case .A_F475W: return "A_F475W"
case .A_F475W_MAD: return "A_F475W_MAD"
case .A_F475W_N: return "A_F475W_N"
case .A_F475W_Sigma: return "A_F475W_Sigma"
case .A_F502N: return "A_F502N"
case .A_F502N_MAD: return "A_F502N_MAD"
case .A_F502N_N: return "A_F502N_N"
case .A_F502N_Sigma: return "A_F502N_Sigma"
case .A_F550M: return "A_F550M"
case .A_F550M_MAD: return "A_F550M_MAD"
case .A_F550M_N: return "A_F550M_N"
case .A_F550M_Sigma: return "A_F550M_Sigma"
case .A_F555W: return "A_F555W"
case .A_F555W_MAD: return "A_F555W_MAD"
case .A_F555W_N: return "A_F555W_N"
case .A_F555W_Sigma: return "A_F555W_Sigma"
case .A_F606W: return "A_F606W"
case .A_F606W_MAD: return "A_F606W_MAD"
case .A_F606W_N: return "A_F606W_N"
case .A_F606W_Sigma: return "A_F606W_Sigma"
case .A_F625W: return "A_F625W"
case .A_F625W_MAD: return "A_F625W_MAD"
case .A_F625W_N: return "A_F625W_N"
case .A_F625W_Sigma: return "A_F625W_Sigma"
case .A_F658N: return "A_F658N"
case .A_F658N_MAD: return "A_F658N_MAD"
case .A_F658N_N: return "A_F658N_N"
case .A_F658N_Sigma: return "A_F658N_Sigma"
case .A_F660N: return "A_F660N"
case .A_F660N_MAD: return "A_F660N_MAD"
case .A_F660N_N: return "A_F660N_N"
case .A_F660N_Sigma: return "A_F660N_Sigma"
case .A_F775W: return "A_F775W"
case .A_F775W_MAD: return "A_F775W_MAD"
case .A_F775W_N: return "A_F775W_N"
case .A_F775W_Sigma: return "A_F775W_Sigma"
case .A_F814W: return "A_F814W"
case .A_F814W_MAD: return "A_F814W_MAD"
case .A_F814W_N: return "A_F814W_N"
case .A_F814W_Sigma: return "A_F814W_Sigma"
case .A_F850LP: return "A_F850LP"
case .A_F850LP_MAD: return "A_F850LP"
case .A_F850LP_N: return "A_F850LP_N"
case .A_F850LP_Sigma: return "A_F850LP_Sigma"
case .AbsCorr: return "AbsCorr"
case .CI: return "CI"
case .CI_Sigma: return "CI_Sigma"
case .DSigma: return "DSigma"
case .Distance: return "Distance"
case .Extinction: return "Extinction"
case .KronRadius: return "KronRadius"
case .KronRadius_Sigma: return "KronRadius_Sigma"
case .MatchDec: return "MatchDec"
case .MatchID: return "MatchID"
case .MatchRA: return "MatchRA"
case .NumFilters: return "NumFilters"
case .NumImages: return "NumImages"
case .NumVisits: return "NumVisits"
case .StartMJD: return "Start MJD"
case .StartTime: return "StartTime"
case .StopMJD: return "Stop MJD"
case .StopTime: return "StopTime"
case .TargetName: return "TargetName"
case .W2_F1042M: return "W2_F1042M"
case .W2_F1042M_MAD: return "W2_F1042M_MAD"
case .W2_F1042M_N: return "W2_F1042M_N"
case .W2_F1042M_Sigma: return "W2_F1042M_Sigma"
case .W2_F122M: return "W2_F122M"
case .W2_F122M_MAD: return "W2_F122M_MAD"
case .W2_F122M_N: return "W2_F122M_N"
case .W2_F122M_Sigma: return "W2_F122M_Sigma"
case .W2_F160BN15: return "W2_F160BN15"
case .W2_F160BN15_MAD: return "W2_F160BN15"
case .W2_F160BN15_N: return "W2_F160BN15_N"
case .W2_F160BN15_Sigma: return "W2_F160BN15_Sigma"
case .W2_F160BW: return "W2_F160BW"
case .W2_F160BW_MAD: return "W2_F160BW_MAD"
case .W2_F160BW_N: return "W2_F160BW_N"
case .W2_F160BW_Sigma: return "W2_F160BW_Sigma"
case .W2_F170W: return "W2_F170W"
case .W2_F170W_MAD: return "W2_F170W_MAD"
case .W2_F170W_N: return "W2_F170W_N"
case .W2_F170W_Sigma: return "W2_F170W_Sigma"
case .W2_F185W: return "W2_F185W"
case .W2_F185W_MAD: return "W2_F185W_MAD"
case .W2_F185W_N: return "W2_F185W_N"
case .W2_F185W_Sigma: return "W2_F185W_Sigma"
case .W2_F218W: return "W2_F218W"
case .W2_F218W_MAD: return "W2_F218W_MAD"
case .W2_F218W_N: return "W2_F218W_N"
case .W2_F218W_Sigma: return "W2_F218W_Sigma"
case .W2_F255W: return "W2_F255W"
case .W2_F255W_MAD: return "W2_F255W_MAD"
case .W2_F255W_N: return "W2_F255W_N"
case .W2_F255W_Sigma: return "W2_F255W_Sigma"
case .W2_F300W: return "W2_F300W"
case .W2_F300W_MAD: return "W2_F300W_MAD"
case .W2_F300W_N: return "W2_F300W_N"
case .W2_F300W_Sigma: return "W2_F300W_Sigma"
case .W2_F336W: return "W2_F336W"
case .W2_F336W_MAD: return "W2_F336W_MAD"
case .W2_F336W_N: return "W2_F336W_N"
case .W2_F336W_Sigma: return "W2_F336W_Sigma"
case .W2_F343N: return "W2_F343N"
case .W2_F343N_MAD: return "W2_F343N_MAD"
case .W2_F343N_N: return "W2_F343N_N"
case .W2_F343N_Sigma: return "W2_F343N_Sigma"
case .W2_F375N: return "W2_F375N"
case .W2_F375N_MAD: return "W2_F375N_MAD"
case .W2_F375N_N: return "W2_F375N_N"
case .W2_F375N_Sigma: return "W2_F375N_Sigma"
case .W2_F380W: return "W2_F380W"
case .W2_F380W_MAD: return "W2_F380W_MAD"
case .W2_F380W_N: return "W2_F380W_N"
case .W2_F380W_Sigma: return "W2_F380W_Sigma"
case .W2_F390N: return "W2_F390N"
case .W2_F390N_MAD: return "W2_F390N_MAD"
case .W2_F390N_N: return "W2_F390N_N"
case .W2_F390N_Sigma: return "W2_F390N_Sigma"
case .W2_F410M: return "W2_F410M"
case .W2_F410M_MAD: return "W2_F410M_MAD"
case .W2_F410M_N: return "W2_F410M_N"
case .W2_F410M_Sigma: return "W2_F410M_Sigma"
case .W2_F437N: return "W2_F437N"
case .W2_F437N_MAD: return "W2_F437N_MAD"
case .W2_F437N_N: return "W2_F437N_N"
case .W2_F437N_Sigma: return "W2_F437N_Sigma"
case .W2_F439W: return "W2_F439W"
case .W2_F439W_MAD: return "W2_F439W_MAD"
case .W2_F439W_N: return "W2_F439W_N"
case .W2_F439W_Sigma: return "W2_F439W_Sigma"
case .W2_F450W: return "W2_F450W"
case .W2_F450W_MAD: return "W2_F450W_MAD"
case .W2_F450W_N: return "W2_F450W_N"
case .W2_F450W_Sigma: return "W2_F450W_Sigma"
case .W2_F467M: return "W2_F467M"
case .W2_F467M_MAD: return "W2_F467M_MAD"
case .W2_F467M_N: return "W2_F467M_N"
case .W2_F467M_Sigma: return "W2_F467M_Sigma"
case .W2_F469N: return "W2_F469N"
case .W2_F469N_MAD: return "W2_F469N_MAD"
case .W2_F469N_N: return "W2_F469N_N"
case .W2_F469N_Sigma: return "W2_F469N_Sigma"
case .W2_F487N: return "W2_F487N"
case .W2_F487N_MAD: return "W2_F487N_MAD"
case .W2_F487N_N: return "W2_F487N_N"
case .W2_F487N_Sigma: return "W2_F487N_Sigma"
case .W2_F502N: return "W2_F502N"
case .W2_F502N_MAD: return "W2_F502N_MAD"
case .W2_F502N_N: return "W2_F502N_N"
case .W2_F502N_Sigma: return "W2_F502N_Sigma"
case .W2_F547M: return "W2_F547M"
case .W2_F547M_MAD: return "W2_F547M_MAD"
case .W2_F547M_N: return "W2_F547M_N"
case .W2_F547M_Sigma: return "W2_F547M_Sigma"
case .W2_F555W: return "W2_F555W"
case .W2_F555W_MAD: return "W2_F555W_MAD"
case .W2_F555W_N: return "W2_F555W_N"
case .W2_F555W_Sigma: return "W2_F555W_Sigma"
case .W2_F569W: return "W2_F569W"
case .W2_F569W_MAD: return "W2_F569W_MAD"
case .W2_F569W_N: return "W2_F569W_N"
case .W2_F569W_Sigma: return "W2_F569W_Sigma"
case .W2_F588N: return "W2_F588N"
case .W2_F588N_MAD: return "W2_F588N_MAD"
case .W2_F588N_N: return "W2_F588N_N"
case .W2_F588N_Sigma: return "W2_F588N_Sigma"
case .W2_F606W: return "W2_F606W"
case .W2_F606W_MAD: return "W2_F606W_MAD"
case .W2_F606W_N: return "W2_F606W_N"
case .W2_F606W_Sigma: return "W2_F606W_Sigma"
case .W2_F622W: return "W2_F622W"
case .W2_F622W_MAD: return "W2_F622W_MAD"
case .W2_F622W_N: return "W2_F622W_N"
case .W2_F622W_Sigma: return "W2_F622W_Sigma"
case .W2_F631N: return "W2_F631N"
case .W2_F631N_MAD: return "W2_F631N_MAD"
case .W2_F631N_N: return "W2_F631N_N"
case .W2_F631N_Sigma: return "W2_F631N_Sigma"
case .W2_F656N: return "W2_F656N"
case .W2_F656N_MAD: return "W2_F656N_MAD"
case .W2_F656N_N: return "W2_F656N_N"
case .W2_F656N_N_MAD: return "W2_F656N_N_MAD"
case .W2_F656N_Sigma: return "W2_F656N_Sigma"
case .W2_F656N_Sigma_MAD: return "W2_F656N_Sigma"
case .W2_F658N: return "W2_F658N"
case .W2_F658N_MAD: return "W2_F658N_MAD"
case .W2_F658N_N: return "W2_F658N_N"
case .W2_F658N_Sigma: return "W2_F658N_Sigma"
case .W2_F673N: return "W2_F673N"
case .W2_F673N_MAD: return "W2_F673N_MAD"
case .W2_F673N_N: return "W2_F673N_N"
case .W2_F673N_Sigma: return "W2_F673N_Sigma"
case .W2_F675W: return "W2_F675W"
case .W2_F675W_MAD: return "W2_F675W_MAD"
case .W2_F675W_N: return "W2_F675W_N"
case .W2_F675W_Sigma: return "W2_F675W_Sigma"
case .W2_F702W: return "W2_F702W"
case .W2_F702W_MAD: return "W2_F702W_MAD"
case .W2_F702W_N: return "W2_F702W_N"
case .W2_F702W_Sigma: return "W2_F702W_Sigma"
case .W2_F785LP: return "W2_F785LP"
case .W2_F785LP_MAD: return "W2_F785LP"
case .W2_F785LP_N: return "W2_F785LP_N"
case .W2_F785LP_Sigma: return "W2_F785LP_Sigma"
case .W2_F791W: return "W2_F791W"
case .W2_F791W_MAD: return "W2_F791W_MAD"
case .W2_F791W_N: return "W2_F791W_N"
case .W2_F791W_Sigma: return "W2_F791W_Sigma"
case .W2_F814W: return "W2_F814W"
case .W2_F814W_MAD: return "W2_F814W_MAD"
case .W2_F814W_N: return "W2_F814W_N"
case .W2_F814W_Sigma: return "W2_F814W_Sigma"
case .W2_F850LP: return "W2_F850LP"
case .W2_F850LP_MAD: return "W2_F850LP"
case .W2_F850LP_N: return "W2_F850LP_N"
case .W2_F850LP_Sigma: return "W2_F850LP_Sigma"
case .W2_F953N: return "W2_F953N"
case .W2_F953N_MAD: return "W2_F953N_MAD"
case .W2_F953N_N: return "W2_F953N_N"
case .W2_F953N_Sigma: return "W2_F953N_Sigma"
case .W3_BLANK: return "W3_BLANK"
case .W3_BLANK_MAD: return "W3_BLANK"
case .W3_BLANK_N: return "W3_BLANK_N"
case .W3_BLANK_Sigma: return "W3_BLANK_Sigma"
case .W3_F098M: return "W3_F098M"
case .W3_F098M_MAD: return "W3_F098M_MAD"
case .W3_F098M_N: return "W3_F098M_N"
case .W3_F098M_Sigma: return "W3_F098M_Sigma"
case .W3_F105W: return "W3_F105W"
case .W3_F105W_MAD: return "W3_F105W_MAD"
case .W3_F105W_N: return "W3_F105W_N"
case .W3_F105W_Sigma: return "W3_F105W_Sigma"
case .W3_F110W: return "W3_F110W"
case .W3_F110W_MAD: return "W3_F110W_MAD"
case .W3_F110W_N: return "W3_F110W_N"
case .W3_F110W_Sigma: return "W3_F110W_Sigma"
case .W3_F125W: return "W3_F125W"
case .W3_F125W_MAD: return "W3_F125W_MAD"
case .W3_F125W_N: return "W3_F125W_N"
case .W3_F125W_Sigma: return "W3_F125W_Sigma"
case .W3_F126N: return "W3_F126N"
case .W3_F126N_MAD: return "W3_F126N_MAD"
case .W3_F126N_N: return "W3_F126N_N"
case .W3_F126N_Sigma: return "W3_F126N_Sigma"
case .W3_F127M: return "W3_F127M"
case .W3_F127M_MAD: return "W3_F127M_MAD"
case .W3_F127M_N: return "W3_F127M_N"
case .W3_F127M_Sigma: return "W3_F127M_Sigma"
case .W3_F128N: return "W3_F128N"
case .W3_F128N_MAD: return "W3_F128N_MAD"
case .W3_F128N_N: return "W3_F128N_N"
case .W3_F128N_Sigma: return "W3_F128N_Sigma"
case .W3_F130N: return "W3_F130N"
case .W3_F130N_MAD: return "W3_F130N_MAD"
case .W3_F130N_N: return "W3_F130N_N"
case .W3_F130N_Sigma: return "W3_F130N_Sigma"
case .W3_F132N: return "W3_F132N"
case .W3_F132N_MAD: return "W3_F132N_MAD"
case .W3_F132N_N: return "W3_F132N_N"
case .W3_F132N_Sigma: return "W3_F132N_Sigma"
case .W3_F139M: return "W3_F139M"
case .W3_F139M_MAD: return "W3_F139M_MAD"
case .W3_F139M_N: return "W3_F139M_N"
case .W3_F139M_Sigma: return "W3_F139M_Sigma"
case .W3_F140W: return "W3_F140W"
case .W3_F140W_MAD: return "W3_F140W_MAD"
case .W3_F140W_N: return "W3_F140W_N"
case .W3_F140W_Sigma: return "W3_F140W_Sigma"
case .W3_F153M: return "W3_F153M"
case .W3_F153M_MAD: return "W3_F153M_MAD"
case .W3_F153M_N: return "W3_F153M_N"
case .W3_F153M_Sigma: return "W3_F153M_Sigma"
case .W3_F160W: return "W3_F160W"
case .W3_F160W_MAD: return "W3_F160W_MAD"
case .W3_F160W_N: return "W3_F160W_N"
case .W3_F160W_Sigma: return "W3_F160W_Sigma"
case .W3_F164N: return "W3_F164N"
case .W3_F164N_MAD: return "W3_F164N_MAD"
case .W3_F164N_N: return "W3_F164N_N"
case .W3_F164N_Sigma: return "W3_F164N_Sigma"
case .W3_F167N: return "W3_F167N"
case .W3_F167N_MAD: return "W3_F167N_MAD"
case .W3_F167N_N: return "W3_F167N_N"
case .W3_F167N_Sigma: return "W3_F167N_Sigma"
case .W3_F200LP: return "W3_F200LP"
case .W3_F200LP_MAD: return "W3_F200LP"
case .W3_F200LP_N: return "W3_F200LP_N"
case .W3_F200LP_Sigma: return "W3_F200LP_Sigma"
case .W3_F218W: return "W3_F218W"
case .W3_F218W_MAD: return "W3_F218W_MAD"
case .W3_F218W_N: return "W3_F218W_N"
case .W3_F218W_Sigma: return "W3_F218W_Sigma"
case .W3_F225W: return "W3_F225W"
case .W3_F225W_MAD: return "W3_F225W_MAD"
case .W3_F225W_N: return "W3_F225W_N"
case .W3_F225W_Sigma: return "W3_F225W_Sigma"
case .W3_F275W: return "W3_F275W"
case .W3_F275W_MAD: return "W3_F275W_MAD"
case .W3_F275W_N: return "W3_F275W_N"
case .W3_F275W_Sigma: return "W3_F275W_Sigma"
case .W3_F280N: return "W3_F280N"
case .W3_F280N_MAD: return "W3_F280N_MAD"
case .W3_F280N_N: return "W3_F280N_N"
case .W3_F280N_Sigma: return "W3_F280N_Sigma"
case .W3_F300X: return "W3_F300X"
case .W3_F300X_MAD: return "W3_F300X"
case .W3_F300X_N: return "W3_F300X_N"
case .W3_F300X_Sigma: return "W3_F300X_Sigma"
case .W3_F336W: return "W3_F336W"
case .W3_F336W_MAD: return "W3_F336W_MAD"
case .W3_F336W_N: return "W3_F336W_N"
case .W3_F336W_Sigma: return "W3_F336W_Sigma"
case .W3_F343N: return "W3_F343N"
case .W3_F343N_MAD: return "W3_F343N_MAD"
case .W3_F343N_N: return "W3_F343N_N"
case .W3_F343N_Sigma: return "W3_F343N_Sigma"
case .W3_F350LP: return "W3_F350LP"
case .W3_F350LP_MAD: return "W3_F350LP"
case .W3_F350LP_N: return "W3_F350LP_N"
case .W3_F350LP_Sigma: return "W3_F350LP_Sigma"
case .W3_F373N: return "W3_F373N"
case .W3_F373N_MAD: return "W3_F373N_MAD"
case .W3_F373N_N: return "W3_F373N_N"
case .W3_F373N_Sigma: return "W3_F373N_Sigma"
case .W3_F390M: return "W3_F390M"
case .W3_F390M_MAD: return "W3_F390M_MAD"
case .W3_F390M_N: return "W3_F390M_N"
case .W3_F390M_Sigma: return "W3_F390M_Sigma"
case .W3_F390W: return "W3_F390W"
case .W3_F390W_MAD: return "W3_F390W_MAD"
case .W3_F390W_N: return "W3_F390W_N"
case .W3_F390W_Sigma: return "W3_F390W_Sigma"
case .W3_F395N: return "W3_F395N"
case .W3_F395N_MAD: return "W3_F395N_MAD"
case .W3_F395N_N: return "W3_F395N_N"
case .W3_F395N_Sigma: return "W3_F395N_Sigma"
case .W3_F410M: return "W3_F410M"
case .W3_F410M_MAD: return "W3_F410M_MAD"
case .W3_F410M_N: return "W3_F410M_N"
case .W3_F410M_Sigma: return "W3_F410M_Sigma"
case .W3_F438W: return "W3_F438W"
case .W3_F438W_MAD: return "W3_F438W_MAD"
case .W3_F438W_N: return "W3_F438W_N"
case .W3_F438W_Sigma: return "W3_F438W_Sigma"
case .W3_F467M: return "W3_F467M"
case .W3_F467M_MAD: return "W3_F467M_MAD"
case .W3_F467M_N: return "W3_F467M_N"
case .W3_F467M_Sigma: return "W3_F467M_Sigma"
case .W3_F469N: return "W3_F469N"
case .W3_F469N_MAD: return "W3_F469N_MAD"
case .W3_F469N_N: return "W3_F469N_N"
case .W3_F469N_Sigma: return "W3_F469N_Sigma"
case .W3_F475W: return "W3_F475W"
case .W3_F475W_MAD: return "W3_F475W_MAD"
case .W3_F475W_N: return "W3_F475W_N"
case .W3_F475W_Sigma: return "W3_F475W_Sigma"
case .W3_F475X: return "W3_F475X"
case .W3_F475X_MAD: return "W3_F475X"
case .W3_F475X_N: return "W3_F475X_N"
case .W3_F475X_Sigma: return "W3_F475X_Sigma"
case .W3_F487N: return "W3_F487N"
case .W3_F487N_MAD: return "W3_F487N_MAD"
case .W3_F487N_N: return "W3_F487N_N"
case .W3_F487N_Sigma: return "W3_F487N_Sigma"
case .W3_F502N: return "W3_F502N"
case .W3_F502N_MAD: return "W3_F502N_MAD"
case .W3_F502N_N: return "W3_F502N_N"
case .W3_F502N_Sigma: return "W3_F502N_Sigma"
case .W3_F547M: return "W3_F547M"
case .W3_F547M_MAD: return "W3_F547M_MAD"
case .W3_F547M_N: return "W3_F547M_N"
case .W3_F547M_Sigma: return "W3_F547M_Sigma"
case .W3_F555W: return "W3_F555W"
case .W3_F555W_MAD: return "W3_F555W_MAD"
case .W3_F555W_N: return "W3_F555W_N"
case .W3_F555W_Sigma: return "W3_F555W_Sigma"
case .W3_F600LP: return "W3_F600LP"
case .W3_F600LP_MAD: return "W3_F600LP"
case .W3_F600LP_N: return "W3_F600LP_N"
case .W3_F600LP_Sigma: return "W3_F600LP_Sigma"
case .W3_F606W: return "W3_F606W"
case .W3_F606W_MAD: return "W3_F606W_MAD"
case .W3_F606W_N: return "W3_F606W_N"
case .W3_F606W_Sigma: return "W3_F606W_Sigma"
case .W3_F621M: return "W3_F621M"
case .W3_F621M_MAD: return "W3_F621M_MAD"
case .W3_F621M_N: return "W3_F621M_N"
case .W3_F621M_Sigma: return "W3_F621M_Sigma"
case .W3_F625W: return "W3_F625W"
case .W3_F625W_MAD: return "W3_F625W_MAD"
case .W3_F625W_N: return "W3_F625W_N"
case .W3_F625W_Sigma: return "W3_F625W_Sigma"
case .W3_F631N: return "W3_F631N"
case .W3_F631N_MAD: return "W3_F631N_MAD"
case .W3_F631N_N: return "W3_F631N_N"
case .W3_F631N_Sigma: return "W3_F631N_Sigma"
case .W3_F645N: return "W3_F645N"
case .W3_F645N_MAD: return "W3_F645N_MAD"
case .W3_F645N_N: return "W3_F645N_N"
case .W3_F645N_Sigma: return "W3_F645N_Sigma"
case .W3_F656N: return "W3_F656N"
case .W3_F656N_MAD: return "W3_F656N_MAD"
case .W3_F656N_N: return "W3_F656N_N"
case .W3_F656N_Sigma: return "W3_F656N_Sigma"
case .W3_F657N: return "W3_F657N"
case .W3_F657N_MAD: return "W3_F657N_MAD"
case .W3_F657N_N: return "W3_F657N_N"
case .W3_F657N_Sigma: return "W3_F657N_Sigma"
case .W3_F658N: return "W3_F658N"
case .W3_F658N_MAD: return "W3_F658N_MAD"
case .W3_F658N_N: return "W3_F658N_N"
case .W3_F658N_Sigma: return "W3_F658N_Sigma"
case .W3_F665N: return "W3_F665N"
case .W3_F665N_F6: return "W3_F665N_F6"
case .W3_F665N_F6_MAD: return "W3_F665N_F6"
case .W3_F665N_F6_N: return "W3_F665N_F6_N"
case .W3_F665N_F6_Sigma: return "W3_F665N_F6_Sigma"
case .W3_F665N_MAD: return "W3_F665N_MAD"
case .W3_F665N_N: return "W3_F665N_N"
case .W3_F665N_Sigma: return "W3_F665N_Sigma"
case .W3_F673N: return "W3_F673N"
case .W3_F673N_MAD: return "W3_F673N_MAD"
case .W3_F673N_N: return "W3_F673N_N"
case .W3_F673N_Sigma: return "W3_F673N_Sigma"
case .W3_F680N: return "W3_F680N"
case .W3_F680N_MAD: return "W3_F680N_MAD"
case .W3_F680N_N: return "W3_F680N_N"
case .W3_F680N_Sigma: return "W3_F680N_Sigma"
case .W3_F689M: return "W3_F689M"
case .W3_F689M_MAD: return "W3_F689M_MAD"
case .W3_F689M_N: return "W3_F689M_N"
case .W3_F689M_Sigma: return "W3_F689M_Sigma"
case .W3_F763M: return "W3_F763M"
case .W3_F763M_MAD: return "W3_F763M_MAD"
case .W3_F763M_N: return "W3_F763M_N"
case .W3_F763M_Sigma: return "W3_F763M_Sigma"
case .W3_F775W: return "W3_F775W"
case .W3_F775W_MAD: return "W3_F775W_MAD"
case .W3_F775W_N: return "W3_F775W_N"
case .W3_F775W_Sigma: return "W3_F775W_Sigma"
case .W3_F814W: return "W3_F814W"
case .W3_F814W_MAD: return "W3_F814W_MAD"
case .W3_F814W_N: return "W3_F814W_N"
case .W3_F814W_Sigma: return "W3_F814W_Sigma"
case .W3_F845M: return "W3_F845M"
case .W3_F845M_MAD: return "W3_F845M_MAD"
case .W3_F845M_N: return "W3_F845M_N"
case .W3_F845M_Sigma: return "W3_F845M_Sigma"
case .W3_F850LP: return "W3_F850LP"
case .W3_F850LP_MAD: return "W3_F850LP"
case .W3_F850LP_N: return "W3_F850LP_N"
case .W3_F850LP_Sigma: return "W3_F850LP_Sigma"
case .W3_F953N: return "W3_F953N"
case .W3_F953N_MAD: return "W3_F953N_MAD"
case .W3_F953N_N: return "W3_F953N_N"
case .W3_F953N_Sigma: return "W3_F953N_Sigma"
case .W3_FQ232N: return "W3_FQ232N"
case .W3_FQ232N_MAD: return "W3_FQ232N_MAD"
case .W3_FQ232N_N: return "W3_FQ232N_N"
case .W3_FQ232N_Sigma: return "W3_FQ232N_Sigma"
case .W3_FQ243N: return "W3_FQ243N"
case .W3_FQ243N_MAD: return "W3_FQ243N_MAD"
case .W3_FQ243N_N: return "W3_FQ243N_N"
case .W3_FQ243N_Sigma: return "W3_FQ243N_Sigma"
case .W3_FQ378N: return "W3_FQ378N"
case .W3_FQ378N_MAD: return "W3_FQ378N_MAD"
case .W3_FQ378N_N: return "W3_FQ378N_N"
case .W3_FQ378N_Sigma: return "W3_FQ378N_Sigma"
case .W3_FQ387N: return "W3_FQ387N"
case .W3_FQ387N_MAD: return "W3_FQ387N_MAD"
case .W3_FQ387N_N: return "W3_FQ387N_N"
case .W3_FQ387N_Sigma: return "W3_FQ387N_Sigma"
case .W3_FQ422M: return "W3_FQ422M"
case .W3_FQ422M_MAD: return "W3_FQ422M_MAD"
case .W3_FQ422M_N: return "W3_FQ422M_N"
case .W3_FQ422M_Sigma: return "W3_FQ422M_Sigma"
case .W3_FQ436N: return "W3_FQ436N"
case .W3_FQ436N_MAD: return "W3_FQ436N_MAD"
case .W3_FQ436N_N: return "W3_FQ436N_N"
case .W3_FQ436N_Sigma: return "W3_FQ436N_Sigma"
case .W3_FQ437N: return "W3_FQ437N"
case .W3_FQ437N_MAD: return "W3_FQ437N_MAD"
case .W3_FQ437N_N: return "W3_FQ437N_N"
case .W3_FQ437N_Sigma: return "W3_FQ437N_Sigma"
case .W3_FQ492N: return "W3_FQ492N"
case .W3_FQ492N_MAD: return "W3_FQ492N_MAD"
case .W3_FQ492N_N: return "W3_FQ492N_N"
case .W3_FQ492N_Sigma: return "W3_FQ492N_Sigma"
case .W3_FQ508N: return "W3_FQ508N"
case .W3_FQ508N_MAD: return "W3_FQ508N_MAD"
case .W3_FQ508N_N: return "W3_FQ508N_N"
case .W3_FQ508N_Sigma: return "W3_FQ508N_Sigma"
case .W3_FQ575N: return "W3_FQ575N"
case .W3_FQ575N_MAD: return "W3_FQ575N_MAD"
case .W3_FQ575N_N: return "W3_FQ575N_N"
case .W3_FQ575N_Sigma: return "W3_FQ575N_Sigma"
case .W3_FQ619N: return "W3_FQ619N"
case .W3_FQ619N_MAD: return "W3_FQ619N_MAD"
case .W3_FQ619N_N: return "W3_FQ619N_N"
case .W3_FQ619N_Sigma: return "W3_FQ619N_Sigma"
case .W3_FQ634N: return "W3_FQ634N"
case .W3_FQ634N_MAD: return "W3_FQ634N_MAD"
case .W3_FQ634N_N: return "W3_FQ634N_N"
case .W3_FQ634N_Sigma: return "W3_FQ634N_Sigma"
case .W3_FQ672N: return "W3_FQ672N"
case .W3_FQ672N_MAD: return "W3_FQ672N_MAD"
case .W3_FQ672N_N: return "W3_FQ672N_N"
case .W3_FQ672N_Sigma: return "W3_FQ672N_Sigma"
case .W3_FQ674N: return "W3_FQ674N"
case .W3_FQ674N_MAD: return "W3_FQ674N_MAD"
case .W3_FQ674N_N: return "W3_FQ674N_N"
case .W3_FQ674N_Sigma: return "W3_FQ674N_Sigma"
case .W3_FQ727N: return "W3_FQ727N"
case .W3_FQ727N_MAD: return "W3_FQ727N_MAD"
case .W3_FQ727N_N: return "W3_FQ727N_N"
case .W3_FQ727N_Sigma: return "W3_FQ727N_Sigma"
case .W3_FQ750N: return "W3_FQ750N"
case .W3_FQ750N_MAD: return "W3_FQ750N_MAD"
case .W3_FQ750N_N: return "W3_FQ750N_N"
case .W3_FQ750N_Sigma: return "W3_FQ750N_Sigma"
case .W3_FQ889N: return "W3_FQ889N"
case .W3_FQ889N_MAD: return "W3_FQ889N_MAD"
case .W3_FQ889N_N: return "W3_FQ889N_N"
case .W3_FQ889N_Sigma: return "W3_FQ889N_Sigma"
case .W3_FQ906N: return "W3_FQ906N"
case .W3_FQ906N_MAD: return "W3_FQ906N_MAD"
case .W3_FQ906N_N: return "W3_FQ906N_N"
case .W3_FQ906N_Sigma: return "W3_FQ906N_Sigma"
case .W3_FQ924N: return "W3_FQ924N"
case .W3_FQ924N_MAD: return "W3_FQ924N_MAD"
case .W3_FQ924N_N: return "W3_FQ924N_N"
case .W3_FQ924N_Sigma: return "W3_FQ924N_Sigma"
case .W3_FQ937N: return "W3_FQ937N"
case .W3_FQ937N_MAD: return "W3_FQ937N_MAD"
case .W3_FQ937N_N: return "W3_FQ937N_N"
case .W3_FQ937N_Sigma: return "W3_FQ937N_Sigma"

}
}
 }

