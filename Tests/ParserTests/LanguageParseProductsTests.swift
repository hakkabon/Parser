import IncrementalParsing
@testable import Parser
import Testing

@Suite("Language-kit parse products")
struct LanguageParseProductsTests {
    enum NodeKind: String, Hashable, Sendable { case root, leaf }
    enum TokenKind: String, Hashable, Sendable { case name }

    struct Token: ConcreteSyntaxToken, Equatable {
        let concreteIdentity: Int
        let concreteKind: TokenKind
        let concreteLexeme: String
        let concreteRange: SourceRange
        let concretePosition: SourcePosition
        let isEndOfInput = false
    }

    @Test func syntaxEqualityIgnoresReuseIdentityAndRelocationRetainsIt() {
        let range = SourceRange(location: 2, length: 3)
        let lhs = LanguageSyntaxNode(
            id: "stable", kind: NodeKind.leaf, range: range)
        let rhs = LanguageSyntaxNode(
            id: "fresh", kind: NodeKind.leaf, range: range)

        #expect(lhs == rhs)
        let moved = lhs.relocated(by: 5)
        #expect(moved.id == "stable")
        #expect(moved.range == SourceRange(location: 7, length: 3))
    }

    @Test func concreteTreePublishesMissingAndSkippedTerminals() {
        let root = LanguageSyntaxNode(
            kind: NodeKind.root, range: SourceRange(location: 0, length: 4))
        let tree = LanguageConcreteSyntaxTree(
            root: root,
            terminals: [
                ConcreteSyntaxTerminal(
                    id: "missing", kind: TokenKind.name, lexeme: "",
                    range: SourceRange(location: 0, length: 0),
                    position: SourcePosition(offset: 0, line: 1, column: 1),
                    disposition: .missing),
                ConcreteSyntaxTerminal(
                    id: "skipped", kind: TokenKind.name, lexeme: "name",
                    range: SourceRange(location: 0, length: 4),
                    position: SourcePosition(offset: 0, line: 1, column: 1),
                    disposition: .skipped),
            ])

        #expect(tree.missingTerminals.map(\.id) == ["missing"])
        #expect(tree.skippedTerminals.map(\.id) == ["skipped"])
        #expect(tree.terminals(in: root).count == 2)
    }

    @Test func richRecoveryActionsProjectToTheCanonicalContract() {
        let token = Token(
            concreteIdentity: 42,
            concreteKind: .name,
            concreteLexeme: "value",
            concreteRange: SourceRange(location: 3, length: 5),
            concretePosition: SourcePosition(offset: 3, line: 1, column: 4))

        let action = LanguageRecoveryAction<TokenKind, Token>.delete(token: token)

        #expect(action.incrementalRecoveryAction == .delete(
            42, range: SourceRange(location: 3, length: 5)))
    }
}
