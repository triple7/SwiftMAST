//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation
public typealias APIReturnType = MASTAPIReturnType

public enum MASTAPIReturnType:String, CaseIterable, Identifiable {
    case json
    case extjs
    case csv
    case votable
    case xml
    
    public var id:String {
        return self.rawValue
    }
}

