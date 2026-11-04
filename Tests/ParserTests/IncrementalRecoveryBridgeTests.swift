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

    func testResultProjectsACompleteDiagnosticLinkedRecoveryPlan() throws {
        let source = "a b"
        let diagnostic = ParseDiagnostic(
            reason: .extraToken,
            message: "unexpected b",
            range: source.index(source.startIndex, offsetBy: 2)..<source.endIndex,
            expected: [.string(string: ";")],
            found: .string(string: "b"),
            tokenIndex: 1,
            source: source)
        let result = UntracedParseResult(
            status: .recovered,
            tree: nil,
            diagnostics: [diagnostic],
            recoveryEdits: [.delete(terminal: .string(string: "b"), atToken: 1)])

        let plan = try result.incrementalRecoveryPlan(
            tokens: tokens, endOfInputOffset: 3)

        XCTAssertEqual(plan.totalCost, 1)
        XCTAssertEqual(plan.maximumCost, 1)
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].expected, [terminal])
        XCTAssertEqual(plan.steps[0].diagnosticID, "parser.diagnostic.0")
        let expectedAction: RecoveryAction<GrammarNormalizedTerminal, String> =
            .delete("b", range: SourceRange(2, 3))
        XCTAssertEqual(plan.steps[0].action, expectedAction)
    }

    func testSkipCostReflectsNumberOfDiscardedTokens() throws {
        let result = UntracedParseResult(
            status: .recovered,
            tree: nil,
            recoveryEdits: [.skip(
                terminals: [.string(string: "a"), .string(string: "b")],
                fromToken: 0)])

        let plan = try result.incrementalRecoveryPlan(
            tokens: tokens, endOfInputOffset: 3)
        XCTAssertEqual(plan.steps[0].cost, 2)
        XCTAssertEqual(plan.totalCost, 2)
        XCTAssertThrowsError(try result.incrementalRecoveryPlan(
            tokens: tokens, endOfInputOffset: 3, maximumCost: 1)) {
            XCTAssertEqual(
                $0 as? RecoveryPlanError,
                .budgetExceeded(cost: 2, maximum: 1))
        }
    }

    func testMalformedStableTokenEvidenceIsRejected() throws {
        let duplicate = [tokens[0], tokens[0]]
        XCTAssertThrowsError(try ParseRecoveryEdit.insert(
            terminal: terminal, atToken: 0
        ).incrementalAction(tokens: duplicate, endOfInputOffset: 3)) {
            XCTAssertEqual($0 as? ParseRecoveryBridgeError, .duplicateTokenIndex(0))
        }

        XCTAssertThrowsError(try ParseRecoveryEdit.insert(
            terminal: terminal, atToken: 4
        ).incrementalAction(tokens: tokens, endOfInputOffset: 3)) {
            XCTAssertEqual($0 as? ParseRecoveryBridgeError, .invalidInsertionIndex(4))
        }
    }
}
