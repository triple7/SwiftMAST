//
//  FilterBands.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 14/4/2025.
//

public let FILTER_BANDS: [String: [String]] = [
    "UV/Blue": [
        "F212N", "F336W", "F250M", "F140M", "F150W2"
    ],
    "Visible": [
        "F555W", "F502N", "F606W", "F631N", "F656N",
        "F673N", "F675W", "g", "r", "i", "z"
    ],
    "Red/Near-IR": [
        "F814W", "F850LP", "F953N", "F108N", "F110W",
        "F110M", "F113N", "F160W", "F164N", "F166N",
        "F187N", "F190N", "F215N", "F222M", "F237M", "y"
    ],
    "Mid-IR": [
        "F560W", "F770W", "F1130W", "F2100W"
    ],
    "Broad": [
        "TESS", "MIRVIS", "detection"
    ]
]
