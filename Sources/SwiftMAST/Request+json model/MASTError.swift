//
//  File.swift
//  
//
//  Created by Yuma decaux on 2/1/2023.
//

import Foundation


public enum MASTError:LocalizedError {
    case NoSuchObject
    case RequestError
    case DataCorrupted
    case Timeout
    case OK

    public var errorDescription: String? {
        switch self {
        case .NoSuchObject:
            return "No matching MAST object was found."
        case .RequestError:
            return "The MAST request could not be completed."
        case .DataCorrupted:
            return "The MAST data could not be processed."
        case .Timeout:
            return "The MAST request timed out."
        case .OK:
            return nil
        }
    }
}
