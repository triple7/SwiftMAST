import FITS
import SwiftQValue
import XCTest
@testable import SwiftMAST

final class FITSObservationProductTests: XCTestCase {
    func testHduRoleClassifierUsesExtensionNames() {
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [header("EXTNAME", .string("SCI"))]),
            .science
        )
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [header("EXTNAME", .string("WHT"))]),
            .weight
        )
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [header("EXTNAME", .string("ERR"))]),
            .error
        )
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [header("EXTNAME", .string("DQ"))]),
            .dataQuality
        )
    }

    func testHduRoleClassifierUsesFilenameHints() {
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [], sourceFilename: "target_f444w_wht.fits"),
            .weight
        )
        XCTAssertEqual(
            FITSHDURoleClassifier.classify(headers: [], sourceFilename: "target_f444w_sci.fits"),
            .science
        )
    }

    func testWCSParsesCDMatrixAndRoundTripsPixelCoordinate() throws {
        let headers = [
            header("CRPIX1", .double(10)),
            header("CRPIX2", .double(20)),
            header("CRVAL1", .double(150)),
            header("CRVAL2", .double(2)),
            header("CTYPE1", .string("RA---TAN")),
            header("CTYPE2", .string("DEC--TAN")),
            header("CD1_1", .double(-0.0001)),
            header("CD1_2", .double(0)),
            header("CD2_1", .double(0)),
            header("CD2_2", .double(0.0001)),
        ]

        let wcs = try XCTUnwrap(FITSWCS(headers: headers))
        let world = wcs.worldCoordinate(x: 9, y: 19)
        XCTAssertEqual(world.ra, 150, accuracy: 1e-12)
        XCTAssertEqual(world.dec, 2, accuracy: 1e-12)

        let pixel = try XCTUnwrap(wcs.pixelCoordinate(ra: world.ra, dec: world.dec))
        XCTAssertEqual(pixel.x, 9, accuracy: 1e-9)
        XCTAssertEqual(pixel.y, 19, accuracy: 1e-9)
    }

    func testWCSParsesPCMatrixWithCDELT() throws {
        let headers = [
            header("CRPIX1", .double(1)),
            header("CRPIX2", .double(1)),
            header("CRVAL1", .double(10)),
            header("CRVAL2", .double(20)),
            header("CTYPE1", .string("RA---TAN")),
            header("CTYPE2", .string("DEC--TAN")),
            header("CDELT1", .double(0.25)),
            header("CDELT2", .double(0.5)),
            header("PC1_1", .double(1)),
            header("PC1_2", .double(0)),
            header("PC2_1", .double(0)),
            header("PC2_2", .double(1)),
        ]

        let wcs = try XCTUnwrap(FITSWCS(headers: headers))
        let world = wcs.worldCoordinate(x: 2, y: 4)
        XCTAssertEqual(world.ra, 10.5, accuracy: 1e-12)
        XCTAssertEqual(world.dec, 22, accuracy: 1e-12)
    }

    func testExtractFITSObservationProductDecodesScienceAndWeightPlanes() throws {
        let fitsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("fits")
        defer { try? FileManager.default.removeItem(at: fitsURL) }

        let file = makeSyntheticFitsFile()
        var data = Data()
        try file.write(to: &data)
        try data.write(to: fitsURL)

        let product = try XCTUnwrap(
            SwiftMAST().extractFITSObservationProduct(
                fitsUrl: fitsURL,
                coamResult: makeCoamResult()
            )
        )

        XCTAssertGreaterThanOrEqual(product.planes.count, 2)

        let science = try XCTUnwrap(product.planes.first { $0.role == .science })
        XCTAssertEqual(science.extName, "SCI")
        XCTAssertEqual(science.extIndex, 1)
        XCTAssertEqual(science.width, 2)
        XCTAssertEqual(science.height, 2)
        XCTAssertEqual(science.pixels.bitpix, 16)
        XCTAssertEqual(science.pixels.values, [1, 2, 3, 4])
        XCTAssertNotNil(science.wcs)

        let weight = try XCTUnwrap(product.planes.first { $0.role == .weight })
        XCTAssertEqual(weight.extName, "WHT")
        XCTAssertEqual(weight.extIndex, 2)
        XCTAssertEqual(weight.pixels.values, [10, 20, 30, 40])

        let pair = try XCTUnwrap(product.preferredScienceWeightPair)
        XCTAssertEqual(pair.science.extName, "SCI")
        XCTAssertEqual(pair.weight?.extName, "WHT")
        XCTAssertEqual(product.weightPlane(matching: science)?.extIndex, 2)
    }

    func testExtractFITSObservationProductRejectsTruncatedInput() throws {
        let fitsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("fits")
        defer { try? FileManager.default.removeItem(at: fitsURL) }

        try Data("SIMPLE  =                    T".utf8).write(to: fitsURL)

        let product = SwiftMAST().extractFITSObservationProduct(
            fitsUrl: fitsURL,
            coamResult: makeCoamResult()
        )

        XCTAssertNil(product)
    }

    func testExtractFITSObservationProductRejectsNonFITSInput() throws {
        let fitsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("fits")
        defer { try? FileManager.default.removeItem(at: fitsURL) }

        try Data("<html>not a fits file</html>".utf8).write(to: fitsURL)

        let product = SwiftMAST().extractFITSObservationProduct(
            fitsUrl: fitsURL,
            coamResult: makeCoamResult()
        )

        XCTAssertNil(product)
    }

    func testParseFITSHeaderSummaryReadsImageExtensionWithoutImageBytes() throws {
        let data = makePartialFITSHeaderData()
        let summary = try XCTUnwrap(
            SwiftMAST().parseFITSHeaderSummary(
                data: data,
                sourceURL: URL(string: "https://example.com/test.fits")!,
                remoteFileSizeBytes: 123_456_789
            )
        )

        XCTAssertEqual(summary.bytesFetched, data.count)
        XCTAssertEqual(summary.remoteFileSizeBytes, 123_456_789)
        XCTAssertEqual(summary.parsedHeaderCount, 2)
        XCTAssertFalse(summary.reachedEndOfAvailableHeaders)
        XCTAssertEqual(summary.primaryHeaders.first?.keyword, "SIMPLE")

        let image = try XCTUnwrap(summary.preferredImageHDU)
        XCTAssertEqual(image.extIndex, 1)
        XCTAssertEqual(image.extName, "SCI")
        XCTAssertEqual(image.role, .science)
        XCTAssertEqual(image.width, 4654)
        XCTAssertEqual(image.height, 4648)
        XCTAssertEqual(image.axisCount, 2)
        XCTAssertEqual(image.bitpix, -32)
        XCTAssertEqual(image.dataOffset, 5760)
        XCTAssertEqual(image.dataSizeBytes, 86_527_168)
        XCTAssertNotNil(image.wcs)
        XCTAssertEqual(image.wcs?.crval1 ?? 0, 254.2253014526158, accuracy: 1e-12)
        XCTAssertEqual(image.wcs?.crval2 ?? 0, -4.022223357292208, accuracy: 1e-12)
    }

    func testFetchFITSHeaderSummaryUsesRangeRequest() throws {
        let data = makePartialFITSHeaderData()
        let expectedURL = URL(string: "https://example.com/test.fits")!
        let expectation = expectation(description: "Fetch FITS header summary")

        FITSHeaderSummaryMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-5759")

            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 206,
                httpVersion: nil,
                headerFields: [
                    "Content-Range": "bytes 0-5759/123456789",
                    "Content-Length": "\(data.count)",
                ]
            )!
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FITSHeaderSummaryMockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        SwiftMAST().fetchFITSHeaderSummary(
            from: expectedURL,
            initialByteCount: data.count,
            maxByteCount: data.count,
            session: session
        ) { summary in
            XCTAssertEqual(summary?.remoteFileSizeBytes, 123_456_789)
            XCTAssertEqual(summary?.preferredImageHDU?.width, 4654)
            XCTAssertEqual(summary?.preferredImageHDU?.height, 4648)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        FITSHeaderSummaryMockURLProtocol.requestHandler = nil
    }

    private func makeSyntheticFitsFile() -> FitsFile {
        let primary = PrimaryHDU(width: 1, height: 1, vectors: [FITSByte_16](arrayLiteral: 0))
        primary.hasExtensions = true

        let science = ImageHDU(width: 2, height: 2, vectors: [FITSByte_16](arrayLiteral: 1, 2, 3, 4))
        addImageHeaders(to: science, extName: "SCI")

        let weight = ImageHDU(width: 2, height: 2, vectors: [FITSByte_16](arrayLiteral: 10, 20, 30, 40))
        addImageHeaders(to: weight, extName: "WHT")

        let file = FitsFile(prime: primary)
        file.HDUs.append(science)
        file.HDUs.append(weight)
        return file
    }

    private func makePartialFITSHeaderData() -> Data {
        var data = Data()
        data.append(
            makeFITSHeaderBlock([
                fitsCard("SIMPLE", "T", "conforms to FITS standard"),
                fitsCard("BITPIX", "8", "array data type"),
                fitsCard("NAXIS", "0", "number of data array dimensions"),
                fitsCard("EXTEND", "T", "extensions may be present"),
            ]))
        data.append(
            makeFITSHeaderBlock([
                fitsCard("XTENSION", "'IMAGE'", "image extension"),
                fitsCard("BITPIX", "-32", "array data type"),
                fitsCard("NAXIS", "2", "number of axes"),
                fitsCard("NAXIS1", "4654", "axis 1 length"),
                fitsCard("NAXIS2", "4648", "axis 2 length"),
                fitsCard("EXTNAME", "'SCI'", "extension name"),
                fitsCard("CRPIX1", "2327.0", nil),
                fitsCard("CRPIX2", "2324.0", nil),
                fitsCard("CRVAL1", "254.2253014526158", nil),
                fitsCard("CRVAL2", "-4.022223357292208", nil),
                fitsCard("CTYPE1", "'RA---TAN'", nil),
                fitsCard("CTYPE2", "'DEC--TAN'", nil),
                fitsCard("CD1_1", "-0.0000277777778", nil),
                fitsCard("CD1_2", "0.0", nil),
                fitsCard("CD2_1", "0.0", nil),
                fitsCard("CD2_2", "0.0000277777778", nil),
            ]))
        return data
    }

    private func makeFITSHeaderBlock(_ cards: [String]) -> Data {
        var text = cards.joined()
        text += paddedFITSCard("END")
        let paddingLength = (2880 - (text.utf8.count % 2880)) % 2880
        text += String(repeating: " ", count: paddingLength)
        return Data(text.utf8)
    }

    private func fitsCard(_ keyword: String, _ value: String, _ comment: String?) -> String {
        var card = keyword.padding(toLength: 8, withPad: " ", startingAt: 0) + "= "
        card += value.padding(toLength: 20, withPad: " ", startingAt: 0)
        if let comment {
            card += " / \(comment)"
        }
        return paddedFITSCard(card)
    }

    private func paddedFITSCard(_ value: String) -> String {
        String(value.prefix(80)).padding(toLength: 80, withPad: " ", startingAt: 0)
    }

    private func addImageHeaders(to image: ImageHDU, extName: String) {
        image.header("EXTNAME", value: extName, comment: nil)
        image.header("CRPIX1", value: Float(1.0), comment: nil)
        image.header("CRPIX2", value: Float(1.0), comment: nil)
        image.header("CRVAL1", value: Float(150.0), comment: nil)
        image.header("CRVAL2", value: Float(2.0), comment: nil)
        image.header("CTYPE1", value: "RA---TAN", comment: nil)
        image.header("CTYPE2", value: "DEC--TAN", comment: nil)
        image.header("CD1_1", value: Float(-0.0001), comment: nil)
        image.header("CD1_2", value: Float(0.0), comment: nil)
        image.header("CD2_1", value: Float(0.0), comment: nil)
        image.header("CD2_2", value: Float(0.0001), comment: nil)
    }

    private func makeCoamResult() -> CoamResult {
        CoamResult(
            calib_level: 3,
            dataRights: "PUBLIC",
            dataURL: "",
            dataproduct_type: "IMAGE",
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: "F606W",
            instrument_name: "ACS",
            intentType: "science",
            jpegURL: "",
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
            target_name: "NGC 628",
            wavelength_region: "OPTICAL"
        )
    }

    private func header(_ keyword: String, _ value: FITSHeaderValue) -> FITSHeaderUnit {
        FITSHeaderUnit(keyword: keyword, value: value, comment: "")
    }
}

private final class FITSHeaderSummaryMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
