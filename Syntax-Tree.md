# API Summary: Syntax-Tree Submodule

The `Syntax-Tree` submodule provides a generic, recursive representation of a syntax tree. It is used as the base type for parse trees produced by the parser.

## Core Types

### 1. `SyntaxTree<Node: Equatable, Leaf: Equatable>`

A generic enum representing the tree structure.

* **Specialization**: `public typealias ParseTree = SyntaxTree<NonTerminal, Range<String.Index>>`

#### Enum Cases

* `.leaf(Leaf)`: Stores a value at the leaf level (e.g. terminal token position).
* `.node(Node, children: [SyntaxTree])`: Represents an internal branch with a node label and an array of subtrees.
* `.empty`: A placeholder representation representing an empty tree.

#### Initializers

* `init(node: Node, children: [SyntaxTree])`: Initializes a branch node.
* `init(node: Node)`: Initializes a branch node with no children.
* `init(value: Leaf)`: Initializes a leaf node.

#### Computed Properties

* `var root: Node?`: The label of the node if it is a `.node`, otherwise `nil`.
* `var leaf: Leaf?`: The leaf value if it is a `.leaf`, otherwise `nil`.
* `var children: [SyntaxTree]?`: The child subtrees if it is a `.node`, otherwise `nil`.
* `var leafs: [Leaf]`: Traverses the tree and returns all leaf values in left-to-right order.
* `var description: String`: Returns a formatted text drawing of the tree (powered by `SyntaxTreePrinter`).

---

## Operations & Transformations

The `SyntaxTree` type contains operations defined:

### `reduce(leaf:node:empty:)`

Performs a bottom-up post-order reduction (catamorphism) of the tree structure into a single value.

```swift
func reduce<Result>(
    leaf: (Leaf) throws -> Result,
    node: (Node, [Result]) throws -> Result,
    empty: Result
) rethrows -> Result
```

### `mapNodes(_:)`

Generates a new syntax tree by mapping internal node values.

```swift
func mapNodes<Result>(_ transform: (Node) throws -> Result) rethrows -> SyntaxTree<Result, Leaf>
```

### `mapLeafs(_:)`

Generates a new syntax tree by mapping leaf values.

```swift
func mapLeafs<Result>(_ transform: (Leaf) throws -> Result) rethrows -> SyntaxTree<Node, Result>
```

### `filter(_:)`

Prunes nodes and their subtrees where the predicate returns false.

```swift
func filter(_ predicate: (Node) throws -> Bool) rethrows -> SyntaxTree<Node, Leaf>?
```

### `flattened(_:)`

Bypasses specified nodes and promotes their children to the parent node level.

```swift
func flattened(_ where: (Node) throws -> Bool) rethrows -> [SyntaxTree<Node, Leaf>]
```

### `simplified()`

Simplifies the tree by collapsing chain nodes containing exactly one child node (unary paths).

```swift
func simplified() -> SyntaxTree<Node, Leaf>
```

### `allNodes(where:)`

Recursively finds all nodes satisfying a given predicate.

```swift
func allNodes(where predicate: (Node) throws -> Bool) rethrows -> [SyntaxTree<Node, Leaf>]
```

### `resolved(in:)`

Maps the tree's leaf ranges to actual substrings from the source document.

```swift
func resolved(in source: String) -> SyntaxTree<Node, Substring>
```

---

### What is Catamorphism / Tree Fold?

In category theory, a **catamorphism** (from Greek *kata-*, meaning "downward") is the generalization of list folding (`foldLeft`/`reduce`) to arbitrary recursive algebraic data types (like trees).

Instead of manually writing a recursive function with case-switching logic to walk the tree, a catamorphism abstracts away the traversal pattern. You provide:

1. **A leaf handler** to transform leaf values (`Leaf -> Result`).
2. **A node combiner** to combine an internal node's label with the pre-reduced results of its children (`(Node, [Result]) -> Result`).
3. **An empty sentinel** for empty trees (`Result`).

The `reduce` method automatically propagates these handlers bottom-up (post-order traversal) from the leaves to the root, returning a single accumulated value.

---

### Snippet Examples

#### 1. Resolving Token Ranges to Substrings

Addressing your previous question about the clumsiness of traversing the tree to substitute `Range<String.Index>` values: `reduce` lets you map index ranges to `Substring` values in a single, elegant step.

```swift
let source = "1 + 2"

// Transforms SyntaxTree<NonTerminal, Range<String.Index>> into SyntaxTree<NonTerminal, Substring>
let readableTree = parseTree.reduce(
    leaf: { range in 
        source[range] // String.Index range -> Substring
    },
    node: { nonTerminal, resolvedChildren in
        SyntaxTree<NonTerminal, Substring>.node(nonTerminal, children: resolvedChildren)
    },
    empty: SyntaxTree<NonTerminal, Substring>.empty
)
```

#### 2. Evaluating a Math Expression AST

If you map the parser tree into a simple mathematical AST (where leaves are numbers and nodes are arithmetic operators), evaluation is incredibly concise:

```swift
// leaf holds Double, node holds String operators like "+", "*"
let evaluationResult = mathTree.reduce(
    leaf: { leafValue in 
        leafValue 
    },
    node: { op, childValues in
        switch op {
        case "+": return childValues[0] + childValues[1]
        case "*": return childValues[0] * childValues[1]
        default:  return 0.0
        }
    },
    empty: 0.0
)
```

#### 3. Calculating Tree Depth

You can query structural properties of the tree. To find the maximum height/depth:

```swift
let maxDepth = tree.reduce(
    leaf: { _ in 1 },
    node: { _, childDepths in (childDepths.max() ?? 0) + 1 },
    empty: 0
)
```

---

## Formatting & Export Utilities

### 1. `SyntaxTreePrinter`

Generates a visually appealing console tree diagram using ANSI terminal colors:

* `branchColor`: Blue (`├── `, `└── `, `│   `)
* `leafColor`: Green
* `nodeColor`: Bold
* `emptyColor`: Dim gray

### 2. `SyntaxTreeGraphviz`

Exports the syntax tree in Graphviz DOT format.

* **Property**: `var graphviz: String` on `SyntaxTree`
* **Helper Type**: `Unique<Node>` (used to tag nodes with identifiers to distinguish duplicate values in Graphviz output).
