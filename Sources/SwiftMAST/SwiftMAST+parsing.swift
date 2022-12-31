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
     
     internal func parseJson(data: Data)->MASTTarget {
         let text = String(decoding: data, as: UTF8.self)
         print(text)

         let payload = try! JSONDecoder().decode(JsonPayload.self, from: data)
         let fields = payload.fields.map{$0.name}
         var values = [[String]]()
         for row in payload.data {
             values.append(fields.map{String(row[$0].debugDescription)})
         }
         return MASTTarget(fields: fields, values: values)
     }

     internal func parseCsvTable(text: String)->MASTTarget {
         var table = text.components(separatedBy: "\n")
         let header = table.removeFirst().components(separatedBy: ",")
         let rows = table.map{$0.components(separatedBy: ",")}
         return MASTTarget(fields: header, values: rows)
     }

}
