import IncrementalParsing

/// Minimal token view used by structural language providers. Parser engines
/// and language kits retain ownership of their richer token representations.
public struct DelimiterToken<Kind, Identity>: Sendable
where Kind: Hashable & Sendable, Identity: Hashable & Sendable {
    public let id: Identity
    public let kind: Kind
    public let range: SourceRange

    public init(id: Identity, kind: Kind, range: SourceRange) {
        self.id = id
        self.kind = kind
        self.range = range
    }
}

public struct DelimiterPair<Kind>: Sendable, Hashable
where Kind: Hashable & Sendable {
    public let open: Kind
    public let close: Kind

    public init(open: Kind, close: Kind) {
        self.open = open
        self.close = close
    }
}

public struct BalancedDelimiterResult<Kind, Identity>: Sendable
where Kind: Hashable & Sendable, Identity: Hashable & Sendable {
    public let diagnostics: [IncrementalParsing.ParseDiagnostic<Kind>]
    public let repairs: [RecoveryAction<Kind, Identity>]

    public init(diagnostics: [IncrementalParsing.ParseDiagnostic<Kind>],
                repairs: [RecoveryAction<Kind, Identity>]) {
        self.diagnostics = diagnostics
        self.repairs = repairs
    }
}

/// Validates nested delimiter structure and publishes deterministic repairs.
/// It deliberately does not interpret productions or language semantics.
public struct BalancedDelimiterRecovery<Kind, Identity>: Sendable
where Kind: Hashable & Sendable, Identity: Hashable & Sendable {
    private let closingByOpening: [Kind: Kind]
    private let openingByClosing: [Kind: Kind]

    public init(pairs: [DelimiterPair<Kind>]) {
        precondition(Set(pairs.map(\.open)).count == pairs.count)
        precondition(Set(pairs.map(\.close)).count == pairs.count)
        closingByOpening = Dictionary(uniqueKeysWithValues:
            pairs.map { ($0.open, $0.close) })
        openingByClosing = Dictionary(uniqueKeysWithValues:
            pairs.map { ($0.close, $0.open) })
    }

    public func validate(
        _ tokens: [DelimiterToken<Kind, Identity>], endOffset: Int
    ) -> BalancedDelimiterResult<Kind, Identity> {
        var stack: [DelimiterToken<Kind, Identity>] = []
        var diagnostics: [IncrementalParsing.ParseDiagnostic<Kind>] = []
        var repairs: [RecoveryAction<Kind, Identity>] = []

        for token in tokens {
            if closingByOpening[token.kind] != nil {
                stack.append(token)
                continue
            }
            guard openingByClosing[token.kind] != nil else { continue }
            guard !stack.isEmpty else {
                diagnostics.append(.init(
                    severity: .error,
                    message: "Unexpected closing delimiter",
                    range: token.range))
                repairs.append(.delete(token.id, range: token.range))
                continue
            }
            while let opening = stack.last,
                  closingByOpening[opening.kind] != token.kind {
                let expected = closingByOpening[opening.kind]!
                diagnostics.append(.init(
                    severity: .error,
                    message: "Mismatched closing delimiter",
                    range: SourceRange(location: token.range.location, length: 0),
                    expected: [expected]))
                repairs.append(.insert(expected, at: token.range.location))
                stack.removeLast()
            }
            if stack.last.map({ closingByOpening[$0.kind] == token.kind }) == true {
                stack.removeLast()
            } else {
                diagnostics.append(.init(
                    severity: .error,
                    message: "Unexpected closing delimiter",
                    range: token.range))
                repairs.append(.delete(token.id, range: token.range))
            }
        }

        while let opening = stack.popLast() {
            let expected = closingByOpening[opening.kind]!
            diagnostics.append(.init(
                severity: .error,
                message: "Unclosed delimiter",
                range: SourceRange(location: endOffset, length: 0),
                expected: [expected]))
            repairs.append(.insert(expected, at: endOffset))
        }
        return .init(diagnostics: diagnostics, repairs: repairs)
    }
}
