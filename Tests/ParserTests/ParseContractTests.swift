import Foundation
import Grammar
import Parser
import Testing

private struct ContractLabel: Codable, ProductionIdentifiedSPPFLabel {
    let productionID: GrammarProductionID
    let goal: NonTerminal
    let symbols: [Symbol]
    let position: Int

    var description: String {
        "\(productionID.rawValue)@\(position)"
    }
}

private func singleTokenGraph(ambiguous: Bool = false) -> SPPFGraph<ContractLabel> {
    let graph = SPPFGraph<ContractLabel>()
    let root = SPPFNode<ContractLabel>.symbol(label: "S", leftExtent: 0, rightExtent: 1)
    let leaf = SPPFNode<ContractLabel>.leaf(label: "\"😀\"", leftExtent: 0, rightExtent: 1)
    let labels = ["s-emoji"] + (ambiguous ? ["s-emoji-alternative"] : [])
    for identity in labels {
        let label = ContractLabel(
            productionID: .init(rawValue: identity),
            goal: "S",
            symbols: [.terminal(.string(string: "😀"))],
            position: 1
        )
        let packed = SPPFNode.packed(
            label: label, leftExtent: 0, rightExtent: 1, pivot: 0
        )
        graph.addEdge(from: root, to: packed)
        graph.addEdge(from: packed, to: leaf)
    }
    return graph
}

@Test func identifiedSPPFExportsDeterministicPortableForest() throws {
    let first = try singleTokenGraph(ambiguous: true).portableSnapshot()
    let second = try singleTokenGraph(ambiguous: true).portableSnapshot()

    #expect(first == second)
    #expect(first.nodes.count == 4)
    #expect(first.edges.count == 4)
    #expect(first.roots == ["symbol:1:S:0:1"])
    #expect(first.isAmbiguous)
    #expect(first.ambiguityNodes == first.roots)
    #expect(Set(first.nodes.compactMap { $0.productionID?.rawValue }) == Set([
        "s-emoji", "s-emoji-alternative"
    ]))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(first)
    #expect(try JSONDecoder().decode(ParseForestSnapshot.self, from: data) == first)
}

@Test func identifiedTreeRetainsProductionAndPortableUnicodeSpan() throws {
    let source = "😀"
    let result = try singleTokenGraph().buildProductionParseTrees(
        startSymbol: "S",
        ranges: [source.startIndex..<source.endIndex],
        source: source
    )

    #expect(!result.reachedLimit)
    #expect(result.trees.count == 1)
    guard case .production(let nonterminal, let identity, let span, let children) = result.trees[0]
    else {
        Issue.record("Expected a production root")
        return
    }
    #expect(nonterminal == "S")
    #expect(identity.rawValue == "s-emoji")
    #expect(span == .init(leftToken: 0, rightToken: 1, lowerUTF16Offset: 0, upperUTF16Offset: 2))
    #expect(children.count == 1)
    #expect(children[0].span == span)

    let data = try JSONEncoder().encode(result.trees[0])
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["kind"] as? String == "production")
    #expect(object["productionID"] as? String == "s-emoji")
    #expect(try JSONDecoder().decode(ProductionParseTree.self, from: data) == result.trees[0])
}

@Test func identifiedTreeEnumerationIsBoundedAndReportsTruncation() throws {
    let source = "😀"
    let result = try singleTokenGraph(ambiguous: true).buildProductionParseTrees(
        startSymbol: "S",
        ranges: [source.startIndex..<source.endIndex],
        source: source,
        maximumTrees: 1
    )

    #expect(result.trees.count == 1)
    #expect(result.reachedLimit)
}

@Test func epsilonTreeUsesEmptyChildrenWithoutAPlaceholderToken() throws {
    let graph = SPPFGraph<ContractLabel>()
    let root = SPPFNode<ContractLabel>.symbol(label: "S", leftExtent: 0, rightExtent: 0)
    let label = ContractLabel(
        productionID: .init(rawValue: "s-empty"), goal: "S", symbols: [], position: 0
    )
    let packed = SPPFNode.packed(label: label, leftExtent: 0, rightExtent: 0, pivot: 0)
    let epsilon = SPPFNode<ContractLabel>.leaf(label: "ε", leftExtent: 0, rightExtent: 0)
    graph.addEdge(from: root, to: packed)
    graph.addEdge(from: packed, to: epsilon)

    let result = try graph.buildProductionParseTrees(
        startSymbol: "S", ranges: [], source: ""
    )

    guard case .production(_, let identity, let span, let children) = result.trees.first
    else {
        Issue.record("Expected an epsilon production root")
        return
    }
    #expect(identity.rawValue == "s-empty")
    #expect(span.leftToken == span.rightToken)
    #expect(children.isEmpty)
}

@Test func diagnosticsRecoveryAndReplayFormPortableComparisonEnvelope() throws {
    let source = "a😀"
    let lower = source.index(after: source.startIndex)
    let diagnostic = ParseDiagnostic(
        severity: .warning,
        reason: .unexpectedToken,
        message: "Unexpected emoji.",
        range: lower..<source.endIndex,
        context: ["Expression"],
        expected: [.string(string: "+"), .string(string: "name")],
        found: .string(string: "😀"),
        parserState: 42,
        productionID: .init(rawValue: "expression-add"),
        tokenIndex: 1,
        source: source
    )
    let snapshot = ParseDiagnosticSnapshot(diagnostic)
    #expect(snapshot.range?.lowerUTF16Offset == 1)
    #expect(snapshot.range?.upperUTF16Offset == 3)
    #expect(snapshot.productionID?.rawValue == "expression-add")
    #expect(snapshot.tokenIndex == 1)
    #expect(snapshot.expected == [.literal("+"), .literal("name")])

    let contract = ParseContractSnapshot(
        engine: .init(identity: "test-lr", displayName: "Test LR", algorithm: "lalr"),
        status: .recovered,
        diagnostics: [snapshot],
        recoveryEdits: [.init(.delete(terminal: .string(string: "😀"), atToken: 1))],
        replay: [
            .init(step: 0, kind: .start, tokenIndex: 0),
            .init(
                step: 1, kind: .recover, tokenIndex: 1,
                productionID: .init(rawValue: "expression-add"),
                diagnosticReason: .unexpectedToken
            ),
        ]
    )
    let data = try JSONEncoder().encode(contract)
    #expect(try JSONDecoder().decode(ParseContractSnapshot.self, from: data) == contract)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let edits = try #require(object["recoveryEdits"] as? [[String: Any]])
    #expect(edits[0]["kind"] as? String == "delete")
}

@Test func deterministicResultsProjectWithoutExposingAlgorithmTraceState() throws {
    let source = "x"
    let result = DeterministicParseResult<Int>(
        status: .recovered,
        tree: nil,
        diagnostics: [
            ParseDiagnostic(
                severity: .warning,
                reason: .missingToken,
                message: "Inserted semicolon.",
                expected: [.string(string: ";")],
                parserState: 73,
                tokenIndex: 1,
                source: source
            )
        ],
        recoveryEdits: [.insert(terminal: .string(string: ";"), atToken: 1)],
        trace: [73, 81]
    )

    let snapshot = result.contractSnapshot(
        engine: .init(identity: "test-lr", displayName: "Test LR", algorithm: "lr")
    )

    #expect(snapshot.status == .recovered)
    #expect(snapshot.diagnostics.first?.expected == [GrammarNormalizedTerminal.literal(";")])
    #expect(snapshot.recoveryEdits == [
        ParseRecoveryEdit.insert(terminal: .literal(";"), atToken: 1)
    ])
    let data = try JSONEncoder().encode(snapshot)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("73"))
    #expect(!json.contains("81"))
}

@Test func generalizedResultsProjectTheirIdentifiedForest() throws {
    let result = ParseResult<ContractLabel>(
        isSuccessful: true,
        bsr: [],
        sppfGraph: singleTokenGraph(ambiguous: true)
    )

    let snapshot = try result.contractSnapshot(
        engine: .init(
            identity: "test-earley", displayName: "Test Earley", algorithm: "earley"
        )
    )

    #expect(snapshot.status == .accepted)
    #expect(snapshot.forest?.isAmbiguous == true)
    #expect(snapshot.isAmbiguous)
}

@Test func futureContractSchemasFailExplicitly() throws {
    let snapshot = ParseContractSnapshot(
        engine: .init(identity: "test", displayName: "Test", algorithm: "test"),
        status: .accepted
    )
    let data = try JSONEncoder().encode(snapshot)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["schemaVersion"] = ParseContractSnapshot.currentSchemaVersion + 1
    let futureData = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: ParseContractError.self) {
        try JSONDecoder().decode(ParseContractSnapshot.self, from: futureData)
    }
}

@Test func malformedForestExtentsAreRejectedAtExport() throws {
    let graph = SPPFGraph<ContractLabel>()
    let root = SPPFNode<ContractLabel>.symbol(label: "S", leftExtent: 0, rightExtent: 1)
    let label = ContractLabel(
        productionID: .init(rawValue: "s-x"),
        goal: "S",
        symbols: [.terminal(.string(string: "x"))],
        position: 1
    )
    let invalid = SPPFNode.packed(label: label, leftExtent: 0, rightExtent: 1, pivot: 2)
    graph.addEdge(from: root, to: invalid)

    #expect(throws: ParseContractError.self) {
        try graph.portableSnapshot()
    }
}

@Test func publishedSchemaMatchesTheCurrentContractVersion() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Schemas/ParseContract.schema.json"))
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let contract = try #require(definitions["contract"] as? [String: Any])
    let properties = try #require(contract["properties"] as? [String: Any])
    let version = try #require(properties["schemaVersion"] as? [String: Any])
    #expect(version["const"] as? Int == ParseContractSnapshot.currentSchemaVersion)
}
