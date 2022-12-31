//
//  File.swift
//  
//
//  Created by Yuma decaux on 30/12/2022.
//

import Foundation

public class MASTTable:NSObject {
    /** Initial key value pair return type
     for all MAST search table requests.
     The dictionary is further processed from the associated search type
     
     This table allows for json and xml processing
     Properties:
     * fields: the header of the table
     values: rows of values mapped to the fields
     */
    private var fields:[String]
    private var values:[[String]]
    
    /* XML parsing related objects */
    var xmlDict = [String: Any]()
    var xmlDictArr = [[String: Any]]()
    var currentElement = ""
    
    public init(fields: [String], values:[[String]]) {
        self.fields = fields
        self.values = values
    }
    
    public override init() {
        self.fields = [String]()
        self.values = [[String]]()
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

    internal func populateTable() {
        print(self.xmlDictArr)
    }
    
}
