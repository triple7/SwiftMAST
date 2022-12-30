////  JwstInstrument.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public enum MASTJwstinstrument:String, CaseIterable, Identifiable {
 case nextend
 
public var id:String {
return self.rawValue
}
 
public var description:String {
switch self {
    case .nextend: return "File Extensions"

}
}
 }

