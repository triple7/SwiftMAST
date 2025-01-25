//
//  MASTTAPResponse.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//

import SwiftQValue

public struct MASTTAPResponse: Codable {
    public var metadata:[[String: String]]
    public var data: QObject
}

