//
//  MASTTapParameter.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 25/1/2025.
//


public struct MASTTapParameter:Codable {
    let variable:String
    let operation:MASTOperator
    let value:String
    var postOperator:MASTOperator?

    
    public init(variable: String, operation: MASTOperator, value: String) {
        self.variable = variable
        self.operation = operation
        self.value = value
    }
    
    
    public mutating func setPostOperator(postOperator: MASTOperator) {
        self.postOperator = postOperator
    }
    
    
    public func getPredicate() -> String {
        var output = "\(variable) \(operation.id)"
        output = operation == .like ? "\(output) '\(value)'" : "\(output) \(value)"
        return postOperator == nil ? output : "\(output) \(postOperator!)"
    }
    
}


