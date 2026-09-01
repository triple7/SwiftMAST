import Foundation

public struct FunctionGraph: Codable, Equatable {
    public var schemaVersion: String
    public var module: String
    public var generatedAt: String
    public var pipeline: [PipelineStage]
    public var functions: [FunctionNode]
    public var edges: [FunctionEdge]

    public init(
        schemaVersion: String = "1.0",
        module: String,
        generatedAt: String,
        pipeline: [PipelineStage] = [],
        functions: [FunctionNode],
        edges: [FunctionEdge] = []
    ) {
        self.schemaVersion = schemaVersion
        self.module = module
        self.generatedAt = generatedAt
        self.pipeline = pipeline
        self.functions = functions
        self.edges = edges
    }
}
public struct PipelineStage: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var input: String?
    public var output: String
    public var description: String?

    public init(id: String, name: String, input: String? = nil, output: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.input = input
        self.output = output
        self.description = description
    }
}

public struct FunctionNode: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var ownerType: String?
    public var arguments: [ArgumentDescriptor]
    public var output: TypeShape
    public var isAsync: Bool
    public var canThrow: Bool
    public var documentation: String?
    public var source: SourceLocation

    public var displayName: String {
        ownerType.map { "\($0).\(name)" } ?? name
    }
}

public struct ArgumentDescriptor: Codable, Equatable {
    public var label: String
    public var localName: String
    public var type: String
    public var defaultValue: String?
    public var required: Bool
}

public struct NamedShape: Codable, Equatable {
    public var name: String
    public var shape: TypeShape

    public init(name: String, shape: TypeShape) {
        self.name = name
        self.shape = shape
    }
}

public struct OutputVariant: Codable, Equatable {
    public var name: String
    public var when: String
    public var shape: TypeShape

    public init(name: String, when condition: String, shape: TypeShape) {
        self.name = name
        self.when = condition
        self.shape = shape
    }
}

/// A recursive, language-neutral description of a Swift type.
public final class TypeShape: Codable, Equatable {
    public enum Kind: String, Codable {
        case void, value, optional, array, dictionary, tuple, object, oneOf
    }

    public var kind: Kind
    public var name: String?
    public var fields: [NamedShape]?
    public var element: TypeShape?
    public var key: TypeShape?
    public var variants: [OutputVariant]?

    public init(
        kind: Kind,
        name: String? = nil,
        fields: [NamedShape]? = nil,
        element: TypeShape? = nil,
        key: TypeShape? = nil,
        variants: [OutputVariant]? = nil
    ) {
        self.kind = kind
        self.name = name
        self.fields = fields
        self.element = element
        self.key = key
        self.variants = variants
    }

    public static let void = TypeShape(kind: .void, name: "Void")
    public static func value(_ name: String) -> TypeShape { TypeShape(kind: .value, name: name) }

    public static func == (lhs: TypeShape, rhs: TypeShape) -> Bool {
        lhs.kind == rhs.kind && lhs.name == rhs.name && lhs.fields == rhs.fields
            && lhs.element == rhs.element && lhs.key == rhs.key && lhs.variants == rhs.variants
    }
}

public struct SourceLocation: Codable, Equatable {
    public var file: String
    public var line: Int
}

public struct FunctionEdge: Codable, Equatable {
    public enum Kind: String, Codable {
        case contains, calls, dataFlow
    }

    public var from: String
    public var to: String
    public var kind: Kind
    public var label: String?

    public init(from: String, to: String, kind: Kind, label: String? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.label = label
    }
}
