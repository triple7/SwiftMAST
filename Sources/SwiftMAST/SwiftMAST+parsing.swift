//
//  File.swift
//  
//
//  Created by Yuma decaux on 29/12/2022.
//

import Foundation

 extension SwiftMAST {

     internal func parseCsvTable(text: String)->MASTTarget {
         var table = text.components(separatedBy: "\n")
         let header = table.removeFirst().components(separatedBy: ",")
         let rows = table.map{$0.components(separatedBy: ",")}
         return MASTTarget(header: header, data: rows)
     }
     
}
