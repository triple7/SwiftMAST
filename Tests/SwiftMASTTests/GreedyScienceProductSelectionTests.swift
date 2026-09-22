import SwiftQValue
import XCTest

@testable import SwiftMAST

final class GreedyScienceProductSelectionTests: XCTestCase {
    func testGreedySelectionAddsNewCoverageAndFilters() {
        let mast = SwiftMAST()
        let products = [
            makeProduct(
                id: "large-blue",
                filter: "F435W",
                sizeMB: 20,
                region: "CIRCLE ICRS 10.0 0.0 0.035"
            ),
            makeProduct(
                id: "small-blue",
                filter: "F435W",
                sizeMB: 5,
                region: "CIRCLE ICRS 10.0 0.0 0.035"
            ),
            makeProduct(
                id: "red-offset",
                filter: "F814W",
                sizeMB: 10,
                region: "CIRCLE ICRS 10.03 0.0 0.035"
            ),
        ]
        let options = GreedyScienceProductSelectionOptions(
            maxSelectedProducts: 3,
            targetCoverageFraction: 0.50,
            minimumDistinctFilters: 2,
            coverageGridDimension: 40,
            fetchFITSHeadersForSelectedProducts: false
        )

        let result = mast.selectScienceProductsGreedily(
            from: [makeGroup(products)],
            targetName: "Test target",
            targetRA: 10,
            targetDec: 0,
            radiusDegrees: 0.05,
            options: options
        )

        XCTAssertEqual(result.selectedProducts.first?.obs_id, "small-blue")
        XCTAssertEqual(Set(result.selectedProducts.map(\.obs_id)), ["small-blue", "red-offset"])
        XCTAssertEqual(result.selectedFilters, ["F435W", "F814W"])
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertGreaterThan(result.steps[1].newCoverageFraction, 0)
        XCTAssertEqual(result.steps[1].newFilterCount, 1)
        XCTAssertEqual(result.stopReason, .targetSatisfied)
        XCTAssertEqual(result.branchCandidateCounts, ["JWST": 3])
        XCTAssertEqual(result.observationGroupCount, 3)
        XCTAssertEqual(result.selectedObservationGroupCount, 2)
        XCTAssertGreaterThan(result.targetAreaSquareDegrees, 0)
        XCTAssertGreaterThan(result.coverageGridPointCount, 0)
        XCTAssertEqual(result.complexityMetrics.fullCandidateRescans, 0)
        XCTAssertGreaterThan(result.complexityMetrics.groupHeapPops, 0)
    }

    func testGreedySelectionRejectsMissingCompulsoryFieldsAndOversizedProducts() {
        let mast = SwiftMAST()
        let products = [
            makeProduct(id: "valid", filter: "F200W", sizeMB: 10),
            makeProduct(id: "missing-size", filter: "F356W", sizeMB: nil),
            makeProduct(id: "missing-region", filter: "F444W", sizeMB: 10, region: ""),
            makeProduct(id: "missing-filter", filter: "", sizeMB: 10),
            makeProduct(id: "too-large", filter: "F090W", sizeMB: 80),
        ]
        let options = GreedyScienceProductSelectionOptions(
            maxSelectedProducts: 5,
            maxProductSizeBytes: 70 * 1_048_576,
            targetCoverageFraction: 1,
            minimumDistinctFilters: 5,
            fetchFITSHeadersForSelectedProducts: false
        )

        let result = mast.selectScienceProductsGreedily(
            from: [makeGroup(products)],
            targetName: "Test target",
            targetRA: 10,
            targetDec: 0,
            radiusDegrees: 0.05,
            options: options
        )

        XCTAssertEqual(result.candidateCount, 5)
        XCTAssertEqual(result.eligibleCandidateCount, 1)
        XCTAssertEqual(result.selectedProducts.map(\.obs_id), ["valid"])
        XCTAssertEqual(
            Set(result.excludedCandidates.map(\.reason)),
            [.missingFileSize, .missingFootprint, .missingFilter, .exceedsProductSizeLimit]
        )
    }

    func testGreedySelectionHonorsAggregateSizeBudget() {
        let mast = SwiftMAST()
        let products = [
            makeProduct(id: "blue", filter: "F435W", sizeMB: 8),
            makeProduct(id: "green", filter: "F555W", sizeMB: 8),
            makeProduct(id: "red", filter: "F814W", sizeMB: 8),
        ]
        let options = GreedyScienceProductSelectionOptions(
            maxSelectedProducts: 3,
            maxTotalSizeBytes: 12 * 1_048_576,
            targetCoverageFraction: 1,
            minimumDistinctFilters: 3,
            fetchFITSHeadersForSelectedProducts: false
        )

        let result = mast.selectScienceProductsGreedily(
            from: [makeGroup(products)],
            targetName: "Test target",
            targetRA: 10,
            targetDec: 0,
            radiusDegrees: 0.05,
            options: options
        )

        XCTAssertEqual(result.selectedProducts.count, 1)
        XCTAssertEqual(result.totalSelectedSizeBytes, 8 * 1_048_576)
        XCTAssertEqual(result.budgetSkippedCandidateCount, 2)
        XCTAssertEqual(result.stopReason, .noAdditionalBenefit)
    }

    func testHierarchicalTraversalIsDeterministicAndUpdatesOnlyGraphNeighbors() {
        let mast = SwiftMAST()
        let products = [
            makeProduct(
                id: "jw00001-o001_t001_nircam_f200w",
                filter: "F200W",
                sizeMB: 6,
                region: "CIRCLE ICRS 10.0 0.0 0.03"
            ),
            makeProduct(
                id: "jw00001-o001_t001_nircam_f356w",
                filter: "F356W",
                sizeMB: 7,
                region: "CIRCLE ICRS 10.0 0.0 0.03"
            ),
            makeProduct(
                id: "jw00001-o002_t001_nircam_f444w",
                filter: "F444W",
                sizeMB: 8,
                region: "CIRCLE ICRS 10.035 0.0 0.03"
            ),
            makeProduct(
                id: "jw00001-o002_t001_nircam_f200w",
                filter: "F200W",
                sizeMB: 9,
                region: "CIRCLE ICRS 10.035 0.0 0.03"
            ),
        ]
        let options = GreedyScienceProductSelectionOptions(
            maxSelectedProducts: 4,
            targetCoverageFraction: 0.75,
            minimumDistinctFilters: 3,
            coverageGridDimension: 40,
            fetchFITSHeadersForSelectedProducts: false
        )

        let forward = mast.selectScienceProductsGreedily(
            from: [makeGroup(products)],
            targetName: "Test target",
            targetRA: 10,
            targetDec: 0,
            radiusDegrees: 0.05,
            options: options
        )
        let reversed = mast.selectScienceProductsGreedily(
            from: [makeGroup(Array(products.reversed()))],
            targetName: "Test target",
            targetRA: 10,
            targetDec: 0,
            radiusDegrees: 0.05,
            options: options
        )

        XCTAssertEqual(
            forward.selectedProducts.map(\.dataURL),
            reversed.selectedProducts.map(\.dataURL)
        )
        XCTAssertEqual(forward.observationGroupCount, 2)
        XCTAssertEqual(forward.selectedObservationGroupCount, 2)
        XCTAssertEqual(forward.complexityMetrics.fullCandidateRescans, 0)
        XCTAssertGreaterThan(forward.complexityMetrics.candidateScoreUpdates, 0)
        XCTAssertGreaterThan(forward.complexityMetrics.coverageEdgeVisits, 0)
        XCTAssertGreaterThan(forward.complexityMetrics.filterEdgeVisits, 0)
    }

    private func makeGroup(_ products: [CoamResult]) -> ObservationGroup {
        ObservationGroup(
            mission: "JWST",
            observationKey: "jw-test-o001_t001_nircam",
            instrument: "NIRCAM/IMAGE",
            products: products
        )
    }

    private func makeProduct(
        id: String,
        filter: String,
        sizeMB: Int?,
        region: String = "CIRCLE ICRS 10.0 0.0 0.04"
    ) -> CoamResult {
        CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: "mast:TEST/product/\(id)_i2d.fits",
            dataproduct_type: "IMAGE",
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: filter,
            instrument_name: "NIRCAM/IMAGE",
            intentType: "science",
            jpegURL: "",
            mtFlag: false,
            objID: 0,
            obs_collection: "JWST",
            obs_id: id,
            obs_title: "",
            obsid: 1,
            project: "",
            proposal_id: "",
            proposal_pi: "",
            proposal_type: "",
            provenance_name: "",
            s_dec: .float(0),
            s_ra: .float(10),
            s_region: region,
            sequence_number: 0,
            srcDen: 0,
            t_exptime: 100,
            t_max: 0,
            t_min: 0,
            t_obs_release: 0,
            target_classification: "",
            target_name: "Test target",
            wavelength_region: "",
            dataURLSizeBytes: sizeMB.map { Int64($0 * 1_048_576) },
            productFilename: "\(id)_i2d.fits",
            artifactContentType: "application/fits"
        )
    }
}
