//
//  MASTTable.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public class MASTTable:NSObject {
    /** Initial key value pair return type
     for all MAST search table requests.
     The dictionary is further processed from the associated search type
     
     This table results from json and xml processing
     Properties:
     * fields: the header of the table
     * values: rows of values mapped to the fields
     */
    public var fields:[String]
    internal var values:[[QValue]]
    
    /* XML parsing related objects */
    var xmlDict = [String: Any]()
    var xmlDictArr = [[String: Any]]()
    var currentElement = ""
    
    public init(fields: [String], values:[[QValue]]) {
        self.fields = fields
        self.values = values
    }
    
    public override init() {
        self.fields = [String]()
        self.values = [[QValue]]()
    }
    
    /** Returns all fields from the payload
     */
    public func getFields() -> [String] {
        return self.fields
    }
    
    /** Gets the column of values specified by field
     Parameters
     field: String
     */
    public func getValues( for field: String) -> [QValue] {
        print("Field \(field)")
        // Sometimes fields are inconsistent with casing
        if let idx = self.fields.firstIndex(of: field) {
            return self.values.map{$0[idx]}
        } else {
            let lowercaseFields = self.fields.map{$0.lowercased()}
            let idx = lowercaseFields.firstIndex(of: field)!
                return self.values.map{$0[idx]}
        }
    }
    
    /** Gets string values for a given field
     Parameters
     field: String
     */
    public func getStringValues(for field: String) -> [String] {
        return getValues(for: field).map{$0.value as! String}
    }

    /** Gets Int values for a given field
     Parameters
     field: String
     */
    public func getIntValues(for field: String) -> [Int] {
        return getValues(for: field).map{$0.value as! Int}
    }

    /** Gets Float values for a given field
     Parameters
     field: String
     */
    public func getFloatValues(for field: String) -> [Float] {
        return getValues(for: field).map{$0.value as! Float}
    }

    /** Gets Bool values for a given field
     Parameters
     field: String
     */
    public func getBoolValues(for field: String) -> [Bool] {
        return getValues(for: field).map{$0.value as! Bool}
    }

    /** get unique values for a given field column
     Parameter
     field: String
     */
    public func getUniqueValues(for field: String) -> [QValue] {
        return Array(Set(getValues(for: field)))
    }
    
    /** Returns unique string values for a field
     Parameters
     field: String
     */
    public func getUniqueString(for field: String) -> [String] {
        return getUniqueValues(for: field).map{$0.value as! String}
    }
    
    /** Returns unique Int values for a field
     Parameters
     field: String
     */
    public func getUniqueInt(for field: String) -> [Int] {
        return getUniqueValues(for: field).map{$0.value as! Int}
    }

    /** Returns unique Float values for a field
     Parameters
     field: String
     */
    public func getUniqueInt(for field: String) -> [Float] {
        return getUniqueValues(for: field).map{$0.value as! Float}
    }

    /** Gets all values for a given set of fields
     Parameters
     fields: [String]
     */
    public func getRows( for fields: [String]) -> [[QValue]] {
        var output:[[QValue]] = []
        let rowCount = values.count
        for i in 0..<rowCount {
            output.append(fields.compactMap{getValues(for: $0)[i]})
        }
        return output
    }
    
/** Get MAST json Coam results
 using the default returned fields and associated values
 https://mast.stsci.edu/api/v0/_c_a_o_mfields.html
 The CoamResult format can be sorted
 by its t_min value which is a temporally
 increasing decimal JD measure.
 */
    public func getCoamResults() -> [CoamResult] {
        let rows = getRows(for: Coam.allCases.map{$0.id})
        return rows.map{CoamResult(data: $0)}
    }
    
}

                        extension MASTTable:XMLParserDelegate {
    
    public func parserDidStartDocument(_ parser: XMLParser) {
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            if elementName == "element" {
                xmlDict = [:]
            } else {
                currentElement = elementName
            }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if xmlDict[currentElement] == nil {
                       xmlDict.updateValue(string, forKey: currentElement)
                }
            }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "element" {
                xmlDictArr.append(xmlDict)
        }
    }

    public func parserDidEndDocument(_ parser: XMLParser) {
        populateTable()
    }

    public func populateTable() {
        self.fields = self.xmlDict.keys.map{$0}
        self.values.append(self.xmlDict.keys.map{QValue(value: self.xmlDict[$0]! as! String)})
    }
    
}

extension MASTTable {
    
    public func getRows(filters: [ResultField])->[ResultField: [QValue]] {
        print(fields)
        var output = [ResultField: [QValue]]()
        for filter in filters {
            if let idx = fields.firstIndex(of: filter.id) {
                print("filter \(filters) idx \(idx)")
                output[filter] = values.map{$0[idx]}
            }
        }
        return output
    }
    
}
