import Foundation
import Grammar

/// A half-open input span using token indices and UTF-16 offsets.
///
/// Token extents match SPPF notation (`[leftToken, rightToken)`). UTF-16
/// offsets make the same span portable to LSP, editors, and serialized traces.
public struct ParseInputSpan: Hashable, Codable, Sendable {
    public let leftToken: Int
    public let rightToken: Int
    public let lowerUTF16Offset: Int
    public let upperUTF16Offset: Int

    public init(
        leftToken: Int,
        rightToken: Int,
        lowerUTF16Offset: Int,
        upperUTF16Offset: Int
    ) {
        self.leftToken = leftToken
        self.rightToken = rightToken
        self.lowerUTF16Offset = lowerUTF16Offset
        self.upperUTF16Offset = upperUTF16Offset
    }
}

/// A concrete parse tree whose internal nodes retain production identity.
public indirect enum ProductionParseTree: Hashable, Codable, Sendable {
    case token(label: String, span: ParseInputSpan)
    case production(
        nonterminal: String,
        productionID: GrammarProductionID,
        span: ParseInputSpan,
        children: [ProductionParseTree]
    )

    public var span: ParseInputSpan {
        switch self {
        case .token(_, let span), .production(_, _, let span, _): span
        }
    }

    public var productionID: GrammarProductionID? {
        guard case .production(_, let identity, _, _) = self else { return nil }
        return identity
    }

    public var children: [ProductionParseTree] {
        guard case .production(_, _, _, let children) = self else { return [] }
        return children
    }
}

extension ProductionParseTree {
    private enum CodingKeys: String, CodingKey {
        case kind, label, span, nonterminal, productionID, children
    }
    private enum Kind: String, Codable { case token, production }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .token:
            self = .token(
                label: try values.decode(String.self, forKey: .label),
                span: try values.decode(ParseInputSpan.self, forKey: .span)
            )
        case .production:
            self = .production(
                nonterminal: try values.decode(String.self, forKey: .nonterminal),
                productionID: try values.decode(GrammarProductionID.self, forKey: .productionID),
                span: try values.decode(ParseInputSpan.self, forKey: .span),
                children: try values.decode([ProductionParseTree].self, forKey: .children)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .token(let label, let span):
            try values.encode(Kind.token, forKey: .kind)
            try values.encode(label, forKey: .label)
            try values.encode(span, forKey: .span)
        case .production(let nonterminal, let productionID, let span, let children):
            try values.encode(Kind.production, forKey: .kind)
            try values.encode(nonterminal, forKey: .nonterminal)
            try values.encode(productionID, forKey: .productionID)
            try values.encode(span, forKey: .span)
            try values.encode(children, forKey: .children)
        }
    }
}

public enum ParseForestNodeKind: String, Hashable, Codable, Sendable {
    case token
    case symbol
    case intermediate
    case packed
}

/// One portable SPPF node. Fields not meaningful for `kind` are nil.
public struct ParseForestNode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: ParseForestNodeKind
    public let label: String?
    public let productionID: GrammarProductionID?
    public let position: Int?
    public let leftExtent: Int
    public let rightExtent: Int
    public let pivot: Int?

    public init(
        id: String,
        kind: ParseForestNodeKind,
        label: String? = nil,
        productionID: GrammarProductionID? = nil,
        position: Int? = nil,
        leftExtent: Int,
        rightExtent: Int,
        pivot: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.productionID = productionID
        self.position = position
        self.leftExtent = leftExtent
        self.rightExtent = rightExtent
        self.pivot = pivot
    }
}

public struct ParseForestEdge: Hashable, Codable, Sendable, Comparable {
    public let parent: String
    public let child: String

    public init(parent: String, child: String) {
        self.parent = parent
        self.child = child
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.parent, lhs.child) < (rhs.parent, rhs.child)
    }
}

/// A deterministic, serializable SPPF for engine comparison and exploration.
public struct ParseForestSnapshot: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let nodes: [ParseForestNode]
    public let edges: [ParseForestEdge]
    public let roots: [String]
    public let ambiguityNodes: [String]

    public init(
        nodes: [ParseForestNode],
        edges: [ParseForestEdge],
        roots: [String],
        ambiguityNodes: [String]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.nodes = nodes
        self.edges = edges
        self.roots = roots
        self.ambiguityNodes = ambiguityNodes
    }

    public var isAmbiguous: Bool { !ambiguityNodes.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, nodes, edges, roots, ambiguityNodes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ParseContractError.unsupportedSchema(
                contract: "ParseForestSnapshot", version: version
            )
        }
        schemaVersion = version
        nodes = try values.decode([ParseForestNode].self, forKey: .nodes)
        edges = try values.decode([ParseForestEdge].self, forKey: .edges)
        roots = try values.decode([String].self, forKey: .roots)
        ambiguityNodes = try values.decode([String].self, forKey: .ambiguityNodes)
    }
}

public enum ParseContractError: Error, Equatable, Sendable, LocalizedError {
    case invalidExtent(left: Int, right: Int, tokenCount: Int)
    case duplicateForestNodeIdentity(String)
    case missingRoot(startSymbol: String, rightExtent: Int)
    case unsupportedSchema(contract: String, version: Int)
    case invalidForestExtent(left: Int, right: Int, pivot: Int?)

    public var errorDescription: String? {
        switch self {
        case .invalidExtent(let left, let right, let count):
            "Invalid token extent [\(left), \(right)) for \(count) token ranges."
        case .duplicateForestNodeIdentity(let identity):
            "More than one SPPF node maps to portable identity \(identity)."
        case .missingRoot(let start, let right):
            "No SPPF root for \(start) spanning [0, \(right)) was found."
        case .unsupportedSchema(let contract, let version):
            "\(contract) schema \(version) is not supported."
        case .invalidForestExtent(let left, let right, let pivot):
            "Invalid forest extent [\(left), \(right)) with pivot \(pivot.map(String.init) ?? "none")."
        }
    }
}

/// Bounded output from concrete-tree enumeration over a packed forest.
public struct ProductionParseTreeEnumeration: Hashable, Codable, Sendable {
    public let trees: [ProductionParseTree]
    public let reachedLimit: Bool

    public init(trees: [ProductionParseTree], reachedLimit: Bool) {
        self.trees = trees
        self.reachedLimit = reachedLimit
    }
}

/// Portable source location for a parser diagnostic.
public struct ParseDiagnosticRange: Hashable, Codable, Sendable {
    public let lowerUTF16Offset: Int
    public let upperUTF16Offset: Int
    public let line: Int
    public let column: Int

    public init(
        lowerUTF16Offset: Int,
        upperUTF16Offset: Int,
        line: Int,
        column: Int
    ) {
        self.lowerUTF16Offset = lowerUTF16Offset
        self.upperUTF16Offset = upperUTF16Offset
        self.line = line
        self.column = column
    }
}

/// Codable, engine-neutral projection of ``ParseDiagnostic``.
public struct ParseDiagnosticSnapshot: Hashable, Codable, Sendable {
    public let severity: ParseDiagnostic.Severity
    public let reason: ParseDiagnostic.Reason
    public let message: String
    public let range: ParseDiagnosticRange?
    public let context: [String]
    public let expected: [GrammarNormalizedTerminal]
    public let found: GrammarNormalizedTerminal?
    public let productionID: GrammarProductionID?
    public let tokenIndex: Int?

    public init(_ diagnostic: ParseDiagnostic) {
        severity = diagnostic.severity
        reason = diagnostic.reason
        message = diagnostic.message
        context = diagnostic.context.map(\.name)
        expected = diagnostic.expected.map(normalizedTerminal).sorted()
        found = diagnostic.found.map(normalizedTerminal)
        productionID = diagnostic.productionID
        tokenIndex = diagnostic.tokenIndex
        if let sourceRange = diagnostic.range {
            range = ParseDiagnosticRange(
                lowerUTF16Offset: diagnostic.source[..<sourceRange.lowerBound].utf16.count,
                upperUTF16Offset: diagnostic.source[..<sourceRange.upperBound].utf16.count,
                line: diagnostic.line,
                column: diagnostic.column
            )
        } else {
            range = nil
        }
    }
}

/// Codable recovery edit using normalized terminals and token positions.
public enum ParseRecoveryEdit: Hashable, Codable, Sendable {
    case insert(terminal: GrammarNormalizedTerminal, atToken: Int)
    case delete(terminal: GrammarNormalizedTerminal, atToken: Int)
    case skip(terminals: [GrammarNormalizedTerminal], fromToken: Int)

    public init(_ edit: RecoveryEdit) {
        switch edit {
        case .insert(let terminal, let index):
            self = .insert(terminal: normalizedTerminal(terminal), atToken: index)
        case .delete(let terminal, let index):
            self = .delete(terminal: normalizedTerminal(terminal), atToken: index)
        case .skip(let terminals, let index):
            self = .skip(terminals: terminals.map(normalizedTerminal), fromToken: index)
        }
    }
}

extension ParseRecoveryEdit {
    private enum CodingKeys: String, CodingKey { case kind, terminal, terminals, atToken, fromToken }
    private enum Kind: String, Codable { case insert, delete, skip }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .insert:
            self = .insert(
                terminal: try values.decode(GrammarNormalizedTerminal.self, forKey: .terminal),
                atToken: try values.decode(Int.self, forKey: .atToken)
            )
        case .delete:
            self = .delete(
                terminal: try values.decode(GrammarNormalizedTerminal.self, forKey: .terminal),
                atToken: try values.decode(Int.self, forKey: .atToken)
            )
        case .skip:
            self = .skip(
                terminals: try values.decode([GrammarNormalizedTerminal].self, forKey: .terminals),
                fromToken: try values.decode(Int.self, forKey: .fromToken)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insert(let terminal, let index):
            try values.encode(Kind.insert, forKey: .kind)
            try values.encode(terminal, forKey: .terminal)
            try values.encode(index, forKey: .atToken)
        case .delete(let terminal, let index):
            try values.encode(Kind.delete, forKey: .kind)
            try values.encode(terminal, forKey: .terminal)
            try values.encode(index, forKey: .atToken)
        case .skip(let terminals, let index):
            try values.encode(Kind.skip, forKey: .kind)
            try values.encode(terminals, forKey: .terminals)
            try values.encode(index, forKey: .fromToken)
        }
    }
}

/// Stable identity and presentation metadata for one parser engine.
public struct ParseEngineDescriptor: Hashable, Codable, Sendable {
    public let identity: String
    public let displayName: String
    public let algorithm: String

    public init(identity: String, displayName: String, algorithm: String) {
        self.identity = identity
        self.displayName = displayName
        self.algorithm = algorithm
    }
}

/// Semantic milestones suitable for replay without exposing engine state layout.
public enum ParseReplayEventKind: String, Hashable, Codable, Sendable {
    case start
    case inspect
    case consume
    case applyProduction
    case discoverAmbiguity
    case recover
    case accept
    case reject
}

public struct ParseReplayEvent: Identifiable, Hashable, Codable, Sendable {
    public let step: Int
    public let kind: ParseReplayEventKind
    public let tokenIndex: Int?
    public let productionID: GrammarProductionID?
    public let forestNodeID: String?
    public let diagnosticReason: ParseDiagnostic.Reason?
    public var id: Int { step }

    public init(
        step: Int,
        kind: ParseReplayEventKind,
        tokenIndex: Int? = nil,
        productionID: GrammarProductionID? = nil,
        forestNodeID: String? = nil,
        diagnosticReason: ParseDiagnostic.Reason? = nil
    ) {
        self.step = step
        self.kind = kind
        self.tokenIndex = tokenIndex
        self.productionID = productionID
        self.forestNodeID = forestNodeID
        self.diagnosticReason = diagnosticReason
    }
}

/// The shared result envelope compared across deterministic and generalized engines.
public struct ParseContractSnapshot: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let engine: ParseEngineDescriptor
    public let status: ParseStatus
    public let tree: ProductionParseTree?
    public let forest: ParseForestSnapshot?
    public let diagnostics: [ParseDiagnosticSnapshot]
    public let recoveryEdits: [ParseRecoveryEdit]
    public let replay: [ParseReplayEvent]

    public init(
        engine: ParseEngineDescriptor,
        status: ParseStatus,
        tree: ProductionParseTree? = nil,
        forest: ParseForestSnapshot? = nil,
        diagnostics: [ParseDiagnosticSnapshot] = [],
        recoveryEdits: [ParseRecoveryEdit] = [],
        replay: [ParseReplayEvent] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.engine = engine
        self.status = status
        self.tree = tree
        self.forest = forest
        self.diagnostics = diagnostics
        self.recoveryEdits = recoveryEdits
        self.replay = replay
    }

    public var isAmbiguous: Bool { forest?.isAmbiguous ?? false }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, engine, status, tree, forest, diagnostics, recoveryEdits, replay
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ParseContractError.unsupportedSchema(
                contract: "ParseContractSnapshot", version: version
            )
        }
        schemaVersion = version
        engine = try values.decode(ParseEngineDescriptor.self, forKey: .engine)
        status = try values.decode(ParseStatus.self, forKey: .status)
        tree = try values.decodeIfPresent(ProductionParseTree.self, forKey: .tree)
        forest = try values.decodeIfPresent(ParseForestSnapshot.self, forKey: .forest)
        diagnostics = try values.decode([ParseDiagnosticSnapshot].self, forKey: .diagnostics)
        recoveryEdits = try values.decode([ParseRecoveryEdit].self, forKey: .recoveryEdits)
        replay = try values.decode([ParseReplayEvent].self, forKey: .replay)
    }
}

public extension DeterministicParseResult {
    /// Projects a deterministic engine result into the shared comparison contract.
    func contractSnapshot(
        engine: ParseEngineDescriptor,
        identifiedTree: ProductionParseTree? = nil,
        forest: ParseForestSnapshot? = nil,
        replay: [ParseReplayEvent] = []
    ) -> ParseContractSnapshot {
        ParseContractSnapshot(
            engine: engine,
            status: status,
            tree: identifiedTree,
            forest: forest,
            diagnostics: diagnostics.map(ParseDiagnosticSnapshot.init),
            recoveryEdits: recoveryEdits.map(ParseRecoveryEdit.init),
            replay: replay
        )
    }
}

public extension ParseResult where Label: ProductionIdentifiedSPPFLabel {
    /// Projects a generalized engine result and its SPPF into the shared contract.
    func contractSnapshot(
        engine: ParseEngineDescriptor,
        identifiedTree: ProductionParseTree? = nil,
        replay: [ParseReplayEvent] = []
    ) throws -> ParseContractSnapshot {
        try ParseContractSnapshot(
            engine: engine,
            status: isSuccessful ? .accepted : .rejected,
            tree: identifiedTree,
            forest: sppfGraph?.portableSnapshot(),
            replay: replay
        )
    }
}

private func normalizedTerminal(_ terminal: Terminal) -> GrammarNormalizedTerminal {
    switch terminal {
    case .string(let value): .literal(value)
    case .stringList(let values): .literals(values)
    case .characterRange(let range):
        .characterRange(lower: range.lowerBound, upper: range.upperBound)
    case .regularExpression(let expression): .regularExpression(expression.pattern)
    case .meta(let value): .boundary(value.rawValue)
    }
}

public extension SPPFGraph where Label: ProductionIdentifiedSPPFLabel {
    /// Exports this graph without algorithm-specific label types.
    func portableSnapshot() throws -> ParseForestSnapshot {
        let graphNodes = getAllNodes()
        var portableByNode: [SPPFNode<Label>: ParseForestNode] = [:]
        var nodeIDs: Set<String> = []
        for node in graphNodes {
            let portable = portableNode(node)
            guard portable.leftExtent >= 0,
                  portable.rightExtent >= portable.leftExtent,
                  portable.pivot.map({ $0 >= portable.leftExtent && $0 <= portable.rightExtent }) ?? true else {
                throw ParseContractError.invalidForestExtent(
                    left: portable.leftExtent,
                    right: portable.rightExtent,
                    pivot: portable.pivot
                )
            }
            guard nodeIDs.insert(portable.id).inserted else {
                throw ParseContractError.duplicateForestNodeIdentity(portable.id)
            }
            portableByNode[node] = portable
        }

        var edges: Set<ParseForestEdge> = []
        var children: Set<String> = []
        var ambiguities: [String] = []
        for node in graphNodes {
            guard let parent = portableByNode[node] else { continue }
            let graphChildren = getChildren(of: node)
            for child in graphChildren {
                guard let childID = portableByNode[child]?.id else { continue }
                edges.insert(.init(parent: parent.id, child: childID))
                children.insert(childID)
            }
            switch node {
            case .symbol, .intermediate:
                if graphChildren.filter({ if case .packed = $0 { return true }; return false }).count > 1 {
                    ambiguities.append(parent.id)
                }
            case .leaf, .packed:
                break
            }
        }
        let nodes = portableByNode.values.sorted { $0.id < $1.id }
        return ParseForestSnapshot(
            nodes: nodes,
            edges: edges.sorted(),
            roots: nodes.map(\.id).filter { !children.contains($0) }.sorted(),
            ambiguityNodes: ambiguities.sorted()
        )
    }

    /// Enumerates production-identified concrete trees up to `maximumTrees`.
    func buildProductionParseTrees(
        startSymbol: String,
        ranges: [Range<String.Index>],
        source: String,
        maximumTrees: Int = 128
    ) throws -> ProductionParseTreeEnumeration {
        let limit = max(1, maximumTrees)
        let roots = getAllNodes().filter { node in
            if case .symbol(let label, let left, let right) = node {
                return label == startSymbol && left == 0 && right == ranges.count
            }
            return false
        }.sorted { portableNodeID($0) < portableNodeID($1) }
        guard !roots.isEmpty else {
            throw ParseContractError.missingRoot(startSymbol: startSymbol, rightExtent: ranges.count)
        }

        var reachedLimit = false
        var trees: [ProductionParseTree] = []
        for root in roots {
            var active: Set<SPPFNode<Label>> = []
            let alternatives = try expandIdentified(
                root, ranges: ranges, source: source, limit: limit,
                active: &active, reachedLimit: &reachedLimit
            )
            for alternative in alternatives {
                guard let tree = alternative.first, !trees.contains(tree) else { continue }
                if trees.count == limit { reachedLimit = true; break }
                trees.append(tree)
            }
            if trees.count == limit { break }
        }
        return ProductionParseTreeEnumeration(trees: trees, reachedLimit: reachedLimit)
    }

    private func expandIdentified(
        _ node: SPPFNode<Label>,
        ranges: [Range<String.Index>],
        source: String,
        limit: Int,
        active: inout Set<SPPFNode<Label>>,
        reachedLimit: inout Bool
    ) throws -> [[ProductionParseTree]] {
        guard active.insert(node).inserted else { return [] }
        defer { active.remove(node) }

        switch node {
        case .leaf(let label, let left, let right):
            return [[.token(label: label, span: try inputSpan(
                left: left, right: right, ranges: ranges, source: source
            ))]]

        case .symbol(let nonterminal, let left, let right):
            let span = try inputSpan(left: left, right: right, ranges: ranges, source: source)
            var alternatives: [[ProductionParseTree]] = []
            for child in getChildren(of: node).sorted(by: { portableNodeID($0) < portableNodeID($1) }) {
                guard case .packed(let label, _, _, _) = child else { continue }
                let childAlternatives = try expandIdentified(
                    child, ranges: ranges, source: source, limit: limit,
                    active: &active, reachedLimit: &reachedLimit
                )
                for children in childAlternatives {
                    appendBounded(
                        [.production(
                            nonterminal: nonterminal,
                            productionID: label.productionID,
                            span: span,
                            children: children
                        )],
                        to: &alternatives, limit: limit, reachedLimit: &reachedLimit
                    )
                }
            }
            return alternatives

        case .intermediate:
            var alternatives: [[ProductionParseTree]] = []
            for child in getChildren(of: node).sorted(by: { portableNodeID($0) < portableNodeID($1) }) {
                guard case .packed = child else { continue }
                let childAlternatives = try expandIdentified(
                    child, ranges: ranges, source: source, limit: limit,
                    active: &active, reachedLimit: &reachedLimit
                )
                for alternative in childAlternatives {
                    appendBounded(
                        alternative, to: &alternatives,
                        limit: limit, reachedLimit: &reachedLimit
                    )
                }
            }
            return alternatives

        case .packed(let label, let left, let right, let pivot):
            if label.symbols.isEmpty { return [[]] }
            return try expandPacked(
                node, label: label, left: left, right: right, pivot: pivot,
                ranges: ranges, source: source, limit: limit,
                active: &active, reachedLimit: &reachedLimit
            )
        }
    }

    private func expandPacked(
        _ node: SPPFNode<Label>,
        label: Label,
        left: Int,
        right: Int,
        pivot: Int,
        ranges: [Range<String.Index>],
        source: String,
        limit: Int,
        active: inout Set<SPPFNode<Label>>,
        reachedLimit: inout Bool
    ) throws -> [[ProductionParseTree]] {
        _ = try inputSpan(left: left, right: right, ranges: ranges, source: source)
        guard pivot >= left, pivot <= right else {
            throw ParseContractError.invalidExtent(left: left, right: pivot, tokenCount: ranges.count)
        }
        let alpha = Array(label.symbols.prefix(label.position))
        let children = getChildren(of: node)
        var leftChild: SPPFNode<Label>?
        var rightChild: SPPFNode<Label>?
        for child in children {
            let extents = extents(of: child)
            if extents == (pivot, right), let symbol = alpha.last,
               matches(symbol, node: child) {
                rightChild = child
            } else if extents == (left, pivot) {
                if alpha.count == 2, let symbol = alpha.first, matches(symbol, node: child) {
                    leftChild = child
                } else if alpha.count > 2, case .intermediate = child {
                    leftChild = child
                }
            }
        }
        if leftChild == nil && rightChild == nil {
            for child in children {
                let extents = extents(of: child)
                if extents == (pivot, right) { rightChild = child }
                else if extents == (left, pivot) { leftChild = child }
            }
        }

        let leftAlternatives = try leftChild.map {
            try expandIdentified(
                $0, ranges: ranges, source: source, limit: limit,
                active: &active, reachedLimit: &reachedLimit
            )
        } ?? [[]]
        let rightAlternatives = try rightChild.map {
            try expandIdentified(
                $0, ranges: ranges, source: source, limit: limit,
                active: &active, reachedLimit: &reachedLimit
            )
        } ?? [[]]

        var result: [[ProductionParseTree]] = []
        for lhs in leftAlternatives {
            for rhs in rightAlternatives {
                appendBounded(
                    lhs + rhs, to: &result, limit: limit, reachedLimit: &reachedLimit
                )
            }
        }
        return result
    }

    private func portableNode(_ node: SPPFNode<Label>) -> ParseForestNode {
        switch node {
        case .leaf(let label, let left, let right):
            return .init(
                id: portableNodeID(node), kind: .token, label: label,
                leftExtent: left, rightExtent: right
            )
        case .symbol(let label, let left, let right):
            return .init(
                id: portableNodeID(node), kind: .symbol, label: label,
                leftExtent: left, rightExtent: right
            )
        case .intermediate(let label, let left, let right):
            return .init(
                id: portableNodeID(node), kind: .intermediate,
                productionID: label.productionID, position: label.position,
                leftExtent: left, rightExtent: right
            )
        case .packed(let label, let left, let right, let pivot):
            return .init(
                id: portableNodeID(node), kind: .packed,
                productionID: label.productionID, position: label.position,
                leftExtent: left, rightExtent: right, pivot: pivot
            )
        }
    }

    private func portableNodeID(_ node: SPPFNode<Label>) -> String {
        func field(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        switch node {
        case .leaf(let label, let left, let right):
            return "token:\(field(label)):\(left):\(right)"
        case .symbol(let label, let left, let right):
            return "symbol:\(field(label)):\(left):\(right)"
        case .intermediate(let label, let left, let right):
            return "intermediate:\(field(label.productionID.rawValue)):\(label.position):\(left):\(right)"
        case .packed(let label, let left, let right, let pivot):
            return "packed:\(field(label.productionID.rawValue)):\(label.position):\(left):\(right):\(pivot)"
        }
    }

    private func extents(of node: SPPFNode<Label>) -> (Int, Int) {
        switch node {
        case .leaf(_, let left, let right), .symbol(_, let left, let right),
             .intermediate(_, let left, let right), .packed(_, let left, let right, _):
            return (left, right)
        }
    }

    private func matches(_ symbol: Symbol, node: SPPFNode<Label>) -> Bool {
        switch (symbol, node) {
        case (.terminal(let terminal), .leaf(let label, _, _)):
            return terminal.description == label
        case (.nonTerminal(let nonterminal), .symbol(let label, _, _)):
            return nonterminal.name == label
        case (.metaSymbol(let meta), .leaf(let label, _, _)):
            return meta.description == label
        default:
            return false
        }
    }

    private func inputSpan(
        left: Int,
        right: Int,
        ranges: [Range<String.Index>],
        source: String
    ) throws -> ParseInputSpan {
        guard left >= 0, right >= left, right <= ranges.count else {
            throw ParseContractError.invalidExtent(left: left, right: right, tokenCount: ranges.count)
        }
        let lowerIndex: String.Index
        let upperIndex: String.Index
        if left == right {
            lowerIndex = left < ranges.count ? ranges[left].lowerBound : source.endIndex
            upperIndex = lowerIndex
        } else {
            lowerIndex = ranges[left].lowerBound
            upperIndex = ranges[right - 1].upperBound
        }
        return ParseInputSpan(
            leftToken: left,
            rightToken: right,
            lowerUTF16Offset: source[..<lowerIndex].utf16.count,
            upperUTF16Offset: source[..<upperIndex].utf16.count
        )
    }

    private func appendBounded<T>(
        _ value: T,
        to result: inout [T],
        limit: Int,
        reachedLimit: inout Bool
    ) {
        if result.count < limit { result.append(value) }
        else { reachedLimit = true }
    }
}
