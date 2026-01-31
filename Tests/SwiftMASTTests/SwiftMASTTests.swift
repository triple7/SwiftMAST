import SwiftQValue
import XCTest

@testable import SwiftMAST

final class SwiftMASTTests: XCTestCase {

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
}
