import Foundation
import XCTest
@testable import SwiftMASTFunctionGraphCore

final class SwiftSourceExtractorTests: XCTestCase {
    func testExtractsDefaultsOwnerAndRecursiveObjectOutput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMASTFunctionGraphTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        public struct ResultRow {
            public let identifier: String
            public let values: [Double]
        }
        public final class Client {
            /// Performs a typed query.
            public func query(service: String, limit: Int = 50) -> ResultRow? { nil }
        }
        """
        try source.write(to: directory.appendingPathComponent("Input.swift"), atomically: true, encoding: .utf8)

        let graph = try SwiftSourceExtractor().extract(module: "Fixture", sourceRoot: directory)
        let function = try XCTUnwrap(graph.functions.first { $0.name == "query" })
        XCTAssertEqual(function.ownerType, "Client")
        XCTAssertEqual(function.arguments.map(\.label), ["service", "limit"])
        XCTAssertEqual(function.arguments[1].defaultValue, "50")
        XCTAssertEqual(function.output.kind, .optional)
        XCTAssertEqual(function.output.element?.kind, .object)
        XCTAssertEqual(function.output.element?.fields?.map(\.name), ["identifier", "values"])
        XCTAssertEqual(function.documentation, "Performs a typed query.")
        XCTAssertEqual(graph.pipeline.count, 7)
        XCTAssertEqual(graph.edges.filter { $0.kind == .dataFlow }.count, 6)
    }

    func testOverloadsHaveUniqueIDsAndOperatorsKeepNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMASTFunctionGraphTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        public struct Value {
            public init(value: Int) {}
            public init(value: String) {}
            public static func == (lhs: Value, rhs: Value) -> Bool { true }
        }
        """
        try source.write(to: directory.appendingPathComponent("Input.swift"), atomically: true, encoding: .utf8)
        let graph = try SwiftSourceExtractor().extract(module: "Fixture", sourceRoot: directory)
        XCTAssertEqual(Set(graph.functions.map(\.id)).count, graph.functions.count)
        XCTAssertNotNil(graph.functions.first { $0.name == "==" })
    }

    func testJSONFirstRenderersProduceOrderedPresentations() throws {
        let graph = FunctionGraph(
            module: "Fixture", generatedAt: "2026-01-01T00:00:00Z",
            pipeline: [
                PipelineStage(id: "input", name: "Input", output: "String"),
                PipelineStage(id: "result", name: "Result", input: "String", output: "Value"),
            ], functions: [], edges: [FunctionEdge(from: "input", to: "result", kind: .dataFlow)])
        let data = try FunctionGraphRenderer.json(graph)
        let canonical = try JSONDecoder().decode(FunctionGraph.self, from: data)
        XCTAssertTrue(FunctionGraphRenderer.mermaid(canonical).contains("stage0 --> stage1"))
        XCTAssertTrue(FunctionGraphRenderer.mermaidDetailed(canonical).contains("flowchart LR"))
        let html = try FunctionGraphRenderer.html(canonical)
        XCTAssertTrue(html.contains("lane-layer"))
        XCTAssertTrue(html.contains("fetch('./function-graph.json')"))
        XCTAssertFalse(html.contains("application/json"))
    }
}
