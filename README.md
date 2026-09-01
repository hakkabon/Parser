# Parser

A small Swift package containing the parts of a general context-free parser that don't depend on *which* parsing algorithm produced them: **Binary Subtree Representations (BSR)**, a **Shared Packed Parse Forest (SPPF)**, the **CST/parse-tree enumeration** algorithm that turns an SPPF into one or more concrete syntax trees, and the **syntax tree** type itself.

It was extracted from `Earley-Parser` — where this machinery was first built and debugged against Scott & Johnstone's derivation-representation formalism — and generalized so that `CYK-Parser`, `RNGLR-Parser`, and `Earley-Parser` can all share one implementation instead of three (soon four, five, six…) copies of the same BSR/SPPF/tree-extraction code with the same bugs fixed three separate times.

If you're writing a new parser for the `hakkabon` grammar toolkit — Earley, CYK, GLR, LL, LR, whatever — this is almost certainly the module you build its parse forest on top of.

## Table of contents

- [Mental model](#mental-model)
- [Adding this package as a dependency](#adding-this-package-as-a-dependency)
- [The one thing you write: `SPPFLabel`](#the-one-thing-you-write-sppflabel)
- [`BSR<Label>`](#bsrlabel)
- [`SPPFNode<Label>` and `SPPFGraph<Label>`](#sppfnodelabel-and-sppfgraphlabel)
- [The packed-node child convention (read this before you build an SPPF)](#the-packed-node-child-convention-read-this-before-you-build-an-sppf)
- [CST enumeration: from SPPF to `ParseTree`](#cst-enumeration-from-sppf-to-parsetree)
- [`SyntaxTree<Node, Leaf>` and `ParseTree`](#syntaxtreenode-leaf-and-parsetree)
- [`DeterministicParser` and `GeneralizedParser`](#deterministicparser-and-generalizedparser)
- [Shared deterministic parse diagnostics](#shared-deterministic-parse-diagnostics)
- [Graphviz output](#graphviz-output)
- [Logging and debugging](#logging-and-debugging)
- [Wiring up a new parser: step by step](#wiring-up-a-new-parser-step-by-step)
- [Design notes and known gotchas](#design-notes-and-known-gotchas)
- [Who uses this today](#who-uses-this-today)

## Mental model

Every parser in the toolkit that supports ambiguous grammars follows the same pipeline, regardless of the recognition algorithm it uses internally:

```
your algorithm's chart / GSS / DP table
            │
            │  (your code decides which derivation steps are "complete")
            ▼
      Set<BSR<Label>>                  ← this module: BSR.swift
            │
            │  (your code walks the BSR set and binarises multi-symbol
            │   productions into packed/intermediate nodes — this is the
            │   one algorithm-specific piece you still have to write)
            ▼
      SPPFGraph<Label>                 ← this module: SPPFGraph.swift, SPPFNode.swift
            │
            │  (this module's code — no further input from you)
            ▼
  buildParseTree / buildAllParseTrees  ← this module: TreeBuilder.swift, CSTEnumeration.swift
            │
            ▼
         ParseTree                     ← this module: SyntaxTree.swift
   (= SyntaxTree<NonTerminal, Range<String.Index>>)
```

Three things in that pipeline are generic and fully provided by this module: the BSR set, the SPPF graph, and the SPPF → `ParseTree` extraction. One thing is generic *in shape* but you provide the concrete type: `Label`, the type attached to intermediate and packed SPPF nodes, which must conform to `SPPFLabel`. And one thing is entirely yours: the algorithm that walks your parser's own completed-derivation bookkeeping (a chart, a GSS, a DP table — whatever your algorithm uses) and turns it into `SPPFNode`/`BSR` values. That last part is usually 100–250 lines and is the only place genuine algorithm-specific logic lives.

## Adding this package as a dependency

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/hakkabon/Grammar.git",
        revision: "69f85d7a493e1862412c34493e3656e94331df06"
    ),
    .package(url: "https://github.com/hakkabon/Parser.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyParser",
        dependencies: [
            .product(name: "Grammar", package: "Grammar"),
            .product(name: "Parser", package: "Parser"),
        ]
    ),
]
```

`Parser` depends on `Grammar` (for `NonTerminal`, `Symbol`, `Terminal`) and `TerminalColors` (for the pretty-printed `SyntaxTree.description`). It does not depend on `Lexer` or `GrammarTokenizer` — tokenization is entirely your parser's concern; this module only ever sees token *indices* and `Range<String.Index>` values you hand it.

## The one thing you write: `SPPFLabel`

```swift
public protocol SPPFLabel: Hashable, CustomStringConvertible {
    /// The goal (left-hand side) non-terminal of the production.
    var goal: NonTerminal { get }
    /// The symbols on the right-hand side of the production — the full
    /// right-hand side, not just the part matched so far.
    var symbols: [Symbol] { get }
    /// The current dot position within `symbols`.
    var position: Int { get }
}
```

Every algorithm-specific piece of this module (`SPPFNode<Label>`, `SPPFGraph<Label>`, `BSR<Label>`, and the CST enumeration in `CSTEnumeration.swift`) is generic over a `Label` conforming to `SPPFLabel`. `Label` is attached to `.intermediate` and `.packed` SPPF nodes (leaf and symbol nodes just carry a `String`), and it needs to answer exactly one question the shared algorithm asks over and over: **"how much of this production's right-hand side has been matched so far?"** — which is `symbols.prefix(position)`.

`position == symbols.count` means the production is fully matched (this is what CYK-Parser's `CNFRule.position` and RNGLR-Parser's/Earley-Parser's `.isCompleted` check both mean, even though none of them spell out an `isCompleted` requirement in the protocol — it's just `position == symbols.count`, so you're free to add it as a convenience computed property on your own type, as `NodeLabel` and `GrammarSlot` both do).

Three real implementations exist today, and they show the range of what a conforming type can look like:

**`NodeLabel`** — shipped *inside this module* (`SPPF/SPPFGraph/NodeLabel.swift`), ready to use as-is. It's the literal `(goal, symbols, position)` triple with nothing added, used directly by `Earley-Parser` and `Earley-TableParser`. If your algorithm doesn't already have its own natural "dotted production" type, start here — you may not need to write a `Label` type at all.

```swift
public struct NodeLabel: Codable, SPPFLabel {
    public let goal: NonTerminal
    public let symbols: [Symbol]
    public let position: Int
}
```

**`GrammarSlot`** (RNGLR-Parser) — an existing LR-item type that already had `production`/`dot` fields for its own automaton, so conformance is a thin pass-through:

```swift
extension GrammarSlot: SPPFLabel {
    public var goal: NonTerminal { production.goal }
    public var symbols: [Symbol]  { production.rule }
    public var position: Int      { dot }
}
```

**`CNFRule`** (CYK-Parser) — CYK's grammar is already in Chomsky Normal Form, so there's no real "dot" to track; a packed node always represents a fully-applied production, so `position` is simply always `symbols.count`:

```swift
public enum CNFRule: Hashable, Codable, CustomStringConvertible, SPPFLabel {
    case binary(NonTerminal, NonTerminal, NonTerminal)  // A -> B C
    case terminal(NonTerminal, Terminal)                // A -> a

    public var symbols: [Symbol] {
        switch self {
        case .binary(_, let b, let c): return [.nonTerminal(b), .nonTerminal(c)]
        case .terminal(_, let t):      return [.terminal(t)]
        }
    }
    public var position: Int { symbols.count }   // always fully matched
}
```

Pick whichever shape fits: reuse `NodeLabel`, adapt an existing item/slot type, or write a small purpose-built enum. The only hard requirement is that `symbols` is always the **full** right-hand side (never a truncated prefix) and `position` is the dot *within that full array* — see [Design notes](#design-notes-and-known-gotchas) for what goes wrong if you truncate.

## `BSR<Label>`

```swift
public struct BSR<Label: Hashable & Codable>: Codable, Hashable {
    public let label: Label
    public let leftExtent: Int
    public let pivot: Int
    public let rightExtent: Int
}
```

A Binary Subtree Representation entry records one derivation step your algorithm has proven: production `label` (or its matched-so-far prefix, if `Label.position < Label.symbols.count`) spans input positions `[leftExtent, rightExtent)`, split at `pivot` into "everything before the last matched symbol" and "the last matched symbol itself."

- `BSR: CustomStringConvertible` when `Label` is — gives `"(label, leftExtent, pivot, rightExtent)"`.
- `BSR: Comparable` **only** when `Label: Comparable` — none of the three existing `Label` types (`NodeLabel`, `GrammarSlot`, `CNFRule`) are `Comparable`, so `someBSRSet.sorted()` won't compile against them. Use `someBSRSet.sorted(by: { $0.description < $1.description })` instead (all three concrete parsers' `gtool` targets do exactly this).
- `Set<BSR<Label>>.log()` (an extension on `Set` when `Element: CustomStringConvertible`) pretty-prints a sorted BSR set via `Logger.bsr.trace(...)`.

**The pivot convention that matters most:** for a completed *single-symbol* match (`position == 1`, i.e. the production/slot has exactly one symbol in its matched prefix), `pivot` must equal `leftExtent` — there's no split, the lone child spans the whole range. Every existing BSR-emitting algorithm in the toolkit relies on this (see [the packed-node convention](#the-packed-node-child-convention-read-this-before-you-build-an-sppf) below for why), and it's the single easiest thing to get backwards when porting a new algorithm — CYK-Parser's original hand-rolled SPPF code used `pivot = leftExtent + 1` for this case and it happened not to matter until it was ported to this module's shared CST enumeration, which does care.

## `SPPFNode<Label>` and `SPPFGraph<Label>`

```swift
public enum SPPFNode<Label: Hashable>: Codable where Label: Codable {
    case leaf(label: String, leftExtent: Int, rightExtent: Int)
    case symbol(label: String, leftExtent: Int, rightExtent: Int)
    case intermediate(label: Label, leftExtent: Int, rightExtent: Int)
    case packed(label: Label, leftExtent: Int, rightExtent: Int, pivot: Int)
}
```

Four node kinds, matching the standard SPPF literature (Scott & Johnstone):

| Case | Represents | Label type |
|---|---|---|
| `.leaf` | a terminal token (or an epsilon marker) | `String` — the token's display text |
| `.symbol` | "non-terminal `X` derives the span `[i, j)`" | `String` — the non-terminal's name |
| `.intermediate` | a *partial* right-hand side match (dot not at either end) | your `Label` |
| `.packed` | one specific production application explaining a `.symbol` or `.intermediate` node's span | your `Label` |

`.leaf` and `.symbol` deliberately use a bare `String` rather than `Label` — a terminal or non-terminal *name* is all that's needed to identify them, and using a plain string means the root-lookup code in `TreeBuilder.swift` (`buildAllParseTrees(startSymbol: String, ...)`) never needs to know anything about your `Label` type to find the start symbol's node.

`SPPFNode` is `Hashable`/`Equatable` (structural — a node's identity is entirely its case + associated values, there's no separate identity beyond that) and, when `Label: CustomStringConvertible`, `Comparable` (ordered by kind, then label text, then extents — used to give deterministic iteration order for output like `.graphviz` and `printGraph()`).

```swift
public class SPPFGraph<Label: Hashable & Codable & CustomStringConvertible> {
    public init()
    public func add(_ node: SPPFNode<Label>)
    public func addEdge(from parent: SPPFNode<Label>, to child: SPPFNode<Label>)
    public func getChildren(of node: SPPFNode<Label>) -> Set<SPPFNode<Label>>
    public func getAllNodes() -> [SPPFNode<Label>]
    public func getExtendableNodes() -> [SPPFNode<Label>]
    public func cleanup()
    public func printGraph()   // Logger.sppf.trace(...)
}
```

It's an adjacency map (`[SPPFNode<Label>: Set<SPPFNode<Label>>]`) under the hood, nothing fancier. A few things worth knowing:

- `addEdge(from:to:)` implicitly calls `add(_:)` on the child (and, via the dictionary's `default:` subscript, on the parent too), so you rarely need to call `add(_:)` yourself except to register an isolated node before it has any edges — CYK-Parser's `buildSPPF` does this defensively for every node it constructs; RNGLR-Parser's `BSRSet.buildSPPF` relies on `addEdge` alone for everything except the root.
- `getChildren(of:)` returns a **`Set`**, not an array — there is no defined child order. If your old, pre-migration SPPF code relied on children being visited left-to-right in insertion order (RNGLR-Parser's did), that ordering assumption is gone; the shared CST enumeration algorithm below never needs it (it identifies left/right children structurally, by extent and symbol match, not by position), but if *you* need a stable order for something like deterministic `.graphviz` output, sort explicitly.
- `getExtendableNodes()` returns `.symbol` and `.intermediate` nodes that have no children yet — useful for a worklist-driven, bottom-up-then-iteratively-expanded SPPF construction (this is exactly how `Earley-Parser`'s `extractSPPF` works: seed the root, then repeatedly expand extendable nodes until none remain).
- `cleanup()` removes unproductive nodes — anything not transitively reachable from a `.leaf` — which prunes packed nodes and their parents that turned out to be dead ends (e.g. from a completed item that was later found to not actually connect to the accepted parse).

## The packed-node child convention (read this before you build an SPPF)

This is the part of writing a new algorithm's BSR→SPPF construction that's easy to get subtly wrong, because it doesn't show up as a compile error or even necessarily a crash — it shows up as silently wrong or silently missing parse trees. It comes directly from Scott & Johnstone's `mkPN` (make packed node) procedure, and every `Label`-emitting algorithm in this toolkit (`Earley-Parser`'s `ExtractSPPF.swift`, `RNGLR-Parser`'s `BSRSet.swift`, `Earley-TableParser`'s `EarleyParser.swift`) implements the same three-way split:

Let `α = label.symbols.prefix(label.position)` — the part of the right-hand side matched so far. A packed node for `α` spanning `[leftExtent, rightExtent)`, split at `pivot`, gets:

- **`α.count == 1`** — *no left child at all.* The single symbol in `α` is attached as the packed node's only child, spanning `[pivot, rightExtent)`. By the pivot convention above, `pivot == leftExtent` here, so that one child spans the packed node's entire range.
- **`α.count == 2`** — a **direct** left child (a `.leaf` or `.symbol` node — never `.intermediate`) for `α[0]`, spanning `[leftExtent, pivot)`, plus a direct right child for `α[1]`, spanning `[pivot, rightExtent)`.
- **`α.count > 2`** — the right child is still a direct node for `α.last`, spanning `[pivot, rightExtent)`. But the left child is now an **`.intermediate`** node representing `α` *minus its last symbol* (`position - 1`), spanning `[leftExtent, pivot)` — which itself needs to be recursively expanded the same way.

The `α.count == 2` case is the one that's easy to miss if you write the construction as a simple "walk the right-hand side right-to-left, wrap everything already-consumed in an intermediate node" loop: that natural-looking recursive structure wraps the *second-to-last* symbol in an intermediate node too, when it should be a plain symbol/leaf node instead. `CSTEnumeration.swift`'s `_expandPackedNode` specifically looks for a direct symbol/leaf node when `alpha.count == 2` and an `.intermediate` node when `alpha.count > 2` — get this backwards and those two-symbol productions either fail to produce a tree or (worse) silently fall through to a much looser fallback match purely by extent, which usually still works but stops verifying that the matched child is actually the right *symbol*.

If you want a worked reference implementation, `RNGLR-Parser`'s `BSRSet.attachSymbol` is written explicitly as a three-case `switch` on `idx` (`0`, `1`, `default`) for exactly this reason, with comments pointing at each branch's corresponding case above.

## CST enumeration: from SPPF to `ParseTree`

Once your algorithm has produced a populated `SPPFGraph<Label>`, everything else is provided:

```swift
public extension SPPFGraph where Label: SPPFLabel {
    func buildParseTree(startSymbol: String, ranges: [Range<String.Index>], string: String) -> ParseTree
    func buildAllParseTrees(startSymbol: String, ranges: [Range<String.Index>], string: String) -> [ParseTree]
}
```

These are almost always the only two entry points you call directly:

- `ranges[i]` must be the `Range<String.Index>` of the token at index `i` — i.e. whatever your tokenizer produced, zipped with the same token-index numbering your algorithm used when it built `SPPFNode.leaf`/`.symbol` extents. This module has no opinion about tokenization; it only ever asks for this array.
- `buildParseTree` returns the first tree found (`.empty` if none), `buildAllParseTrees` returns every distinct derivation, deduplicated.
- Root-finding is automatic: both functions filter `getAllNodes()` for a `.symbol(label: startSymbol, leftExtent: 0, rightExtent: ranges.count)` node — you don't need to look up or pass in the root node yourself.

Underneath, `CSTEnumeration.swift`'s `extractNodeAlternatives(node:ranges:string:memo:)` does the real work, recursively expanding a node into `[[ParseTree]]` — an array of *alternatives*, each alternative itself a flat array of children to place under the enclosing non-terminal. It's memoized (`memo: inout [SPPFNode<Label>: [[ParseTree]]?]`) with a cycle guard (an in-progress node is marked with a sentinel `nil` before its children are visited, so a cyclic SPPF — which can arise from certain grammar/derivation shapes — degrades to "contributes nothing" instead of infinite-looping). You can call it directly if you need finer control than `buildAllParseTrees` gives you, but the two `TreeBuilder` entry points cover what every current parser needs.

`deduplicateParseTrees(_:)` is also public if you're assembling trees from multiple SPPF roots yourself (CYK-Parser does this after running its CNF-undoing `TreeTransformer`, since deduplication has to happen before the transform to be meaningful, and `buildAllParseTrees` already deduplicates the *pre-transform* trees for you).

## `SyntaxTree<Node, Leaf>` and `ParseTree`

```swift
public typealias ParseTree = SyntaxTree<NonTerminal, Range<String.Index>>
```

This is the artifact every parser in the toolkit ultimately hands back to its caller.

```swift
public enum SyntaxTree<Node: Hashable & Equatable, Leaf: Hashable & Equatable> {
    case leaf(Leaf)
    indirect case node(Node, children: [SyntaxTree<Node, Leaf>])
    case empty
}
```

`.empty` is a real, distinct case (not just "no tree") — used for a successful parse of an empty input under a grammar whose start symbol is nullable, and returned by `buildParseTree` when no root is found at all. `tree.root` and `tree.leaf` both return `nil` for it, so `if tree.root == nil` alone doesn't distinguish "parse failed to build a tree" from "genuinely empty parse" — check the case directly if that distinction matters to you.

Useful members (all in `public extension SyntaxTree`):

| Member | What it does |
|---|---|
| `root` / `leaf` / `children` | `Node?` / `Leaf?` / `[SyntaxTree]?` — nil unless the tree is that case |
| `subscript(index:)` | direct child access by position |
| `mapNodes(_:)` / `mapLeafs(_:)` | structure-preserving transform of every inner node / every leaf |
| `leafs` | all leaves, left to right, flattened |
| `filter(_:)` | drop nodes (and their subtrees) failing a predicate |
| `flattened(where:)` | replace a node with its children wherever a predicate holds ("un-wrap" nodes) |
| `simplified()` | collapse unary chains (a node with exactly one non-leaf child) |
| `allNodes(where:)` | every subtree whose root matches a predicate |
| `resolved(in:)` | (only when `Leaf == Range<String.Index>`) — maps every leaf range to the actual `Substring` from a source string, i.e. the same idea as `mapLeafs { source[$0] }` but built in |

`SyntaxTree` is `Hashable` and, since Swift 5.9 doesn't support recursive `Equatable` synthesis for enums with `indirect case`, has a hand-written `==` that compares case-by-case, recursing into children. `description` (via `CustomStringConvertible`) is a colour-coded (via `TerminalColors`) tree-drawing pretty printer (`SyntaxTreePrinter`) — what you see when you `print(tree)` in a terminal, complete with `├──`/`└──` branch drawing.

`mapLeafs { String(input[$0]) }` is the standard way to turn a `ParseTree`'s `Range<String.Index>` leaves into readable source text before printing or inspecting it — you'll see this pattern in every `gtool`'s `.tree` analysis case.

## `DeterministicParser` and `GeneralizedParser`

Two small protocols tie the pipeline above to a concrete parser type's public API. Neither one does anything algorithm-specific — they're purely structural, so a new parser conforms to them and immediately gets a uniform, toolkit-wide surface (`syntaxTree(for:)`, `recognizes(_:)`, `parse(_:)`, `allSyntaxTrees(for:)`) regardless of which recognition algorithm it uses underneath.

```swift
public protocol DeterministicParser {
    func syntaxTree(for string: String) throws -> ParseTree
}
public extension DeterministicParser {
    func recognizes(_ string: String) -> Bool   // (try? syntaxTree(for: string)) != nil
}
```

```swift
public protocol GeneralizedParser {
    associatedtype Label: Hashable & Codable & CustomStringConvertible
    func parse(_ string: String) throws -> ParseResult<Label>
    func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
```

`ParseResult<Label>` is the raw outcome of a `GeneralizedParser.parse(_:)` call:

```swift
public struct ParseResult<Label: Hashable & Codable & CustomStringConvertible> {
    public let isSuccessful: Bool
    public let bsr: Set<BSR<Label>>
    public let sppfGraph: SPPFGraph<Label>?
    public var hasAmbiguity: Bool { get }   // true if any .symbol/.intermediate node has >1 packed-node child
}
```

A few conventions worth calling out, since they're conventions rather than anything the type system enforces:

- **On a syntactic failure** (well-formed tokens, just not in the language), `parse(_:)` should return `ParseResult(isSuccessful: false, bsr: ..., sppfGraph: nil)` rather than throwing — `isSuccessful` exists precisely so callers can distinguish "no derivation found" from an exceptional failure. Reserve `throws` for genuine errors bubbling up from tokenization (an invalid token, an unterminated string, etc.) — i.e. situations `Terminal` resolution itself can't recover from.
- **`syntaxTree(for:)`/`allSyntaxTrees(for:)`, by contrast, throw on failure** — they're the ergonomic, tree-returning entry points, and "the input isn't in the language" is exactly the kind of failure a `throws` function is for. Concrete packages may retain algorithm-specific thrown errors, while recoverable deterministic entry points can use the shared diagnostic model below.
- `hasAmbiguity` only inspects `sppfGraph`; it says nothing if `sppfGraph` is `nil`. It's a *local* ambiguity signal (some node has more than one packed-node child derivation) — not a claim about whether the grammar is ambiguous in general, only whether this particular input exercised an ambiguity.

`ParseResult.bsr` is for diagnostics and tooling (every `gtool`'s `--analysis sppf` case prints it) — nothing in this module's own SPPF-construction or tree-extraction code reads it back. If your algorithm's own BSR bookkeeping doesn't naturally produce a `pivot` for every entry (RNGLR-Parser's `BSRTriple` doesn't — see [Design notes](#design-notes-and-known-gotchas)), it's fine to fill `pivot` with a documented placeholder purely for this field; just don't let anything load-bearing depend on it being meaningful.

## Shared deterministic parse diagnostics

Recovering deterministic parsers share data and presentation while retaining their own recovery algorithms:

```swift
public struct ParseDiagnostic: Error { /* source range, reason, message,
                                          expected/found terminals, context */ }
public enum ParseStatus { case accepted, recovered, rejected }
public enum RecoveryEdit { case insert(...), delete(...), skip(...) }
public struct DeterministicParseResult<Trace> {
    public let status: ParseStatus
    public let tree: ParseTree?
    public let diagnostics: [ParseDiagnostic]
    public let recoveryEdits: [RecoveryEdit]
    public let trace: [Trace]
}
```

`NoParseTrace` and `UntracedParseResult` cover parsers such as LL that do not expose execution traces. LR specializes the generic result with its own trace event. `DiagnosticReporter` renders any shared diagnostic batch with one-based line/column information and source underlines. Recovery policies are intentionally not shared: FIRST/FOLLOW synchronization in LL and ACTION-table repair in LR make different decisions even though they return the same result vocabulary.

## Graphviz output

Two independent `.graphviz` properties, for the two different tree-shaped things this module deals with:

```swift
// On SPPFGraph where Label: SPPFLabel
var graphviz: String                                                          // quick, uniform styling
func graphviz(title: String = "SPPF", showExtents: Bool = true,
              clusterByExtent: Bool = false) -> String                        // richer styling + legend
```

The simple `graphviz` property draws every node as `shape=box`, distinguished only by fill colour (`.leaf` → light blue, `.symbol` → light green, `.intermediate` → light gray, `.packed` → light coral), with plain unlabeled edges — good for a quick sanity check. The detailed `graphviz(title:showExtents:clusterByExtent:)` overload uses different shapes per kind (ellipse for symbols, box for leaves/intermediates, circle for packed nodes), styles edges differently depending on parent/child kind (solid for symbol→packed, bold for packed→child, dashed for intermediate→child), optionally clusters nodes into Graphviz subgraphs by their `(leftExtent, rightExtent)` span, and appends a legend subgraph. Both require `Label: SPPFLabel` and iterate `getAllNodes().sorted()`, so output is deterministic across runs for the same graph.

`SyntaxTree.graphviz` is unrelated and unconditional (no `SPPFLabel` requirement — it works on any `SyntaxTree<Node, Leaf>`), producing a plain `digraph { ... }` with one node per tree element (internal nodes and leaves alike) and edges following the tree structure. It assigns synthetic sequential IDs internally (via a private `Unique<T>` wrapper) so that structurally-equal-but-distinct subtrees don't collapse into a single Graphviz node.

Neither one writes a file or shells out to `dot` by itself — that's left to each parser package's own `gtool`/`demo` targets (typically a thin `writeDot(to:)`/`renderPDF(to:)` pair living in that package, since "where do I put the file, and is `dot` even installed" is deployment-specific, not something this module should own).

## Logging and debugging

```swift
extension Logger {
    public static let bsr:  Logger   // subsystem "com.hakkabon.Parser", category "BSR"
    public static let sppf: Logger   // subsystem "com.hakkabon.Parser", category "SPPF"
}
```

Two `OSLog` categories, used by `Set<BSR<Label>>.log()` (`Logger.bsr.trace`) and `SPPFGraph.printGraph()` (`Logger.sppf.trace`). Note that `AnalyzeSPPF.swift`'s `SPPFGraph.log()` is a *different*, plain-`print`-based debug dump (not `OSLog`) — a holdover from before `printGraph()` existed on `SPPFGraph` itself, kept because it does more: alongside listing every node and its children, it flags nodes with more than five children ("potential explosion") and does a depth-first cycle check from every `.symbol` root, printing a warning if it finds one. Reach for `.log()` when you suspect something structural is wrong with a graph you just built; reach for `.printGraph()` or `.graphviz` for a quick, low-ceremony look.

## Wiring up a new parser: step by step

This is the sequence `CYK-Parser`, `RNGLR-Parser`, and `Earley-Parser` all followed (in that order, chronologically) to align to this module. If you're bringing up a fourth algorithm — GLR, LL, LR, whatever's next in the toolkit — this is the path of least resistance:

1. **Pick or write your `Label` type** and conform it to `SPPFLabel`. If your algorithm already has a natural "dotted production" or "grammar slot" type, add the three computed properties (see the three examples above). If not, just use this module's own `NodeLabel` directly — you may not need a type of your own at all.
2. **Write the BSR-emitting half of your algorithm** — wherever your algorithm currently recognizes "this production/slot is now complete" or "this partial match now spans further," emit a `BSR<Label>(label:leftExtent:pivot:rightExtent:)`. Remember the single-symbol pivot convention above.
3. **Write the BSR → SPPF construction.** This is the one piece of real algorithm-specific work — walk your `Set<BSR<Label>>` (or your chart/GSS directly, if that's more natural) and build an `SPPFGraph<Label>`, following the [packed-node child convention](#the-packed-node-child-convention-read-this-before-you-build-an-sppf) exactly. `Earley-Parser`'s `BSR/ExtractSPPF.swift` is the cleanest reference implementation to copy from — it's the original this module's algorithms were extracted from, and its comments walk through each of the three `α.count` cases explicitly.
4. **Conform your parser type to `DeterministicParser`/`GeneralizedParser`.** `syntaxTree(for:)`/`allSyntaxTrees(for:)` become thin wrappers: parse, check `result.isSuccessful`, and if so call `result.sppfGraph!.buildParseTree(startSymbol:ranges:string:)` / `buildAllParseTrees(...)`. This is usually under 30 lines total.
5. **Delete whatever local `BSR`/`SPPFNode`/`SPPFGraph`/`CSTEnumeration`/`ParseTree` types your algorithm had before** — they're now redundant with this module's generic versions. Keep anything genuinely algorithm-specific (your own `ParseError` type, your own chart/GSS/table types).
6. **Point `.graphviz`/diagnostic tooling at the shared implementation** unless you have a real reason to keep a bespoke renderer — `RNGLR-Parser` kept its own `SPPFGraphviz.swift` because it had richer, already-tested styling (ambiguity double-borders, pivot-labeled edges) that the shared renderer doesn't offer; `Earley-Parser` and `CYK-Parser` just use `SPPFGraph.graphviz` directly. Either is fine — just don't keep a bespoke renderer purely out of inertia.

## Design notes and known gotchas

- **Why generic over `Label` instead of one concrete type?** The whole point of extracting this module was to stop re-solving "how do I represent a partially-matched production" once per algorithm. Earley's chart-based items, RNGLR's LR-slots, and CYK's Chomsky-normal-form rules are genuinely different shapes; making `Label` a protocol lets each algorithm keep its own natural representation while sharing everything downstream of it.
- **`symbols` must always be the full right-hand side, never a truncated prefix.** It's tempting, when constructing a `Label` for a *partial* match, to only store the matched-so-far symbols (since that's "all you need" at that specific call site). Don't — `alpha = symbols.prefix(position)` is how the shared algorithms recover the matched prefix, and `position == symbols.count` is how they recognize a completed match; both break if `symbols` has already been truncated. This exact bug turned up in `Earley-TableParser`'s original `BSRComponent.prefix` case during its migration, and cost nothing to fix once caught (the full rule was already available at the construction site) — but it's an easy trap for a *new* algorithm to fall into for the first time, since a truncated-prefix representation isn't wrong for anything that only ever reads `symbols` directly, only for the shared traversal that expects to be able to compute `isCompleted` from it.
- **`BSR<Label>.pivot` is sometimes a best-effort placeholder, and that's fine.** Nothing in this module reads `BSR.pivot` back — it exists for diagnostics (`ParseResult.bsr`, `gtool`'s SPPF analysis output) and for algorithms whose own bookkeeping naturally produces a real split point at BSR-recording time (Earley's chart-based `bsrAdd`, which processes one symbol at a time and always has a genuine `k` on hand). RNGLR's BSR set, by contrast, records a full-width completed production before it's later binarised — a single scalar `pivot` can't faithfully represent "this production may bind to several different internal split points once its SPPF is built," so `RNGLR-Parser` documents `pivot = leftExtent` there as a known placeholder. If you hit the same shape of algorithm, do the same: pick something documented and harmless, and don't let real construction logic depend on it.
- **`getChildren(of:)` is unordered.** If you're porting an algorithm whose old SPPF representation stored children as an ordered array and relied on that order anywhere outside of display/debugging, that assumption needs to go — verify against extents and symbol identity instead, the way `CSTEnumeration._expandPackedNode` does.
- **Comparable is opt-in and rarely available.** `BSR<Label>` and `SPPFNode<Label>` are only `Comparable` when `Label: Comparable`; none of the three current `Label` types are. Reach for `.sorted(by: { $0.description < $1.description })` rather than bare `.sorted()` when you need deterministic output from a `Set` of either.
- **This module has no error type of its own, on purpose.** `ParseError`/`SyntaxError`-style types stay local to each concrete parser package. What's genuinely shared is the data structures and the tree-extraction algorithm; what counts as a good parse-failure diagnostic is inherently specific to each parser's front end.

## Who uses this today

| Package | `Label` type | Notes |
|---|---|---|
| `CYK-Parser` | `CNFRule` | Chomsky Normal Form — `position` is always `symbols.count` |
| `RNGLR-Parser` | `GrammarSlot` | reuses its existing LR-item type; keeps its own richer `SPPFGraphviz.swift` |
| `Earley-Parser` | `NodeLabel` | this module's own `NodeLabel`, used directly — the original source this module was extracted from |
| `Earley-TableParser` | `NodeLabel` | data model aligned to this module; not yet wired up to `DeterministicParser`/`GeneralizedParser` (no facade type exists yet — see that package's own notes) |
