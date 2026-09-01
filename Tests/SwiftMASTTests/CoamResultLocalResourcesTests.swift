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
        XCTAssertEqual(mast.getCachedObservationGroups(targetName: targetName).count, 1)
    }
}
