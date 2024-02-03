//
//  File.swift
//  
//
//  Created by Yuma decaux on 29/12/2022.
//

import Foundation

 public extension SwiftMAST {
/** MAST request return type parsing functions
 */
     
func parseXml(data: Data)->MASTTable {
         let table = MASTTable()
         let parser = XMLParser(data: data)
         parser.delegate = table
         _ = parser.parse()
return table
     }

func parseJson(data: Data)->MASTTable {
         let _ = String(decoding: data, as: UTF8.self)
         let payload = try! JSONDecoder().decode(ReturnJson.self, from: data)
         let fields = payload.fields.map{$0.name}
         var values = [[QValue]]()
         for row in payload.data {
                     values.append(fields.map{row[$0]!})
         }
         return MASTTable(fields: fields, values: values)
     }

func parseCsvTable(text: String)->MASTTable {
         var table = text.components(separatedBy: "\n")
         let fields = table.removeFirst().components(separatedBy: ",")
         let rows = table.map{$0.components(separatedBy: ",")}
         let values = rows.map{$0.map{QValue(value: $0)}}
         return MASTTable(fields: fields, values: values)
     }

}
