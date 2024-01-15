////  JwstInstrument.swift
//
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public typealias JWSTInstruments = MASTJwstInstrumentField

public enum MASTJwstInstrumentField:String, CaseIterable, Identifiable {
    // TODO: populate with all instruments
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

