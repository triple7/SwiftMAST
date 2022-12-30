//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias MAP = MASTApiParameter

public enum MASTApiParameter:String, CaseIterable, Identifiable {
    /** MAST API general parameters
     reference [general parameters](https://mast.stsci.edu/api/v0/_services.html)
     */
    case columns //String
    case filters //String
    case paramName //String
    case values //String
    case separator //String
    case freeText //String
    case ra //Float
    case dec //Float
    case radius //Float
    case raColumn //String
    case decColumn //String
    case exclude_hla //Bool
    case position //String
    case obsid //Int
    case nr //Int
    case ni //Int
    case magtype //Int
    case input //String
    case format //String
    case url //String
    case maxrecords //Int

    public var id:String {
        return self.rawValue
    }
}

