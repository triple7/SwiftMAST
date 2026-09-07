import Foundation
import SwiftQValue
import XCTest

@testable import SwiftMAST

final class CoamResultLocalResourcesTests: XCTestCase {
    func testPositionalInitializerReadsObjectIDFromObjectIDColumn() {
        var row = (0..<34).map { QValue(value: "value-\($0)") }
        row[0] = QValue(value: "3")
        row[10] = QValue(value: "https://example.com/preview.jpg")
        row[11] = QValue(value: "true")
        row[12] = QValue(value: "42")
        row[13] = QValue(value: "JWST")
        row[14] = QValue(value: "jw-test")
        row[27] = QValue(value: "10")
        row[28] = QValue(value: "20")
        row[29] = QValue(value: "15")
        row[30] = QValue(value: "30")

        let result = CoamResult(data: row)

        XCTAssertEqual(result.objID, 42)
        XCTAssertEqual(result.jpegURL, "https://example.com/preview.jpg")
        XCTAssertEqual(result.obs_collection, "JWST")
        XCTAssertEqual(result.obs_id, "jw-test")
    }

    func testPositionalInitializerSafelyHandlesPartialRows() {
        let result = CoamResult(data: [QValue(value: "2")])

        XCTAssertEqual(result.calib_level, 2)
        XCTAssertEqual(result.objID, 0)
        XCTAssertEqual(result.filters, "")
        XCTAssertEqual(result.dataURL, "")
    }

    func testLocalResultRoundTripsResourcesAndCapabilities() throws {
        let resources = CoamLocalResources(
            fitsPath: "/tmp/science.fits",
            imagePath: "/tmp/science.png",
            previewImagePath: "/tmp/preview.jpg"
        )
        let result = CoamResult(
            localTargetName: "NGC 628",
            mission: "JWST",
            observationID: "jw-test",
            filter: "F770W",
            localResources: resources
        )

        let decoded = try JSONDecoder().decode(
            CoamResult.self,
            from: JSONEncoder().encode(result)
        )

        XCTAssertEqual(decoded.localFITSURL?.path, "/tmp/science.fits")
        XCTAssertEqual(decoded.preferredLocalImageURL?.path, "/tmp/science.png")
        XCTAssertEqual(decoded.wavelengthMicrons ?? 0, 7.7, accuracy: 0.0001)
        XCTAssertTrue(decoded.isLocallyRenderable)
    }

    func testLocalCacheWithoutSidecarProducesCanonicalCoamResult() throws {
        let mast = SwiftMAST()
        let targetName = "LocalCanonical\(UUID().uuidString)"
        let targetFolder = mast.mastStorageRootURL()
            .appendingPathComponent(targetName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: targetFolder) }

        let imageFolder = targetFolder
            .appendingPathComponent("JWST", isDirectory: true)
            .appendingPathComponent("jw-local-observation", isDirectory: true)
            .appendingPathComponent("F770W", isDirectory: true)
            .appendingPathComponent("image", isDirectory: true)
        try FileManager.default.createDirectory(
            at: imageFolder,
            withIntermediateDirectories: true
        )
        let imageURL = imageFolder.appendingPathComponent("local.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: imageURL)

        let results = mast.getLocalCoamResults(targetName: targetName)
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.obs_collection, "JWST")
        XCTAssertEqual(result.obs_id, "jw-local-observation")
        XCTAssertEqual(result.filters, "F770W")
        XCTAssertEqual(result.localImageURL, imageURL)
        let groups = mast.getCachedObservationGroups(targetName: targetName)
        let groupedProduct = try XCTUnwrap(groups.first?.products.first)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groupedProduct.productIdentifier, result.productIdentifier)
        XCTAssertEqual(groupedProduct.localImageURL, imageURL)
    }

    func testCacheDataProductsReturnsLocallyEnrichedCoamResults() throws {
        let mast = SwiftMAST()
        let targetName = "CoamCache\(UUID().uuidString)"
        let targetFolder = mast.mastStorageRootURL()
            .appendingPathComponent(targetName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: targetFolder) }

        var row = (0..<34).map { _ in QValue(value: "") }
        row[7] = QValue(value: "F606W")
        row[8] = QValue(value: "ACS/WFC")
        row[10] = QValue(value: "https://example.invalid/not-requested.jpg")
        row[13] = QValue(value: "HST")
        row[14] = QValue(value: "obs-cache-coam")
        row[32] = QValue(value: targetName)
        let product = CoamResult(data: row)

        let cachedURL = mast.localProductURL(
            targetName: targetName,
            product: product,
            productType: .Jpeg
        )
        try FileManager.default.createDirectory(
            at: cachedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: cachedURL)

        let expectation = expectation(description: "Canonical cache result returns")
        mast.cacheDataProducts(
            targetName: targetName,
            products: [product],
            productType: .Jpeg,
            token: nil
        ) { products in
            XCTAssertEqual(products.count, 1)
            XCTAssertEqual(products.first?.productIdentifier, product.productIdentifier)
            XCTAssertEqual(products.first?.localPreviewImageURL, cachedURL)
            XCTAssertEqual(products.first?.jpegURL, product.jpegURL)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testCoamResultOwnsFilterIdentityAndImageMappingKeys() {
        let product = CoamResult(
            localTargetName: "NGC 628",
            mission: "JWST",
            observationID: "jw02107-o039_t018_miri_f770w",
            filter: "F770W; CLEAR",
            localResources: CoamLocalResources(imagePath: "/tmp/F770W image.png")
        )

        XCTAssertEqual(product.primaryFilterName, "F770W")
        XCTAssertEqual(product.primaryFilterColor?.filterName, "F770W")
        XCTAssertEqual(product.imageMappingKey, product.productIdentifier)
        XCTAssertFalse(product.imageFileSafeKey.contains(" "))
        XCTAssertFalse(product.imageFileSafeKey.contains(":"))
        XCTAssertTrue(product.isRenderableScienceImage())
    }

    func testObservationImageAssignmentsAreIndexedByProductKeyAndWavelength() {
        let longWave = CoamResult(
            localTargetName: "NGC 628",
            mission: "JWST",
            observationID: "jw-test-f1000w",
            filter: "F1000W",
            localResources: CoamLocalResources(imagePath: "/tmp/F1000W.png")
        )
        let shortWave = CoamResult(
            localTargetName: "NGC 628",
            mission: "JWST",
            observationID: "jw-test-f200w",
            filter: "F200W",
            localResources: CoamLocalResources(imagePath: "/tmp/F200W.png")
        )

        let assignments = [longWave, shortWave].observationImageAssignments()

        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(assignments[shortWave.imageMappingKey]?.paletteIndex, 0)
        XCTAssertEqual(assignments[longWave.imageMappingKey]?.paletteIndex, 1)
        XCTAssertEqual(assignments[shortWave.imageMappingKey]?.paletteCount, 2)
    }

    func testRenderableScienceProductsFiltersDetectionAndSegmentation() {
        let science = CoamResult(
            localTargetName: "Target",
            mission: "JWST",
            observationID: "science",
            filter: "F770W",
            localResources: CoamLocalResources(imagePath: "/tmp/science.png")
        )
        let detection = CoamResult(
            localTargetName: "Target",
            mission: "JWST",
            observationID: "detection",
            filter: "DETECTION",
            localResources: CoamLocalResources(imagePath: "/tmp/detection.png")
        )
        let segmentation = CoamResult(
            localTargetName: "Target",
            mission: "JWST",
            observationID: "segmentation",
            filter: "F770W",
            localResources: CoamLocalResources(imagePath: "/tmp/source_segm.png")
        )

        XCTAssertEqual(
            [science, detection, segmentation].renderableScienceImages().map(\.obs_id),
            ["science"]
        )
        XCTAssertEqual(
            [science, detection, segmentation]
                .renderableScienceImages(includeSegmentationProducts: true)
                .map(\.obs_id),
            ["science", "segmentation"]
        )
    }

    func testObservationGroupSelectsScienceProductsUsingWCSPolicyAndLimit() {
        let wcsOne = makeLocalProduct(
            observationID: "wcs-one",
            filter: "F200W",
            fitsPath: "/tmp/wcs-one.fits"
        )
        let rasterOnly = makeLocalProduct(
            observationID: "raster-only",
            filter: "F444W",
            imagePath: "/tmp/raster-only.png"
        )
        let wcsTwo = makeLocalProduct(
            observationID: "wcs-two",
            filter: "F770W",
            fitsPath: "/tmp/wcs-two.fits"
        )
        let group = ObservationGroup(
            mission: "JWST",
            observationKey: "jw-test",
            instrument: "NIRCAM",
            products: [wcsOne, rasterOnly, wcsTwo]
        )

        XCTAssertEqual(
            group.selectedScienceProducts(
                maximumCount: 10,
                wcsPolicy: .required
            ).map(\.obs_id),
            ["wcs-one", "wcs-two"]
        )
        XCTAssertEqual(
            group.selectedScienceProducts(
                maximumCount: 1,
                wcsPolicy: .preferred(minimumCount: 2)
            ).map(\.obs_id),
            ["wcs-one"]
        )
        XCTAssertEqual(
            group.selectedScienceProducts(
                maximumCount: 10,
                wcsPolicy: .preferred(minimumCount: 3)
            ).map(\.obs_id),
            ["wcs-one", "raster-only", "wcs-two"]
        )
        XCTAssertTrue(
            group.selectedScienceProducts(maximumCount: 0).isEmpty
        )
    }

    private func makeLocalProduct(
        observationID: String,
        filter: String,
        fitsPath: String? = nil,
        imagePath: String? = nil
    ) -> CoamResult {
        CoamResult(
            localTargetName: "Target",
            mission: "JWST",
            observationID: observationID,
            filter: filter,
            localResources: CoamLocalResources(
                fitsPath: fitsPath,
                imagePath: imagePath
            )
        )
    }
}
