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
    var assets:[CoamResult]?
    var preview:FitsData?

    public mutating func setAssets(assets: [CoamResult]) {
        if self.assets == nil {
            self.assets = assets
        } else {
            self.assets!.append(contentsOf: assets)
        }
    }

    public mutating func setPreview(preview: FitsData) {
        self.preview = preview
    }
    
}

