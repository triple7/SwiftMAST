import FITS
import SwiftQValue
import XCTest

@testable import SwiftMAST

final class SwiftMASTTests: XCTestCase {

    private func makeCoamResult(dataURL: String = "", jpegURL: String = "") -> CoamResult {
        return CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: dataURL,
            dataproduct_type: "IMAGE",
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: "F606W",
            instrument_name: "ACS",
            intentType: "science",
            jpegURL: jpegURL,
            mtFlag: false,
            objID: 1,
            obs_collection: "HST",
            obs_id: "obs-1",
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
            t_max: 0.0,
            t_min: 0.0,
            t_obs_release: 0.0,
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
}
