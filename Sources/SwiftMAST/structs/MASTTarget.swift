//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation


public struct MASTTarget {
    /** Initial key value pair return type
     for all MAST search table requests.
     The dictionary is further processed from the associated search type
     */
    private let header:[String]
    private let data:[[String]]
    
    public init(header: [String], data:[[String]]) {
        self.header = header
        self.data = data
    }
    
    public func headers()->[String] {
        return self.header
    }
}

