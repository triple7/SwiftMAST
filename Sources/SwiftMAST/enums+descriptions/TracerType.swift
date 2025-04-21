//
//  TracerType.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 14/4/2025.
//


enum TracerType: String, Codable {
    case stellarContinuum
    case ionizedHydrogen
    case molecularHydrogen
    case ionizedOxygen
    case ionizedSulfur
    case ironEmission
    case dustExtinction
    case dustEmission
    case pahEmission
    case iceAbsorption
    case silicate
    case broadPhotometry
    case unknown
}

enum BandType: String, Codable {
    case broadband
    case narrowband
    case mediumband
    case wideband
    case virtual
}

struct FilterType:Codable {
    let name: String
    let centralWavelengthMicrons: Double? // in μm
    let bandType: BandType
    let tracer: TracerType
}
