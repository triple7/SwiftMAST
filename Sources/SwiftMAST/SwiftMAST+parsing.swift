//
//  File.swift
//  
//
//  Created by Yuma decaux on 29/12/2022.
//

import Foundation

 extension SwiftMAST {
/** MAST request return type parsing functions
 */
     
     internal func parseXml(data: Data)->MASTTable {
         let text = String(decoding: data, as: UTF8.self)
         let table = MASTTable()
         let parser = XMLParser(data: data)
         parser.delegate = table
         _ = parser.parse()
return table
     }

     internal func parseJson(data: Data)->MASTTable {
         let text = String(decoding: data, as: UTF8.self)

         let payload = try! JSONDecoder().decode(JsonPayload.self, from: data)
         let fields = payload.fields.map{$0.name}
         var values = [[String]]()
         for row in payload.data {
             values.append(fields.map{String(row[$0].debugDescription)})
         }
         return MASTTable(fields: fields, values: values)
     }

     internal func parseCsvTable(text: String)->MASTTable {
         var table = text.components(separatedBy: "\n")
         let header = table.removeFirst().components(separatedBy: ",")
         let rows = table.map{$0.components(separatedBy: ",")}
         return MASTTable(fields: header, values: rows)
     }

}
