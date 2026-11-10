import Foundation
import IncrementalParsing

/// Whether syntax was present in the source or synthesized by recovery.
public enum LanguageSyntaxOrigin: String, Sendable, Codable {
    case source
    case recovered
}

/// Stable, parser-neutral syntax node shared by language kits and engines.
public struct LanguageSyntaxNode<Kind>: Sendable, Identifiable
where Kind: Hashable & Sendable {
    public let id: String
    public let kind: Kind
    public let range: SourceRange
    public let origin: LanguageSyntaxOrigin
    public let children: [Self]

    public init(id: String? = nil, kind: Kind, range: SourceRange,
                origin: LanguageSyntaxOrigin = .source,
                children: [Self] = []) {
        self.id = id ?? UUID().uuidString
        self.kind = kind
        self.range = range
        self.origin = origin
        self.children = children
    }

    public var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }

    public func relocated(by delta: Int) -> Self {
        guard delta != 0 else { return self }
        return Self(
            id: id, kind: kind,
            range: SourceRange(location: range.location + delta,
                               length: range.length),
            origin: origin,
            children: children.map { $0.relocated(by: delta) })
    }
}

extension LanguageSyntaxNode: Equatable {
    /// Equality intentionally ignores identity: independent parses of the same
    /// source have equal structure, while IDs remain available to measure reuse.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.range == rhs.range
            && lhs.origin == rhs.origin && lhs.children == rhs.children
    }
}

public extension LanguageSyntaxNode where Kind == String {
    func outline(indentation: String = "") -> String {
        let marker = origin == .recovered ? " [recovered]" : ""
        let current = "\(indentation)\(kind) @\(range.location)..<\(range.end)\(marker)"
        guard !children.isEmpty else { return current }
        return ([current] + children.map {
            $0.outline(indentation: indentation + "  ")
        }).joined(separator: "\n")
    }
}

public enum ConcreteTerminalDisposition: String, Sendable, Codable {
    case source
    case missing
    case skipped
}

public protocol ConcreteSyntaxToken: Sendable {
    associatedtype Kind: Hashable & Sendable
    associatedtype Identity: Hashable & Sendable
    var concreteIdentity: Identity { get }
    var concreteKind: Kind { get }
    var concreteLexeme: String { get }
    var concreteRange: SourceRange { get }
    var concretePosition: SourcePosition { get }
    var isEndOfInput: Bool { get }
}

public struct ConcreteSyntaxTerminal<Kind, Identity>: Sendable, Identifiable
where Kind: Hashable & Sendable, Identity: Hashable & Sendable {
    public let id: Identity
    public let kind: Kind
    public let lexeme: String
    public let range: SourceRange
    public let position: SourcePosition
    public let disposition: ConcreteTerminalDisposition

    public init(id: Identity, kind: Kind, lexeme: String, range: SourceRange,
                position: SourcePosition,
                disposition: ConcreteTerminalDisposition) {
        self.id = id
        self.kind = kind
        self.lexeme = lexeme
        self.range = range
        self.position = position
        self.disposition = disposition
    }

    public var location: SourcePosition { position }
}

extension ConcreteSyntaxTerminal: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.lexeme == rhs.lexeme
            && lhs.range == rhs.range && lhs.position == rhs.position
            && lhs.disposition == rhs.disposition
    }
}

public struct LanguageConcreteSyntaxTree<NodeKind, TokenKind, TokenIdentity>: Sendable
where NodeKind: Hashable & Sendable,
      TokenKind: Hashable & Sendable,
      TokenIdentity: Hashable & Sendable {
    public let root: LanguageSyntaxNode<NodeKind>
    public let terminals: [ConcreteSyntaxTerminal<TokenKind, TokenIdentity>]

    public init(
        root: LanguageSyntaxNode<NodeKind>,
        terminals: [ConcreteSyntaxTerminal<TokenKind, TokenIdentity>]
    ) {
        self.root = root
        self.terminals = terminals
    }

    public var missingTerminals: [ConcreteSyntaxTerminal<TokenKind, TokenIdentity>] {
        terminals.filter { $0.disposition == .missing }
    }

    public var skippedTerminals: [ConcreteSyntaxTerminal<TokenKind, TokenIdentity>] {
        terminals.filter { $0.disposition == .skipped }
    }

    public func terminals(
        in node: LanguageSyntaxNode<NodeKind>
    ) -> [ConcreteSyntaxTerminal<TokenKind, TokenIdentity>] {
        terminals.filter { terminal in
            if terminal.disposition == .missing {
                return terminal.range.location >= node.range.location
                    && terminal.range.location <= node.range.end
            }
            return terminal.range.location >= node.range.location
                && terminal.range.end <= node.range.end
        }
    }
}

extension LanguageConcreteSyntaxTree: Equatable {}

public struct LanguageParserCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let deterministicTree = Self(rawValue: 1 << 0)
    public static let errorRecovery = Self(rawValue: 1 << 1)
    public static let expectedTokens = Self(rawValue: 1 << 2)
    public static let incremental = Self(rawValue: 1 << 3)
    public static let ambiguity = Self(rawValue: 1 << 4)
}

public struct LanguageParserDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let capabilities: LanguageParserCapabilities
    public init(id: String, displayName: String,
                capabilities: LanguageParserCapabilities) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

public struct LanguageParseExpectation<TokenKind>: Sendable, Equatable, Identifiable
where TokenKind: RawRepresentable & Hashable & Sendable,
      TokenKind.RawValue == String {
    public let offset: Int
    public let kinds: [TokenKind]
    public var id: String {
        "\(offset):\(kinds.map(\.rawValue).joined(separator: ","))"
    }
    public init(offset: Int, kinds: [TokenKind]) {
        self.offset = offset
        self.kinds = kinds
    }
}

public typealias LanguageParseDiagnostic<TokenKind: Hashable & Sendable> =
    IncrementalParsing.ParseDiagnostic<TokenKind>

public enum LanguageRecoveryAction<TokenKind, Token>: Sendable
where TokenKind: Hashable & Sendable, Token: Equatable & Sendable {
    case insert(kind: TokenKind, at: Int)
    case delete(token: Token)
}

extension LanguageRecoveryAction: Equatable {}

public extension LanguageRecoveryAction where Token: ConcreteSyntaxToken,
    Token.Kind == TokenKind {
    /// Canonical parser-neutral repair used by providers, measurements, and
    /// serialized contracts. Engine and cache layers may retain the richer
    /// token value until they cross this boundary.
    var incrementalRecoveryAction:
        IncrementalParsing.RecoveryAction<TokenKind, Token.Identity> {
        switch self {
        case let .insert(kind, offset):
            .insert(kind, at: offset)
        case let .delete(token):
            .delete(token.concreteIdentity, range: token.concreteRange)
        }
    }
}

public struct LanguageRecoveryEvent<TokenKind, Token>: Sendable, Equatable, Identifiable
where TokenKind: RawRepresentable & Hashable & Sendable,
      TokenKind.RawValue == String, Token: Equatable & Sendable {
    public let id: String
    public let sequence: Int
    public let action: LanguageRecoveryAction<TokenKind, Token>
    public let expected: [TokenKind]
    public let diagnosticIDs: [String]
    public let cost: Int

    public init(id: String, sequence: Int,
                action: LanguageRecoveryAction<TokenKind, Token>,
                expected: [TokenKind], diagnosticIDs: [String], cost: Int) {
        self.id = id
        self.sequence = sequence
        self.action = action
        self.expected = expected
        self.diagnosticIDs = diagnosticIDs
        self.cost = cost
    }
}

public struct LanguageRecoveryModel<TokenKind, Token>: Sendable, Equatable
where TokenKind: RawRepresentable & Hashable & Sendable,
      TokenKind.RawValue == String, Token: Equatable & Sendable {
    public let events: [LanguageRecoveryEvent<TokenKind, Token>]
    public let expectations: [LanguageParseExpectation<TokenKind>]

    public init(events: [LanguageRecoveryEvent<TokenKind, Token>],
                expectations: [LanguageParseExpectation<TokenKind>]) {
        self.events = events
        self.expectations = expectations
    }

    public var isClean: Bool { events.isEmpty }
    public var totalCost: Int { events.reduce(0) { $0 + $1.cost } }
    public var insertionCount: Int {
        events.count { if case .insert = $0.action { true } else { false } }
    }
    public var deletionCount: Int {
        events.count { if case .delete = $0.action { true } else { false } }
    }
    public var actions: [LanguageRecoveryAction<TokenKind, Token>] {
        events.map(\.action)
    }
}

public struct LanguageParserReuseMetrics: Sendable, Equatable {
    public let reusedNodeCount: Int
    public let reusedTokenCount: Int
    public let parsedNodeCount: Int
    public let incremental: Bool

    public init(reusedNodeCount: Int, reusedTokenCount: Int,
                parsedNodeCount: Int, incremental: Bool) {
        self.reusedNodeCount = reusedNodeCount
        self.reusedTokenCount = reusedTokenCount
        self.parsedNodeCount = parsedNodeCount
        self.incremental = incremental
    }

    public static var fullParse: Self {
        Self(reusedNodeCount: 0, reusedTokenCount: 0,
             parsedNodeCount: 0, incremental: false)
    }
}

public struct LanguageParserInput<Token, Diagnostic>: Sendable
where Token: Sendable, Diagnostic: Sendable {
    public let tokens: [Token]
    public let lexicalDiagnostics: [Diagnostic]
    public let source: String?
    public init(tokens: [Token], lexicalDiagnostics: [Diagnostic],
                source: String? = nil) {
        self.tokens = tokens
        self.lexicalDiagnostics = lexicalDiagnostics
        self.source = source
    }
}

public struct LanguageParserOutput<Tree, Diagnostic, Recovery>: Sendable
where Tree: Sendable, Diagnostic: Sendable, Recovery: Sendable {
    public let syntaxTree: Tree
    public let diagnostics: [Diagnostic]
    public let recovery: Recovery
    public let reuseMetrics: LanguageParserReuseMetrics
    public init(syntaxTree: Tree, diagnostics: [Diagnostic],
                recovery: Recovery,
                reuseMetrics: LanguageParserReuseMetrics = .fullParse) {
        self.syntaxTree = syntaxTree
        self.diagnostics = diagnostics
        self.recovery = recovery
        self.reuseMetrics = reuseMetrics
    }
}

public protocol LanguageParserProtocol: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    var descriptor: LanguageParserDescriptor { get }
    func parse(_ input: Input) -> Output
}
