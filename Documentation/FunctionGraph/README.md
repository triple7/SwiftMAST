# SwiftMAST function graph

This directory is generated from SwiftMAST's public Swift declarations.

- `function-graph.json` is the canonical machine-readable source of truth.
- `function-graph.mmd` is an ordered Mermaid overview of the request lifecycle
  and public API owner types.
- `function-graph-detail.mmd` is the complete function-level call graph,
  grouped into owner-type subgraphs.
- `index.html` is an interactive SVG node-and-edge graph. It fetches the JSON at
  runtime and does not embed a second copy of graph data.

## Generate

From the package root:

```sh
swift run swiftmast-function-graph
```

Custom paths are also supported:

```sh
swift run swiftmast-function-graph \
  --source Sources/SwiftMAST \
  --output Documentation/FunctionGraph \
  --module SwiftMAST
```

## View

Browsers normally block an HTML file opened through `file://` from fetching a
neighboring JSON file. Serve the directory locally:

```sh
python3 -m http.server 8080 --directory Documentation/FunctionGraph
```

Then open <http://localhost:8080>.

The viewer provides three deterministic layouts:

- Request lifecycle: target/service input through typed Swift result.
- Function calls: connected functions grouped into owning-type swimlanes.
- All nodes: the full API and lifecycle, still grouped rather than scattered.

Search highlights matching nodes. Select a node for complete arguments,
defaults, source location, and recursive output structure. The canvas supports
pan, zoom, and fit-to-graph.

## Graph semantics

Every function node records a signature-and-return-type identity, owner,
arguments, default values, `async`/`throws` flags, documentation, source
location, and recursive output shape. Shapes distinguish values, optionals,
arrays, dictionaries, tuples, and public objects with named fields.

Pipeline stages and all relationships live in JSON. The CLI serializes JSON
first, decodes that exact artifact, and only then creates Mermaid and HTML.

Call edges are conservative. An edge is emitted only when a called name maps to
one extracted public function. Dynamic dispatch, private helpers, closures, and
ambiguous overloaded calls may not appear.
