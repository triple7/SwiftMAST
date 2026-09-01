import Foundation

public enum FunctionGraphError: Error, LocalizedError {
    case unreadableSource(String)
    case noSwiftSources(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableSource(let path): return "Could not read Swift source at \(path)"
        case .noSwiftSources(let path): return "No Swift source files found below \(path)"
        }
    }
}

public struct SwiftSourceExtractor {
    private struct TypeScope {
        var name: String
        var kind: String
        var openBrace: Int
        var closeBrace: Int
        var fields: [(String, String)]
    }

    private struct Candidate {
        var node: FunctionNode
        var body: String
    }

    public init() {}

    public func extract(module: String, sourceRoot: URL) throws -> FunctionGraph {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FunctionGraphError.unreadableSource(sourceRoot.path)
        }

        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw FunctionGraphError.noSwiftSources(sourceRoot.path) }

        var candidates: [Candidate] = []
        var objectFields: [String: [(String, String)]] = [:]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = relative(file, to: sourceRoot)
            let extraction = extractFile(source, file: relativePath)
            candidates.append(contentsOf: extraction.candidates)
            for scope in extraction.scopes where scope.kind == "struct" || scope.kind == "class" {
                if !scope.fields.isEmpty { objectFields[scope.name] = scope.fields }
            }
        }

        for index in candidates.indices {
            let rawName = candidates[index].node.output.name ?? "Void"
            candidates[index].node.output = shape(for: rawName, objects: objectFields, visited: [])
        }

        let functions = candidates.map(\.node).sorted { $0.id < $1.id }
        let pipeline = pipelineStages()
        var edges = inferCallEdges(candidates)
        edges.append(contentsOf: pipelineEdges())
        return FunctionGraph(
            module: module,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            pipeline: pipeline,
            functions: functions,
            edges: edges
        )
    }

    private func pipelineStages() -> [PipelineStage] {
        [
            PipelineStage(id: "stage.input", name: "Target or service input", output: "Target / coordinates / service"),
            PipelineStage(
                id: "stage.resolve", name: "Resolve target", input: "Target name", output: "RA / Dec / radius",
                description: "Optionally resolves a target name to sky coordinates."),
            PipelineStage(
                id: "stage.request", name: "Build request", input: "Service + parameters", output: "MASTJson / TAP / URLRequest",
                description: "Constructs MAST, TAP, PS1, NED, or product requests."),
            PipelineStage(
                id: "stage.network", name: "Execute query", input: "URLRequest", output: "Data / file URL",
                description: "Uses cache or network services and records request telemetry."),
            PipelineStage(
                id: "stage.parse", name: "Parse response", input: "JSON / XML / FITS", output: "MASTTable / metadata",
                description: "Decodes archive responses into SwiftMAST models."),
            PipelineStage(
                id: "stage.enrich", name: "Enrich or download", input: "Products", output: "Sizes / FITS headers / local files",
                description: "Optionally enriches products or downloads science data."),
            PipelineStage(
                id: "stage.result", name: "Typed result", input: "Parsed products", output: "CoamResult / ObservationGroup / ScienceProduct",
                description: "Returns typed results through the public API completion handler."),
        ]
    }

    private func pipelineEdges() -> [FunctionEdge] {
        [
            FunctionEdge(from: "stage.input", to: "stage.resolve", kind: .dataFlow),
            FunctionEdge(from: "stage.resolve", to: "stage.request", kind: .dataFlow),
            FunctionEdge(from: "stage.request", to: "stage.network", kind: .dataFlow),
            FunctionEdge(from: "stage.network", to: "stage.parse", kind: .dataFlow),
            FunctionEdge(from: "stage.parse", to: "stage.enrich", kind: .dataFlow),
            FunctionEdge(from: "stage.enrich", to: "stage.result", kind: .dataFlow),
        ]
    }

    private func extractFile(_ source: String, file: String) -> (candidates: [Candidate], scopes: [TypeScope]) {
        let masked = maskCommentsAndStrings(source)
        let maskedNSString = masked as NSString
        let sourceNSString = source as NSString
        var scopes = extractScopes(maskedNSString, source: sourceNSString)
        extractFields(&scopes, masked: maskedNSString, source: sourceNSString)

        let pattern = #"\bpublic\s+(?:(?:static|class|final|mutating|nonmutating|override|required|convenience)\s+)*(func|init|subscript)\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: masked, range: NSRange(location: 0, length: maskedNSString.length))
        var result: [Candidate] = []

        for match in matches {
            let kind = maskedNSString.substring(with: match.range(at: 1))
            guard let openParen = find("(", in: maskedNSString, from: NSMaxRange(match.range)),
                  let closeParen = matchingDelimiter(in: maskedNSString, opening: openParen, open: "(", close: ")")
            else { continue }

            let owner = scopes
                .filter { $0.openBrace < match.range.location && match.range.location < $0.closeBrace }
                .min { ($0.closeBrace - $0.openBrace) < ($1.closeBrace - $1.openBrace) }?.name

            let name: String
            if kind == "func" {
                let between = sourceNSString.substring(
                    with: NSRange(location: NSMaxRange(match.range(at: 1)), length: openParen - NSMaxRange(match.range(at: 1))))
                name = firstIdentifier(in: between)
                    ?? between.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).first.map(String.init)
                    ?? "unknown"
            } else {
                name = kind
            }

            let parameterText = sourceNSString.substring(
                with: NSRange(location: openParen + 1, length: closeParen - openParen - 1))
            let arguments = parseArguments(parameterText)
            let declarationEnd = findDeclarationEnd(maskedNSString, from: closeParen + 1)
            let tail = sourceNSString.substring(
                with: NSRange(location: closeParen + 1, length: max(0, declarationEnd - closeParen - 1)))
            let returnType = parseReturnType(tail) ?? "Void"
            let line = 1 + sourceNSString.substring(to: match.range.location).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            let signature = arguments.map { "\($0.label):\($0.type)" }.joined(separator: ",")
            // Swift permits overloads distinguished only by contextual return
            // type, so the return type is part of the stable graph identity.
            let id = "\(owner.map { "\($0)." } ?? "")\(name)(\(signature))->\(returnType)"
            let body: String
            if declarationEnd < maskedNSString.length,
               maskedNSString.substring(with: NSRange(location: declarationEnd, length: 1)) == "{",
               let bodyEnd = matchingDelimiter(in: maskedNSString, opening: declarationEnd, open: "{", close: "}") {
                body = sourceNSString.substring(
                    with: NSRange(location: declarationEnd + 1, length: max(0, bodyEnd - declarationEnd - 1)))
            } else {
                body = ""
            }

            result.append(Candidate(
                node: FunctionNode(
                    id: id,
                    name: name,
                    ownerType: owner,
                    arguments: arguments,
                    output: .value(returnType),
                    isAsync: containsWord("async", in: tail),
                    canThrow: containsWord("throws", in: tail) || containsWord("rethrows", in: tail),
                    documentation: documentation(before: match.range.location, in: sourceNSString),
                    source: SourceLocation(file: file, line: line)
                ),
                body: body
            ))
        }
        return (result, scopes)
    }

    private func extractScopes(_ masked: NSString, source: NSString) -> [TypeScope] {
        let pattern = #"\b(?:public\s+)?(?:final\s+)?(struct|class|enum|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_.]*)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = masked as String
        return regex.matches(in: text, range: NSRange(location: 0, length: masked.length)).compactMap { match in
            guard let open = find("{", in: masked, from: NSMaxRange(match.range)),
                  let close = matchingDelimiter(in: masked, opening: open, open: "{", close: "}")
            else { return nil }
            return TypeScope(
                name: source.substring(with: match.range(at: 2)),
                kind: source.substring(with: match.range(at: 1)),
                openBrace: open,
                closeBrace: close,
                fields: []
            )
        }
    }

    private func extractFields(_ scopes: inout [TypeScope], masked: NSString, source: NSString) {
        let regex = try! NSRegularExpression(
            pattern: #"\bpublic\s+(?:private\s*\(\s*set\s*\)\s+)?(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^\n={]+)"#
        )
        let text = masked as String
        for index in scopes.indices {
            let range = NSRange(
                location: scopes[index].openBrace + 1,
                length: max(0, scopes[index].closeBrace - scopes[index].openBrace - 1))
            scopes[index].fields = regex.matches(in: text, range: range).compactMap { match in
                guard !scopes.contains(where: {
                    $0.openBrace > scopes[index].openBrace && $0.openBrace < match.range.location
                        && match.range.location < $0.closeBrace && $0.closeBrace < scopes[index].closeBrace
                }) else { return nil }
                let name = source.substring(with: match.range(at: 1))
                let type = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                return (name, type)
            }
        }
    }

    private func parseArguments(_ text: String) -> [ArgumentDescriptor] {
        splitTopLevel(text, separator: ",").compactMap { raw in
            let part = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty, let colon = topLevelIndex(of: ":", in: part) else { return nil }
            let lhs = String(part[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            var rhs = String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let equal = topLevelIndex(of: "=", in: rhs)
            let defaultValue: String?
            if let equal {
                defaultValue = String(rhs[rhs.index(after: equal)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                rhs = String(rhs[..<equal]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                defaultValue = nil
            }
            let names = lhs.split(whereSeparator: \.isWhitespace).map(String.init)
                .filter { !$0.hasPrefix("@") && $0 != "inout" }
            guard let first = names.first else { return nil }
            let local = names.count > 1 ? names[1] : first
            return ArgumentDescriptor(
                label: first,
                localName: local,
                type: rhs,
                defaultValue: defaultValue,
                required: defaultValue == nil
            )
        }
    }

    private func parseReturnType(_ tail: String) -> String? {
        guard let arrow = tail.range(of: "->") else { return nil }
        var result = String(tail[arrow.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let whereRange = result.range(of: #"\swhere\s"#, options: .regularExpression) {
            result = String(result[..<whereRange.lowerBound])
        }
        return result.isEmpty ? nil : result
    }

    private func shape(
        for rawType: String,
        objects: [String: [(String, String)]],
        visited: Set<String>
    ) -> TypeShape {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "Void" || type == "()" { return .void }
        if type.hasSuffix("?") {
            return TypeShape(kind: .optional, name: type, element: shape(for: String(type.dropLast()), objects: objects, visited: visited))
        }
        if type.hasPrefix("[") && type.hasSuffix("]") {
            let inner = String(type.dropFirst().dropLast())
            let parts = splitTopLevel(inner, separator: ":")
            if parts.count == 2 {
                return TypeShape(
                    kind: .dictionary, name: type,
                    element: shape(for: parts[1], objects: objects, visited: visited),
                    key: shape(for: parts[0], objects: objects, visited: visited))
            }
            return TypeShape(kind: .array, name: type, element: shape(for: inner, objects: objects, visited: visited))
        }
        if type.hasPrefix("(") && type.hasSuffix(")") {
            let inner = String(type.dropFirst().dropLast())
            let fields = splitTopLevel(inner, separator: ",").enumerated().map { index, item -> NamedShape in
                if let colon = topLevelIndex(of: ":", in: item) {
                    return NamedShape(
                        name: String(item[..<colon]).trimmingCharacters(in: .whitespaces),
                        shape: shape(for: String(item[item.index(after: colon)...]), objects: objects, visited: visited))
                }
                return NamedShape(name: "\(index)", shape: shape(for: item, objects: objects, visited: visited))
            }
            return TypeShape(kind: .tuple, name: type, fields: fields)
        }
        let lookup = type.split(separator: ".").last.map(String.init) ?? type
        if let fields = objects[lookup], !visited.contains(lookup) {
            let nextVisited = visited.union([lookup])
            return TypeShape(
                kind: .object, name: type,
                fields: fields.map { NamedShape(name: $0.0, shape: shape(for: $0.1, objects: objects, visited: nextVisited)) })
        }
        return .value(type)
    }

    private func inferCallEdges(_ candidates: [Candidate]) -> [FunctionEdge] {
        let byName = Dictionary(grouping: candidates, by: { $0.node.name })
        var edges = Set<String>()
        var result: [FunctionEdge] = []
        for caller in candidates where !caller.body.isEmpty {
            for (name, callees) in byName where callees.count == 1 && name != "init" && name != "subscript" {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*\\("
                guard caller.body.range(of: pattern, options: .regularExpression) != nil else { continue }
                let callee = callees[0]
                guard caller.node.id != callee.node.id else { continue }
                let edgeKey = "\(caller.node.id)->\(callee.node.id)"
                if edges.insert(edgeKey).inserted {
                    result.append(FunctionEdge(from: caller.node.id, to: callee.node.id, kind: .calls))
                }
            }
        }
        return result.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    private func documentation(before offset: Int, in source: NSString) -> String? {
        let prefix = source.substring(to: offset)
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        var docs: [String] = []
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                docs.append(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.isEmpty && docs.isEmpty {
                continue
            } else {
                break
            }
        }
        let result = docs.reversed().joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    private func findDeclarationEnd(_ source: NSString, from start: Int) -> Int {
        var parentheses = 0, brackets = 0, angles = 0
        var index = start
        while index < source.length {
            let char = source.substring(with: NSRange(location: index, length: 1))
            switch char {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "<": angles += 1
            case ">": angles = max(0, angles - 1)
            case "{" where parentheses == 0 && brackets == 0 && angles == 0: return index
            case "\n" where parentheses == 0 && brackets == 0 && angles == 0: return index
            default: break
            }
            index += 1
        }
        return source.length
    }

    private func firstIdentifier(in text: String) -> String? {
        text.range(of: #"[A-Za-z_][A-Za-z0-9_]*"#, options: .regularExpression).map { String(text[$0]) }
    }

    private func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
    }

    private func relative(_ file: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return file.standardizedFileURL.path.replacingOccurrences(of: rootPath, with: "")
    }
}

// MARK: - Lightweight Swift lexical helpers

private func maskCommentsAndStrings(_ source: String) -> String {
    let units = Array(source.utf16)
    var result = units
    enum State { case code, lineComment, blockComment, string }
    var state = State.code
    var blockDepth = 0
    var index = 0
    let slash = UInt16(47), star = UInt16(42), quote = UInt16(34), newline = UInt16(10), space = UInt16(32), backslash = UInt16(92)
    while index < units.count {
        let current = units[index]
        let next = index + 1 < units.count ? units[index + 1] : 0
        switch state {
        case .code:
            if current == slash && next == slash {
                result[index] = space; result[index + 1] = space; index += 1; state = .lineComment
            } else if current == slash && next == star {
                result[index] = space; result[index + 1] = space; index += 1; blockDepth = 1; state = .blockComment
            } else if current == quote {
                result[index] = space; state = .string
            }
        case .lineComment:
            if current == newline { state = .code } else { result[index] = space }
        case .blockComment:
            if current == slash && next == star {
                result[index] = space; result[index + 1] = space; index += 1; blockDepth += 1
            } else if current == star && next == slash {
                result[index] = space; result[index + 1] = space; index += 1; blockDepth -= 1
                if blockDepth == 0 { state = .code }
            } else if current != newline { result[index] = space }
        case .string:
            result[index] = current == newline ? newline : space
            if current == backslash && index + 1 < units.count {
                result[index + 1] = units[index + 1] == newline ? newline : space; index += 1
            } else if current == quote { state = .code }
        }
        index += 1
    }
    return String(decoding: result, as: UTF16.self)
}

private func find(_ needle: String, in source: NSString, from start: Int) -> Int? {
    guard start < source.length else { return nil }
    let range = source.range(of: needle, options: [], range: NSRange(location: start, length: source.length - start))
    return range.location == NSNotFound ? nil : range.location
}

private func matchingDelimiter(in source: NSString, opening: Int, open: String, close: String) -> Int? {
    var depth = 0
    var index = opening
    while index < source.length {
        let char = source.substring(with: NSRange(location: index, length: 1))
        if char == open { depth += 1 }
        if char == close {
            depth -= 1
            if depth == 0 { return index }
        }
        index += 1
    }
    return nil
}

private func splitTopLevel(_ text: String, separator: Character) -> [String] {
    var result: [String] = []
    var start = text.startIndex
    var parens = 0, brackets = 0, braces = 0, angles = 0
    var inString = false, escaped = false
    var index = text.startIndex
    while index < text.endIndex {
        let char = text[index]
        if inString {
            if char == "\\" && !escaped { escaped = true }
            else if char == "\"" && !escaped { inString = false; escaped = false }
            else { escaped = false }
        } else {
            switch char {
            case "\"": inString = true
            case "(": parens += 1
            case ")": parens -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "{": braces += 1
            case "}": braces -= 1
            case "<": angles += 1
            case ">": angles = max(0, angles - 1)
            default: break
            }
            if char == separator && parens == 0 && brackets == 0 && braces == 0 && angles == 0 {
                result.append(String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                start = text.index(after: index)
            }
        }
        index = text.index(after: index)
    }
    result.append(String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
    return result
}

private func topLevelIndex(of target: Character, in text: String) -> String.Index? {
    var parens = 0, brackets = 0, braces = 0, angles = 0
    for index in text.indices {
        let char = text[index]
        if char == target && parens == 0 && brackets == 0 && braces == 0 && angles == 0 { return index }
        switch char {
        case "(": parens += 1
        case ")": parens -= 1
        case "[": brackets += 1
        case "]": brackets -= 1
        case "{": braces += 1
        case "}": braces -= 1
        case "<": angles += 1
        case ">": angles = max(0, angles - 1)
        default: break
        }
    }
    return nil
}
