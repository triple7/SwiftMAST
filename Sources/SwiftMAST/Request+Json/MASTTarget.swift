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
    private let fields:[String]
    private let values:[[String]]
    
    public init(fields: [String], values:[[String]]) {
        self.fields = fields
        self.values = values
    }
    
    public func header()->[String] {
        return self.fields
    }
}

