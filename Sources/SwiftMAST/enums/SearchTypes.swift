//
//  SearchTypes.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTSearchType:String, CaseIterable, Identifiable {
    case mission
    case simpleCone
    case image
    case spectra
    case apiRequest
    case apiDownload
    
    public var id:String {
        return self.rawValue
    }
    
    public var description:String {
        switch self {
        case .mission: return "Mission search"
        case .simpleCone: return "Simple cone search"
        case .image: return "Simple image access protocol"
        case .spectra: return "Simple spectra Access protocol"
        case .apiRequest: return "MAST API request"
        case .apiDownload: return "MAST API download"
        }
    }
    
    var defaultParameters:[MGP: String] {
        switch self {
        case .mission:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .simpleCone:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .image:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        case .spectra:
            return [
                MGP.outputformat: "JSON",
                MGP.makedistinct: "on",
                MGP.max_records: "20",
                MGP.verb: "3"
            ]
        default: return [MGP: String]()
        }
    }
}

