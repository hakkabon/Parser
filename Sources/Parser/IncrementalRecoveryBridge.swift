import IncrementalParsing
import Grammar

/// Stable token evidence needed to convert Parser's token-coordinate recovery
/// script into the source-coordinate repair algebra shared by incremental
/// clients.
public struct ParseRecoveryTokenLocation<TokenID: Hashable & Sendable>: Sendable {
    public let tokenIndex: Int
    public let id: TokenID
    public let range: IncrementalParsing.SourceRange

    public init(tokenIndex: Int, id: TokenID,
                range: IncrementalParsing.SourceRange) {
        self.tokenIndex = tokenIndex
        self.id = id
        self.range = range
    }
}

public enum ParseRecoveryBridgeError: Error, Equatable, Sendable {
    case missingToken(Int)
    case duplicateTokenIndex(Int)
    case invalidTokenIndex(Int)
    case tokenRangeBeyondEnd(tokenIndex: Int, endOfInputOffset: Int)
    case invalidInsertionIndex(Int)
    case invalidEndOffset(Int)
}

private struct RecoveryTokenIndex<TokenID: Hashable & Sendable> {
    let byIndex: [Int: ParseRecoveryTokenLocation<TokenID>]
    let endInsertionIndex: Int

    init(tokens: [ParseRecoveryTokenLocation<TokenID>], endOfInputOffset: Int) throws {
        guard endOfInputOffset >= 0 else {
            throw ParseRecoveryBridgeError.invalidEndOffset(endOfInputOffset)
        }
        var indexed: [Int: ParseRecoveryTokenLocation<TokenID>] = [:]
        for token in tokens {
            guard token.tokenIndex >= 0 else {
                throw ParseRecoveryBridgeError.invalidTokenIndex(token.tokenIndex)
            }
            guard token.range.upperBound <= endOfInputOffset else {
                throw ParseRecoveryBridgeError.tokenRangeBeyondEnd(
                    tokenIndex: token.tokenIndex,
                    endOfInputOffset: endOfInputOffset)
            }
            guard indexed.updateValue(token, forKey: token.tokenIndex) == nil else {
                throw ParseRecoveryBridgeError.duplicateTokenIndex(token.tokenIndex)
            }
        }
        byIndex = indexed
        endInsertionIndex = (indexed.keys.max() ?? -1) + 1
    }
}

extension ParseRecoveryEdit {
    /// Converts normalized parser recovery into stable source evidence. The
    /// caller supplies token identities because those remain lexer-owned.
    public func incrementalAction<TokenID: Hashable & Sendable>(
        tokens: [ParseRecoveryTokenLocation<TokenID>],
        endOfInputOffset: Int
    ) throws -> IncrementalParsing.RecoveryAction<GrammarNormalizedTerminal, TokenID> {
        let locations = try RecoveryTokenIndex(
            tokens: tokens, endOfInputOffset: endOfInputOffset)
        switch self {
        case .insert(let terminal, let index):
            guard index >= 0 else {
                throw ParseRecoveryBridgeError.invalidInsertionIndex(index)
            }
            let offset: Int
            if let token = locations.byIndex[index] {
                offset = token.range.lowerBound
            } else if index == locations.endInsertionIndex {
                offset = endOfInputOffset
            } else {
                throw ParseRecoveryBridgeError.invalidInsertionIndex(index)
            }
            return .insert(terminal, at: offset)
        case .delete(_, let index):
            guard let token = locations.byIndex[index] else {
                throw ParseRecoveryBridgeError.missingToken(index)
            }
            return .delete(token.id, range: token.range)
        case .skip(let terminals, let index):
            let skipped = try (index..<(index + terminals.count)).map { tokenIndex in
                guard let token = locations.byIndex[tokenIndex] else {
                    throw ParseRecoveryBridgeError.missingToken(tokenIndex)
                }
                return token
            }
            guard let first = skipped.first, let last = skipped.last else {
                return .skip([], range: .init(location: endOfInputOffset, length: 0))
            }
            return .skip(
                skipped.map(\.id),
                range: .init(first.range.lowerBound, last.range.upperBound))
        }
    }
}

public extension DeterministicParseResult {
    /// Projects an engine's concrete recovery script into the shared,
    /// replayable repair contract. Diagnostic identifiers are stable within
    /// this result (`parser.diagnostic.<index>`) and allow clients to connect a
    /// repair to its explanatory diagnostic without depending on engine types.
    func incrementalRecoveryPlan<TokenID: Hashable & Sendable>(
        tokens: [ParseRecoveryTokenLocation<TokenID>],
        endOfInputOffset: Int,
        maximumCost: Int? = nil
    ) throws -> RecoveryPlan<GrammarNormalizedTerminal, TokenID> {
        // Validate the evidence even for a clean parse so clients never retain
        // a plan backed by malformed token coordinates.
        _ = try RecoveryTokenIndex(tokens: tokens, endOfInputOffset: endOfInputOffset)

        var unclaimedDiagnostics = Set(diagnostics.indices)
        var steps: [RecoveryStep<GrammarNormalizedTerminal, TokenID>] = []
        for edit in recoveryEdits.map(ParseRecoveryEdit.init) {
            let action = try edit.incrementalAction(
                tokens: tokens, endOfInputOffset: endOfInputOffset)
            let diagnosticIndex = matchingDiagnostic(
                for: edit,
                actionRange: action.range,
                diagnostics: diagnostics,
                candidates: unclaimedDiagnostics)
            if let diagnosticIndex {
                unclaimedDiagnostics.remove(diagnosticIndex)
            }
            let expected = diagnosticIndex.map {
                Set(ParseDiagnosticSnapshot(diagnostics[$0]).expected)
            } ?? []
            let cost: Int
            if case .skip(let terminals, _) = edit {
                cost = max(1, terminals.count)
            } else {
                cost = 1
            }
            steps.append(RecoveryStep(
                action: action,
                expected: expected,
                cost: cost,
                diagnosticID: diagnosticIndex.map { "parser.diagnostic.\($0)" }))
        }
        let totalCost = steps.reduce(0) { $0 + $1.cost }
        return try RecoveryPlan(
            steps: steps,
            maximumCost: maximumCost ?? totalCost)
    }
}

private func matchingDiagnostic(
    for edit: ParseRecoveryEdit,
    actionRange: IncrementalParsing.SourceRange,
    diagnostics: [ParseDiagnostic],
    candidates: Set<Int>
) -> Int? {
    let tokenIndex: Int
    switch edit {
    case .insert(_, let index), .delete(_, let index), .skip(_, let index):
        tokenIndex = index
    }
    let ordered = candidates.sorted()
    if let exact = ordered.first(where: { diagnostics[$0].tokenIndex == tokenIndex }) {
        return exact
    }
    if let sameOffset = ordered.first(where: {
        ParseDiagnosticSnapshot(diagnostics[$0]).range?.lowerUTF16Offset == actionRange.lowerBound
    }) {
        return sameOffset
    }
    return ordered.first
}
