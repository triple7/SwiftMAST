import Foundation
import XCTest

@testable import SwiftMAST

final class QueryCacheTests: XCTestCase {
    override func tearDown() {
        QueryCacheMockURLProtocol.requestHandler = nil
        SwiftMAST.queryRequestProtocolClasses = nil
        SwiftMAST().resetQueryCache()
        super.tearDown()
    }

    func testQueryMastUsesCachedResponseForSameInputs() {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        mast.currentTargetId = "cache-target"
        SwiftMAST.queryRequestProtocolClasses = [QueryCacheMockURLProtocol.self]

        var requestCount = 0
        QueryCacheMockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Self.tablePayload(value: "network")
            )
        }

        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: Float(1.0), MAP.dec: Float(2.0), MAP.radius: Float(0.2)])

        let first = expectation(description: "First query returns")
        mast.queryMast(service: service, params: params, returnType: .json) { success in
            XCTAssertTrue(success)
            XCTAssertEqual(mast.targets["cache-target"]?.getStringValues(for: "target_name"), ["network"])
            first.fulfill()
        }
        wait(for: [first], timeout: 2)

        mast.targets.removeAll()
        mast.currentTargetId = "cache-target"

        let second = expectation(description: "Second query returns from cache")
        mast.queryMast(service: service, params: params, returnType: .json) { success in
            XCTAssertTrue(success)
            XCTAssertEqual(mast.targets["cache-target"]?.getStringValues(for: "target_name"), ["network"])
            second.fulfill()
        }
        wait(for: [second], timeout: 2)

        XCTAssertEqual(requestCount, 1)
    }

    func testQueryCacheKeyChangesWhenInputsChange() {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        mast.currentTargetId = "cache-target"
        SwiftMAST.queryRequestProtocolClasses = [QueryCacheMockURLProtocol.self]

        var requestCount = 0
        QueryCacheMockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Self.tablePayload(value: "network-\(requestCount)")
            )
        }

        let service = Service.Mast_Caom_Cone
        var firstParams = service.serviceRequest(requestType: .coneSearch)
        firstParams.setParameters(params: [MAP.ra: Float(1.0), MAP.dec: Float(2.0), MAP.radius: Float(0.2)])
        var secondParams = service.serviceRequest(requestType: .coneSearch)
        secondParams.setParameters(params: [MAP.ra: Float(1.0), MAP.dec: Float(2.0), MAP.radius: Float(0.3)])

        let first = expectation(description: "First query returns")
        mast.queryMast(service: service, params: firstParams, returnType: .json) { success in
            XCTAssertTrue(success)
            first.fulfill()
        }
        wait(for: [first], timeout: 2)

        mast.currentTargetId = "cache-target"
        let second = expectation(description: "Changed query returns")
        mast.queryMast(service: service, params: secondParams, returnType: .json) { success in
            XCTAssertTrue(success)
            second.fulfill()
        }
        wait(for: [second], timeout: 2)

        XCTAssertEqual(requestCount, 2)
    }

    func testExpiredQueryCacheIsIgnoredAndReplaced() {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        mast.currentTargetId = "cache-target"
        SwiftMAST.queryRequestProtocolClasses = [QueryCacheMockURLProtocol.self]

        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: Float(1.0), MAP.dec: Float(2.0), MAP.radius: Float(0.2)])
        var extendedParams = params
        extendedParams.setParameter(param: MAP.format, value: APIReturnType.json.id as Any)
        let key = mast.mastQueryCacheKey(service: service, returnType: .json, params: extendedParams)!

        mast.storeCachedQueryResponse(
            Self.tablePayload(value: "expired"),
            key: key,
            service: service.id,
            returnType: APIReturnType.json.id,
            createdAt: Date(timeIntervalSinceNow: -(SwiftMAST.defaultQueryCacheTTL + 60))
        )

        var requestCount = 0
        QueryCacheMockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Self.tablePayload(value: "fresh")
            )
        }

        let complete = expectation(description: "Expired query fetches")
        mast.queryMast(service: service, params: params, returnType: .json) { success in
            XCTAssertTrue(success)
            XCTAssertEqual(mast.targets["cache-target"]?.getStringValues(for: "target_name"), ["fresh"])
            complete.fulfill()
        }
        wait(for: [complete], timeout: 2)

        XCTAssertEqual(requestCount, 1)
    }

    func testFailedQueryResponseIsNotCached() {
        let mast = SwiftMAST()
        mast.resetQueryCache()
        mast.currentTargetId = "cache-target"
        SwiftMAST.queryRequestProtocolClasses = [QueryCacheMockURLProtocol.self]

        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: Float(1.0), MAP.dec: Float(2.0), MAP.radius: Float(0.2)])

        var extendedParams = params
        extendedParams.setParameter(param: MAP.format, value: APIReturnType.json.id as Any)
        let key = mast.mastQueryCacheKey(service: service, returnType: .json, params: extendedParams)!

        QueryCacheMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let complete = expectation(description: "Failed query returns")
        mast.queryMast(service: service, params: params, returnType: .json) { success in
            XCTAssertFalse(success)
            complete.fulfill()
        }
        wait(for: [complete], timeout: 2)

        XCTAssertNil(mast.cachedQueryResponse(key: key))
    }

    func testResetQueryCacheRemovesStoredEntries() {
        let mast = SwiftMAST()
        mast.resetQueryCache()

        let key = "mast-test-reset"
        mast.storeCachedQueryResponse(
            Self.tablePayload(value: "stored"),
            key: key,
            service: Service.Mast_Caom_Cone.id,
            returnType: APIReturnType.json.id
        )

        XCTAssertNotNil(mast.cachedQueryResponse(key: key))
        mast.resetQueryCache()
        XCTAssertNil(mast.cachedQueryResponse(key: key))
    }

    private static func tablePayload(value: String) -> Data {
        """
        {
          "fields": [
            { "name": "target_name", "type": "string" }
          ],
          "data": [
            { "target_name": "\(value)" }
          ]
        }
        """.data(using: .utf8)!
    }
}

private final class QueryCacheMockURLProtocol: URLProtocol {
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
