import Grammar

/// Whether parsing completed without repairs, completed after recovery, or
/// could not produce a complete parse.
public enum ParseStatus: String, Sendable, Equatable {
    case accepted
    case recovered
    case rejected
}

/// A concrete input edit performed by a parser's recovery policy.
public enum RecoveryEdit: CustomStringConvertible {
    case insert(terminal: Terminal, atToken: Int)
    case delete(terminal: Terminal, atToken: Int)
    case skip(terminals: [Terminal], fromToken: Int)

    public var description: String {
        switch self {
        case .insert(let terminal, let index):
            return "insert \(terminal) at token \(index)"
        case .delete(let terminal, let index):
            return "delete \(terminal) at token \(index)"
        case .skip(let terminals, let index):
            return "skip \(terminals.map(\.description).joined(separator: " ")) from token \(index)"
        }
    }
}

/// The immutable output of a recoverable deterministic parse.
///
/// `Trace` remains generic because trace events are inherently tied to an
/// algorithm. Parsers that do not trace use ``NoParseTrace``.
public struct DeterministicParseResult<Trace> {
    public let status: ParseStatus
    public let tree: ParseTree?
    public let diagnostics: [ParseDiagnostic]
    public let recoveryEdits: [RecoveryEdit]
    public let trace: [Trace]

    public init(
        status: ParseStatus,
        tree: ParseTree?,
        diagnostics: [ParseDiagnostic] = [],
        recoveryEdits: [RecoveryEdit] = [],
        trace: [Trace] = []
    ) {
        self.status = status
        self.tree = tree
        self.diagnostics = diagnostics
        self.recoveryEdits = recoveryEdits
        self.trace = trace
    }
}

/// Trace marker used by parsers that do not expose algorithm trace events.
public enum NoParseTrace: Sendable {}

public typealias UntracedParseResult = DeterministicParseResult<NoParseTrace>
