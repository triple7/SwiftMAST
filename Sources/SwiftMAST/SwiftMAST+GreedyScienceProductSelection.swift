//
//  SwiftMAST+GreedyScienceProductSelection.swift
//  SwiftMAST
//
//  A deliberately self-contained, reviewable implementation of the TAP-backed
//  greedy science-product selection flow.
//

import Foundation

/// Controls both TAP candidate discovery and the greedy science-product search.
public struct GreedyScienceProductSelectionOptions {
    public var missions: [ObservationMission]
    public var instruments: [String]?
    public var filterBands: [String]?
    public var calibLevels: [String]?
    public var dataProductTypes: [String]?

    /// Maximum artifact rows requested from each mission branch before local selection.
    public var candidateRowLimit: Int

    /// Hard limit on the number of products returned by the greedy search.
    public var maxSelectedProducts: Int

    /// Products with missing sizes or sizes above this value are ineligible.
    public var maxProductSizeBytes: Int64

    /// Optional aggregate download budget for all selected products.
    public var maxTotalSizeBytes: Int64?

    /// The search stops after this fraction of the target grid is covered and the
    /// requested filter count has also been reached.
    public var targetCoverageFraction: Double
    public var minimumDistinctFilters: Int

    /// Benefit weights in `(coverageWeight * newCoverage + filterWeight * newFilters) / size`.
    public var coverageWeight: Double
    public var filterWeight: Double

    /// Exponent applied to the size cost. `0` ignores size, `1` uses size directly.
    public var sizePenaltyExponent: Double

    /// Number of cells on each side of the target's square sampling grid.
    public var coverageGridDimension: Int

    /// Fetch WCS-oriented FITS headers only for products selected by the greedy pass.
    public var fetchFITSHeadersForSelectedProducts: Bool

    public init(
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        candidateRowLimit: Int = 400,
        maxSelectedProducts: Int = 5,
        maxProductSizeBytes: Int64 = 70 * 1_048_576,
        maxTotalSizeBytes: Int64? = nil,
        targetCoverageFraction: Double = 0.80,
        minimumDistinctFilters: Int = 3,
        coverageWeight: Double = 0.65,
        filterWeight: Double = 0.35,
        sizePenaltyExponent: Double = 1.0,
        coverageGridDimension: Int = 48,
        fetchFITSHeadersForSelectedProducts: Bool = false
    ) {
        self.missions = missions
        self.instruments = instruments
        self.filterBands = filterBands
        self.calibLevels = calibLevels
        self.dataProductTypes = dataProductTypes
        self.candidateRowLimit = candidateRowLimit
        self.maxSelectedProducts = maxSelectedProducts
        self.maxProductSizeBytes = maxProductSizeBytes
        self.maxTotalSizeBytes = maxTotalSizeBytes
        self.targetCoverageFraction = targetCoverageFraction
        self.minimumDistinctFilters = minimumDistinctFilters
        self.coverageWeight = coverageWeight
        self.filterWeight = filterWeight
        self.sizePenaltyExponent = sizePenaltyExponent
        self.coverageGridDimension = coverageGridDimension
        self.fetchFITSHeadersForSelectedProducts = fetchFITSHeadersForSelectedProducts
    }
}

/// Why a TAP row could not enter the greedy search frontier.
public enum GreedyScienceProductExclusionReason: String, Codable {
    case duplicateProduct
    case missingDownloadURL
    case missingFileSize
    case exceedsProductSizeLimit
    case missingFootprint
    case invalidFootprint
    case missingFilter
    case missingInstrument
}

public struct GreedyScienceProductExclusion: Codable {
    public let observationID: String
    public let productURL: String
    public let reason: GreedyScienceProductExclusionReason
}

/// One accepted edge in the greedy graph traversal.
public struct GreedyScienceProductSelectionStep: Codable {
    public let iteration: Int
    public let instrumentBranch: String
    public let observationKey: String
    public let observationID: String
    public let filters: [String]
    public let fileSizeBytes: Int64
    public let newCoverageFraction: Double
    public let newAreaSquareDegrees: Double
    public let newFilterCount: Int
    public let score: Double
    public let cumulativeCoverageFraction: Double
    public let cumulativeFilters: [String]
    public let cumulativeSizeBytes: Int64
}

public enum GreedyScienceProductSelectionStopReason: String, Codable {
    case targetSatisfied
    case maximumProductsReached
    case noEligibleCandidates
    case noAdditionalBenefit
    case targetResolutionFailed
    case invalidConfiguration
}

/// Review data and selected products produced by the greedy traversal.
public struct GreedyScienceProductSelectionResult {
    public let targetName: String
    public let targetRA: Double?
    public let targetDec: Double?
    public let radiusDegrees: Double
    public let candidateCount: Int
    public let eligibleCandidateCount: Int
    public let branchCandidateCounts: [String: Int]
    public let excludedCandidates: [GreedyScienceProductExclusion]
    public let steps: [GreedyScienceProductSelectionStep]
    public let selectedProducts: [CoamResult]
    public let selectedObservationGroups: [ObservationGroup]
    public let coveredFraction: Double
    public let selectedFilters: [String]
    public let totalSelectedSizeBytes: Int64
    public let stopReason: GreedyScienceProductSelectionStopReason

    internal func replacingSelectedProducts(
        _ products: [CoamResult],
        groups: [ObservationGroup]
    ) -> GreedyScienceProductSelectionResult {
        GreedyScienceProductSelectionResult(
            targetName: targetName,
            targetRA: targetRA,
            targetDec: targetDec,
            radiusDegrees: radiusDegrees,
            candidateCount: candidateCount,
            eligibleCandidateCount: eligibleCandidateCount,
            branchCandidateCounts: branchCandidateCounts,
            excludedCandidates: excludedCandidates,
            steps: steps,
            selectedProducts: products,
            selectedObservationGroups: groups,
            coveredFraction: coveredFraction,
            selectedFilters: selectedFilters,
            totalSelectedSizeBytes: totalSelectedSizeBytes,
            stopReason: stopReason
        )
    }
}

extension SwiftMAST {
    /// Fetch calibrated science FITS candidates from CAOM TAP and greedily choose a small,
    /// filter-diverse set whose footprints cover as much of the target cone as possible.
    ///
    /// This API intentionally does not call ``getTargetCompositeCandidates``. It uses the shared
    /// TAP executor so the complete selection process remains visible in this file:
    /// fetch -> validate -> branch -> score -> select -> enrich selected headers -> regroup.
    public func selectScienceProductsUsingGreedyTAP(
        targetName: String,
        radiusDegrees: Double = 0.05,
        options: GreedyScienceProductSelectionOptions = .init(),
        result: @escaping (GreedyScienceProductSelectionResult) -> Void
    ) {
        let trimmedTargetName = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTargetName.isEmpty,
              radiusDegrees > 0,
              !options.missions.isEmpty,
              options.candidateRowLimit > 0,
              options.maxSelectedProducts > 0,
              options.maxProductSizeBytes > 0,
              options.coverageGridDimension > 0,
              options.coverageWeight >= 0,
              options.filterWeight >= 0,
              options.sizePenaltyExponent >= 0
        else {
            result(
                emptyGreedyScienceProductSelectionResult(
                    targetName: trimmedTargetName,
                    radiusDegrees: radiusDegrees,
                    stopReason: .invalidConfiguration
                )
            )
            return
        }

        lookupTargetCoordinates(targetName: trimmedTargetName) { coordinates in
            guard let coordinates else {
                result(
                    self.emptyGreedyScienceProductSelectionResult(
                        targetName: trimmedTargetName,
                        radiusDegrees: radiusDegrees,
                        stopReason: .targetResolutionFailed
                    )
                )
                return
            }

            self.log(
                .OK,
                message: "Started greedy TAP science-product selection",
                metadata: [
                    "event": "greedyScienceProductSelectionStarted",
                    "targetName": trimmedTargetName,
                    "radiusDegrees": String(radiusDegrees),
                    "candidateRowLimit": String(options.candidateRowLimit),
                ]
            )

            func selectAndFinish(_ groups: [ObservationGroup]) {
                let selection = self.selectScienceProductsGreedily(
                    from: groups,
                    targetName: trimmedTargetName,
                    targetRA: Double(coordinates.ra),
                    targetDec: Double(coordinates.dec),
                    radiusDegrees: radiusDegrees,
                    options: options
                )

                let finish: (GreedyScienceProductSelectionResult) -> Void = { finalSelection in
                    self.log(
                        .OK,
                        message: "Finished greedy TAP science-product selection",
                        metadata: [
                            "event": "greedyScienceProductSelectionFinished",
                            "candidateCount": String(finalSelection.candidateCount),
                            "eligibleCandidateCount": String(finalSelection.eligibleCandidateCount),
                            "selectedProductCount": String(finalSelection.selectedProducts.count),
                            "selectedFilterCount": String(finalSelection.selectedFilters.count),
                            "coveredFraction": String(finalSelection.coveredFraction),
                            "stopReason": finalSelection.stopReason.rawValue,
                        ]
                    )
                    result(finalSelection)
                }

                guard options.fetchFITSHeadersForSelectedProducts,
                      !selection.selectedProducts.isEmpty
                else {
                    finish(selection)
                    return
                }

                self.enrichCoamResultsWithFITSImageMetadata(selection.selectedProducts) {
                    enrichedProducts in
                    finish(
                        selection.replacingSelectedProducts(
                            enrichedProducts,
                            groups: self.buildObservationGroups(from: enrichedProducts)
                        )
                    )
                }
            }

            // Query each mission independently so a SELECT TOP result ordered by collection cannot
            // fill the entire frontier with HST/HLA rows before any JWST rows are considered.
            let fetchGroup = DispatchGroup()
            let fetchLock = NSLock()
            var fetchedGroups: [ObservationGroup] = []
            for mission in options.missions {
                fetchGroup.enter()
                self.executeObservationGroupsTAPQuery(
                    targetName: trimmedTargetName,
                    ra: coordinates.ra,
                    dec: coordinates.dec,
                    radius: Float(radiusDegrees),
                    missions: [mission],
                    instruments: options.instruments,
                    filterBands: options.filterBands,
                    calibLevels: options.calibLevels,
                    dataProductTypes: options.dataProductTypes,
                    pageSize: options.candidateRowLimit,
                    limit: nil,
                    sortOrder: .filter,
                    columnProfile: .targetCompositeSelection,
                    productKinds: [.scienceFITS],
                    maxProductsPerFilter: nil,
                    headerFetchPolicy: .none
                ) { groups in
                    fetchLock.lock()
                    fetchedGroups.append(contentsOf: groups)
                    fetchLock.unlock()
                    fetchGroup.leave()
                }
            }
            fetchGroup.notify(queue: .main) {
                selectAndFinish(fetchedGroups)
            }
        }
    }

    /// Pure local portion of the algorithm. It is internal so unit tests can review the greedy
    /// behavior without making network requests, while library users see one public workflow API.
    internal func selectScienceProductsGreedily(
        from groups: [ObservationGroup],
        targetName: String,
        targetRA: Double,
        targetDec: Double,
        radiusDegrees: Double,
        options: GreedyScienceProductSelectionOptions
    ) -> GreedyScienceProductSelectionResult {
        let products = groups.flatMap(\.products)
        let grid = GreedyCoverageGrid(
            centerRA: targetRA,
            centerDec: targetDec,
            radiusDegrees: radiusDegrees,
            requestedDimension: options.coverageGridDimension
        )

        var candidates: [GreedyScienceProductCandidate] = []
        var exclusions: [GreedyScienceProductExclusion] = []
        var seenProductIDs = Set<String>()

        for product in products {
            let identity = greedyScienceProductIdentity(product)
            guard seenProductIDs.insert(identity).inserted else {
                exclusions.append(greedyExclusion(product, .duplicateProduct))
                continue
            }
            guard !product.dataURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                exclusions.append(greedyExclusion(product, .missingDownloadURL))
                continue
            }
            guard let size = product.dataURLSizeBytes, size > 0 else {
                exclusions.append(greedyExclusion(product, .missingFileSize))
                continue
            }
            guard size <= options.maxProductSizeBytes else {
                exclusions.append(greedyExclusion(product, .exceedsProductSizeLimit))
                continue
            }
            guard !product.s_region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                exclusions.append(greedyExclusion(product, .missingFootprint))
                continue
            }
            guard let region = product.spaceRegion else {
                exclusions.append(greedyExclusion(product, .invalidFootprint))
                continue
            }
            let filters = greedyFilterKeys(product.filters)
            guard !filters.isEmpty else {
                exclusions.append(greedyExclusion(product, .missingFilter))
                continue
            }
            let instrument = product.instrument_name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instrument.isEmpty else {
                exclusions.append(greedyExclusion(product, .missingInstrument))
                continue
            }

            let cells = Set(
                grid.points.enumerated().compactMap { index, point in
                    region.contains(point) ? index : nil
                }
            )
            candidates.append(
                GreedyScienceProductCandidate(
                    product: product,
                    instrumentBranch: instrument.uppercased(),
                    observationKey: observationGroupKey(product),
                    filters: filters,
                    fileSizeBytes: size,
                    coveredCells: cells
                )
            )
        }

        let branchCounts = Dictionary(grouping: candidates, by: \.instrumentBranch)
            .mapValues(\.count)
        guard !candidates.isEmpty else {
            return GreedyScienceProductSelectionResult(
                targetName: targetName,
                targetRA: targetRA,
                targetDec: targetDec,
                radiusDegrees: radiusDegrees,
                candidateCount: products.count,
                eligibleCandidateCount: 0,
                branchCandidateCounts: branchCounts,
                excludedCandidates: exclusions,
                steps: [],
                selectedProducts: [],
                selectedObservationGroups: [],
                coveredFraction: 0,
                selectedFilters: [],
                totalSelectedSizeBytes: 0,
                stopReason: .noEligibleCandidates
            )
        }

        let targetCoverage = min(max(options.targetCoverageFraction, 0), 1)
        let minimumFilters = max(options.minimumDistinctFilters, 0)
        let coverageWeight = max(options.coverageWeight, 0)
        let filterWeight = max(options.filterWeight, 0)
        let sizeExponent = max(options.sizePenaltyExponent, 0)

        var remaining = candidates
        var selectedCandidates: [GreedyScienceProductCandidate] = []
        var selectedCells = Set<Int>()
        var selectedFilters = Set<String>()
        var totalSize: Int64 = 0
        var steps: [GreedyScienceProductSelectionStep] = []
        var stopReason: GreedyScienceProductSelectionStopReason = .noAdditionalBenefit

        while selectedCandidates.count < options.maxSelectedProducts {
            let coveredFraction = grid.coverageFraction(for: selectedCells)
            if coveredFraction >= targetCoverage && selectedFilters.count >= minimumFilters {
                stopReason = .targetSatisfied
                break
            }

            var best: GreedyScoredScienceProductCandidate?
            for candidate in remaining {
                if let maxTotal = options.maxTotalSizeBytes,
                   totalSize > maxTotal - candidate.fileSizeBytes
                {
                    continue
                }

                let newCells = candidate.coveredCells.subtracting(selectedCells)
                let newCoverage = grid.coverageFraction(for: newCells)
                let newFilters = candidate.filters.subtracting(selectedFilters)
                let benefit = coverageWeight * newCoverage
                    + filterWeight * Double(newFilters.count)
                guard benefit > 0 else { continue }

                let sizeMiB = max(Double(candidate.fileSizeBytes) / 1_048_576.0, 0.001)
                let sizeCost = pow(sizeMiB, sizeExponent)
                let scored = GreedyScoredScienceProductCandidate(
                    candidate: candidate,
                    newCells: newCells,
                    newFilters: newFilters,
                    newCoverageFraction: newCoverage,
                    score: benefit / max(sizeCost, 0.000_001)
                )
                if best == nil || greedyCandidate(scored, ranksBefore: best!) {
                    best = scored
                }
            }

            guard let best else {
                stopReason = .noAdditionalBenefit
                break
            }

            let candidate = best.candidate
            selectedCandidates.append(candidate)
            selectedCells.formUnion(candidate.coveredCells)
            selectedFilters.formUnion(candidate.filters)
            totalSize += candidate.fileSizeBytes
            remaining.removeAll { $0.identity == candidate.identity }

            let cumulativeCoverage = grid.coverageFraction(for: selectedCells)
            steps.append(
                GreedyScienceProductSelectionStep(
                    iteration: steps.count + 1,
                    instrumentBranch: candidate.instrumentBranch,
                    observationKey: candidate.observationKey,
                    observationID: candidate.product.obs_id,
                    filters: candidate.filters.sorted(),
                    fileSizeBytes: candidate.fileSizeBytes,
                    newCoverageFraction: best.newCoverageFraction,
                    newAreaSquareDegrees: best.newCoverageFraction * grid.targetAreaSquareDegrees,
                    newFilterCount: best.newFilters.count,
                    score: best.score,
                    cumulativeCoverageFraction: cumulativeCoverage,
                    cumulativeFilters: selectedFilters.sorted(),
                    cumulativeSizeBytes: totalSize
                )
            )
        }

        if selectedCandidates.count >= options.maxSelectedProducts {
            let coveredFraction = grid.coverageFraction(for: selectedCells)
            stopReason = coveredFraction >= targetCoverage && selectedFilters.count >= minimumFilters
                ? .targetSatisfied
                : .maximumProductsReached
        }

        let selectedProducts = selectedCandidates.map(\.product)
        return GreedyScienceProductSelectionResult(
            targetName: targetName,
            targetRA: targetRA,
            targetDec: targetDec,
            radiusDegrees: radiusDegrees,
            candidateCount: products.count,
            eligibleCandidateCount: candidates.count,
            branchCandidateCounts: branchCounts,
            excludedCandidates: exclusions,
            steps: steps,
            selectedProducts: selectedProducts,
            selectedObservationGroups: buildObservationGroups(from: selectedProducts),
            coveredFraction: grid.coverageFraction(for: selectedCells),
            selectedFilters: selectedFilters.sorted(),
            totalSelectedSizeBytes: totalSize,
            stopReason: stopReason
        )
    }

    private func emptyGreedyScienceProductSelectionResult(
        targetName: String,
        radiusDegrees: Double,
        stopReason: GreedyScienceProductSelectionStopReason
    ) -> GreedyScienceProductSelectionResult {
        GreedyScienceProductSelectionResult(
            targetName: targetName,
            targetRA: nil,
            targetDec: nil,
            radiusDegrees: radiusDegrees,
            candidateCount: 0,
            eligibleCandidateCount: 0,
            branchCandidateCounts: [:],
            excludedCandidates: [],
            steps: [],
            selectedProducts: [],
            selectedObservationGroups: [],
            coveredFraction: 0,
            selectedFilters: [],
            totalSelectedSizeBytes: 0,
            stopReason: stopReason
        )
    }
}

private struct GreedyScienceProductCandidate {
    let product: CoamResult
    let instrumentBranch: String
    let observationKey: String
    let filters: Set<String>
    let fileSizeBytes: Int64
    let coveredCells: Set<Int>

    var identity: String {
        greedyScienceProductIdentity(product)
    }
}

private struct GreedyScoredScienceProductCandidate {
    let candidate: GreedyScienceProductCandidate
    let newCells: Set<Int>
    let newFilters: Set<String>
    let newCoverageFraction: Double
    let score: Double
}

private struct GreedyCoverageGrid {
    let points: [SpaceRegion.Coordinate]
    let targetAreaSquareDegrees: Double

    init(
        centerRA: Double,
        centerDec: Double,
        radiusDegrees: Double,
        requestedDimension: Int
    ) {
        let dimension = min(max(requestedDimension, 4), 200)
        let centerDecRadians = centerDec * Double.pi / 180
        let raScale = max(abs(cos(centerDecRadians)), 0.01)
        var samples: [SpaceRegion.Coordinate] = []
        samples.reserveCapacity(dimension * dimension)

        for row in 0..<dimension {
            let normalizedY = ((Double(row) + 0.5) / Double(dimension)) * 2 - 1
            for column in 0..<dimension {
                let normalizedX = ((Double(column) + 0.5) / Double(dimension)) * 2 - 1
                guard normalizedX * normalizedX + normalizedY * normalizedY <= 1 else {
                    continue
                }
                let dec = min(90, max(-90, centerDec + normalizedY * radiusDegrees))
                let ra = centerRA + normalizedX * radiusDegrees / raScale
                samples.append(SpaceRegion.Coordinate(ra: ra, dec: dec))
            }
        }

        self.points = samples.isEmpty
            ? [SpaceRegion.Coordinate(ra: centerRA, dec: centerDec)]
            : samples

        let radiusRadians = radiusDegrees * Double.pi / 180
        let steradians = 2 * Double.pi * (1 - cos(radiusRadians))
        self.targetAreaSquareDegrees = steradians * pow(180 / Double.pi, 2)
    }

    func coverageFraction(for cells: Set<Int>) -> Double {
        guard !points.isEmpty else { return 0 }
        return min(Double(cells.count) / Double(points.count), 1)
    }
}

private func greedyScienceProductIdentity(_ product: CoamResult) -> String {
    if !product.dataURL.isEmpty { return product.dataURL }
    return [
        product.obs_collection,
        product.obs_id,
        product.instrument_name,
        product.filters,
    ].joined(separator: "\u{1f}")
}

private func greedyFilterKeys(_ value: String) -> Set<String> {
    let ignored = Set(["", "CLEAR", "DETECTION", "N/A", "NA", "NONE", "UNKNOWN", "WHITE"])
    return Set(
        value
            .components(separatedBy: CharacterSet(charactersIn: ";,| "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !ignored.contains($0) }
    )
}

private func greedyExclusion(
    _ product: CoamResult,
    _ reason: GreedyScienceProductExclusionReason
) -> GreedyScienceProductExclusion {
    GreedyScienceProductExclusion(
        observationID: product.obs_id,
        productURL: product.dataURL,
        reason: reason
    )
}

private func greedyCandidate(
    _ lhs: GreedyScoredScienceProductCandidate,
    ranksBefore rhs: GreedyScoredScienceProductCandidate
) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.newCoverageFraction != rhs.newCoverageFraction {
        return lhs.newCoverageFraction > rhs.newCoverageFraction
    }
    if lhs.newFilters.count != rhs.newFilters.count {
        return lhs.newFilters.count > rhs.newFilters.count
    }
    if lhs.candidate.fileSizeBytes != rhs.candidate.fileSizeBytes {
        return lhs.candidate.fileSizeBytes < rhs.candidate.fileSizeBytes
    }
    return lhs.candidate.identity < rhs.candidate.identity
}
