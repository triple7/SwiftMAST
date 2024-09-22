//
//  File.swift
//  
//
//  Created by Yuma decaux on 21/9/2024.
//

import Foundation


public enum ProductType:String, Identifiable {
    case Fits
    case Jpeg

    public var id:String {
        return self.rawValue
    }
    
}


public enum PS1FileType:String, Identifiable {
    case fits
    case jpg
    case png

    public var id:String {
        return self.rawValue
    }
    
}
