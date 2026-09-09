# Parser contract

Parser 0.3 adds a portable, versioned result contract for comparing parser engines and building parse-tree, forest, and replay tools. It is additive: the existing `ParseTree`, `SPPFGraph`, `ParseResult`, and deterministic result APIs remain available.

The contract is deliberately about semantic parse results, not an engine's implementation. LR states, Earley chart entries, GSS nodes, and recovery search queues stay in their owning engine. This lets tools compare engines without claiming that unlike algorithms have identical internal steps.

## Production identity

An engine label opts in by refining `SPPFLabel`:

```swift
struct Label: ProductionIdentifiedSPPFLabel {
    let productionID: GrammarProductionID
    // goal, symbols, position, Hashable, Codable, description …
}
```

The identity comes from Grammar's normalized production model. It must describe the production represented by the packed or intermediate node; it must not be derived from an engine-local table row or memory address.

## Trees and forests

`ProductionParseTree` complements the legacy `ParseTree`. Its production nodes retain `GrammarProductionID`; all nodes carry half-open token extents and UTF-16 offsets. Epsilon productions are represented by a production with no children, not by a synthetic token.

Use `buildProductionParseTrees(startSymbol:ranges:source:maximumTrees:)` on an identified SPPF. Enumeration is explicitly bounded and reports `reachedLimit`, so an explorer never has to materialize an unbounded ambiguous forest.

`portableSnapshot()` exports a deterministic `ParseForestSnapshot`. It removes the generic engine label while preserving node kind, production identity, dot position, token extents, packed pivots, roots, edges, and ambiguity sites. Node identities are structural and length-prefixed; arrays are sorted for reproducible corpus output. Invalid extents and duplicate portable identities fail rather than producing a misleading graph.

## Diagnostics and recovery

`ParseDiagnosticSnapshot` converts source indices to UTF-16 offsets and normalizes expected/found terminals through Grammar 0.3. Optional production and token identities connect a diagnostic back to the tree, forest, and replay.

`ParseRecoveryEdit` is the portable form of `RecoveryEdit`. Parser-specific recovery policy remains outside this package; only the observable insertion, deletion, or skip is shared.

## Comparison and replay

`ParseContractSnapshot` is the common envelope:

```swift
let comparison = deterministicResult.contractSnapshot(
    engine: .init(identity: "lr", displayName: "LR", algorithm: "lalr"),
    identifiedTree: tree,
    replay: replay
)

let comparison = try generalizedResult.contractSnapshot(
    engine: .init(identity: "earley", displayName: "Earley", algorithm: "earley")
)
```

It carries acceptance status, an optional identified tree and forest, normalized diagnostics and recovery edits, and semantic replay events. Events describe shared milestones—inspect, consume, apply a production, discover ambiguity, recover, accept, or reject. An engine may still expose a richer native trace beside this projection.

Both the top-level contract and nested forest declare schema version 1 and reject unsupported versions during decoding. The authoritative serialized shape is [Schemas/ParseContract.schema.json](Schemas/ParseContract.schema.json).

## Ownership boundary

- Grammar owns normalized symbols and stable production identity.
- Parser owns portable result, tree, forest, diagnostic, recovery, and replay vocabulary.
- Parser engines own construction, algorithm traces, tables/charts, and recovery policy.
- Grammar-REPL and Workbench own comparison, exploration, persistence, and rendering.

Graphviz text and other presentation formats are not part of the portable contract. They remain useful diagnostics, but consumers should build durable tooling from `ParseForestSnapshot` and `ProductionParseTree`.
