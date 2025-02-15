//
//  MASTTAPResponse.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//

import SwiftQValue

public struct MASTTAPResponse: Codable {
    public var info:[[String: QValue]]
    public var data: QObject
}

