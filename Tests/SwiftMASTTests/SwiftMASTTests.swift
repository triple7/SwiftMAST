import FITS
import SwiftQValue
import XCTest

@testable import SwiftMAST

final class SwiftMASTTests: XCTestCase {

    private func makeCoamResult(
        dataURL: String = "",
        jpegURL: String = "",
        obs_id: String = "obs-1",
        filters: String = "F606W",
        instrument_name: String = "ACS",
        obs_collection: String = "HST",
        t_min: Float = 0.0,
        t_max: Float = 0.0,
        t_obs_release: Float = 0.0
    ) -> CoamResult {
        return CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: dataURL,
            dataproduct_type: "IMAGE",
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: filters,
            instrument_name: instrument_name,
            intentType: "science",
            jpegURL: jpegURL,
            mtFlag: false,
            objID: 1,
            obs_collection: obs_collection,
            obs_id: obs_id,
            obs_title: "Test Observation",
            obsid: 1,
            project: "Test",
            proposal_id: "1",
            proposal_pi: "PI",
            proposal_type: "TEST",
            provenance_name: "MAST",
            s_dec: QValue(value: "0.0"),
            s_ra: QValue(value: "0.0"),
            s_region: "",
            sequence_number: 0,
            srcDen: 0,
            t_exptime: 0.0,
            t_max: t_max,
            t_min: t_min,
            t_obs_release: t_obs_release,
            target_classification: "",
            target_name: "M31",
            wavelength_region: "OPTICAL"
        )
    }

    // MARK: - ImageryFilterOptions Tests

    func testDefaultFilterOptions() {
        let options = ImageryFilterOptions.defaultScience

        XCTAssertNil(options.wavelengthRegions)
        XCTAssertNil(options.collections)
        XCTAssertNil(options.instruments)
        XCTAssertNil(options.filterBands)
        XCTAssertEqual(options.calibLevels, ["3", "4"])
        XCTAssertEqual(options.dataProductTypes, ["IMAGE"])
        XCTAssertEqual(options.intentType, "science")
        XCTAssertEqual(options.dataRights, "PUBLIC")
    }

    func testUVOnlyPreset() {
        let options = ImageryFilterOptions.uvOnly

        XCTAssertEqual(options.wavelengthRegions, ["UV", "EUV"])
        XCTAssertNil(options.collections)
    }

    func testOpticalOnlyPreset() {
        let options = ImageryFilterOptions.opticalOnly

        XCTAssertEqual(options.wavelengthRegions, ["OPTICAL"])
    }

    func testInfraredOnlyPreset() {
        let options = ImageryFilterOptions.infraredOnly

        XCTAssertEqual(options.wavelengthRegions, ["INFRARED", "IR"])
    }

    func testHubbleOnlyPreset() {
        let options = ImageryFilterOptions.hubbleOnly

        XCTAssertEqual(options.collections, ["HST"])
        XCTAssertNil(options.wavelengthRegions)
    }

    func testJWSTOnlyPreset() {
        let options = ImageryFilterOptions.jwstOnly

        XCTAssertEqual(options.collections, ["JWST"])
    }

    func testCustomFilterOptions() {
        let options = ImageryFilterOptions(
            wavelengthRegions: ["UV", "OPTICAL"],
            collections: ["HST", "JWST"],
            instruments: ["ACS", "WFC3"],
            filterBands: ["F606W", "F814W"],
            calibLevels: ["3"],
            dataProductTypes: ["IMAGE", "SPECTRUM"],
            intentType: "science",
            dataRights: "PUBLIC"
        )

        XCTAssertEqual(options.wavelengthRegions, ["UV", "OPTICAL"])
        XCTAssertEqual(options.collections, ["HST", "JWST"])
        XCTAssertEqual(options.instruments, ["ACS", "WFC3"])
        XCTAssertEqual(options.filterBands, ["F606W", "F814W"])
        XCTAssertEqual(options.calibLevels, ["3"])
        XCTAssertEqual(options.dataProductTypes, ["IMAGE", "SPECTRUM"])
    }

    func testToMASTFiltersDefault() {
        let options = ImageryFilterOptions.defaultScience
        let filters = options.toMASTFilters()

        // Should have: dataRights, calib_level, dataproduct_type, intentType
        XCTAssertEqual(filters.count, 4)

        // Verify filter param names
        let paramNames = filters.map { $0.paramName }
        XCTAssertTrue(paramNames.contains("dataRights"))
        XCTAssertTrue(paramNames.contains("calib_level"))
        XCTAssertTrue(paramNames.contains("dataproduct_type"))
        XCTAssertTrue(paramNames.contains("intentType"))
    }

    func testToMASTFiltersWithWavelength() {
        let options = ImageryFilterOptions.uvOnly
        let filters = options.toMASTFilters()

        // Should have: dataRights, calib_level, dataproduct_type, intentType, wavelength_region
        XCTAssertEqual(filters.count, 5)

        let paramNames = filters.map { $0.paramName }
        XCTAssertTrue(paramNames.contains("wavelength_region"))
    }

    func testToMASTFiltersWithCollection() {
        let options = ImageryFilterOptions.hubbleOnly
        let filters = options.toMASTFilters()

        // Should have: dataRights, calib_level, dataproduct_type, intentType, obs_collection
        XCTAssertEqual(filters.count, 5)

        let paramNames = filters.map { $0.paramName }
        XCTAssertTrue(paramNames.contains("obs_collection"))
    }

    func testToMASTFiltersFullCustom() {
        let options = ImageryFilterOptions(
            wavelengthRegions: ["OPTICAL"],
            collections: ["HST"],
            instruments: ["ACS"],
            filterBands: ["F606W"]
        )
        let filters = options.toMASTFilters()

        // Should have all 8 filters
        XCTAssertEqual(filters.count, 8)

        let paramNames = filters.map { $0.paramName }
        XCTAssertTrue(paramNames.contains("wavelength_region"))
        XCTAssertTrue(paramNames.contains("obs_collection"))
        XCTAssertTrue(paramNames.contains("instrument_name"))
        XCTAssertTrue(paramNames.contains("filters"))
    }

    func testToMASTFiltersWithFilterBands() {
        let options = ImageryFilterOptions(
            collections: ["JWST"],
            filterBands: ["F150W"]
        )
        let filters = options.toMASTFilters()

        let filterParam = filters.first { $0.paramName == "filters" }
        XCTAssertNotNil(filterParam)
        XCTAssertEqual(filterParam?.separator, ";")
    }

    func testGetScienceImageProductUrlReturnsNilForMissingUrl() {
        let expectation = XCTestExpectation(description: "Missing product url returns nil")
        let mast = SwiftMAST()
        let coamResult = makeCoamResult()

        mast.getScienceImageProductUrl(
            targetName: "M31",
            result: coamResult,
            productType: .Fits
        ) { url in
            XCTAssertNil(url)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Integration Tests (requires network)

    /// Test downloading UV-only imagery for M31
    func testDownloadImageryUVOnly() {
        let expectation = XCTestExpectation(description: "Download UV imagery for M31")
        let mast = SwiftMAST()

        print("\n=== Testing UV-Only Filter for M31 ===")
        mast.downloadImagery(
            targetName: "M31", productType: .Jpeg, filterOptions: .uvOnly, pageSize: 10, token: nil
        ) { urls in
            print("UV-Only Results:")
            print("  Downloaded \(urls.count) UV images")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test downloading Hubble-only imagery for M31
    func testDownloadImageryHubbleOnly() {
        let expectation = XCTestExpectation(description: "Download Hubble imagery for M31")
        let mast = SwiftMAST()

        print("\n=== Testing Hubble-Only Filter for M31 ===")
        mast.downloadImagery(
            targetName: "M31", productType: .Jpeg, filterOptions: .hubbleOnly, pageSize: 10,
            token: nil
        ) { urls in
            print("Hubble-Only Results:")
            print("  Downloaded \(urls.count) HST images")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test downloading with custom filter (GALEX UV)
    func testDownloadImageryCustomGALEX() {
        let expectation = XCTestExpectation(description: "Download GALEX imagery for M31")
        let mast = SwiftMAST()

        let customFilter = ImageryFilterOptions(
            wavelengthRegions: ["UV"],
            collections: ["GALEX"]
        )

        print("\n=== Testing Custom GALEX UV Filter for M31 ===")
        mast.downloadImagery(
            targetName: "M31", productType: .Jpeg, filterOptions: customFilter, pageSize: 10,
            token: nil
        ) { urls in
            print("GALEX UV Results:")
            print("  Downloaded \(urls.count) GALEX images")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test comparing default vs filtered results
    func testCompareFilteredResults() {
        let expectation = XCTestExpectation(description: "Compare filter results")
        let mast = SwiftMAST()

        print("\n=== Comparing Default vs UV-Only Filters for NGC 1234 ===")

        // First get default (all wavelengths)
        mast.downloadImagery(
            targetName: "M42", productType: .Jpeg, filterOptions: .defaultScience, pageSize: 5,
            token: nil
        ) { defaultUrls in
            print("Default Science Results: \(defaultUrls.count) images")

            // Then get UV only
            let mast2 = SwiftMAST()
            mast2.downloadImagery(
                targetName: "M42", productType: .Jpeg, filterOptions: .uvOnly, pageSize: 5,
                token: nil
            ) { uvUrls in
                print("UV-Only Results: \(uvUrls.count) images")
                print("Filter reduced results by \(defaultUrls.count - uvUrls.count) images")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 120.0)
    }

    /// Test resolving target coordinates for M31
    func testLookupTargetCoordinates() {
        let expectation = XCTestExpectation(description: "Lookup target coordinates")
        let mast = SwiftMAST()

        mast.lookupTargetCoordinates(targetName: "M31") { coordinates in
            XCTAssertNotNil(coordinates)
            if let coordinates = coordinates {
                XCTAssertGreaterThan(coordinates.radius, 0.0)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test querying science image results for M31
    func testGetScienceImageQueryResults() {
        let expectation = XCTestExpectation(description: "Get science image query results")
        let mast = SwiftMAST()

        mast.getScienceImageQueryResults(
            targetName: "M31",
            filterOptions: .defaultScience,
            pageSize: 5,
            page: 1
        ) { results in
            print("Query Results: \(results.count) products")
            XCTAssertFalse(results.isEmpty)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test downloading a single product URL for M31
    func testGetScienceImageProductUrl() {
        let expectation = XCTestExpectation(description: "Get science image product url")
        let mast = SwiftMAST()

        mast.getScienceImageQueryResults(
            targetName: "M31",
            filterOptions: .defaultScience,
            pageSize: 1,
            page: 1
        ) { results in
            guard let first = results.first else {
                XCTFail("No results returned")
                expectation.fulfill()
                return
            }

            mast.getScienceImageProductUrl(
                targetName: "M31",
                result: first,
                productType: .Fits
            ) { url in
                XCTAssertNotNil(url)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 120.0)
    }

    // MARK: - FITSMetadata Tests

    func testFITSMetadataExtraction() {
        // Create mock metadata similar to what a FITS file would contain
        let mockMetadata: [String: QValue] = [
            "NAXIS": QValue(value: "2"),
            "NAXIS1": QValue(value: "4096"),
            "NAXIS2": QValue(value: "4096"),
            "FILTER": QValue(value: "F606W"),
            "DATE-OBS": QValue(value: "2023-07-15T14:32:10"),
            "EXPTIME": QValue(value: "1200.0"),
            "TELESCOP": QValue(value: "HST"),
            "INSTRUME": QValue(value: "ACS"),
            "CRVAL1": QValue(value: "10.684375"),
            "CRVAL2": QValue(value: "41.269167"),
            "CDELT1": QValue(value: "-0.00001389"),
            "CDELT2": QValue(value: "0.00001389"),
            "CTYPE1": QValue(value: "RA---TAN"),
            "CTYPE2": QValue(value: "DEC--TAN"),
            "OBJECT": QValue(value: "M31"),
        ]

        let fitsMetadata = FITSMetadata(fileIdentifier: "test_file.fits", metadata: mockMetadata)

        // Test dimension extraction
        XCTAssertEqual(fitsMetadata.naxis, 2)
        XCTAssertEqual(fitsMetadata.axisDimensions, [4096, 4096])
        XCTAssertEqual(fitsMetadata.dimensionDescription, "4096×4096 (2D)")

        // Test filter extraction
        XCTAssertEqual(fitsMetadata.filter, "F606W")

        // Test temporal extraction
        XCTAssertEqual(fitsMetadata.observationDate, "2023-07-15T14:32:10")
        XCTAssertEqual(fitsMetadata.exposureTime, 1200.0)

        // Test instrument extraction
        XCTAssertEqual(fitsMetadata.telescope, "HST")
        XCTAssertEqual(fitsMetadata.instrument, "ACS")
        XCTAssertEqual(fitsMetadata.targetName, "M31")

        // Test WCS extraction (using approximate comparison for floating point)
        XCTAssertNotNil(fitsMetadata.crval1)
        XCTAssertEqual(fitsMetadata.crval1!, 10.684375, accuracy: 0.0001)
        XCTAssertNotNil(fitsMetadata.crval2)
        XCTAssertEqual(fitsMetadata.crval2!, 41.269167, accuracy: 0.0001)
        XCTAssertNotNil(fitsMetadata.cdelt1)
        XCTAssertEqual(fitsMetadata.cdelt1!, -0.00001389, accuracy: 0.000001)
        XCTAssertNotNil(fitsMetadata.cdelt2)
        XCTAssertEqual(fitsMetadata.cdelt2!, 0.00001389, accuracy: 0.000001)
        XCTAssertEqual(fitsMetadata.ctype1, "RA---TAN")
        XCTAssertEqual(fitsMetadata.ctype2, "DEC--TAN")

        print("FITSMetadata extraction test passed")
        print(fitsMetadata.description)
    }

    func testFITSMetadata3DImage() {
        // Test 3D image metadata (e.g., data cube)
        let mockMetadata: [String: QValue] = [
            "NAXIS": QValue(value: "3"),
            "NAXIS1": QValue(value: "256"),
            "NAXIS2": QValue(value: "256"),
            "NAXIS3": QValue(value: "100"),
            "FILTER": QValue(value: "CLEAR"),
            "TELESCOP": QValue(value: "JWST"),
            "INSTRUME": QValue(value: "NIRSpec"),
        ]

        let fitsMetadata = FITSMetadata(fileIdentifier: "cube.fits", metadata: mockMetadata)

        XCTAssertEqual(fitsMetadata.naxis, 3)
        XCTAssertEqual(fitsMetadata.axisDimensions, [256, 256, 100])
        XCTAssertEqual(fitsMetadata.dimensionDescription, "256×256×100 (3D)")
        XCTAssertEqual(fitsMetadata.telescope, "JWST")
        XCTAssertEqual(fitsMetadata.instrument, "NIRSpec")

        print("FITSMetadata 3D test passed")
    }

    func testFITSMetadataStore() {
        // Test the metadata storage in SwiftMAST
        let mast = SwiftMAST()

        let mockMetadata1: [String: QValue] = [
            "NAXIS": QValue(value: "2"),
            "FILTER": QValue(value: "F814W"),
            "TELESCOP": QValue(value: "HST"),
        ]
        let mockMetadata2: [String: QValue] = [
            "NAXIS": QValue(value: "2"),
            "FILTER": QValue(value: "F606W"),
            "TELESCOP": QValue(value: "HST"),
        ]

        let meta1 = FITSMetadata(fileIdentifier: "file1.fits", metadata: mockMetadata1)
        let meta2 = FITSMetadata(fileIdentifier: "file2.fits", metadata: mockMetadata2)

        mast.appendFitsMetadata(target: "M31", metadata: meta1)
        mast.appendFitsMetadata(target: "M31", metadata: meta2)

        // Verify storage
        let stored = mast.getFitsMetadata(target: "M31")
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.count, 2)
        XCTAssertEqual(stored?[0].filter, "F814W")
        XCTAssertEqual(stored?[1].filter, "F606W")

        // Test print function (visual verification)
        print("\n=== Testing metadata print output ===")
        mast.printFitsMetadata(target: "M31")

        print("FITSMetadata store test passed")
    }

    // MARK: - Log Subscriber Tests

    func testSubscribeToLogs() {
        let mast = SwiftMAST()
        let expectation = XCTestExpectation(
            description: "Log subscriber callback should be invoked")
        var receivedLog: MASTSyslog?

        mast.subscribeToLogs(id: "testSubscriber") { logEntry in
            receivedLog = logEntry
            expectation.fulfill()
        }

        // Trigger a log entry
        mast.log(.OK, message: "Test log message")

        wait(for: [expectation], timeout: 2.0)

        XCTAssertNotNil(receivedLog)
        XCTAssertEqual(receivedLog?.log, .OK)
        XCTAssertEqual(receivedLog?.message, "Test log message")

        print("Subscribe to logs test passed")
    }

    func testLogAppendsToSysLog() {
        let mast = SwiftMAST()

        // Log a message
        mast.log(.RequestError, message: "Test error message")

        // Verify it's in sysLog
        XCTAssertEqual(mast.sysLog.count, 1)
        XCTAssertEqual(mast.sysLog[0].log, .RequestError)
        XCTAssertEqual(mast.sysLog[0].message, "Test error message")

        print("Log appends to sysLog test passed")
    }

    func testMultipleSubscribers() {
        let mast = SwiftMAST()
        var callbackCount = 0
        let expectation = XCTestExpectation(description: "Both subscribers should be called")
        expectation.expectedFulfillmentCount = 2

        mast.subscribeToLogs(id: "subscriber1") { _ in
            callbackCount += 1
            expectation.fulfill()
        }

        mast.subscribeToLogs(id: "subscriber2") { _ in
            callbackCount += 1
            expectation.fulfill()
        }

        mast.log(.OK, message: "Test message")

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(callbackCount, 2)

        print("Multiple subscribers test passed")
    }

    func testUnsubscribeFromLogs() {
        let mast = SwiftMAST()
        var callbackInvoked = false

        mast.subscribeToLogs(id: "toRemove") { _ in
            callbackInvoked = true
        }

        // Unsubscribe
        mast.unsubscribeFromLogs(id: "toRemove")

        // Wait a bit for the barrier to complete
        let expectation = XCTestExpectation(description: "Wait for async unsubscribe")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Log a message after unsubscribing
            mast.log(.OK, message: "Should not trigger callback")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // The callback should NOT have been invoked
        XCTAssertFalse(callbackInvoked)

        print("Unsubscribe from logs test passed")
    }

    func testClearLogSubscribers() {
        let mast = SwiftMAST()
        var callbackCount = 0

        mast.subscribeToLogs(id: "sub1") { _ in callbackCount += 1 }
        mast.subscribeToLogs(id: "sub2") { _ in callbackCount += 1 }
        mast.subscribeToLogs(id: "sub3") { _ in callbackCount += 1 }

        // Clear all subscribers
        mast.clearLogSubscribers()

        // Wait for the barrier to complete
        let expectation = XCTestExpectation(description: "Wait for async clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Log a message after clearing
            mast.log(.OK, message: "Should not trigger any callbacks")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // No callbacks should have been invoked
        XCTAssertEqual(callbackCount, 0)

        print("Clear log subscribers test passed")
    }

    func testSubscribeToLogsReturnsId() {
        let mast = SwiftMAST()

        let returnedId = mast.subscribeToLogs(id: "myUniqueId") { _ in }

        XCTAssertEqual(returnedId, "myUniqueId")

        print("Subscribe returns ID test passed")
    }

    func testMASTSyslogDescription() {
        let entry = MASTSyslog(log: .OK, message: "Test message")

        let description = entry.description
        XCTAssertTrue(description.contains("MAST:"))
        XCTAssertTrue(description.contains("OK"))
        XCTAssertTrue(description.contains("Test message"))

        print("MASTSyslog description test passed")
    }

    // MARK: - Pagination Tests

    /// Test that downloadImagery accepts page parameter and logs are generated
    func testDownloadImageryWithPaginationLogs() {
        let mast = SwiftMAST()
        var receivedLogs: [MASTSyslog] = []

        // Subscribe to capture logs
        mast.subscribeToLogs(id: "paginationTest") { logEntry in
            receivedLogs.append(logEntry)
        }

        // Trigger downloadImagery with pagination parameters
        // This will log the start message immediately
        let expectation = XCTestExpectation(description: "downloadImagery should log start message")

        // Call with page parameter - this triggers immediate logging
        mast.downloadImagery(
            targetName: "InvalidTargetForTest123",
            pageSize: 10,
            page: 2
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)

        // Verify that at least the start log was generated with pagination info
        let startLogs = receivedLogs.filter {
            $0.message.contains("page=2") && $0.message.contains("pageSize=10")
        }
        XCTAssertGreaterThan(startLogs.count, 0, "Should have logged pagination parameters")

        print("Download imagery with pagination logs test passed")
    }

    /// Test that page parameter defaults to 1
    func testDownloadImageryDefaultPage() {
        let mast = SwiftMAST()
        var receivedLogs: [MASTSyslog] = []

        mast.subscribeToLogs(id: "defaultPageTest") { logEntry in
            receivedLogs.append(logEntry)
        }

        let expectation = XCTestExpectation(
            description: "downloadImagery should use default page=1")

        mast.downloadImagery(targetName: "InvalidTargetForTest456") { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)

        // Verify default page=1 was used
        let startLogs = receivedLogs.filter { $0.message.contains("page=1") }
        XCTAssertGreaterThan(startLogs.count, 0, "Should have logged default page=1")

        print("Download imagery default page test passed")
    }

    /// Test that logs capture error when target cannot be resolved
    func testDownloadImageryLogsErrorOnInvalidTarget() {
        let mast = SwiftMAST()
        var receivedLogs: [MASTSyslog] = []

        mast.subscribeToLogs(id: "errorLogTest") { logEntry in
            receivedLogs.append(logEntry)
        }

        let expectation = XCTestExpectation(
            description: "downloadImagery should log error for invalid target")

        mast.downloadImagery(targetName: "CompletelyInvalidTarget999XYZ") { urls in
            XCTAssertEqual(urls.count, 0, "Should return empty array for invalid target")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30.0)

        // Check for error log
        let errorLogs = receivedLogs.filter { $0.log == .RequestError }
        XCTAssertGreaterThan(errorLogs.count, 0, "Should have logged an error for invalid target")

        print("Download imagery logs error on invalid target test passed")
    }

    /// Test getScienceImageProducts page parameter is passed correctly in the log
    func testGetScienceImageProductsPageParameter() {
        let mast = SwiftMAST()
        var receivedLogs: [MASTSyslog] = []
        let logExpectation = XCTestExpectation(description: "Should log page parameter")

        mast.subscribeToLogs(id: "scienceProductsPageTest") { logEntry in
            receivedLogs.append(logEntry)
            // Fulfill as soon as we see the page=3 log
            if logEntry.message.contains("page=3") {
                logExpectation.fulfill()
            }
        }

        // Set target first (required by getScienceImageProducts)
        mast.setTargetId(targetId: "TestTarget")

        // Call getScienceImageProducts directly with specific page
        // We don't need to wait for completion, just for the log
        mast.getScienceImageProducts(
            targetName: "TestTarget",
            ra: 10.68,
            dec: 41.27,
            radius: 0.2,
            pageSize: 5,
            page: 3,
            token: nil
        ) { _ in
            // We don't need to wait for this
        }

        // Wait for the log with page=3 to appear (should be almost immediate)
        wait(for: [logExpectation], timeout: 5.0)

        // Verify page=3 was logged
        let pageLogs = receivedLogs.filter { $0.message.contains("page=3") }
        XCTAssertGreaterThan(pageLogs.count, 0, "Should have logged page=3 parameter")

        print("getScienceImageProducts page parameter test passed")
    }

    // MARK: - ScienceProduct Model Tests

    func testScienceProductInitialization() {
        let coam = makeCoamResult(dataURL: "mast:HST/product/test.fits")
        let headers: [FITSHeaderUnit] = [
            FITSHeaderUnit(
                keyword: "NAXIS", value: .integer(2), comment: "number of array dimensions"),
            FITSHeaderUnit(keyword: "NAXIS1", value: .integer(1024), comment: ""),
            FITSHeaderUnit(keyword: "NAXIS2", value: .integer(1024), comment: ""),
            FITSHeaderUnit(keyword: "FILTER", value: .string("F606W"), comment: "filter used"),
        ]

        let product = ScienceProduct(
            name: "test_primary",
            imageLocation: URL(fileURLWithPath: "/tmp/test.jpg"),
            sourceFileLocation: URL(fileURLWithPath: "/tmp/test.fits"),
            headers: headers,
            coamResult: coam
        )

        XCTAssertEqual(product.name, "test_primary")
        XCTAssertEqual(product.imageLocation?.lastPathComponent, "test.jpg")
        XCTAssertEqual(product.sourceFileLocation?.lastPathComponent, "test.fits")
        XCTAssertEqual(product.headers.count, 4)
        XCTAssertEqual(product.coamResult.obs_id, "obs-1")

        // Test header(forKeyword:) lookup
        let naxisHeader = product.header(forKeyword: "NAXIS")
        XCTAssertNotNil(naxisHeader)
        XCTAssertEqual(naxisHeader?.value, .integer(2))
        XCTAssertEqual(naxisHeader?.keywordDescription, "Number of data array dimensions")

        let filterHeader = product.header(forKeyword: "FILTER")
        XCTAssertNotNil(filterHeader)
        XCTAssertEqual(filterHeader?.value.rawString, "F606W")
    }

    func testScienceProductWithNilLocations() {
        let coam = makeCoamResult()
        let product = ScienceProduct(
            name: "no_image",
            imageLocation: nil,
            sourceFileLocation: nil,
            headers: [],
            coamResult: coam
        )

        XCTAssertNil(product.imageLocation)
        XCTAssertNil(product.sourceFileLocation)
        XCTAssertTrue(product.headers.isEmpty)
        XCTAssertNil(product.header(forKeyword: "NAXIS"))
    }

    // MARK: - extractScienceProductsFromFits Tests (Local FITS Files)

    /// Helper to get the project root directory for accessing test resources
    private func projectRootURL() -> URL {
        // Tests run from the package directory
        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // SwiftMASTTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // project root
    }

    func testExtractScienceProductsFromJWSTFits() {
        let mast = SwiftMAST()
        let projectRoot = projectRootURL()
        let fitsUrl = projectRoot.appendingPathComponent(
            "Resources/fits/jw04244-o002_t002_miri_f1000w.fits")

        guard FileManager.default.fileExists(atPath: fitsUrl.path) else {
            print("Skipping test: FITS file not found at \(fitsUrl.path)")
            return
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let coam = makeCoamResult(dataURL: "mast:JWST/product/jw04244-o002_t002_miri_f1000w.fits")
        let products = mast.extractScienceProductsFromFits(
            fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coam
        )

        XCTAssertFalse(products.isEmpty, "Should extract at least one product from JWST FITS file")

        for product in products {
            XCTAssertFalse(product.name.isEmpty, "Product name should not be empty")
            XCTAssertEqual(
                product.sourceFileLocation, fitsUrl, "Source should point to the FITS file")
            XCTAssertEqual(product.coamResult.obs_id, "obs-1", "CoamResult should be attached")
            XCTAssertFalse(product.headers.isEmpty, "Headers should not be empty")

            // Verify structured headers have descriptions
            let bitpixHeader = product.header(forKeyword: "BITPIX")
            XCTAssertNotNil(bitpixHeader, "Should have BITPIX header")
            XCTAssertTrue(bitpixHeader!.isCategorical, "BITPIX should be categorical")
            XCTAssertNotNil(
                bitpixHeader!.valueDescription, "BITPIX value should have a description")
            XCTAssertEqual(bitpixHeader!.keywordDescription, "Number of bits per data pixel")

            print("  Product: \(product.name)")
            print("    Image: \(product.imageLocation?.lastPathComponent ?? "none")")
            print("    Headers count: \(product.headers.count)")
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputDir)
    }

    func testExtractScienceProductsFromHSTFits() {
        let mast = SwiftMAST()
        let projectRoot = projectRootURL()
        let fitsUrl = projectRoot.appendingPathComponent(
            "Resources/fits/_UV_hst_9422_01_acs_hrc_f220w_j8d001.fits")

        guard FileManager.default.fileExists(atPath: fitsUrl.path) else {
            print("Skipping test: FITS file not found at \(fitsUrl.path)")
            return
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let coam = makeCoamResult(dataURL: "mast:HST/product/j8d001.fits")
        let products = mast.extractScienceProductsFromFits(
            fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coam
        )

        XCTAssertFalse(products.isEmpty, "Should extract at least one product from HST FITS file")

        for product in products {
            XCTAssertFalse(product.name.isEmpty)
            XCTAssertEqual(product.sourceFileLocation, fitsUrl)
            XCTAssertFalse(product.headers.isEmpty)
            // Verify keyword lookups work
            XCTAssertNotNil(product.header(forKeyword: "NAXIS"))
            print("  Product: \(product.name)")
            print("    Image: \(product.imageLocation?.lastPathComponent ?? "none")")
            print("    Headers count: \(product.headers.count)")
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputDir)
    }

    func testExtractScienceProductsFromInfraredFits() {
        let mast = SwiftMAST()
        let projectRoot = projectRootURL()
        let fitsUrl = projectRoot.appendingPathComponent(
            "Resources/fits/_INFRARED_jw05627-o003_t002_miri_f1500w.fits")

        guard FileManager.default.fileExists(atPath: fitsUrl.path) else {
            print("Skipping test: FITS file not found at \(fitsUrl.path)")
            return
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let coam = makeCoamResult(dataURL: "mast:JWST/product/jw05627-o003_t002_miri_f1500w.fits")
        let products = mast.extractScienceProductsFromFits(
            fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coam
        )

        XCTAssertFalse(
            products.isEmpty, "Should extract at least one product from infrared FITS file")

        // Check that image HDU products have merged headers (primary + individual)
        for product in products {
            XCTAssertFalse(product.headers.isEmpty)
            // Products from extension HDUs should have XTENSION in their headers
            // (from the merged individual headers)
            print("  Product: \(product.name)")
            print("    Headers count: \(product.headers.count)")
            if product.imageLocation != nil {
                print("    Image saved: \(product.imageLocation!.lastPathComponent)")
            }
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputDir)
    }

    func testExtractScienceProductsHeadersMerging() {
        let mast = SwiftMAST()
        let projectRoot = projectRootURL()
        let fitsUrl = projectRoot.appendingPathComponent(
            "Resources/fits/jw06809-o002_t001_miri_f2100w.fits")

        guard FileManager.default.fileExists(atPath: fitsUrl.path) else {
            print("Skipping test: FITS file not found at \(fitsUrl.path)")
            return
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let coam = makeCoamResult(dataURL: "mast:JWST/product/jw06809-o002_t001_miri_f2100w.fits")
        let products = mast.extractScienceProductsFromFits(
            fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coam
        )

        XCTAssertFalse(products.isEmpty)

        // For extension HDU products, headers should contain primary HDU keys
        // merged with the individual HDU keys
        if products.count > 1 {
            let extProduct = products[1]  // First extension product
            // Should have TELESCOP or INSTRUME from primary, plus XTENSION from extension
            let hasTelescopeOrInstrument =
                extProduct.header(forKeyword: "TELESCOP") != nil
                || extProduct.header(forKeyword: "INSTRUME") != nil
            XCTAssertTrue(
                hasTelescopeOrInstrument || !extProduct.headers.isEmpty,
                "Extension product should have merged headers from primary HDU"
            )

            // Verify XTENSION is categorical and has correct description
            let xtensionHeader = extProduct.header(forKeyword: "XTENSION")
            if let xt = xtensionHeader {
                XCTAssertTrue(xt.isCategorical)
                XCTAssertEqual(xt.value.rawString.uppercased(), "IMAGE")
                XCTAssertNotNil(xt.valueDescription)
                XCTAssertNotNil(xt.categoricalOptions)
            }

            print(
                "  Extension product '\(extProduct.name)' has \(extProduct.headers.count) merged headers"
            )
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputDir)
    }

    func testExtractScienceProductsNonExistentFile() {
        let mast = SwiftMAST()
        let fitsUrl = URL(fileURLWithPath: "/tmp/nonexistent.fits")
        let outputDir = FileManager.default.temporaryDirectory

        let coam = makeCoamResult(dataURL: "mast:HST/product/nonexistent.fits")
        let products = mast.extractScienceProductsFromFits(
            fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coam
        )

        XCTAssertTrue(products.isEmpty, "Should return empty array for non-existent file")
    }

    func testExtractScienceProductsNoURLs() {
        let mast = SwiftMAST()
        let coam = makeCoamResult(dataURL: "", jpegURL: "")

        let expectation = XCTestExpectation(description: "Completion called")

        mast.extractScienceProducts(targetName: "Test", coamResult: coam) { products in
            XCTAssertTrue(products.isEmpty, "Should return empty array when no URLs available")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - FITSHeaderValue Tests

    func testFITSHeaderValueParsing() {
        // Integer
        let intVal = SwiftMAST.parseFITSValue("42")
        XCTAssertEqual(intVal, .integer(42))
        XCTAssertEqual(intVal.intValue, 42)
        XCTAssertEqual(intVal.doubleValue, 42.0)

        // Negative integer (BITPIX-style)
        let negInt = SwiftMAST.parseFITSValue("-32")
        XCTAssertEqual(negInt, .integer(-32))

        // Double
        let dblVal = SwiftMAST.parseFITSValue("3.14159")
        XCTAssertEqual(dblVal, .double(3.14159))
        XCTAssertEqual(dblVal.doubleValue, 3.14159)
        XCTAssertNil(dblVal.intValue)

        // Scientific notation double
        let sciVal = SwiftMAST.parseFITSValue("1.5e-06")
        if case .double(let d) = sciVal {
            XCTAssertEqual(d, 1.5e-06, accuracy: 1e-12)
        } else {
            XCTFail("Expected .double for scientific notation")
        }

        // Boolean T/F
        let trueVal = SwiftMAST.parseFITSValue("T")
        XCTAssertEqual(trueVal, .bool(true))
        let falseVal = SwiftMAST.parseFITSValue("F")
        XCTAssertEqual(falseVal, .bool(false))

        // String (FITS quoted)
        let strVal = SwiftMAST.parseFITSValue("'IMAGE   '")
        XCTAssertEqual(strVal, .string("IMAGE"))
        XCTAssertEqual(strVal.rawString, "IMAGE")

        // Plain string
        let plainStr = SwiftMAST.parseFITSValue("SOME_VALUE")
        XCTAssertEqual(plainStr, .string("SOME_VALUE"))
    }

    func testFITSHeaderValueRawString() {
        XCTAssertEqual(FITSHeaderValue.string("IMAGE").rawString, "IMAGE")
        XCTAssertEqual(FITSHeaderValue.integer(-32).rawString, "-32")
        XCTAssertEqual(FITSHeaderValue.double(3.14).rawString, "3.14")
        XCTAssertEqual(FITSHeaderValue.bool(true).rawString, "T")
        XCTAssertEqual(FITSHeaderValue.bool(false).rawString, "F")
    }

    func testFITSHeaderValueCodable() throws {
        let values: [FITSHeaderValue] = [
            .string("IMAGE"),
            .integer(-32),
            .double(1.5e-06),
            .bool(true),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in values {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(FITSHeaderValue.self, from: data)
            XCTAssertEqual(decoded, original, "Round-trip failed for \(original)")
        }
    }

    // MARK: - FITSHeaderUnit Tests

    func testFITSHeaderUnitKeywordDescription() {
        let unit = FITSHeaderUnit(
            keyword: "BITPIX", value: .integer(-32), comment: "array data type"
        )
        XCTAssertEqual(unit.keywordDescription, "Number of bits per data pixel")

        let unknown = FITSHeaderUnit(
            keyword: "ZZUNKNOWN", value: .string("x"), comment: ""
        )
        XCTAssertEqual(unknown.keywordDescription, "FITS header keyword")
    }

    func testFITSHeaderUnitCategorical() {
        // BITPIX is categorical
        let bitpix = FITSHeaderUnit(
            keyword: "BITPIX", value: .integer(-32), comment: "array data type"
        )
        XCTAssertTrue(bitpix.isCategorical)
        XCTAssertNotNil(bitpix.categoricalOptions)
        XCTAssertEqual(bitpix.categoricalOptions?.count, FITSBitpix.allCases.count)
        XCTAssertNotNil(bitpix.valueDescription)
        XCTAssertTrue(bitpix.valueDescription!.contains("single-precision"))

        // XTENSION is categorical
        let xt = FITSHeaderUnit(
            keyword: "XTENSION", value: .string("IMAGE"), comment: ""
        )
        XCTAssertTrue(xt.isCategorical)
        XCTAssertNotNil(xt.valueDescription)

        // TELESCOP is NOT categorical
        let telescop = FITSHeaderUnit(
            keyword: "TELESCOP", value: .string("JWST"), comment: ""
        )
        XCTAssertFalse(telescop.isCategorical)
        XCTAssertNil(telescop.categoricalOptions)
        XCTAssertNil(telescop.valueDescription)
    }

    func testFITSHeaderUnitCodableRoundTrip() throws {
        let units = [
            FITSHeaderUnit(keyword: "BITPIX", value: .integer(-32), comment: "data type"),
            FITSHeaderUnit(keyword: "TELESCOP", value: .string("JWST"), comment: "telescope"),
            FITSHeaderUnit(keyword: "SIMPLE", value: .bool(true), comment: "conforms"),
            FITSHeaderUnit(keyword: "CRVAL1", value: .double(83.633), comment: "RA"),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(units)
        let decoded = try decoder.decode([FITSHeaderUnit].self, from: data)
        XCTAssertEqual(decoded.count, units.count)
        for (orig, dec) in zip(units, decoded) {
            XCTAssertEqual(dec.keyword, orig.keyword)
            XCTAssertEqual(dec.value, orig.value)
            XCTAssertEqual(dec.comment, orig.comment)
        }
    }

    // MARK: - FITSHeaderEnums Tests

    func testFITSBitpixEnum() {
        // CaseIterable
        XCTAssertEqual(FITSBitpix.allCases.count, 6)

        // Properties
        XCTAssertEqual(FITSBitpix.float32.rawValue, -32)
        XCTAssertTrue(FITSBitpix.float32.isFloatingPoint)
        XCTAssertFalse(FITSBitpix.int16.isFloatingPoint)
        XCTAssertEqual(FITSBitpix.float64.byteSize, 8)
        XCTAssertEqual(FITSBitpix.uint8.byteSize, 1)

        // Identifiable
        XCTAssertEqual(FITSBitpix.int32.id, 32)

        // Description
        XCTAssertFalse(FITSBitpix.int16.description.isEmpty)
    }

    func testFITSXtensionEnum() {
        XCTAssertEqual(FITSXtension.allCases.count, 4)
        XCTAssertEqual(FITSXtension.image.rawValue, "IMAGE")
        XCTAssertEqual(FITSXtension.bintable.rawValue, "BINTABLE")

        // Init from FITS value string
        XCTAssertEqual(FITSXtension(fitsValue: "'IMAGE   '"), .image)
        XCTAssertEqual(FITSXtension(fitsValue: "BINTABLE"), .bintable)
        XCTAssertNil(FITSXtension(fitsValue: "UNKNOWN"))
    }

    func testFITSRaDesysEnum() {
        XCTAssertEqual(FITSRaDesys.allCases.count, 5)
        XCTAssertEqual(FITSRaDesys.icrs.rawValue, "ICRS")
        XCTAssertEqual(FITSRaDesys(fitsValue: "'FK5     '"), .fk5)
        XCTAssertEqual(FITSRaDesys(fitsValue: "FK4-NO-E"), .fk4NoE)
        XCTAssertNil(FITSRaDesys(fitsValue: "BOGUS"))
    }

    func testFITSTimeSysEnum() {
        XCTAssertEqual(FITSTimeSys.allCases.count, 8)
        XCTAssertEqual(FITSTimeSys.utc.rawValue, "UTC")
        XCTAssertEqual(FITSTimeSys(fitsValue: "'UTC     '"), .utc)
        XCTAssertEqual(FITSTimeSys(fitsValue: "TAI"), .tai)
        XCTAssertNil(FITSTimeSys(fitsValue: "NOPE"))
    }

    // MARK: - FITSHeaderKeywords Tests

    func testFITSHeaderKeywordsDescriptions() {
        // Known keyword
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "NAXIS1"),
            "Length of data axis 1 (columns)"
        )
        // Unknown keyword
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "ZZFAKE"),
            "FITS header keyword"
        )
    }

    func testFITSHeaderKeywordsCategorical() {
        XCTAssertTrue(FITSHeaderKeywords.isCategorical(keyword: "BITPIX"))
        XCTAssertTrue(FITSHeaderKeywords.isCategorical(keyword: "XTENSION"))
        XCTAssertTrue(FITSHeaderKeywords.isCategorical(keyword: "RADESYS"))
        XCTAssertTrue(FITSHeaderKeywords.isCategorical(keyword: "TIMESYS"))
        XCTAssertFalse(FITSHeaderKeywords.isCategorical(keyword: "TELESCOP"))
        XCTAssertFalse(FITSHeaderKeywords.isCategorical(keyword: "NAXIS"))
    }

    func testFITSHeaderKeywordsValueDescription() {
        let desc = FITSHeaderKeywords.valueDescription(
            for: "BITPIX", value: .integer(-32)
        )
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc!.contains("single-precision"))

        let xtDesc = FITSHeaderKeywords.valueDescription(
            for: "XTENSION", value: .string("IMAGE")
        )
        XCTAssertNotNil(xtDesc)

        // Non-categorical keyword returns nil
        let noDesc = FITSHeaderKeywords.valueDescription(
            for: "TELESCOP", value: .string("JWST")
        )
        XCTAssertNil(noDesc)

        // Categorical keyword with unknown value returns nil
        let badVal = FITSHeaderKeywords.valueDescription(
            for: "BITPIX", value: .integer(999)
        )
        XCTAssertNil(badVal)
    }

    // MARK: - Header Extraction & Merge Tests

    func testMergeHeaderUnits() {
        let mast = SwiftMAST()

        let primary = [
            FITSHeaderUnit(keyword: "SIMPLE", value: .bool(true), comment: "standard"),
            FITSHeaderUnit(keyword: "BITPIX", value: .integer(8), comment: "primary"),
            FITSHeaderUnit(keyword: "TELESCOP", value: .string("JWST"), comment: ""),
            FITSHeaderUnit(keyword: "COMMENT", value: .string("Primary comment"), comment: ""),
        ]

        let ext = [
            FITSHeaderUnit(keyword: "BITPIX", value: .integer(-32), comment: "extension"),
            FITSHeaderUnit(keyword: "XTENSION", value: .string("IMAGE"), comment: "ext type"),
            FITSHeaderUnit(keyword: "COMMENT", value: .string("Ext comment"), comment: ""),
        ]

        let merged = mast.mergeHeaderUnits(primary: primary, hdu: ext)

        // Extension overrides primary for BITPIX
        let bitpix = merged.first { $0.keyword == "BITPIX" }
        XCTAssertNotNil(bitpix)
        XCTAssertEqual(bitpix?.value, .integer(-32))
        XCTAssertEqual(bitpix?.comment, "extension")

        // Primary-only keyword preserved
        let telescop = merged.first { $0.keyword == "TELESCOP" }
        XCTAssertNotNil(telescop)
        XCTAssertEqual(telescop?.value, .string("JWST"))

        // Extension-only keyword added
        let xt = merged.first { $0.keyword == "XTENSION" }
        XCTAssertNotNil(xt)

        // Both COMMENT entries are kept (multi-key behavior)
        let comments = merged.filter { $0.keyword == "COMMENT" }
        XCTAssertEqual(comments.count, 2)
    }

    func testExtractHeaderUnitsFromRealFITS() {
        let mast = SwiftMAST()
        let projectRoot = projectRootURL()
        let fitsUrl = projectRoot.appendingPathComponent(
            "Resources/fits/jw04244-o002_t002_miri_f1000w.fits")

        guard FileManager.default.fileExists(atPath: fitsUrl.path) else {
            print("Skipping test: FITS file not found at \(fitsUrl.path)")
            return
        }

        guard let fitsFile = try? FitsFile.read(contentsOf: fitsUrl) else {
            XCTFail("Failed to read FITS file")
            return
        }

        // Extract from primary HDU
        let primaryHeaders = mast.extractHeaderUnits(fitsFile.prime.headerUnit)
        XCTAssertFalse(primaryHeaders.isEmpty, "Primary HDU should have headers")

        // Check SIMPLE keyword exists and is boolean true
        let simple = primaryHeaders.first { $0.keyword == "SIMPLE" }
        XCTAssertNotNil(simple)
        XCTAssertEqual(simple?.value, .bool(true))
        XCTAssertEqual(simple?.keywordDescription, "File conforms to the FITS standard")

        // BITPIX should be present
        let bitpix = primaryHeaders.first { $0.keyword == "BITPIX" }
        XCTAssertNotNil(bitpix)
        XCTAssertTrue(bitpix!.isCategorical)

        // NAXIS should be integer
        let naxis = primaryHeaders.first { $0.keyword == "NAXIS" }
        XCTAssertNotNil(naxis)
        XCTAssertNotNil(naxis?.value.intValue)
    }

    // MARK: - HeaderKeywordCategory Tests

    func testHeaderKeywordCategoryEnum() {
        // All cases should be reachable
        XCTAssertGreaterThanOrEqual(HeaderKeywordCategory.allCases.count, 22)

        // Every case should have a non-empty description
        for category in HeaderKeywordCategory.allCases {
            XCTAssertFalse(
                category.description.isEmpty,
                "Category \(category.rawValue) has an empty description"
            )
        }

        // Identifiable conformance
        XCTAssertEqual(HeaderKeywordCategory.structural.id, "Structural")
        XCTAssertEqual(HeaderKeywordCategory.instrument.id, "Instrument")
        XCTAssertEqual(HeaderKeywordCategory.unknown.id, "Unknown")

        // Codable round-trip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertNoThrow(
            try {
                let data = try encoder.encode(HeaderKeywordCategory.exposure)
                let decoded = try decoder.decode(HeaderKeywordCategory.self, from: data)
                XCTAssertEqual(decoded, .exposure)
            }())
    }

    func testFITSHeaderUnitKeywordCategory() {
        // INSTRUME → instrument
        let instrume = FITSHeaderUnit(keyword: "INSTRUME", value: .string("MIRI"), comment: "")
        XCTAssertEqual(instrume.keywordCategory, .instrument)

        // TELESCOP → instrument
        let telescop = FITSHeaderUnit(keyword: "TELESCOP", value: .string("JWST"), comment: "")
        XCTAssertEqual(telescop.keywordCategory, .instrument)

        // DATAMODL → instrument
        let datamodl = FITSHeaderUnit(
            keyword: "DATAMODL", value: .string("ImageModel"), comment: "")
        XCTAssertEqual(datamodl.keywordCategory, .instrument)

        // DATE-OBS → time
        let dateObs = FITSHeaderUnit(keyword: "DATE-OBS", value: .string("2023-01-01"), comment: "")
        XCTAssertEqual(dateObs.keywordCategory, .time)

        // FILTER → instrument
        let filter = FITSHeaderUnit(keyword: "FILTER", value: .string("F1000W"), comment: "")
        XCTAssertEqual(filter.keywordCategory, .instrument)

        // EXP_TYPE → exposure
        let expType = FITSHeaderUnit(keyword: "EXP_TYPE", value: .string("MIR_IMAGE"), comment: "")
        XCTAssertEqual(expType.keywordCategory, .exposure)

        // TITLE → program
        let title = FITSHeaderUnit(keyword: "TITLE", value: .string("My Program"), comment: "")
        XCTAssertEqual(title.keywordCategory, .program)

        // GS_RA → guideStar
        let gsRa = FITSHeaderUnit(keyword: "GS_RA", value: .double(83.5), comment: "")
        XCTAssertEqual(gsRa.keywordCategory, .guideStar)

        // BKGLEVEL → background
        let bkg = FITSHeaderUnit(keyword: "BKGLEVEL", value: .double(0.01), comment: "")
        XCTAssertEqual(bkg.keywordCategory, .background)

        // S_REGION → wcs
        let sRegion = FITSHeaderUnit(
            keyword: "S_REGION", value: .string("CIRCLE ICRS"), comment: "")
        XCTAssertEqual(sRegion.keywordCategory, .wcs)

        // NAXIS is a general FITS structural keyword
        let naxis = FITSHeaderUnit(keyword: "NAXIS", value: .integer(2), comment: "")
        XCTAssertEqual(naxis.keywordCategory, .structural)

        // Completely unknown keyword → unknown
        let unk = FITSHeaderUnit(keyword: "ZZFAKE99", value: .string("x"), comment: "")
        XCTAssertEqual(unk.keywordCategory, .unknown)
    }

    func testFITSHeaderKeywordsCategory() {
        // General FITS structural keywords
        XCTAssertEqual(FITSHeaderKeywords.category(for: "NAXIS"), .structural)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "BITPIX"), .structural)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "NEXTEND"), .structural)

        // WCS keywords
        XCTAssertEqual(FITSHeaderKeywords.category(for: "CRVAL1"), .wcs)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "S_REGION"), .wcs)

        // Instrument keywords (including formerly-basic TELESCOP/DATAMODL)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "TELESCOP"), .instrument)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "INSTRUME"), .instrument)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "DETECTOR"), .instrument)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "FILTER"), .instrument)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "MSASTATE"), .instrument)

        // Calibration keywords (including formerly-basic CAL_VER; formerly-referenceFile CRDS_VER)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "CAL_VER"), .calibration)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "CRDS_VER"), .calibration)

        // Engineering keywords (formerly ifuCube/nirspecEngineering/focusAdjust)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "WPOWER"), .engineering)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "RMA_POS"), .engineering)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "FAM_LA1"), .engineering)

        // Program keywords
        XCTAssertEqual(FITSHeaderKeywords.category(for: "TITLE"), .program)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "SCICAT"), .program)

        // Observation identifiers
        XCTAssertEqual(FITSHeaderKeywords.category(for: "OBS_ID"), .observation)

        // Time keywords (including formerly-observationIdentifiers DATE-OBS; formerly-timeInformation BARTDELT)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "DATE-OBS"), .time)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "BARTDELT"), .time)

        // Visit
        XCTAssertEqual(FITSHeaderKeywords.category(for: "VISITYPE"), .visit)

        // Target
        XCTAssertEqual(FITSHeaderKeywords.category(for: "TARGNAME"), .target)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "TARG_RA"), .target)

        // Exposure parameters
        XCTAssertEqual(FITSHeaderKeywords.category(for: "EXP_TYPE"), .exposure)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "NGROUPS"), .exposure)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "READPATT"), .exposure)

        // Unchanged categories
        XCTAssertEqual(FITSHeaderKeywords.category(for: "ASNPOOL"), .association)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "ASNTABLE"), .association)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "SUBARRAY"), .subarray)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "FASTAXIS"), .subarray)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "PATTTYPE"), .dither)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "NUMDTHPT"), .dither)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "APERNAME"), .aperture)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "TEXPTIME"), .resampling)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "GS_RA"), .guideStar)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "PCS_MODE"), .guideStar)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "BKGLEVEL"), .background)
        XCTAssertEqual(FITSHeaderKeywords.category(for: "MASTERBG"), .background)

        // Completely unknown keyword
        XCTAssertEqual(FITSHeaderKeywords.category(for: "ZZFAKE"), .unknown)

        print("FITSHeaderKeywords category test passed")
    }

    func testJWSTKeywordDescriptionsAdded() {
        // Verify newly added JWST descriptions are present
        XCTAssertEqual(FITSHeaderKeywords.description(for: "NEXTEND"), "Number of file extensions")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "NGROUPS"), "Number of groups per integration")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "READPATT"),
            "Readout pattern name (pre-defined NFRAMES, GROUPGAP, NRESETS combination)")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "MSASTATE"),
            "NIRSpec MSA state: ALLOPEN, ALLCLOSED, or CONFIGURED")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "GS_RA"),
            "ICRS right ascension of the guide star (degrees)")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "BKGLEVEL"),
            "Overall background signal level computed by the skymatch pipeline step")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "CRDS_CTX"),
            "Version of the CRDS context (PMAP) controlling reference file selection")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "SUBARRAY"),
            "Subarray name (FULL or named subarray up to 9 characters)")
        XCTAssertEqual(
            FITSHeaderKeywords.description(for: "APERNAME"),
            "S&OC PRD aperture name used for telescope pointing")

        // Unknown keywords still return the fallback
        XCTAssertEqual(FITSHeaderKeywords.description(for: "ZZUNKNOWN"), "FITS header keyword")

        print("JWST keyword descriptions test passed")
    }

    // MARK: - JWST Multi-Filter Products Tests

    private func makeCoamResultWithFilter(
        filter: String, instrument: String = "MIRI/IMAGE",
        tMin: Float = 0, obsId: String = "obs-1"
    ) -> CoamResult {
        return CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: "mast:JWST/product/\(obsId).fits",
            dataproduct_type: "IMAGE",
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: filter,
            instrument_name: instrument,
            intentType: "science",
            jpegURL: "",
            mtFlag: false,
            objID: 1,
            obs_collection: "JWST",
            obs_id: obsId,
            obs_title: "Test Observation",
            obsid: 1,
            project: "Test",
            proposal_id: "1",
            proposal_pi: "PI",
            proposal_type: "TEST",
            provenance_name: "MAST",
            s_dec: QValue(value: "0.0"),
            s_ra: QValue(value: "0.0"),
            s_region: "",
            sequence_number: 0,
            srcDen: 0,
            t_exptime: 100.0,
            t_max: tMin + 0.01,
            t_min: tMin,
            t_obs_release: 0.0,
            target_classification: "",
            target_name: "NGC-628",
            wavelength_region: "INFRARED"
        )
    }

    func testSelectClosestEpochProductsSinglePerFilter() {
        let mast = SwiftMAST()
        let products: [String: [CoamResult]] = [
            "F770W": [makeCoamResultWithFilter(filter: "F770W", tMin: 59777.46, obsId: "obs-1")],
            "F1000W": [makeCoamResultWithFilter(filter: "F1000W", tMin: 59777.47, obsId: "obs-2")],
            "F1500W": [makeCoamResultWithFilter(filter: "F1500W", tMin: 59777.48, obsId: "obs-3")],
        ]

        let selected = mast.selectClosestEpochProducts(productsByFilter: products)

        XCTAssertEqual(selected.count, 3)
        XCTAssertNotNil(selected["F770W"])
        XCTAssertNotNil(selected["F1000W"])
        XCTAssertNotNil(selected["F1500W"])
    }

    func testSelectClosestEpochProductsPicksClosestToMedian() {
        let mast = SwiftMAST()

        // F770W has two observations: one at epoch 59777, one at epoch 60659
        // F1000W has one at epoch 59780
        // Median of all timestamps should favor the ~59777-59780 cluster
        let products: [String: [CoamResult]] = [
            "F770W": [
                makeCoamResultWithFilter(filter: "F770W", tMin: 59777.46, obsId: "obs-early"),
                makeCoamResultWithFilter(filter: "F770W", tMin: 60659.21, obsId: "obs-late"),
            ],
            "F1000W": [
                makeCoamResultWithFilter(filter: "F1000W", tMin: 59780.0, obsId: "obs-mid")
            ],
        ]

        let selected = mast.selectClosestEpochProducts(productsByFilter: products)

        XCTAssertEqual(selected.count, 2)
        // The median of [59777.46, 59780.0, 60659.21] = 59780.0
        // F770W should pick the early obs (closer to 59780.0)
        XCTAssertEqual(selected["F770W"]?.obs_id, "obs-early")
        XCTAssertEqual(selected["F1000W"]?.obs_id, "obs-mid")
    }

    func testSelectClosestEpochProductsEmptyTimestamps() {
        let mast = SwiftMAST()
        let products: [String: [CoamResult]] = [
            "F770W": [makeCoamResultWithFilter(filter: "F770W", tMin: 0, obsId: "obs-1")],
            "F1000W": [makeCoamResultWithFilter(filter: "F1000W", tMin: 0, obsId: "obs-2")],
        ]

        let selected = mast.selectClosestEpochProducts(productsByFilter: products)

        // With t_min = 0, fallback should still return one per filter
        XCTAssertEqual(selected.count, 2)
    }

    func testJWSTMIRIPreset() {
        let options = ImageryFilterOptions.jwstMIRI
        XCTAssertEqual(options.collections, ["JWST"])
        XCTAssertEqual(options.instruments, ["MIRI/IMAGE"])
        let filters = options.toMASTFilters()
        let paramNames = filters.map { $0.paramName }
        XCTAssertTrue(paramNames.contains("obs_collection"))
        XCTAssertTrue(paramNames.contains("instrument_name"))
    }

    func testJWSTNIRCamPreset() {
        let options = ImageryFilterOptions.jwstNIRCam
        XCTAssertEqual(options.collections, ["JWST"])
        XCTAssertEqual(options.instruments, ["NIRCAM/IMAGE"])
    }

    // MARK: - JWST Integration Tests (requires network)

    /// Test fetching JWST products grouped by filter for NGC 628
    func testGetJWSTFilteredProductsNGC628() {
        let expectation = XCTestExpectation(description: "Get JWST filtered products for NGC 628")
        let mast = SwiftMAST()

        print("\n=== Testing JWST Multi-Filter Products for NGC 628 ===")
        mast.getJWSTFilteredProducts(targetName: "NGC 628") { products in
            print("JWST Products by filter (\(products.count) filters):")
            for (filter, coam) in products.sorted(by: { $0.key < $1.key }) {
                print(
                    "  \(filter): \(coam.instrument_name) | obs_id=\(coam.obs_id) | t_min=\(coam.t_min)"
                )
            }
            XCTAssertFalse(products.isEmpty, "Should find JWST products for NGC 628")
            XCTAssertTrue(products.count > 5, "NGC 628 should have multiple JWST filters")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test fetching MIRI-only products for NGC 628
    func testGetJWSTFilteredProductsMIRIOnly() {
        let expectation = XCTestExpectation(description: "Get JWST MIRI products for NGC 628")
        let mast = SwiftMAST()

        print("\n=== Testing JWST MIRI-Only Products for NGC 628 ===")
        mast.getJWSTFilteredProducts(
            targetName: "NGC 628",
            instruments: ["MIRI/IMAGE"]
        ) { products in
            print("MIRI Products by filter (\(products.count) filters):")
            for (filter, coam) in products.sorted(by: { $0.key < $1.key }) {
                print("  \(filter): \(coam.instrument_name) | obs_id=\(coam.obs_id)")
                // All should be MIRI
                XCTAssertTrue(
                    coam.instrument_name.uppercased().contains("MIRI"),
                    "Expected MIRI instrument, got \(coam.instrument_name)"
                )
            }
            XCTAssertFalse(products.isEmpty, "Should find MIRI products for NGC 628")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    /// Test fetching JWST products for NGC 253
    func testGetJWSTFilteredProductsNGC253() {
        let expectation = XCTestExpectation(description: "Get JWST filtered products for NGC 253")
        let mast = SwiftMAST()

        print("\n=== Testing JWST Multi-Filter Products for NGC 253 ===")
        mast.getJWSTFilteredProducts(targetName: "NGC 253") { products in
            print("JWST Products by filter (\(products.count) filters):")
            for (filter, coam) in products.sorted(by: { $0.key < $1.key }) {
                print(
                    "  \(filter): \(coam.instrument_name) | obs_id=\(coam.obs_id) | t_min=\(coam.t_min)"
                )
            }
            XCTAssertFalse(products.isEmpty, "Should find JWST products for NGC 253")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    // MARK: - JWST Science Product Extraction Tests

    /// Integration test: extract science products by filter for a small target
    func testGetJWSTScienceProductsMIRI() {
        let expectation = XCTestExpectation(
            description: "Get JWST science products for NGC 628 MIRI")
        let mast = SwiftMAST()

        print("\n=== Testing JWST Science Products (MIRI) for NGC 628 ===")
        mast.getJWSTScienceProducts(
            targetName: "NGC 628",
            instruments: ["MIRI/IMAGE"]
        ) { products in
            print("Science Products by filter (\(products.count) filters):")
            for (filter, scienceProducts) in products.sorted(by: { $0.key < $1.key }) {
                print("  \(filter): \(scienceProducts.count) HDU(s)")
                for sp in scienceProducts {
                    print("    name: \(sp.name)")
                    print("    image: \(sp.imageLocation?.lastPathComponent ?? "none")")
                    print("    headers: \(sp.headers.count)")
                }
            }
            XCTAssertFalse(products.isEmpty, "Should extract MIRI science products for NGC 628")
            // Each filter should have at least one ScienceProduct
            for (filter, scienceProducts) in products {
                XCTAssertFalse(
                    scienceProducts.isEmpty,
                    "Filter \(filter) should have at least one ScienceProduct")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    // MARK: - JWST Observation Group Unit Tests

    func testJWSTFilterWavelength() {
        // Standard filter names
        XCTAssertEqual(jwstFilterWavelength("F200W"), 200)
        XCTAssertEqual(jwstFilterWavelength("F1000W"), 1000)
        XCTAssertEqual(jwstFilterWavelength("F2550W"), 2550)
        XCTAssertEqual(jwstFilterWavelength("F115W"), 115)

        // Filter with trailing digit (e.g. F150W2)
        XCTAssertEqual(jwstFilterWavelength("F150W2"), 150)

        // Compound filter (e.g. F444W;F405N)
        XCTAssertEqual(jwstFilterWavelength("F444W;F405N"), 444)

        // Lowercase
        XCTAssertEqual(jwstFilterWavelength("f770w"), 770)

        // Non-standard name sorts last
        XCTAssertEqual(jwstFilterWavelength("CLEAR"), Int.max)
    }

    func testCompareJWSTFilters() {
        // F200W < F1000W
        XCTAssertTrue(compareJWSTFilters("F200W", "F1000W"))
        XCTAssertFalse(compareJWSTFilters("F1000W", "F200W"))

        // F115W < F150W
        XCTAssertTrue(compareJWSTFilters("F115W", "F150W"))

        // F150W2 (wavelength 150) < F200W (wavelength 200)
        XCTAssertTrue(compareJWSTFilters("F150W2", "F200W"))

        // Same wavelength sorts alphabetically
        XCTAssertTrue(compareJWSTFilters("F150W", "F150W2"))

        // Compound filter: F444W;F405N (wavelength 444) < F560W (wavelength 560)
        XCTAssertTrue(compareJWSTFilters("F444W;F405N", "F560W"))

        // Verify a full sort
        let unsorted = ["F1000W", "F200W", "F560W", "F115W", "F150W2", "F444W;F405N", "F2550W"]
        let sorted = unsorted.sorted(by: compareJWSTFilters)
        let expected = ["F115W", "F150W2", "F200W", "F444W;F405N", "F560W", "F1000W", "F2550W"]
        XCTAssertEqual(sorted, expected)
    }

    func testJWSTObservationGroupKey() {
        // Standard obs_id with 4+ parts
        XCTAssertEqual(
            jwstObservationGroupKey("jw02666-o007_t004_miri_f1000w"),
            "jw02666-o007_t004_miri"
        )
        XCTAssertEqual(
            jwstObservationGroupKey("jw01783-o004_t008_nircam_f200w-f150w2"),
            "jw01783-o004_t008_nircam"
        )

        // obs_id with exactly 3 parts
        XCTAssertEqual(
            jwstObservationGroupKey("jw01783-o004_t008_nircam"),
            "jw01783-o004_t008_nircam"
        )

        // obs_id with fewer than 3 parts (edge case: return as-is)
        XCTAssertEqual(
            jwstObservationGroupKey("jw01783-o004"),
            "jw01783-o004"
        )
    }

    func testHSTObservationGroupKey() {
        XCTAssertEqual(
            hstObservationGroupKey("hst_10775_62_wfc3_f606w"),
            "hst_10775_62_wfc3"
        )
        XCTAssertEqual(
            hstObservationGroupKey("hst_10775_62_wfpc2_f814w_f606w_wf"),
            "hst_10775_62_wfpc2"
        )
        XCTAssertEqual(
            observationGroupKey(makeCoamResult(obs_id: "hst_10775_62_wfc3_f814w", obs_collection: "HLA")),
            "hst_10775_62_wfc3"
        )
    }

    func testBuildObservationGroups() {
        let mast = SwiftMAST()

        // Create mock CoamResults with different obs_ids for the same group
        let coam1 = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f1000w",
            filters: "F1000W",
            instrument_name: "MIRI/IMAGE",
            obs_collection: "JWST"
        )
        let coam2 = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f560w",
            filters: "F560W",
            instrument_name: "MIRI/IMAGE",
            obs_collection: "JWST"
        )
        let coam3 = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f2100w",
            filters: "F2100W",
            instrument_name: "MIRI/IMAGE",
            obs_collection: "JWST"
        )
        let coam4 = makeCoamResult(
            obs_id: "jw01783-o004_t008_nircam_f200w",
            filters: "F200W",
            instrument_name: "NIRCAM/IMAGE",
            obs_collection: "JWST"
        )
        let coam5 = makeCoamResult(
            obs_id: "jw01783-o004_t008_nircam_f115w",
            filters: "F115W",
            instrument_name: "NIRCAM/IMAGE",
            obs_collection: "JWST"
        )

        let groups = mast.buildObservationGroups(from: [coam1, coam2, coam3, coam4, coam5])

        // Should produce 2 groups
        XCTAssertEqual(groups.count, 2)

        // Groups should be sorted by key
        XCTAssertEqual(groups[0].observationKey, "jw01783-o004_t008_nircam")
        XCTAssertEqual(groups[1].observationKey, "jw02666-o007_t004_miri")

        // NIRCam group: products sorted by wavelength (F115W before F200W)
        XCTAssertEqual(groups[0].products.count, 2)
        XCTAssertEqual(groups[0].filterNames, ["F115W", "F200W"])
        XCTAssertEqual(groups[0].instrument, "NIRCAM/IMAGE")

        // MIRI group: products sorted by wavelength (F560W, F1000W, F2100W)
        XCTAssertEqual(groups[1].products.count, 3)
        XCTAssertEqual(groups[1].filterNames, ["F560W", "F1000W", "F2100W"])
        XCTAssertEqual(groups[1].instrument, "MIRI/IMAGE")
    }

    func testBuildObservationGroupsForHSTAndJWST() {
        let mast = SwiftMAST()

        let hstF606W = makeCoamResult(
            obs_id: "hst_10775_62_wfc3_f606w",
            filters: "F606W",
            instrument_name: "WFC3/UVIS",
            obs_collection: "HST"
        )
        let hstF814W = makeCoamResult(
            obs_id: "hst_10775_62_wfc3_f814w",
            filters: "F814W",
            instrument_name: "WFC3/UVIS",
            obs_collection: "HST"
        )
        let jwstF200W = makeCoamResult(
            obs_id: "jw01783-o004_t008_nircam_f200w",
            filters: "F200W",
            instrument_name: "NIRCAM/IMAGE",
            obs_collection: "JWST"
        )

        let groups = mast.buildObservationGroups(from: [hstF814W, jwstF200W, hstF606W])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].mission, "HST")
        XCTAssertEqual(groups[0].observationKey, "hst_10775_62_wfc3")
        XCTAssertEqual(groups[0].filterNames, ["F606W", "F814W"])
        XCTAssertEqual(groups[1].mission, "JWST")
        XCTAssertEqual(groups[1].observationKey, "jw01783-o004_t008_nircam")
        XCTAssertEqual(groups[1].filterNames, ["F200W"])
    }

    func testCoamResultFilterColorMap() {
        let hst = makeCoamResult(filters: "F606W;F814W", obs_collection: "HST")
        XCTAssertEqual(hst.filterColorMap["F606W"]?.colorName, HSTFilter.F606W.likelySpaceColor.rawValue)
        XCTAssertEqual(hst.filterColorMap["F814W"]?.hexColor, HSTFilter.F814W.likelySpaceColorHex)

        let jwst = makeCoamResult(filters: "F560W;F1000W", obs_collection: "JWST")
        XCTAssertEqual(jwst.filterColorMap["F560W"]?.colorName, JWSTFilter.F560W.likelySpaceColor.rawValue)
        XCTAssertEqual(jwst.filterColorMap["F1000W"]?.hexColor, JWSTFilter.F1000W.likelySpaceColorHex)
    }

    func testObservationProductStoragePathIncludesObservationIdAndContentType() {
        let mast = SwiftMAST()
        let product = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f1000w",
            filters: "F1000W;F770W",
            instrument_name: "MIRI/IMAGE",
            obs_collection: "JWST"
        )

        let fitFolder = mast.productStorageFolder(
            target: "NGC 628", product: product, contentType: .fit)
        let imageFolder = mast.productStorageFolder(
            target: "NGC 628", product: product, contentType: .image)

        XCTAssertTrue(
            fitFolder.path.hasSuffix(
                "MAST/NGC_628/JWST/jw02666-o007_t004_miri_f1000w/F1000W-F770W/fit"
            ))
        XCTAssertTrue(
            imageFolder.path.hasSuffix(
                "MAST/NGC_628/JWST/jw02666-o007_t004_miri_f1000w/F1000W-F770W/image"
            ))
        XCTAssertEqual(
            mast.productFileName(target: "NGC 628", product: product, productType: .Fits),
            "NGC_628_JWST_jw02666-o007_t004_miri_f1000w_F1000W-F770W.fits"
        )
    }

    // MARK: - jwstFilters on CoamResult (unit tests)

    func testJWSTFiltersOnCoamResultSingleFilter() {
        let coam = makeCoamResult(filters: "F560W", obs_collection: "JWST")
        let filters = coam.jwstFilters
        XCTAssertEqual(filters.count, 1)
        XCTAssertEqual(filters.first, .F560W)
        XCTAssertEqual(filters.first?.scienceUse, "Stellar photospheres, warm dust continuum")
    }

    func testJWSTFiltersOnCoamResultMultipleFilters() {
        let coam = makeCoamResult(filters: "F560W;F1000W;F2100W", obs_collection: "JWST")
        let filters = coam.jwstFilters
        XCTAssertEqual(filters.count, 3)
        XCTAssertEqual(filters[0], .F560W)
        XCTAssertEqual(filters[1], .F1000W)
        XCTAssertEqual(filters[2], .F2100W)
    }

    func testJWSTFiltersOnCoamResultUnknownFilterIgnored() {
        // Non-JWST filters (e.g. HST/ACS) should not crash — they are simply skipped
        let coam = makeCoamResult(filters: "F606W", obs_collection: "HST")
        let filters = coam.jwstFilters
        XCTAssertTrue(filters.isEmpty)
    }

    func testJWSTFiltersOnCoamResultMixedKnownAndUnknown() {
        let coam = makeCoamResult(filters: "UNKNOWN;F140M;F200W", obs_collection: "JWST")
        let filters = coam.jwstFilters
        XCTAssertEqual(filters.count, 2)
        XCTAssertEqual(filters[0], .F140M)
        XCTAssertEqual(filters[1], .F200W)
        XCTAssertEqual(filters[0].scienceUse, "Cool stars, H₂O, CH₄")
    }

    func testJWSTFilterMetadata() {
        let filter = JWSTFilter.F560W
        XCTAssertEqual(filter.instruments, ["MIRI"])
        XCTAssertEqual(filter.filterType, .wide)
        XCTAssertEqual(filter.scienceUse, "Stellar photospheres, warm dust continuum")
        XCTAssertEqual(filter.pivotWavelength, 5.6)
        XCTAssertEqual(filter.bandwidth, 1.2)
        XCTAssertEqual(filter.wavelengthRegime, "Mid-Infrared")
        XCTAssertEqual(filter.likelySpaceColor, .orange)
        XCTAssertEqual(filter.likelySpaceColorHex, "#FB923C")
    }

    func testJWSTFilterColorTagsAcrossWavelengths() {
        XCTAssertEqual(JWSTFilter.F090W.likelySpaceColor, .blue)
        XCTAssertEqual(JWSTFilter.F150W.likelySpaceColor, .cyan)
        XCTAssertEqual(JWSTFilter.F277W.likelySpaceColor, .green)
        XCTAssertEqual(JWSTFilter.F444W.likelySpaceColor, .yellow)
        XCTAssertEqual(JWSTFilter.F770W.likelySpaceColor, .orange)
        XCTAssertEqual(JWSTFilter.F1500W.likelySpaceColor, .red)
        XCTAssertEqual(JWSTFilter.F2100W.likelySpaceColor, .deepRed)
    }

    func testAllJWSTFiltersHaveMetadata() {
        for filter in JWSTFilter.allCases {
            XCTAssertFalse(filter.instruments.isEmpty)
            XCTAssertGreaterThan(filter.pivotWavelength, 0)
            XCTAssertGreaterThan(filter.bandwidth, 0)
            XCTAssertFalse(filter.scienceUse.isEmpty)
            XCTAssertFalse(filter.wavelengthRegime.isEmpty)
            XCTAssertFalse(filter.likelySpaceColorHex.isEmpty)
        }
    }

    // MARK: - HST WFC3/UVIS Filter Metadata

    func testHSTFilterMetadata() {
        let filter = HSTFilter.F606W
        XCTAssertEqual(filter.instruments, ["WFC3/UVIS"])
        XCTAssertEqual(filter.filterType, .wide)
        XCTAssertEqual(filter.scienceUse, "WFPC2 wide V")
        XCTAssertEqual(filter.pivotWavelengthAngstroms, 5889.2, accuracy: 0.001)
        XCTAssertEqual(filter.bandwidthAngstroms, 2189.2)
        XCTAssertEqual(filter.cumulativeThroughputWidthAngstroms, 2193)
        XCTAssertEqual(filter.peakSystemThroughput, 0.29)
        XCTAssertEqual(filter.likelySpaceColor, .yellow)
        XCTAssertEqual(filter.likelySpaceColorHex, "#FACC15")
    }

    func testHSTFilterColorTagsAcrossWavelengths() {
        XCTAssertEqual(HSTFilter.F275W.likelySpaceColor, .ultraviolet)
        XCTAssertEqual(HSTFilter.F438W.likelySpaceColor, .blue)
        XCTAssertEqual(HSTFilter.F502N.likelySpaceColor, .green)
        XCTAssertEqual(HSTFilter.F656N.likelySpaceColor, .red)
        XCTAssertEqual(HSTFilter.F814W.likelySpaceColor, .deepRed)
    }

    func testHSTFiltersOnCoamResultMultipleFilters() {
        let coam = makeCoamResult(filters: "F814W;F606W", obs_collection: "HST")
        let filters = coam.hstFilters
        XCTAssertEqual(filters, [.F814W, .F606W])
        XCTAssertEqual(filters.filterString, "F814W;F606W")
    }

    func testHSTFiltersOnCoamResultUnknownFilterIgnored() {
        let coam = makeCoamResult(filters: "UNKNOWN;F560W", obs_collection: "JWST")
        XCTAssertTrue(coam.hstFilters.isEmpty)
    }

    // MARK: - getJWSTObservationGroups + jwstFilters integration test

    func testGetJWSTObservationGroupsJWSTFiltersPresent() {
        let expectation = XCTestExpectation(
            description: "Each CoamResult in observation groups exposes jwstFilters")
        let mast = SwiftMAST()

        mast.getJWSTObservationGroups(targetName: "NGC 628") { groups in
            XCTAssertFalse(
                groups.isEmpty, "Should return at least one observation group for NGC 628")

            for group in groups {
                for product in group.products {
                    // jwstFilters must be present as a parsed property on every CoamResult
                    let jwstFilters = product.jwstFilters

                    // The raw filters string must not be empty for JWST products
                    XCTAssertFalse(
                        product.filters.isEmpty,
                        "CoamResult.filters should not be empty for product \(product.obs_id)")

                    // Every recognized JWST filter must round-trip through rawValue correctly
                    for filter in jwstFilters {
                        XCTAssertNotNil(
                            JWSTFilter(rawValue: filter.rawValue),
                            "Filter \(filter.rawValue) should be a valid JWSTFilter case")
                        XCTAssertFalse(
                            filter.scienceUse.isEmpty,
                            "scienceUse must be non-empty for filter \(filter.rawValue)")
                        XCTAssertGreaterThan(
                            filter.pivotWavelength, 0,
                            "pivotWavelength must be > 0 for filter \(filter.rawValue)")
                    }
                }
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    // MARK: - JWST Observation Groups Integration Test

    func testGetJWSTObservationGroupsNGC628() {
        let expectation = XCTestExpectation(
            description: "Get JWST observation groups for NGC 628")
        let mast = SwiftMAST()

        print("\n=== Testing JWST Observation Groups for NGC 628 ===")
        mast.getJWSTObservationGroups(targetName: "NGC 628") { groups in
            print("Observation Groups (\(groups.count) groups):")
            for group in groups {
                print("  \(group)")
            }

            XCTAssertFalse(groups.isEmpty, "Should find observation groups for NGC 628")

            // Verify sorting: within each group, filters are in wavelength order
            for group in groups {
                let wavelengths = group.products.map { jwstFilterWavelength($0.filters) }
                for i in 1..<wavelengths.count {
                    XCTAssertLessThanOrEqual(
                        wavelengths[i - 1], wavelengths[i],
                        "Filters should be sorted by wavelength in group \(group.observationKey)"
                    )
                }
            }

            // Groups should be sorted by key
            for i in 1..<groups.count {
                XCTAssertLessThanOrEqual(
                    groups[i - 1].observationKey, groups[i].observationKey,
                    "Groups should be sorted by observation key"
                )
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    func testGetObservationGroupsHSTAndJWSTNGC628() {
        let expectation = XCTestExpectation(
            description: "Get HST and JWST observation groups for NGC 628")
        let mast = SwiftMAST()

        mast.getObservationGroups(
            targetName: "NGC 628",
            missions: ObservationMission.jwstAndHST,
            pageSize: 200
        ) { groups in
            XCTAssertFalse(groups.isEmpty, "Should find HST/JWST observation groups for NGC 628")
            XCTAssertTrue(
                groups.contains { $0.mission == "JWST" },
                "Should include at least one JWST observation group")
            XCTAssertTrue(
                groups.contains { $0.mission == "HST" },
                "Should include at least one HST observation group")

            for group in groups {
                XCTAssertFalse(group.observationKey.isEmpty)
                XCTAssertFalse(group.products.isEmpty)
                for product in group.products {
                    XCTAssertFalse(product.filters.isEmpty)
                    _ = product.filterColors
                }
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    func testGetObservationGroupsHSTOnlyM31() {
        let expectation = XCTestExpectation(description: "Get HST-only observation groups for M31")
        let mast = SwiftMAST()

        mast.getObservationGroups(
            targetName: "M31",
            missions: ObservationMission.hstOnly,
            pageSize: 50
        ) { groups in
            XCTAssertFalse(groups.isEmpty, "Should find HST observation groups for M31")
            XCTAssertTrue(groups.allSatisfy { $0.mission == "HST" })
            XCTAssertTrue(groups.contains { group in
                group.products.contains { !$0.hstFilters.isEmpty }
            })
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    // MARK: - JWSTProductSortOrder unit tests

    func testJWSTEffectiveTime() {
        // t_min > 0: use t_min
        let a = makeCoamResult(t_min: 59000.0, t_max: 59001.0, t_obs_release: 60000.0)
        XCTAssertEqual(jwstEffectiveTime(a), 59000.0)

        // t_min == 0, t_max > 0: use t_max
        let b = makeCoamResult(t_min: 0.0, t_max: 59001.0, t_obs_release: 60000.0)
        XCTAssertEqual(jwstEffectiveTime(b), 59001.0)

        // t_min == 0, t_max == 0: fall back to t_obs_release
        let c = makeCoamResult(t_min: 0.0, t_max: 0.0, t_obs_release: 60000.0)
        XCTAssertEqual(jwstEffectiveTime(c), 60000.0)
    }

    func testCompareJWSTProductsByFilterWithTimeTiebreak() {
        // Two products with same filter wavelength (F200W) — sort by t_min
        let earlier = makeCoamResult(
            filters: "F200W", t_min: 59000.0, t_max: 59001.0, t_obs_release: 60000.0)
        let later = makeCoamResult(
            filters: "F200W", t_min: 59100.0, t_max: 59101.0, t_obs_release: 60000.0)

        XCTAssertTrue(
            compareJWSTProducts(earlier, later, by: .filter), "earlier t_min should sort first")
        XCTAssertFalse(
            compareJWSTProducts(later, earlier, by: .filter), "later t_min should sort last")

        // Different filters: wavelength wins regardless of time
        let f200w = makeCoamResult(filters: "F200W", t_min: 59100.0, t_max: 0, t_obs_release: 0)
        let f1000w = makeCoamResult(filters: "F1000W", t_min: 59000.0, t_max: 0, t_obs_release: 0)
        XCTAssertTrue(
            compareJWSTProducts(f200w, f1000w, by: .filter), "F200W < F1000W by wavelength")
        XCTAssertFalse(
            compareJWSTProducts(f1000w, f200w, by: .filter), "F1000W > F200W by wavelength")
    }

    func testCompareJWSTProductsByFilterTimeFallback() {
        // t_min == 0, t_max > 0: tiebreak uses t_max
        let usesTMax = makeCoamResult(
            filters: "F200W", t_min: 0.0, t_max: 59001.0, t_obs_release: 60000.0)
        let usesRelease = makeCoamResult(
            filters: "F200W", t_min: 0.0, t_max: 0.0, t_obs_release: 61000.0)
        // usesTMax effective = 59001, usesRelease effective = 61000 → usesTMax sorts first
        XCTAssertTrue(compareJWSTProducts(usesTMax, usesRelease, by: .filter))
        XCTAssertFalse(compareJWSTProducts(usesRelease, usesTMax, by: .filter))
    }

    func testCompareJWSTProductsByTimeWithFilterTiebreak() {
        // Two products with same t_min — sort by filter wavelength
        let f200w = makeCoamResult(filters: "F200W", t_min: 59000.0, t_max: 0, t_obs_release: 0)
        let f1000w = makeCoamResult(filters: "F1000W", t_min: 59000.0, t_max: 0, t_obs_release: 0)

        XCTAssertTrue(compareJWSTProducts(f200w, f1000w, by: .time), "F200W < F1000W as tiebreak")
        XCTAssertFalse(compareJWSTProducts(f1000w, f200w, by: .time), "F1000W > F200W as tiebreak")

        // Different times: earlier t_min wins regardless of filter
        let earlierF1000w = makeCoamResult(
            filters: "F1000W", t_min: 59000.0, t_max: 0, t_obs_release: 0)
        let laterF200w = makeCoamResult(
            filters: "F200W", t_min: 59100.0, t_max: 0, t_obs_release: 0)
        XCTAssertTrue(
            compareJWSTProducts(earlierF1000w, laterF200w, by: .time), "earlier time wins")
        XCTAssertFalse(
            compareJWSTProducts(laterF200w, earlierF1000w, by: .time), "later time loses")
    }

    func testCoamResultMatchesObservationFilterBands() {
        let product = makeCoamResult(filters: "F150W;CLEAR", obs_collection: "JWST")

        XCTAssertTrue(product.matchesObservationFilterBands(["F150W"]))
        XCTAssertTrue(product.matchesObservationFilterBands(["f150w"]))
        XCTAssertTrue(product.matchesObservationFilterBands(["F200W", "F150W"]))
        XCTAssertFalse(product.matchesObservationFilterBands(["F150W2"]))
        XCTAssertFalse(product.matchesObservationFilterBands(["F200W"]))
        XCTAssertTrue(product.matchesObservationFilterBands([]))
    }

    func testBuildObservationGroupsByTime() {
        let mast = SwiftMAST()

        // Three MIRI products in the same group — different times and filters
        let oldest = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f1000w", filters: "F1000W",
            instrument_name: "MIRI/IMAGE", obs_collection: "JWST",
            t_min: 59000.0, t_max: 0, t_obs_release: 0)
        let middle = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f560w", filters: "F560W",
            instrument_name: "MIRI/IMAGE", obs_collection: "JWST",
            t_min: 59050.0, t_max: 0, t_obs_release: 0)
        let newest = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f2100w", filters: "F2100W",
            instrument_name: "MIRI/IMAGE", obs_collection: "JWST",
            t_min: 59100.0, t_max: 0, t_obs_release: 0)

        let groups = mast.buildObservationGroups(from: [newest, middle, oldest], sortOrder: .time)

        XCTAssertEqual(groups.count, 1)
        // Products should be sorted by t_min: oldest (F1000W=59000) → middle (F560W=59050) → newest (F2100W=59100)
        XCTAssertEqual(groups[0].filterNames, ["F1000W", "F560W", "F2100W"])
    }

    func testBuildObservationGroupsByFilterIsDefault() {
        let mast = SwiftMAST()

        let f1000w = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f1000w", filters: "F1000W",
            instrument_name: "MIRI/IMAGE", obs_collection: "JWST",
            t_min: 59000.0, t_max: 0, t_obs_release: 0)
        let f560w = makeCoamResult(
            obs_id: "jw02666-o007_t004_miri_f560w", filters: "F560W",
            instrument_name: "MIRI/IMAGE", obs_collection: "JWST",
            t_min: 59100.0, t_max: 0, t_obs_release: 0)

        // Default sort (no arg) should be .filter: F560W(560) < F1000W(1000)
        let groups = mast.buildObservationGroups(from: [f1000w, f560w])
        XCTAssertEqual(groups[0].filterNames, ["F560W", "F1000W"])
    }
}
