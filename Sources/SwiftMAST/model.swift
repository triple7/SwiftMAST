//
//  model.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 5/10/2024.
//

import Foundation

public struct FitsData:Codable {
    let metadata:[String: QValue]
    let url:URL
}


public struct TargetAsset:Codable {
    let targetInfo:NameLookupJson
    var preview:URL?
    var assets:[CoamResult]?
    var fitsData:[FitsData]?
    
    
    public mutating func setPreview(url: URL) {
        if self.preview == nil {
            self.preview = url
        }
    }
    
    
    public mutating func setAssets(assets: [CoamResult]) {
        if self.assets == nil {
            self.assets = assets
        } else {
            self.assets!.append(contentsOf: assets)
        }
    }
    
    public mutating func setFitsData(fitsData: FitsData) {
        if self.fitsData == nil {
            self.fitsData = [fitsData]
        } else {
            self.fitsData?.append(fitsData)
        }
    }
    
}
