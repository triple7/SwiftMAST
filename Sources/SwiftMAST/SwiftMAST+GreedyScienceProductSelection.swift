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

    /// Benefit weights in `(coverageWeight * newCoverage + filterWeight * newGroupFilters) / size`.
    /// Filter novelty is evaluated within the candidate's observation group.
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
    /// Filters not previously selected from this step's observation group.
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

/// Work counters emitted by the hierarchical selector so callers can verify that
/// selection updates graph neighbors instead of rescanning the complete frontier.
public struct GreedyScienceProductSelectionComplexityMetrics: Codable, Equatable {
    public let candidateScoreUpdates: Int
    public let coverageEdgeVisits: Int
    public let filterEdgeVisits: Int
    public let candidateHeapPops: Int
    public let groupHeapPops: Int
    public let fullCandidateRescans: Int

    internal static let zero = GreedyScienceProductSelectionComplexityMetrics(
        candidateScoreUpdates: 0,
        coverageEdgeVisits: 0,
        filterEdgeVisits: 0,
        candidateHeapPops: 0,
        groupHeapPops: 0,
        fullCandidateRescans: 0
    )
}

/// Review data and selected products produced by the greedy traversal.
public struct GreedyScienceProductSelectionResult {
    public let targetName: String
    public let targetRA: Double?
    public let targetDec: Double?
    public let radiusDegrees: Double
    public let targetAreaSquareDegrees: Double
    public let coverageGridPointCount: Int
    public let candidateCount: Int
    public let eligibleCandidateCount: Int
    public let observationGroupCount: Int
    public let branchCandidateCounts: [String: Int]
    public let excludedCandidates: [GreedyScienceProductExclusion]
    public let steps: [GreedyScienceProductSelectionStep]
    public let selectedProducts: [CoamResult]
    public let selectedObservationGroups: [ObservationGroup]
    public let coveredFraction: Double
    /// Global union of filters in the selected products, used for reporting.
    public let selectedFilters: [String]
    public let totalSelectedSizeBytes: Int64
    public let budgetSkippedCandidateCount: Int
    public let complexityMetrics: GreedyScienceProductSelectionComplexityMetrics
    public let stopReason: GreedyScienceProductSelectionStopReason

    public var coveragePercentage: Double { coveredFraction * 100 }
    public var selectedSizeMiB: Double { Double(totalSelectedSizeBytes) / 1_048_576 }
    public var selectedObservationGroupCount: Int { selectedObservationGroups.count }
    /// Count of unique observation-group/filter pairs accepted by the traversal.
    public var selectedGroupFilterCount: Int { steps.reduce(0) { $0 + $1.newFilterCount } }

    internal func replacingSelectedProducts(
        _ products: [CoamResult],
        groups: [ObservationGroup]
    ) -> GreedyScienceProductSelectionResult {
        GreedyScienceProductSelectionResult(
            targetName: targetName,
            targetRA: targetRA,
            targetDec: targetDec,
            radiusDegrees: radiusDegrees,
            targetAreaSquareDegrees: targetAreaSquareDegrees,
            coverageGridPointCount: coverageGridPointCount,
            candidateCount: candidateCount,
            eligibleCandidateCount: eligibleCandidateCount,
            observationGroupCount: observationGroupCount,
            branchCandidateCounts: branchCandidateCounts,
            excludedCandidates: excludedCandidates,
            steps: steps,
            selectedProducts: products,
            selectedObservationGroups: groups,
            coveredFraction: coveredFraction,
            selectedFilters: selectedFilters,
            totalSelectedSizeBytes: totalSelectedSizeBytes,
            budgetSkippedCandidateCount: budgetSkippedCandidateCount,
            complexityMetrics: complexityMetrics,
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
              (options.maxTotalSizeBytes.map({ $0 > 0 }) ?? true),
              (0...1).contains(options.targetCoverageFraction),
              options.minimumDistinctFilters >= 0,
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
                            "observationGroupCount": String(finalSelection.observationGroupCount),
                            "selectedProductCount": String(finalSelection.selectedProducts.count),
                            "selectedFilterCount": String(finalSelection.selectedFilters.count),
                            "coveredFraction": String(finalSelection.coveredFraction),
                            "budgetSkippedCandidateCount": String(
                                finalSelection.budgetSkippedCandidateCount
                            ),
                            "candidateScoreUpdates": String(
                                finalSelection.complexityMetrics.candidateScoreUpdates
                            ),
                            "fullCandidateRescans": String(
                                finalSelection.complexityMetrics.fullCandidateRescans
                            ),
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
    ///
    /// Flow:
    /// 1. Validate and deduplicate products returned by each TAP mission branch.
    /// 2. Sample every `s_region` footprint on the fixed target coverage grid.
    /// 3. Group candidates by mission, instrument, and observation for AOSImageStack use.
    /// 4. Build a product heap per group, a root group heap, and inverted cell/filter indexes.
    /// 5. Pop the highest marginal-benefit-per-size candidate and update only graph neighbors.
    /// 6. Stop at the coverage/filter goal, product limit, budget exhaustion, or zero benefit.
    /// 7. Restore selected products to observation groups for image-stack construction.
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

        var candidates: [GreedyScienceProductCandidateState] = []
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
                GreedyScienceProductCandidateState(
                    product: product,
                    identity: identity,
                    missionBranch: product.obs_collection
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased(),
                    instrumentBranch: instrument.uppercased(),
                    observationKey: observationGroupKey(product),
                    filters: filters,
                    fileSizeBytes: size,
                    coveredCells: cells
                )
            )
        }

        let branchCounts = Dictionary(grouping: candidates, by: \.missionBranch)
            .mapValues(\.count)
        let observationGroupCount = Set(candidates.map(\.groupID)).count
        guard !candidates.isEmpty else {
            return GreedyScienceProductSelectionResult(
                targetName: targetName,
                targetRA: targetRA,
                targetDec: targetDec,
                radiusDegrees: radiusDegrees,
                targetAreaSquareDegrees: grid.targetAreaSquareDegrees,
                coverageGridPointCount: grid.points.count,
                candidateCount: products.count,
                eligibleCandidateCount: 0,
                observationGroupCount: 0,
                branchCandidateCounts: branchCounts,
                excludedCandidates: exclusions,
                steps: [],
                selectedProducts: [],
                selectedObservationGroups: [],
                coveredFraction: 0,
                selectedFilters: [],
                totalSelectedSizeBytes: 0,
                budgetSkippedCandidateCount: 0,
                complexityMetrics: .zero,
                stopReason: .noEligibleCandidates
            )
        }

        let traversal = GreedyHierarchicalScienceProductSelector(
            candidates: candidates,
            grid: grid,
            options: options
        ).select()
        let selectedProducts = traversal.selectedCandidates.map(\.product)
        let selectedGroups = buildObservationGroups(from: selectedProducts)
        return GreedyScienceProductSelectionResult(
            targetName: targetName,
            targetRA: targetRA,
            targetDec: targetDec,
            radiusDegrees: radiusDegrees,
            targetAreaSquareDegrees: grid.targetAreaSquareDegrees,
            coverageGridPointCount: grid.points.count,
            candidateCount: products.count,
            eligibleCandidateCount: candidates.count,
            observationGroupCount: observationGroupCount,
            branchCandidateCounts: branchCounts,
            excludedCandidates: exclusions,
            steps: traversal.steps,
            selectedProducts: selectedProducts,
            selectedObservationGroups: selectedGroups,
            coveredFraction: traversal.coveredFraction,
            selectedFilters: traversal.selectedFilters.sorted(),
            totalSelectedSizeBytes: traversal.totalSelectedSizeBytes,
            budgetSkippedCandidateCount: traversal.budgetSkippedCandidateCount,
            complexityMetrics: traversal.complexityMetrics,
            stopReason: traversal.stopReason
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
            targetAreaSquareDegrees: 0,
            coverageGridPointCount: 0,
            candidateCount: 0,
            eligibleCandidateCount: 0,
            observationGroupCount: 0,
            branchCandidateCounts: [:],
            excludedCandidates: [],
            steps: [],
            selectedProducts: [],
            selectedObservationGroups: [],
            coveredFraction: 0,
            selectedFilters: [],
            totalSelectedSizeBytes: 0,
            budgetSkippedCandidateCount: 0,
            complexityMetrics: .zero,
            stopReason: stopReason
        )
    }
}

private struct GreedyObservationGroupID: Hashable {
    let mission: String
    let instrument: String
    let observationKey: String

    var sortKey: String {
        [mission, instrument, observationKey].joined(separator: "\u{1f}")
    }
}

/// A filter is considered new within one observation group, not globally.
/// This lets the same useful filter compete independently in separate visits.
private struct GreedyObservationGroupFilterID: Hashable {
    let groupID: GreedyObservationGroupID
    let filter: String
}

private final class GreedyScienceProductCandidateState {
    let product: CoamResult
    let identity: String
    let missionBranch: String
    let instrumentBranch: String
    let observationKey: String
    let filters: Set<String>
    let fileSizeBytes: Int64
    let coveredCells: Set<Int>
    var uncoveredCellCount: Int
    var unseenFilterCount: Int
    var score: Double = 0
    var version = 0
    var isActive = true

    init(
        product: CoamResult,
        identity: String,
        missionBranch: String,
        instrumentBranch: String,
        observationKey: String,
        filters: Set<String>,
        fileSizeBytes: Int64,
        coveredCells: Set<Int>
    ) {
        self.product = product
        self.identity = identity
        self.missionBranch = missionBranch.isEmpty ? "UNKNOWN" : missionBranch
        self.instrumentBranch = instrumentBranch
        self.observationKey = observationKey
        self.filters = filters
        self.fileSizeBytes = fileSizeBytes
        self.coveredCells = coveredCells
        self.uncoveredCellCount = coveredCells.count
        self.unseenFilterCount = filters.count
    }

    var groupID: GreedyObservationGroupID {
        GreedyObservationGroupID(
            mission: missionBranch,
            instrument: instrumentBranch,
            observationKey: observationKey
        )
    }
}

private struct GreedyCandidateHeapEntry {
    let identity: String
    let version: Int
    let score: Double
    let uncoveredCellCount: Int
    let unseenFilterCount: Int
    let fileSizeBytes: Int64

    init(_ candidate: GreedyScienceProductCandidateState) {
        identity = candidate.identity
        version = candidate.version
        score = candidate.score
        uncoveredCellCount = candidate.uncoveredCellCount
        unseenFilterCount = candidate.unseenFilterCount
        fileSizeBytes = candidate.fileSizeBytes
    }
}

private struct GreedyRootHeapEntry {
    let candidate: GreedyCandidateHeapEntry
    let groupID: GreedyObservationGroupID
    let groupVersion: Int
}

private final class GreedyObservationGroupQueue {
    let id: GreedyObservationGroupID
    var version = 0
    var candidateHeap = GreedyBinaryHeap<GreedyCandidateHeapEntry>(
        sort: greedyCandidateEntryRanksBefore
    )

    init(id: GreedyObservationGroupID) {
        self.id = id
    }
}

private struct GreedyBinaryHeap<Element> {
    private var elements: [Element] = []
    private let sort: (Element, Element) -> Bool

    init(sort: @escaping (Element, Element) -> Bool) {
        self.sort = sort
    }

    var peek: Element? { elements.first }

    mutating func insert(_ element: Element) {
        elements.append(element)
        var child = elements.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard sort(elements[child], elements[parent]) else { break }
            elements.swapAt(child, parent)
            child = parent
        }
    }

    @discardableResult
    mutating func pop() -> Element? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 { return elements.removeLast() }

        let result = elements[0]
        elements[0] = elements.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < elements.count else { break }
            let right = left + 1
            var preferred = left
            if right < elements.count, sort(elements[right], elements[left]) {
                preferred = right
            }
            guard sort(elements[preferred], elements[parent]) else { break }
            elements.swapAt(parent, preferred)
            parent = preferred
        }
        return result
    }
}

private struct GreedyScienceProductTraversalResult {
    let selectedCandidates: [GreedyScienceProductCandidateState]
    let steps: [GreedyScienceProductSelectionStep]
    let coveredFraction: Double
    let selectedFilters: Set<String>
    let totalSelectedSizeBytes: Int64
    let budgetSkippedCandidateCount: Int
    let complexityMetrics: GreedyScienceProductSelectionComplexityMetrics
    let stopReason: GreedyScienceProductSelectionStopReason
}

/// Heap-based graph traversal equivalent to the Python
/// `HierarchicalIncrementalGreedySelector`.
private final class GreedyHierarchicalScienceProductSelector {
    private let grid: GreedyCoverageGrid
    private let options: GreedyScienceProductSelectionOptions
    private var candidatesByIdentity: [String: GreedyScienceProductCandidateState] = [:]
    private var groups: [GreedyObservationGroupID: GreedyObservationGroupQueue] = [:]
    private var candidatesByCell: [Int: Set<String>] = [:]
    private var candidatesByFilter: [GreedyObservationGroupFilterID: Set<String>] = [:]
    private var rootHeap = GreedyBinaryHeap<GreedyRootHeapEntry>(
        sort: greedyRootEntryRanksBefore
    )

    private var candidateScoreUpdates = 0
    private var coverageEdgeVisits = 0
    private var filterEdgeVisits = 0
    private var candidateHeapPops = 0
    private var groupHeapPops = 0

    init(
        candidates: [GreedyScienceProductCandidateState],
        grid: GreedyCoverageGrid,
        options: GreedyScienceProductSelectionOptions
    ) {
        self.grid = grid
        self.options = options

        for candidate in candidates {
            candidate.score = score(candidate)
            candidatesByIdentity[candidate.identity] = candidate

            let group = groups[candidate.groupID]
                ?? GreedyObservationGroupQueue(id: candidate.groupID)
            groups[candidate.groupID] = group
            group.candidateHeap.insert(GreedyCandidateHeapEntry(candidate))

            for cell in candidate.coveredCells {
                candidatesByCell[cell, default: []].insert(candidate.identity)
            }
            for filter in candidate.filters {
                let groupFilterID = GreedyObservationGroupFilterID(
                    groupID: candidate.groupID,
                    filter: filter
                )
                candidatesByFilter[groupFilterID, default: []].insert(candidate.identity)
            }
        }

        for group in groups.values {
            publish(group)
        }
    }

    func select() -> GreedyScienceProductTraversalResult {
        let targetCoverage = min(max(options.targetCoverageFraction, 0), 1)
        let minimumFilters = max(options.minimumDistinctFilters, 0)
        var selectedCandidates: [GreedyScienceProductCandidateState] = []
        var selectedCells = Set<Int>()
        var selectedFiltersByGroup: [GreedyObservationGroupID: Set<String>] = [:]
        // Keep the global union for reporting and the overall minimum-filter
        // goal. Candidate novelty is calculated from the group-local set.
        var selectedFilters = Set<String>()
        var totalSize: Int64 = 0
        var steps: [GreedyScienceProductSelectionStep] = []
        var budgetSkipped = 0
        var stopReason: GreedyScienceProductSelectionStopReason = candidatesByIdentity.isEmpty
            ? .noEligibleCandidates
            : .noAdditionalBenefit

        while selectedCandidates.count < options.maxSelectedProducts {
            if grid.coverageFraction(for: selectedCells) >= targetCoverage,
               selectedFilters.count >= minimumFilters
            {
                stopReason = .targetSatisfied
                break
            }

            guard let candidate = popBestCandidate(), candidate.score > 0 else {
                stopReason = candidatesByIdentity.isEmpty
                    ? .noEligibleCandidates
                    : .noAdditionalBenefit
                break
            }

            if let maxTotal = options.maxTotalSizeBytes,
               candidate.fileSizeBytes > maxTotal
                || totalSize > maxTotal - candidate.fileSizeBytes
            {
                candidate.isActive = false
                candidate.version += 1
                budgetSkipped += 1
                if let group = groups[candidate.groupID] { publish(group) }
                continue
            }

            let newCells = candidate.coveredCells.subtracting(selectedCells)
            let newGroupFilters = candidate.filters.subtracting(
                selectedFiltersByGroup[candidate.groupID] ?? []
            )
            let selectedScore = candidate.score
            selectedCandidates.append(candidate)
            selectedCells.formUnion(newCells)
            selectedFiltersByGroup[candidate.groupID, default: []].formUnion(newGroupFilters)
            selectedFilters.formUnion(candidate.filters)
            totalSize += candidate.fileSizeBytes
            candidate.isActive = false
            candidate.version += 1

            let newCoverage = grid.coverageFraction(for: newCells)
            steps.append(
                GreedyScienceProductSelectionStep(
                    iteration: steps.count + 1,
                    instrumentBranch: candidate.instrumentBranch,
                    observationKey: candidate.observationKey,
                    observationID: candidate.product.obs_id,
                    filters: candidate.filters.sorted(),
                    fileSizeBytes: candidate.fileSizeBytes,
                    newCoverageFraction: newCoverage,
                    newAreaSquareDegrees: newCoverage * grid.targetAreaSquareDegrees,
                    newFilterCount: newGroupFilters.count,
                    score: selectedScore,
                    cumulativeCoverageFraction: grid.coverageFraction(for: selectedCells),
                    cumulativeFilters: selectedFilters.sorted(),
                    cumulativeSizeBytes: totalSize
                )
            )
            updateAffectedCandidates(
                selected: candidate,
                newCells: newCells,
                newGroupFilters: newGroupFilters
            )
        }

        if selectedCandidates.count >= options.maxSelectedProducts {
            stopReason = grid.coverageFraction(for: selectedCells) >= targetCoverage
                && selectedFilters.count >= minimumFilters
                ? .targetSatisfied
                : .maximumProductsReached
        }

        return GreedyScienceProductTraversalResult(
            selectedCandidates: selectedCandidates,
            steps: steps,
            coveredFraction: grid.coverageFraction(for: selectedCells),
            selectedFilters: selectedFilters,
            totalSelectedSizeBytes: totalSize,
            budgetSkippedCandidateCount: budgetSkipped,
            complexityMetrics: GreedyScienceProductSelectionComplexityMetrics(
                candidateScoreUpdates: candidateScoreUpdates,
                coverageEdgeVisits: coverageEdgeVisits,
                filterEdgeVisits: filterEdgeVisits,
                candidateHeapPops: candidateHeapPops,
                groupHeapPops: groupHeapPops,
                fullCandidateRescans: 0
            ),
            stopReason: stopReason
        )
    }

    private func score(_ candidate: GreedyScienceProductCandidateState) -> Double {
        let coverageWeight = max(options.coverageWeight, 0)
        let filterWeight = max(options.filterWeight, 0)
        let sizeExponent = max(options.sizePenaltyExponent, 0)
        let newCoverage = grid.coverageFraction(forCount: candidate.uncoveredCellCount)
        let benefit = coverageWeight * newCoverage
            + filterWeight * Double(candidate.unseenFilterCount)
        let sizeMiB = max(Double(candidate.fileSizeBytes) / 1_048_576, 0.001)
        let sizeCost = max(pow(sizeMiB, sizeExponent), 0.000_001)
        return benefit / sizeCost
    }

    private func clean(_ group: GreedyObservationGroupQueue)
        -> GreedyScienceProductCandidateState?
    {
        while let entry = group.candidateHeap.peek {
            if let candidate = candidatesByIdentity[entry.identity],
               candidate.isActive,
               candidate.version == entry.version
            {
                return candidate
            }
            group.candidateHeap.pop()
            candidateHeapPops += 1
        }
        return nil
    }

    private func publish(_ group: GreedyObservationGroupQueue) {
        group.version += 1
        guard let best = clean(group) else { return }
        rootHeap.insert(
            GreedyRootHeapEntry(
                candidate: GreedyCandidateHeapEntry(best),
                groupID: group.id,
                groupVersion: group.version
            )
        )
    }

    private func popBestCandidate() -> GreedyScienceProductCandidateState? {
        while let entry = rootHeap.pop() {
            groupHeapPops += 1
            guard let group = groups[entry.groupID],
                  group.version == entry.groupVersion
            else {
                continue
            }
            guard let best = clean(group) else { continue }
            guard best.identity == entry.candidate.identity,
                  best.version == entry.candidate.version
            else {
                publish(group)
                continue
            }
            return best
        }
        return nil
    }

    private func updateAffectedCandidates(
        selected: GreedyScienceProductCandidateState,
        newCells: Set<Int>,
        newGroupFilters: Set<String>
    ) {
        var affected = Set<String>()
        for cell in newCells {
            let identities = candidatesByCell[cell] ?? []
            coverageEdgeVisits += identities.count
            for identity in identities {
                guard let candidate = candidatesByIdentity[identity], candidate.isActive else {
                    continue
                }
                candidate.uncoveredCellCount = max(candidate.uncoveredCellCount - 1, 0)
                affected.insert(identity)
            }
        }
        for filter in newGroupFilters {
            let groupFilterID = GreedyObservationGroupFilterID(
                groupID: selected.groupID,
                filter: filter
            )
            let identities = candidatesByFilter[groupFilterID] ?? []
            filterEdgeVisits += identities.count
            for identity in identities {
                guard let candidate = candidatesByIdentity[identity], candidate.isActive else {
                    continue
                }
                candidate.unseenFilterCount = max(candidate.unseenFilterCount - 1, 0)
                affected.insert(identity)
            }
        }

        var affectedGroups: Set<GreedyObservationGroupID> = [selected.groupID]
        for identity in affected {
            guard let candidate = candidatesByIdentity[identity],
                  let group = groups[candidate.groupID]
            else {
                continue
            }
            candidate.score = score(candidate)
            candidate.version += 1
            candidateScoreUpdates += 1
            group.candidateHeap.insert(GreedyCandidateHeapEntry(candidate))
            affectedGroups.insert(candidate.groupID)
        }
        for groupID in affectedGroups {
            if let group = groups[groupID] { publish(group) }
        }
    }
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
        coverageFraction(forCount: cells.count)
    }

    func coverageFraction(forCount count: Int) -> Double {
        guard !points.isEmpty else { return 0 }
        return min(Double(count) / Double(points.count), 1)
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

private func greedyCandidateEntryRanksBefore(
    _ lhs: GreedyCandidateHeapEntry,
    _ rhs: GreedyCandidateHeapEntry
) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    if lhs.uncoveredCellCount != rhs.uncoveredCellCount {
        return lhs.uncoveredCellCount > rhs.uncoveredCellCount
    }
    if lhs.unseenFilterCount != rhs.unseenFilterCount {
        return lhs.unseenFilterCount > rhs.unseenFilterCount
    }
    if lhs.fileSizeBytes != rhs.fileSizeBytes {
        return lhs.fileSizeBytes < rhs.fileSizeBytes
    }
    return lhs.identity < rhs.identity
}

private func greedyRootEntryRanksBefore(
    _ lhs: GreedyRootHeapEntry,
    _ rhs: GreedyRootHeapEntry
) -> Bool {
    if greedyCandidateEntryRanksBefore(lhs.candidate, rhs.candidate) { return true }
    if greedyCandidateEntryRanksBefore(rhs.candidate, lhs.candidate) { return false }
    return lhs.groupID.sortKey < rhs.groupID.sortKey
}
