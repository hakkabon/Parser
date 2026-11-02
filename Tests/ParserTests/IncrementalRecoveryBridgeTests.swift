import XCTest
import Grammar
import IncrementalParsing
@testable import Parser

final class IncrementalRecoveryBridgeTests: XCTestCase {
    private let terminal = GrammarNormalizedTerminal.literal(";")
    private let tokens = [
        ParseRecoveryTokenLocation(tokenIndex: 0, id: "a", range: SourceRange(0, 1)),
        ParseRecoveryTokenLocation(tokenIndex: 1, id: "b", range: SourceRange(2, 3)),
    ]

    func testInsertionUsesTokenBoundaryOrEndOfInput() throws {
        let before = try ParseRecoveryEdit.insert(terminal: terminal, atToken: 1)
            .incrementalAction(tokens: tokens, endOfInputOffset: 3)
        XCTAssertEqual(before.range, SourceRange(2, 2))

        let atEnd = try ParseRecoveryEdit.insert(terminal: terminal, atToken: 2)
            .incrementalAction(tokens: tokens, endOfInputOffset: 3)
        XCTAssertEqual(atEnd.range, SourceRange(3, 3))
    }

    func testDeletionAndSkipRetainStableTokenIDs() throws {
        let deletion = try ParseRecoveryEdit.delete(terminal: terminal, atToken: 1)
            .incrementalAction(tokens: tokens, endOfInputOffset: 3)
        guard case .delete(let id, let range) = deletion else {
            return XCTFail("expected delete")
        }
        XCTAssertEqual(id, "b")
        XCTAssertEqual(range, SourceRange(2, 3))

        let skip = try ParseRecoveryEdit.skip(
            terminals: [terminal, terminal], fromToken: 0
        ).incrementalAction(tokens: tokens, endOfInputOffset: 3)
        guard case .skip(let ids, let range) = skip else {
            return XCTFail("expected skip")
        }
        XCTAssertEqual(ids, ["a", "b"])
        XCTAssertEqual(range, SourceRange(0, 3))
    }
}
