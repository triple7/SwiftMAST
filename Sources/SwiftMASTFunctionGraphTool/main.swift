import Foundation
import SwiftMASTFunctionGraphCore

struct Options {
    var source = "Sources/SwiftMAST"
    var output = "Documentation/FunctionGraph"
    var module = "SwiftMAST"

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch arguments[index] {
            case "--source" where value != nil: source = value!; index += 1
            case "--output" where value != nil: output = value!; index += 1
            case "--module" where value != nil: module = value!; index += 1
            case "--help", "-h":
                print("Usage: swift run swiftmast-function-graph [--source PATH] [--output PATH] [--module NAME]")
                exit(0)
            default:
                fputs("Unknown or incomplete option: \(arguments[index])\n", stderr)
                exit(2)
            }
            index += 1
        }
    }
}

do {
    let options = Options(arguments: CommandLine.arguments)
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let sourceURL = URL(fileURLWithPath: options.source, relativeTo: cwd).standardizedFileURL
    let outputURL = URL(fileURLWithPath: options.output, relativeTo: cwd).standardizedFileURL
    let graph = try SwiftSourceExtractor().extract(module: options.module, sourceRoot: sourceURL)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let jsonData = try FunctionGraphRenderer.json(graph)
    try jsonData.write(to: outputURL.appendingPathComponent("function-graph.json"))

    // Presentations are produced from the exact serialized JSON artifact.
    let canonicalGraph = try JSONDecoder().decode(FunctionGraph.self, from: jsonData)
    try FunctionGraphRenderer.mermaid(canonicalGraph).write(
        to: outputURL.appendingPathComponent("function-graph.mmd"), atomically: true, encoding: .utf8)
    try FunctionGraphRenderer.mermaidDetailed(canonicalGraph).write(
        to: outputURL.appendingPathComponent("function-graph-detail.mmd"), atomically: true, encoding: .utf8)
    try FunctionGraphRenderer.html(canonicalGraph).write(
        to: outputURL.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    print("Generated \(canonicalGraph.functions.count) functions and \(canonicalGraph.edges.count) edges in \(outputURL.path)")
} catch {
    fputs("swiftmast-function-graph: \(error.localizedDescription)\n", stderr)
    exit(1)
}
