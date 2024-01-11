//
//  File.swift
//  
//
//  Created by Yuma decaux on 11/1/2024.
//

import Foundation

/** MASTTable rows to json transformations for MAST queries
 Existing query types are:
 * Mast.Name.Lookup
 */
extension MASTTable {
    
    public func getNameLookupResults()->[NameLookupJson] {
        var output = [NameLookupJson]()
        print("Field order is: \(self.fields)")
        for row in self.values {
            output.append(NameLookupJson(data: row))
        }
        return [NameLookupJson]()
    }

}
