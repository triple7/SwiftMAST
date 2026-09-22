import Foundation
import SwiftMAST

private struct Arguments {
    var target = "NGC 628"
    var radiusDegrees = 0.05
    var missions = ObservationMission.jwstAndHST
    var instruments: [String]?
    var filters: [String]?
    var candidateRows = 400
    var maxProducts = 5
    var maxProductMB = 70.0
    var maxTotalMB: Double?
    var targetCoverage = 0.80
    var minimumFilters = 3
    var coverageWeight: Double?
    var filterWeight: Double?
    var sizePenaltyExponent: Double?
    var gridDimension = 48
    var fetchHeaders = false
    var preset = "balanced"
    var outputPath = "greedy-science-product-report.json"
}

private struct ProductSummary: Codable {
    let observationID: String
    let mission: String
    let instrument: String
    let filters: String
    let fileSizeBytes: Int64?
    let footprintAreaSquareDegrees: Double?
    let dataURL: String
    let previewURL: String
    let hasFITSHeaderMetadata: Bool
}

private struct SelectionRunReport: Codable {
    let preset: String
    let targetAreaSquareDegrees: Double
    let coverageGridPointCount: Int
    let candidateCount: Int
    let eligibleCandidateCount: Int
    let observationGroupCount: Int
    let selectedObservationGroupCount: Int
    let branchCandidateCounts: [String: Int]
    let excludedCandidates: [GreedyScienceProductExclusion]
    let selectedProducts: [ProductSummary]
    let steps: [GreedyScienceProductSelectionStep]
    let coveredFraction: Double
    let coveragePercentage: Double
    let selectedFilters: [String]
    let totalSelectedSizeBytes: Int64
    let selectedSizeMiB: Double
    let budgetSkippedCandidateCount: Int
    let complexityMetrics: GreedyScienceProductSelectionComplexityMetrics
    let stopReason: GreedyScienceProductSelectionStopReason
}

private struct ComparisonReport: Codable {
    let target: String
    let radiusDegrees: Double
    let generatedAt: String
    let runs: [SelectionRunReport]
}

private let usage = """
Usage:
  swift run swiftmast-greedy-selection [options]

Options:
  --target NAME            Resolvable MAST target (default: NGC 628)
  --radius DEG             Search-cone radius (default: 0.05)
  --missions LIST          Comma-separated JWST,HST,PS1,GALEX,SWIFT,TESS (HST includes HLA)
  --instruments LIST       Optional comma-separated TAP instrument names
  --filters LIST           Optional comma-separated filter names
  --rows N                 TAP row limit per mission branch (default: 400)
  --max-products N         Maximum selected products (default: 5)
  --max-mb MB              Per-product size limit (default: 70)
  --max-total-mb MB        Optional aggregate size budget; omit for unlimited
  --coverage FRACTION      Desired target coverage from 0...1 (default: 0.80)
  --min-filters N          Desired distinct-filter count (default: 3)
  --coverage-weight N      Override the preset's marginal-coverage weight
  --filter-weight N        Override the preset's new-filter weight
  --size-penalty N         Override the preset's file-size exponent
  --grid N                 Coverage grid dimension (default: 48)
  --headers true|false     Read FITS headers after selection (default: false)
  --preset NAME            balanced, coverage, filters, smallest, or all (default: balanced)
  --output PATH            JSON comparison report path
  --help                   Show this help

`all` runs four end-to-end TAP selections. Use a single preset for the lightest
archive load and most direct timing.
"""

private func commaSeparated(_ value: String) -> [String] {
    value.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
}

private func parseArguments() throws -> Arguments {
    var parsed = Arguments()
    let values = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func value(after flag: String) throws -> String {
        guard index + 1 < values.count else {
            throw NSError(
                domain: "SwiftMASTGreedySelectionTool",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing value after \(flag)"]
            )
        }
        index += 1
        return values[index]
    }

    while index < values.count {
        let flag = values[index]
        switch flag {
        case "--help", "-h":
            print(usage)
            exit(0)
        case "--target": parsed.target = try value(after: flag)
        case "--radius": parsed.radiusDegrees = Double(try value(after: flag)) ?? parsed.radiusDegrees
        case "--missions":
            let requested = commaSeparated(try value(after: flag)).map { $0.uppercased() }
            parsed.missions = ObservationMission.allCases.filter { requested.contains($0.rawValue) }
        case "--instruments": parsed.instruments = commaSeparated(try value(after: flag))
        case "--filters": parsed.filters = commaSeparated(try value(after: flag))
        case "--rows": parsed.candidateRows = Int(try value(after: flag)) ?? parsed.candidateRows
        case "--max-products": parsed.maxProducts = Int(try value(after: flag)) ?? parsed.maxProducts
        case "--max-mb": parsed.maxProductMB = Double(try value(after: flag)) ?? parsed.maxProductMB
        case "--max-total-mb": parsed.maxTotalMB = Double(try value(after: flag))
        case "--coverage": parsed.targetCoverage = Double(try value(after: flag)) ?? parsed.targetCoverage
        case "--min-filters": parsed.minimumFilters = Int(try value(after: flag)) ?? parsed.minimumFilters
        case "--coverage-weight": parsed.coverageWeight = Double(try value(after: flag))
        case "--filter-weight": parsed.filterWeight = Double(try value(after: flag))
        case "--size-penalty": parsed.sizePenaltyExponent = Double(try value(after: flag))
        case "--grid": parsed.gridDimension = Int(try value(after: flag)) ?? parsed.gridDimension
        case "--headers": parsed.fetchHeaders = (try value(after: flag)).lowercased() == "true"
        case "--preset": parsed.preset = try value(after: flag).lowercased()
        case "--output": parsed.outputPath = try value(after: flag)
        default:
            throw NSError(
                domain: "SwiftMASTGreedySelectionTool",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown option: \(flag)"]
            )
        }
        index += 1
    }
    return parsed
}

private func selectionOptions(
    arguments: Arguments,
    preset: String
) -> GreedyScienceProductSelectionOptions {
    var coverageWeight = 0.65
    var filterWeight = 0.35
    var sizeExponent = 1.0

    switch preset {
    case "coverage":
        coverageWeight = 1.0
        filterWeight = 0.01
        sizeExponent = 0.25
    case "filters":
        coverageWeight = 0.05
        filterWeight = 1.0
        sizeExponent = 0.25
    case "smallest":
        coverageWeight = 0.50
        filterWeight = 0.50
        sizeExponent = 1.5
    default:
        break
    }

    coverageWeight = arguments.coverageWeight ?? coverageWeight
    filterWeight = arguments.filterWeight ?? filterWeight
    sizeExponent = arguments.sizePenaltyExponent ?? sizeExponent

    return GreedyScienceProductSelectionOptions(
        missions: arguments.missions,
        instruments: arguments.instruments,
        filterBands: arguments.filters,
        candidateRowLimit: arguments.candidateRows,
        maxSelectedProducts: arguments.maxProducts,
        maxProductSizeBytes: Int64(arguments.maxProductMB * 1_048_576),
        maxTotalSizeBytes: arguments.maxTotalMB.map { Int64($0 * 1_048_576) },
        targetCoverageFraction: arguments.targetCoverage,
        minimumDistinctFilters: arguments.minimumFilters,
        coverageWeight: coverageWeight,
        filterWeight: filterWeight,
        sizePenaltyExponent: sizeExponent,
        coverageGridDimension: arguments.gridDimension,
        fetchFITSHeadersForSelectedProducts: arguments.fetchHeaders
    )
}

private func runSelection(
    mast: SwiftMAST,
    arguments: Arguments,
    preset: String
) -> GreedyScienceProductSelectionResult {
    var selection: GreedyScienceProductSelectionResult?
    mast.selectScienceProductsUsingGreedyTAP(
        targetName: arguments.target,
        radiusDegrees: arguments.radiusDegrees,
        options: selectionOptions(arguments: arguments, preset: preset)
    ) {
        selection = $0
    }

    let deadline = Date().addingTimeInterval(300)
    while selection == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    guard let selection else {
        fputs("Timed out waiting for MAST selection.\n", stderr)
        exit(3)
    }
    return selection
}

private func printSelection(_ selection: GreedyScienceProductSelectionResult, preset: String) {
    print("\n[\(preset)] candidates=\(selection.candidateCount) eligible=\(selection.eligibleCandidateCount) groups=\(selection.observationGroupCount) selected=\(selection.selectedProducts.count)")
    print("coverage=\(String(format: "%.2f", selection.coveragePercentage))% gridPoints=\(selection.coverageGridPointCount) filters=\(selection.selectedFilters.joined(separator: ",")) sizeMB=\(String(format: "%.2f", selection.selectedSizeMiB)) stop=\(selection.stopReason.rawValue)")
    print("graph scoreUpdates=\(selection.complexityMetrics.candidateScoreUpdates) coverageEdges=\(selection.complexityMetrics.coverageEdgeVisits) filterEdges=\(selection.complexityMetrics.filterEdgeVisits) groupHeapPops=\(selection.complexityMetrics.groupHeapPops) fullRescans=\(selection.complexityMetrics.fullCandidateRescans) budgetSkipped=\(selection.budgetSkippedCandidateCount)")
    for step in selection.steps {
        print("  \(step.iteration). \(step.instrumentBranch) | \(step.observationID) | \(step.filters.joined(separator: "+")) | newCoverage=\(String(format: "%.4f", step.newCoverageFraction)) | newFilters=\(step.newFilterCount) | sizeMB=\(String(format: "%.2f", Double(step.fileSizeBytes) / 1_048_576)) | score=\(String(format: "%.6f", step.score))")
    }
}

do {
    let arguments = try parseArguments()
    let supportedPresets = ["balanced", "coverage", "filters", "smallest"]
    let presets = arguments.preset == "all" ? supportedPresets : [arguments.preset]
    guard presets.allSatisfy(supportedPresets.contains) else {
        throw NSError(
            domain: "SwiftMASTGreedySelectionTool",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Preset must be all, \(supportedPresets.joined(separator: ", "))"]
        )
    }

    let mast = SwiftMAST()
    var reports: [SelectionRunReport] = []
    for preset in presets {
        let selection = runSelection(mast: mast, arguments: arguments, preset: preset)
        printSelection(selection, preset: preset)
        reports.append(
            SelectionRunReport(
                preset: preset,
                targetAreaSquareDegrees: selection.targetAreaSquareDegrees,
                coverageGridPointCount: selection.coverageGridPointCount,
                candidateCount: selection.candidateCount,
                eligibleCandidateCount: selection.eligibleCandidateCount,
                observationGroupCount: selection.observationGroupCount,
                selectedObservationGroupCount: selection.selectedObservationGroupCount,
                branchCandidateCounts: selection.branchCandidateCounts,
                excludedCandidates: selection.excludedCandidates,
                selectedProducts: selection.selectedProducts.map {
                    ProductSummary(
                        observationID: $0.obs_id,
                        mission: $0.obs_collection,
                        instrument: $0.instrument_name,
                        filters: $0.filters,
                        fileSizeBytes: $0.dataURLSizeBytes,
                        footprintAreaSquareDegrees: $0.s_region_area,
                        dataURL: $0.dataURL,
                        previewURL: $0.jpegURL,
                        hasFITSHeaderMetadata: $0.fitsImageHeaderMetadata != nil
                    )
                },
                steps: selection.steps,
                coveredFraction: selection.coveredFraction,
                coveragePercentage: selection.coveragePercentage,
                selectedFilters: selection.selectedFilters,
                totalSelectedSizeBytes: selection.totalSelectedSizeBytes,
                selectedSizeMiB: selection.selectedSizeMiB,
                budgetSkippedCandidateCount: selection.budgetSkippedCandidateCount,
                complexityMetrics: selection.complexityMetrics,
                stopReason: selection.stopReason
            )
        )
    }

    let report = ComparisonReport(
        target: arguments.target,
        radiusDegrees: arguments.radiusDegrees,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        runs: reports
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputURL = URL(fileURLWithPath: arguments.outputPath)
    try encoder.encode(report).write(to: outputURL, options: .atomic)
    print("\nWrote \(outputURL.path)")
} catch {
    fputs("\(error.localizedDescription)\n\n\(usage)\n", stderr)
    exit(2)
}
