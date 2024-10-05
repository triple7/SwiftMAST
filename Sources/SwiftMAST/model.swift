//
//  model.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 5/10/2024.
//


import Foundation

public struct Fits:Codable {
    let metadata:[String: QValue]
    let url:URL
}


public struct Target:Codable {
    var targetInfo:CoamResult?
    let fitsAssets:[Fits]
}

