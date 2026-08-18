//
//  LocalObservationGroup.swift
//  SwiftMAST
//
//  Models observation products discovered from SwiftMAST's local product cache.
//

import Foundation
import SwiftQValue

/// A locally cached product for one observation filter.
public struct LocalObservationFilterProduct: Codable {
    public let filterName: String
    public let fitFileURL: URL?
    public let imageFileURL: URL?
    public let previewImageFileURL: URL?
    public let coamResult: CoamResult?
    public let rawMetadata: [String: QValue]?
    public let metadata: FITSMetadata?
    public let imageMetadata: FITSImageHeaderMetadata?
    public let wcs: FITSWCSData?

    public init(
        filterName: String,
        fitFileURL: URL?,
        imageFileURL: URL?,
        previewImageFileURL: URL? = nil,
        coamResult: CoamResult?,
        rawMetadata: [String: QValue]?,
        metadata: FITSMetadata?,
        imageMetadata: FITSImageHeaderMetadata?,
        wcs: FITSWCSData?
    ) {
        self.filterName = filterName
        self.fitFileURL = fitFileURL
        self.imageFileURL = imageFileURL
        self.previewImageFileURL = previewImageFileURL
        self.coamResult = coamResult
        self.rawMetadata = rawMetadata
        self.metadata = metadata
        self.imageMetadata = imageMetadata
        self.wcs = wcs
    }
}

/// Observation group reconstructed from locally cached FITS/image products.
public struct LocalObservationGroup: Codable, CustomStringConvertible {
    public let targetName: String
    public let mission: String
    public let observationKey: String
    public let instrument: String
    public let filters: [LocalObservationFilterProduct]

    public init(
        targetName: String,
        mission: String,
        observationKey: String,
        instrument: String,
        filters: [LocalObservationFilterProduct]
    ) {
        self.targetName = targetName
        self.mission = mission
        self.observationKey = observationKey
        self.instrument = instrument
        self.filters = filters
    }

    public var description: String {
        let filterNames = filters.map(\.filterName).joined(separator: ", ")
        return "\(targetName) \(observationKey) [\(mission)/\(instrument)] - \(filters.count) filters: \(filterNames)"
    }
}
