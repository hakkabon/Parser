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
    case invalidEndOffset(Int)
}

extension ParseRecoveryEdit {
    /// Converts normalized parser recovery into stable source evidence. The
    /// caller supplies token identities because those remain lexer-owned.
    public func incrementalAction<TokenID: Hashable & Sendable>(
        tokens: [ParseRecoveryTokenLocation<TokenID>],
        endOfInputOffset: Int
    ) throws -> IncrementalParsing.RecoveryAction<GrammarNormalizedTerminal, TokenID> {
        guard endOfInputOffset >= 0 else {
            throw ParseRecoveryBridgeError.invalidEndOffset(endOfInputOffset)
        }
        let byIndex = Dictionary(uniqueKeysWithValues: tokens.map { ($0.tokenIndex, $0) })
        switch self {
        case .insert(let terminal, let index):
            let offset = byIndex[index]?.range.lowerBound ?? endOfInputOffset
            return .insert(terminal, at: offset)
        case .delete(_, let index):
            guard let token = byIndex[index] else {
                throw ParseRecoveryBridgeError.missingToken(index)
            }
            return .delete(token.id, range: token.range)
        case .skip(let terminals, let index):
            let skipped = try (index..<(index + terminals.count)).map { tokenIndex in
                guard let token = byIndex[tokenIndex] else {
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
