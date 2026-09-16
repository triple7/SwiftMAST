import SwiftQValue
import XCTest

@testable import SwiftMAST

final class MASTTapADQLTests: XCTestCase {
    override func tearDown() {
        SwiftMAST().resetQueryCache()
        super.tearDown()
    }

    func testTargetCompositeTAPQueryUsesNarrowProfileAndScienceFITSSuffixes() {
        let mast = SwiftMAST()
        let query = mast.caomObservationGroupsTAPQuery(
            ra: 24.174,
            dec: 15.783,
            radius: 0.05,
            collections: ObservationMission.jwstAndHST.flatMap(\.collectionNames),
            instruments: nil,
            filterBands: ["F200W"],
            calibLevels: ["3", "4"],
            dataProductTypes: ["IMAGE"],
            pageSize: 25,
            columnProfile: .targetCompositeSelection,
            productKinds: [.scienceFITS]
        )

        XCTAssertTrue(query.contains("SELECT TOP 25"))
        XCTAssertTrue(query.contains("o.obsid"))
        XCTAssertTrue(query.contains("o.em_min"))
        XCTAssertTrue(query.contains("o.em_max"))
        XCTAssertTrue(query.contains("o.wavelength_region"))
        XCTAssertTrue(query.contains("o.t_exptime"))
        XCTAssertTrue(query.contains("o.t_min"))
        XCTAssertTrue(query.contains("o.t_max"))
        XCTAssertTrue(query.contains("o.project"))
        XCTAssertTrue(query.contains("o.provenance_name"))
        XCTAssertTrue(query.contains("p.posdimension1"))
        XCTAssertTrue(query.contains("p.posdimension2"))
        XCTAssertTrue(query.contains("p.possamplesize"))
        XCTAssertTrue(query.contains("COALESCE(a.datauri, o.dataurl)"))
        XCTAssertTrue(query.contains("COALESCE(p.previewuri, o.jpegurl)"))
        XCTAssertTrue(query.contains("a.productfilename"))
        XCTAssertTrue(query.contains("a.contenttype"))
        XCTAssertTrue(query.contains("a.contentlength"))
        XCTAssertTrue(query.contains("%_i2d.fits"))
        XCTAssertTrue(query.contains("%_drz.fits"))
        XCTAssertTrue(query.contains("%_drc.fits"))
        XCTAssertTrue(query.contains("UPPER(o.filters) LIKE '%F200W%'"))
        XCTAssertFalse(query.contains("o.proposal_pi"))
        XCTAssertFalse(query.contains("o.obs_title"))
        XCTAssertFalse(query.contains("o.mtflag"))
        XCTAssertFalse(query.contains("o.srcden"))
        XCTAssertFalse(query.contains("o.target_classification"))
        XCTAssertFalse(query.contains("p.posresolution"))
        XCTAssertFalse(query.contains("p.posboundsstcs"))
        XCTAssertFalse(query.contains("SELECT TOP 25\n                o.calib_level"))
    }

    func testShortlistedHeaderPolicyLimitsProductsPerFilter() {
        let mast = SwiftMAST()
        let products = [
            makeTapCoamResult(obsID: "large-f200w", filter: "F200W", size: 300),
            makeTapCoamResult(obsID: "small-f200w", filter: "F200W", size: 100),
            makeTapCoamResult(obsID: "small-f356w", filter: "F356W", size: 120),
            makeTapCoamResult(obsID: "large-f356w", filter: "F356W", size: 450),
        ]

        let shortlisted = mast.productsForHeaderPolicy(
            products,
            headerFetchPolicy: .shortlistedOnly(maxPerFilter: 1)
        )

        XCTAssertEqual(shortlisted.map(\.obs_id), ["small-f200w", "small-f356w"])
    }

    func testTargetCompositeTAPRowMapsSelectedColumnsInProjectionOrder() throws {
        let row = [
            "101", "jw-observation", "JWST", "NIRCAM/IMAGE", "NGC 628", "F200W",
            "3", "IMAGE", "science", "PUBLIC", "24.174", "15.783",
            "POLYGON ICRS 24.1 15.7 24.2 15.7 24.2 15.8 24.1 15.8", "1234.5",
            "60000.25", "60000.75", "1700", "2300", "Infrared", "2739", "JWST", "CALJWST",
            "4096", "2048", "0.031", "mast:JWST/product/example_i2d.fits",
            "mast:JWST/product/example_i2d.jpg", "example_i2d.fits",
            "application/fits", "73400320",
        ].map(QValue.init(value:))

        let result = try XCTUnwrap(
            SwiftMAST().coamResultFromTargetCompositeTAPRow(row)
        )

        XCTAssertEqual(result.obsid, 101)
        XCTAssertEqual(result.obs_id, "jw-observation")
        XCTAssertEqual(result.t_exptime, 1234.5, accuracy: 0.0001)
        XCTAssertEqual(result.t_min, 60_000.25, accuracy: 0.0001)
        XCTAssertEqual(result.t_max, 60_000.75, accuracy: 0.0001)
        XCTAssertEqual(result.em_min, 1700)
        XCTAssertEqual(result.em_max, 2300)
        XCTAssertEqual(result.proposal_id, "2739")
        XCTAssertEqual(result.project, "JWST")
        XCTAssertEqual(result.provenance_name, "CALJWST")
        XCTAssertEqual(result.jpegURL, "mast:JWST/product/example_i2d.jpg")
        XCTAssertEqual(result.productFilename, "example_i2d.fits")
        XCTAssertEqual(result.artifactContentType, "application/fits")
        XCTAssertEqual(result.positionDimension1, 4096)
        XCTAssertEqual(result.positionDimension2, 2048)
        XCTAssertEqual(result.positionSampleSize ?? 0, 0.031, accuracy: 0.0001)
        XCTAssertEqual(result.dataURLSizeBytes, 73_400_320)
    }

    func testMASTTapAcceptsDirectADQLSelectQuery() {
        let mast = SwiftMAST()
        mast.resetQueryCache()

        let query = """
            SELECT column_name, datatype, description
            FROM TAP_SCHEMA.columns
            WHERE table_name = 'dbo.catalogrecord'
            AND column_name IN ('ID', 'ra', 'dec')
            ORDER BY column_name
            """

        let finished = expectation(description: "MAST TAP ADQL query returns schema rows")
        mast.queryMASTTap(
            selectQuery: query,
            table: .tap_schema_columns,
            fields: [],
            parameters: []
        ) { response in
            let rows = response.data.q2dArray
            XCTAssertEqual(rows.count, 3)

            let columnNames = Set(rows.compactMap { $0.first?.stringValue.lowercased() })
            XCTAssertEqual(columnNames, ["dec", "id", "ra"])

            XCTAssertTrue(rows.allSatisfy { $0.count == 3 })
            XCTAssertTrue(rows.allSatisfy { !$0[1].stringValue.isEmpty })
            finished.fulfill()
        }

        wait(for: [finished], timeout: 15)

        XCTAssertTrue(
            mast.networkTransactions.contains { $0.label == "MAST TAP" },
            "Expected the direct ADQL TAP request to be recorded in the network timeline."
        )
    }

    func testGetObservationGroupsUsingTAPFetchesFITSFileSizes() {
        let mast = SwiftMAST()
        mast.resetQueryCache()

        let finished = expectation(description: "TAP observation groups return FITS products")
        let start = Date()
        mast.getObservationGroupsUsingTAP(
            targetName: "NGC 628",
            ra: 24.174,
            dec: 15.783,
            radius: 0.05,
            missions: ObservationMission.hstOnly,
            pageSize: 4,
            limit: 2,
            includeFITSImageHeaderMetadata: false
        ) { groups in
            let elapsed = Date().timeIntervalSince(start)
            let products = groups.flatMap(\.products)
            print("TAP observation grouping returned \(groups.count) groups / \(products.count) products in \(String(format: "%.3f", elapsed))s")

            XCTAssertFalse(groups.isEmpty)
            XCTAssertFalse(products.isEmpty)
            XCTAssertTrue(products.allSatisfy { !$0.dataURL.isEmpty })
            XCTAssertTrue(products.allSatisfy { !$0.s_region.isEmpty })
            XCTAssertTrue(
                products.contains { ($0.preferredDownloadSizeBytes ?? 0) > 0 },
                "Expected TAP artifact contentlength to populate FITS file size."
            )
            finished.fulfill()
        }

        wait(for: [finished], timeout: 30)

        let tapLog = mast.sysLog.first { $0.metadata["event"] == "tapObservationSearchFinished" }
        XCTAssertNotNil(tapLog?.durationSeconds)
    }

    func testObservationGroupsUsingTAPComparedWithMashupTiming() {
        let tapMast = SwiftMAST()
        tapMast.resetQueryCache()
        let mashupMast = SwiftMAST()
        mashupMast.resetQueryCache()

        var tapProductCount = 0
        var mashupProductCount = 0
        var tapElapsed: TimeInterval = 0
        var mashupElapsed: TimeInterval = 0

        let tapFinished = expectation(description: "TAP observation grouping returns")
        let tapStart = Date()
        tapMast.getObservationGroupsUsingTAP(
            targetName: "NGC 628",
            ra: 24.174,
            dec: 15.783,
            radius: 0.05,
            missions: ObservationMission.hstOnly,
            pageSize: 3,
            limit: 1,
            includeFITSImageHeaderMetadata: false
        ) { groups in
            tapElapsed = Date().timeIntervalSince(tapStart)
            tapProductCount = groups.reduce(0) { $0 + $1.products.count }
            tapFinished.fulfill()
        }
        wait(for: [tapFinished], timeout: 30)

        let mashupFinished = expectation(description: "Mashup observation grouping returns")
        let mashupStart = Date()
        mashupMast.getObservationGroups(
            targetName: "NGC 628",
            ra: 24.174,
            dec: 15.783,
            radius: 0.05,
            mission: .hst,
            pageSize: 3,
            limit: 1
        ) { groups in
            mashupElapsed = Date().timeIntervalSince(mashupStart)
            mashupProductCount = groups.reduce(0) { $0 + $1.products.count }
            mashupFinished.fulfill()
        }
        wait(for: [mashupFinished], timeout: 90)

        print(
            "Observation grouping comparison: TAP \(tapProductCount) products in \(String(format: "%.3f", tapElapsed))s; Mashup \(mashupProductCount) products in \(String(format: "%.3f", mashupElapsed))s"
        )

        XCTAssertGreaterThan(tapProductCount, 0)
        XCTAssertGreaterThan(mashupProductCount, 0)
        XCTAssertTrue(tapMast.networkTransactions.contains { $0.label == "MAST TAP" })
        XCTAssertTrue(
            mashupMast.networkTransactions.contains {
                $0.label == "MAST API \(Service.Mast_Caom_Filtered_Position.id)"
            }
        )
    }

    func testJWSTFootprintHSTComparisonWritesCSV() throws {
        let csvURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("observation_group_tap_comparison.csv")
        let targetName = "NGC 628"
        let limits = [10, 50, 100]
        var summaries: [ObservationComparisonSummary] = []

        for limit in limits {
            let sourceMashup = runCoordinateObservationGroups(
                targetName: targetName,
                method: "mashup",
                phase: "source_jwst_selection",
                limit: limit,
                missions: ObservationMission.jwstOnly,
                timeout: 360
            )
            summaries.append(sourceMashup)

            let sourceTAP = runCoordinateObservationGroups(
                targetName: targetName,
                method: "tap",
                phase: "source_jwst_selection",
                limit: limit,
                missions: ObservationMission.jwstOnly,
                timeout: 120
            )
            summaries.append(sourceTAP)

            let sourceSelection = try XCTUnwrap(
                selectSourceFootprint(from: sourceMashup.groups) ?? selectSourceFootprint(from: sourceTAP.groups),
                "Expected a JWST source footprint for limit \(limit)."
            )

            let tapFootprint = runFootprintObservationGroups(
                targetName: targetName,
                method: "tap",
                limit: limit,
                source: sourceSelection,
                timeout: 180
            )
            summaries.append(tapFootprint)

            let mashupFootprint = runFootprintObservationGroups(
                targetName: targetName,
                method: "mashup",
                limit: limit,
                source: sourceSelection,
                timeout: 420
            )
            summaries.append(mashupFootprint)

            print(
                "Limit \(limit): source Mashup \(String(format: "%.3f", sourceMashup.durationSeconds))s / source TAP \(String(format: "%.3f", sourceTAP.durationSeconds))s / HST TAP \(String(format: "%.3f", tapFootprint.durationSeconds))s / HST Mashup \(String(format: "%.3f", mashupFootprint.durationSeconds))s"
            )
        }

        let csv = ObservationComparisonSummary.csv(summaries)
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        print("Wrote observation group TAP comparison CSV: \(csvURL.path)")

        XCTAssertEqual(summaries.count, limits.count * 4)
        XCTAssertTrue(summaries.allSatisfy { !$0.groups.isEmpty })
        XCTAssertTrue(FileManager.default.fileExists(atPath: csvURL.path))
    }

    private func runCoordinateObservationGroups(
        targetName: String,
        method: String,
        phase: String,
        limit: Int,
        missions: [ObservationMission],
        timeout: TimeInterval
    ) -> ObservationComparisonSummary {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        var groups: [ObservationGroup] = []
        var elapsed: TimeInterval = 0
        let finished = expectation(description: "\(method) \(phase) limit \(limit)")
        let start = Date()

        if method == "tap" {
            mast.getObservationGroupsUsingTAP(
                targetName: targetName,
                ra: 24.174,
                dec: 15.783,
                radius: 0.05,
                missions: missions,
                pageSize: limit,
                limit: limit,
                includeFITSImageHeaderMetadata: false
            ) { output in
                elapsed = Date().timeIntervalSince(start)
                groups = output
                finished.fulfill()
            }
        } else {
            mast.getObservationGroups(
                targetName: targetName,
                ra: 24.174,
                dec: 15.783,
                radius: 0.05,
                missions: missions,
                pageSize: limit,
                limit: limit
            ) { output in
                elapsed = Date().timeIntervalSince(start)
                groups = output
                finished.fulfill()
            }
        }

        wait(for: [finished], timeout: timeout)
        return ObservationComparisonSummary(
            target: targetName,
            limit: limit,
            phase: phase,
            method: method,
            durationSeconds: elapsed,
            groups: groups,
            networkTransactions: mast.networkTransactions,
            source: nil,
            notes: "ra=24.174;dec=15.783;radius=0.05;pageSize=\(limit);limit=\(limit)"
        )
    }

    private func runFootprintObservationGroups(
        targetName: String,
        method: String,
        limit: Int,
        source: ObservationSourceFootprint,
        timeout: TimeInterval
    ) -> ObservationComparisonSummary {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        var groups: [ObservationGroup] = []
        var elapsed: TimeInterval = 0
        let finished = expectation(description: "\(method) HST footprint limit \(limit)")
        let start = Date()

        if method == "tap" {
            mast.getObservationGroupsUsingTAP(
                targetName: targetName,
                spaceRegion: source.product.s_region,
                containment: .footprintIntersects,
                missions: ObservationMission.hstOnly,
                pageSize: limit,
                limit: limit,
                includeFITSImageHeaderMetadata: false
            ) { output in
                elapsed = Date().timeIntervalSince(start)
                groups = output
                finished.fulfill()
            }
        } else {
            mast.getObservationGroups(
                targetName: targetName,
                spaceRegion: source.product.s_region,
                containment: .footprintIntersects,
                missions: ObservationMission.hstOnly,
                pageSize: limit,
                limit: limit
            ) { output in
                elapsed = Date().timeIntervalSince(start)
                groups = output
                finished.fulfill()
            }
        }

        wait(for: [finished], timeout: timeout)
        return ObservationComparisonSummary(
            target: targetName,
            limit: limit,
            phase: "hst_within_jwst_footprint",
            method: method,
            durationSeconds: elapsed,
            groups: groups,
            networkTransactions: mast.networkTransactions,
            source: source,
            notes: "containment=footprintIntersects;pageSize=\(limit);limit=\(limit)"
        )
    }

    private func selectSourceFootprint(from groups: [ObservationGroup]) -> ObservationSourceFootprint? {
        for group in groups {
            if let product = group.products.first(where: { !$0.s_region.isEmpty }) {
                return ObservationSourceFootprint(group: group, product: product)
            }
        }
        return nil
    }

    private func makeTapCoamResult(
        obsID: String,
        filter: String,
        size: Int64
    ) -> CoamResult {
        CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: "mast:TEST/product/\(obsID)_i2d.fits",
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
            obs_id: obsID,
            obs_title: "",
            obsid: 1,
            project: "",
            proposal_id: "",
            proposal_pi: "",
            proposal_type: "",
            provenance_name: "",
            s_dec: .float(15.783),
            s_ra: .float(24.174),
            s_region: "",
            sequence_number: 0,
            srcDen: 0,
            t_exptime: 100,
            t_max: 0,
            t_min: 0,
            t_obs_release: 0,
            target_classification: "",
            target_name: "NGC 628",
            wavelength_region: "",
            dataURLSizeBytes: size
        )
    }
}

private extension QValue {
    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .float(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        }
    }
}

private struct ObservationSourceFootprint {
    let group: ObservationGroup
    let product: CoamResult
}

private struct ObservationComparisonSummary {
    let target: String
    let limit: Int
    let phase: String
    let method: String
    let durationSeconds: TimeInterval
    let groups: [ObservationGroup]
    let networkTransactions: [MASTNetworkTransaction]
    let source: ObservationSourceFootprint?
    let notes: String

    var products: [CoamResult] {
        groups.flatMap(\.products)
    }

    var productKeys: Set<String> {
        Set(products.map { "\($0.obs_collection)|\($0.obs_id)|\($0.instrument_name)|\($0.filters)" })
    }

    var normalizedProductKeys: Set<String> {
        Set(products.map { "\(Self.normalizedObservationID($0.obs_id))|\(Self.normalizedInstrument($0.instrument_name))|\(Self.normalizedFilters($0.filters))" })
    }

    var groupKeys: Set<String> {
        Set(groups.map { "\($0.mission)|\($0.observationKey)|\($0.instrument)" })
    }

    var instruments: Set<String> {
        Set(products.map(\.instrument_name).filter { !$0.isEmpty })
    }

    var filters: Set<String> {
        Set(products.map(\.filters).filter { !$0.isEmpty })
    }

    var networkLabels: [String] {
        Array(Set(networkTransactions.map(\.label))).sorted()
    }

    var totalNetworkDuration: TimeInterval {
        networkTransactions.reduce(0) { $0 + $1.durationSeconds }
    }

    var productsPerSecond: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(products.count) / durationSeconds
    }

    var sourceRegionArea: Double? {
        source?.product.s_region_area
    }

    static func csv(_ summaries: [ObservationComparisonSummary]) -> String {
        let header = [
            "target",
            "limit",
            "phase",
            "method",
            "counterpart_method",
            "source_group_key",
            "source_product_obs_id",
            "source_product_filter",
            "source_product_instrument",
            "source_s_region_area_deg2",
            "requested_page_size",
            "requested_limit",
            "duration_seconds",
            "groups",
            "products",
            "products_per_second",
            "products_with_file_size",
            "products_with_file_size_percent",
            "products_with_s_region",
            "products_with_s_region_percent",
            "products_with_wcs_metadata",
            "products_with_wcs_metadata_percent",
            "network_transactions",
            "network_total_duration_seconds",
            "network_avg_duration_seconds",
            "network_slowest_label",
            "network_slowest_duration_seconds",
            "network_transaction_duration_sample_seconds",
            "network_labels",
            "raw_overlap_with_other_products",
            "raw_only_this_method_products",
            "raw_missing_from_this_method_products",
            "normalized_overlap_with_other_products",
            "normalized_only_this_method_products",
            "normalized_missing_from_this_method_products",
            "unique_instruments",
            "unique_filters",
            "group_keys",
            "product_keys_sample",
            "normalized_product_keys_sample",
            "notes",
        ].joined(separator: ",")

        let rows = summaries.map { summary -> String in
            let counterpart = summaries.first {
                $0.limit == summary.limit
                    && $0.phase == summary.phase
                    && $0.method != summary.method
            }
            let counterpartProductKeys = counterpart?.productKeys ?? []
            let overlap = summary.productKeys.intersection(counterpartProductKeys).count
            let onlyThis = summary.productKeys.subtracting(counterpartProductKeys).count
            let missingThis = counterpartProductKeys.subtracting(summary.productKeys).count
            let counterpartNormalizedProductKeys = counterpart?.normalizedProductKeys ?? []
            let normalizedOverlap = summary.normalizedProductKeys.intersection(counterpartNormalizedProductKeys).count
            let normalizedOnlyThis = summary.normalizedProductKeys.subtracting(counterpartNormalizedProductKeys).count
            let normalizedMissingThis = counterpartNormalizedProductKeys.subtracting(summary.normalizedProductKeys).count
            let avgNetworkDuration =
                summary.networkTransactions.isEmpty
                ? 0 : summary.totalNetworkDuration / Double(summary.networkTransactions.count)
            let fileSizeCount = summary.products.filter { ($0.preferredDownloadSizeBytes ?? 0) > 0 }.count
            let sRegionCount = summary.products.filter { !$0.s_region.isEmpty }.count
            let wcsCount = summary.products.filter { $0.fitsImageHeaderMetadata != nil }.count
            let slowestNetworkTransaction = summary.networkTransactions.max {
                $0.durationSeconds < $1.durationSeconds
            }
            let networkDurationSample = summary.networkTransactions
                .sorted { $0.durationSeconds > $1.durationSeconds }
                .prefix(12)
                .map { "\($0.label)=\(String(format: "%.3f", $0.durationSeconds))" }
                .joined(separator: "|")
            let values: [String] = [
                summary.target,
                String(summary.limit),
                summary.phase,
                summary.method,
                counterpart?.method ?? "",
                summary.source?.group.observationKey ?? "",
                summary.source?.product.obs_id ?? "",
                summary.source?.product.filters ?? "",
                summary.source?.product.instrument_name ?? "",
                summary.sourceRegionArea.map { String(format: "%.8f", $0) } ?? "",
                String(summary.limit),
                String(summary.limit),
                String(format: "%.3f", summary.durationSeconds),
                String(summary.groups.count),
                String(summary.products.count),
                String(format: "%.3f", summary.productsPerSecond),
                String(fileSizeCount),
                Self.percent(fileSizeCount, of: summary.products.count),
                String(sRegionCount),
                Self.percent(sRegionCount, of: summary.products.count),
                String(wcsCount),
                Self.percent(wcsCount, of: summary.products.count),
                String(summary.networkTransactions.count),
                String(format: "%.3f", summary.totalNetworkDuration),
                String(format: "%.3f", avgNetworkDuration),
                slowestNetworkTransaction?.label ?? "",
                slowestNetworkTransaction.map { String(format: "%.3f", $0.durationSeconds) } ?? "",
                networkDurationSample,
                summary.networkLabels.joined(separator: "|"),
                counterpart == nil ? "" : String(overlap),
                counterpart == nil ? "" : String(onlyThis),
                counterpart == nil ? "" : String(missingThis),
                counterpart == nil ? "" : String(normalizedOverlap),
                counterpart == nil ? "" : String(normalizedOnlyThis),
                counterpart == nil ? "" : String(normalizedMissingThis),
                summary.instruments.sorted().joined(separator: "|"),
                summary.filters.sorted().joined(separator: "|"),
                summary.groupKeys.sorted().joined(separator: "|"),
                summary.productKeys.sorted().prefix(12).joined(separator: "|"),
                summary.normalizedProductKeys.sorted().prefix(12).joined(separator: "|"),
                summary.notes,
            ]
            return values.map(csvEscape).joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func normalizedObservationID(_ value: String) -> String {
        let lowercased = value.lowercased()
        guard lowercased.hasPrefix("hst_") else {
            return lowercased
        }

        let parts = lowercased.split(separator: "_", omittingEmptySubsequences: false)
        guard let last = parts.last, last.range(of: #"^[a-z][a-z0-9]{5,}$"#, options: .regularExpression) != nil else {
            return lowercased
        }
        return parts.dropLast().joined(separator: "_")
    }

    private static func normalizedInstrument(_ value: String) -> String {
        value.lowercased()
    }

    private static func normalizedFilters(_ value: String) -> String {
        value
            .lowercased()
            .split(separator: ";")
            .map(String.init)
            .sorted()
            .joined(separator: ";")
    }

    private static func percent(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "0.0" }
        return String(format: "%.1f", Double(count) / Double(total) * 100)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
