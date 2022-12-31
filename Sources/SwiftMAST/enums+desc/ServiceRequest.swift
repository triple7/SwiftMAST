//
//  File.swift
//  
//
//  Created by Yuma decaux on 31/12/2022.
//

import Foundation


public typealias ServiceRequest = MASTServiceRequest

public enum MASTServiceRequest:String, CaseIterable, Identifiable {
    /** MAST service request formatter
     for the main available requests taken from [MAST python examples](https://mast.stsci.edu/api/v0/pyex.html#MastCatalogsFilteredTicPy)
     */
    case lookup
    case missionList
    case coneSearch
    case advancedSearch
    case hscSpectra
    case hscMatches
    case getVoData
    case crossMatch

    public var id:String{
        return self.rawValue
    }
    
    public func parameters()->MAJP {
        /* Returns the default json parameter structure for the given search request
         with "placeholder" values
         */
        switch self {
        case .lookup:
            return MAJP(params: [MAP.input: "target"])
        case .missionList:
                        return MAJP(params: [MAP: String]())
        case .coneSearch:
                                    return MAJP(params: [MAP.ra: 0.0, MAP.dec: 0.0, MAP.radius: 0.0])
        case .advancedSearch:
return MAJP(params: [MAP.columns: "COUNT_BIG(*)"])
        case .hscSpectra:
return MAJP(params: [MAP: String]())
        case .hscMatches:
return MAJP(params: [MAP.input: "target"])
        case .getVoData:
return MAJP(params: [MAP.url: "URL"])
        case .crossMatch:
return MAJP(params: [MAP.raColumn: 0, MAP.decColumn: 0, MAP.radius: 0.0])
        }
    }
    
    public func returnType()->String? {
        switch self {
            /* Only lookup (comes from other services)
             and hscSpectra have their enforced return type
             The rest is best consumed as json
             */
        case .lookup: return nil
        case .hscSpectra: return APIReturnType.votable.id
        default: return APIReturnType.json.id
        }
    }

}
