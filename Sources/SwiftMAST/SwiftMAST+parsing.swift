//
//  File.swift
//  
//
//  Created by Yuma decaux on 29/12/2022.
//

import Foundation
import SwiftQValue

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
         let text = String(decoding: data, as: UTF8.self)
    print("debug return\n\(text)")
         let payload = try! JSONDecoder().decode(ReturnJson.self, from: data)

    // either a json is built as
    // coam results | resolver | missions list
    // Possibly empty tables are tolerated
    var values = [[QValue]]()
    var fields = [String]()
    if let fieldValues = payload.fields {
        fields = fieldValues.map{$0.name}
        for row in payload.data! {
            values.append(fieldValues.map{row[$0.name]!})
        }
    } else if  let resolvedCoordinate = payload.resolvedCoordinate {
        if !resolvedCoordinate.isEmpty {
            let targetFields = Mirror(reflecting: resolvedCoordinate.first!).children.map { (name, value) in
                return (String(describing: name!), QValue(value: String(describing: value)))
            }
            fields = targetFields.map{$0.0}
            print(fields)
            values.append(targetFields.map{$0.1})
            print(values)
        }
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
     
     func parsePS1table(text: String, baseUrl: String)->MASTTable {
         var table = text.components(separatedBy: "\n")
         var fields = table.removeFirst().components(separatedBy: " ")
         let rows = table.map{$0.components(separatedBy: " ")}
         var values = rows.map{$0.map{QValue(value: $0)}}
         // Add the URL from the baseUrl string
         let fileIdx = fields.firstIndex(of: "filename")!
         let raIdx = fields.firstIndex(of: "ra")!
         let decIdx = fields.firstIndex(of: "dec")!
         fields.append("url")
         values = values.map{$0 + [QValue(value: "\(baseUrl)&ra=\($0[raIdx].value)&dec=\($0[decIdx].value)&red=\($0[fileIdx].value)")]}

         return MASTTable(fields: fields, values: values)
     }
     
}

