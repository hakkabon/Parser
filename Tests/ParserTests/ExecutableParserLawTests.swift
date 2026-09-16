import Foundation
import Grammar
import Parser
import Testing

private func parserLawModel() throws -> GrammarNormalizedModel {
    try GrammarNormalizedModel(
        startSymbol: "S",
        productions: [
            .init(id: .init(rawValue: "s-a"), lhs: "S", rhs: [.terminal(.literal("a"))]),
            .init(id: .init(rawValue: "s-b"), lhs: "S", rhs: [.terminal(.literal("b"))]),
        ]
    )
}

private func parserLawContract(
    nonterminal: String = "S", status: ParseStatus = .accepted
) -> ParseContractSnapshot {
    let span = ParseInputSpan(
        leftToken: 0, rightToken: 1, lowerUTF16Offset: 0, upperUTF16Offset: 1
    )
    return .init(
        engine: .init(identity: "law-engine", displayName: "Law engine", algorithm: "test"),
        status: status,
        tree: .production(
            nonterminal: nonterminal, productionID: .init(rawValue: "s-a"),
            span: span, children: [.token(label: "a", span: span)]
        ),
        replay: [
            .init(step: 0, kind: .start, tokenIndex: 0),
            .init(
                step: 1, kind: status == .rejected ? .reject : .accept,
                tokenIndex: 1, productionID: .init(rawValue: "s-a")
            ),
        ]
    )
}

@Test func validTreeAndReplaySatisfyExecutableParserLaws() throws {
    let report = try ParseLawVerifier.validate(
        parserLawContract(), grammar: parserLawModel(), tokenCount: 1
    )
    #expect(report.passed)
    #expect(report.violations.isEmpty)
}

@Test func alphaRenamedObservationsAreComparedModuloTheDeclaredMapping() throws {
    let model = try parserLawModel()
    let witness = try GrammarLawTransformer.alphaRenameNonterminals(
        model, renames: [.init(from: "S", to: "Root")], id: "rename-s"
    )
    let evaluation = try ParseLawVerifier.evaluate(
        witness: witness, input: "a", tokenCount: 1,
        baseline: parserLawContract(), candidate: parserLawContract(nonterminal: "Root")
    )
    #expect(evaluation.passed)
    #expect(evaluation.observationsEquivalent)
}

@Test func structuralFailuresArePositionedAndBecomeFingerprintProtectedDiscrepancies() throws {
    let model = try parserLawModel()
    let witness = try GrammarLawTransformer.permuteProductions(
        model, order: model.productions.map(\.id).reversed(), id: "order"
    )
    let baseline = parserLawContract()
    let candidate = parserLawContract(status: .rejected)
    let possibleDiscrepancy = try ParseLawDiscrepancy.makeIfFailed(
        witness: witness, input: "a", tokenCount: 1,
        baseline: baseline, candidate: candidate
    )
    let discrepancy = try #require(possibleDiscrepancy)
    #expect(!discrepancy.evaluation.passed)
    #expect(discrepancy.fingerprint.count == 16)

    let data = try JSONEncoder().encode(discrepancy)
    #expect(try JSONDecoder().decode(ParseLawDiscrepancy.self, from: data) == discrepancy)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["fingerprint"] = "0000000000000000"
    #expect(throws: ParseLawError.self) {
        try JSONDecoder().decode(
            ParseLawDiscrepancy.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }
}

@Test func malformedForestReferencesAndAmbiguityMarkersFailLaws() throws {
    let forest = ParseForestSnapshot(
        nodes: [
            .init(id: "root", kind: .symbol, label: "S", leftExtent: 0, rightExtent: 1),
            .init(
                id: "packed", kind: .packed, productionID: .init(rawValue: "missing"),
                leftExtent: 0, rightExtent: 1, pivot: 0
            ),
        ],
        edges: [.init(parent: "root", child: "unknown")],
        roots: ["root"], ambiguityNodes: ["root"]
    )
    let snapshot = ParseContractSnapshot(
        engine: .init(identity: "broken", displayName: "Broken", algorithm: "test"),
        status: .accepted, forest: forest
    )
    let report = try ParseLawVerifier.validate(
        snapshot, grammar: parserLawModel(), tokenCount: 1
    )
    #expect(!report.passed)
    #expect(report.violations.contains { $0.path.contains("productionID") })
    #expect(report.violations.contains { $0.path.contains("edges") })
    #expect(report.violations.contains { $0.path.contains("ambiguityNodes") })
}

@Test func discrepancySchemaPublishesCurrentVersion() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let object = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: root.appendingPathComponent("Schemas/ParseLawDiscrepancy.schema.json"))
    ) as? [String: Any])
    let properties = try #require(object["properties"] as? [String: Any])
    let version = try #require(properties["schemaVersion"] as? [String: Any])
    #expect(version["const"] as? Int == ParseLawDiscrepancy.currentSchemaVersion)
}
