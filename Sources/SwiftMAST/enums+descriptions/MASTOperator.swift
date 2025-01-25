//
//  MASTOperator.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//


public enum MASTOperator:String, Codable, Identifiable {
    case eq = "="
    case lt = "<"
    case gt = ">"
    case lte = "<="
    case gte = ">="
    case like = "like"
    case between = "between"
    case and = "and"
    case or = "or"
    case all = "*"
    
    public var id:String {
        return rawValue
    }
}
