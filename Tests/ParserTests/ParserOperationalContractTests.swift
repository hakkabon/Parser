import Foundation
import Grammar
import Parser
import Testing

private let operationalEngine = ParseEngineDescriptor(
    identity: "test-cyk", displayName: "Test CYK", algorithm: "cyk"
)

private let operationalCapabilities = ParseOperationalCapabilities(
    features: [.productionTree, .replay, .normalizationProvenance],
    reportedCounters: [.inputTokens, .workItems, .replayEvents, .diagnostics],
    limitableCounters: [.workItems],
    normalizationTargets: [.chomsky]
)

private func normalizationAndResult() throws -> (
    GrammarNormalizationReport, ParseContractSnapshot
) {
    let grammar = Grammar(
        productions: [Production(goal: "S", rule: [.terminal(.string(string: "a"))])],
        start: "S",
        lexicalTokens: [:]
    )
    let normalization = try grammar.normalizationReport(
        to: .chomsky,
        productionIDs: [.init(rawValue: "source-s-a")]
    )
    let normalizedID = try #require(normalization.output.productions.first?.id)
    let span = ParseInputSpan(
        leftToken: 0, rightToken: 1, lowerUTF16Offset: 0, upperUTF16Offset: 1
    )
    let tree = ProductionParseTree.production(
        nonterminal: "S", productionID: normalizedID, span: span,
        children: [.token(label: "a", span: span)]
    )
    let result = ParseContractSnapshot(
        engine: operationalEngine,
        status: .accepted,
        tree: tree,
        replay: [
            .init(step: 0, kind: .start, tokenIndex: 0),
            .init(step: 1, kind: .applyProduction, productionID: normalizedID),
            .init(step: 2, kind: .consume, tokenIndex: 0),
            .init(step: 3, kind: .accept, tokenIndex: 1),
        ]
    )
    return (normalization, result)
}

@Test func completedOperationCarriesValidatedNormalizationProvenance() throws {
    let (normalization, result) = try normalizationAndResult()
    let operation = try ParseOperationalSnapshot(
        engine: operationalEngine,
        capabilities: operationalCapabilities,
        disposition: .completed,
        result: result,
        normalization: normalization,
        limits: [.init(.workItems, 100)],
        measurements: [
            .init(.inputTokens, 1), .init(.workItems, 4),
            .init(.replayEvents, 4), .init(.diagnostics, 0),
        ]
    )

    #expect(operation.measurement(.workItems) == 4)
    #expect(operation.provenance(
        for: try #require(normalization.output.productions.first?.id)
    )?.sourceProductionIDs == [
        GrammarProductionID(rawValue: "source-s-a")
    ])
    let data = try JSONEncoder().encode(operation)
    #expect(try JSONDecoder().decode(ParseOperationalSnapshot.self, from: data) == operation)
}

@Test func rejectedInputIsACompletedOperation() throws {
    let result = ParseContractSnapshot(engine: operationalEngine, status: .rejected)
    let operation = try ParseOperationalSnapshot(
        engine: operationalEngine,
        capabilities: .init(reportedCounters: [.inputTokens]),
        disposition: .completed,
        result: result,
        measurements: [.init(.inputTokens, 1)]
    )

    #expect(operation.disposition == .completed)
    #expect(operation.result?.status == .rejected)
}

@Test func limitedAndUnsupportedOperationsRemainDistinct() throws {
    let capabilities = ParseOperationalCapabilities(
        reportedCounters: [.workItems], limitableCounters: [.workItems]
    )
    let limited = try ParseOperationalSnapshot(
        engine: operationalEngine,
        capabilities: capabilities,
        disposition: .limited,
        limits: [.init(.workItems, 10)],
        measurements: [.init(.workItems, 10)],
        reachedLimits: [.workItems]
    )
    let unsupported = try ParseOperationalSnapshot(
        engine: operationalEngine,
        capabilities: capabilities,
        disposition: .unsupported,
        message: "This grammar is outside the engine's declared language class."
    )

    #expect(limited.reachedLimits == [.workItems])
    #expect(unsupported.result == nil)
    #expect(unsupported.disposition == .unsupported)
}

@Test func operationalEvidenceFailsClosed() throws {
    #expect(throws: ParseOperationalContractError.undeclaredCounter(.workItems)) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: .init(),
            disposition: .unsupported,
            measurements: [.init(.workItems, 1)]
        )
    }
    #expect(throws: ParseOperationalContractError.dispositionRequiresReachedLimit) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: .init(limitableCounters: [.workItems]),
            disposition: .limited,
            limits: [.init(.workItems, 1)]
        )
    }

    let result = ParseContractSnapshot(
        engine: operationalEngine, status: .accepted,
        replay: [.init(step: 0, kind: .accept)]
    )
    #expect(throws: ParseOperationalContractError.observableCounterMismatch(.replayEvents)) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: .init(features: [.replay], reportedCounters: [.replayEvents]),
            disposition: .completed,
            result: result,
            measurements: [.init(.replayEvents, 2)]
        )
    }
    #expect(throws: ParseOperationalContractError.measurementExceedsLimit(.workItems)) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: .init(
                reportedCounters: [.workItems], limitableCounters: [.workItems]
            ),
            disposition: .unsupported,
            limits: [.init(.workItems, 2)],
            measurements: [.init(.workItems, 3)]
        )
    }
    #expect(throws: ParseOperationalContractError.unsupportedFeature(.cancellation)) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: .init(),
            disposition: .cancelled
        )
    }
}

@Test func normalizationRejectsRuntimeProductionIdentityDrift() throws {
    let (normalization, _) = try normalizationAndResult()
    let span = ParseInputSpan(
        leftToken: 0, rightToken: 1, lowerUTF16Offset: 0, upperUTF16Offset: 1
    )
    let drifted = ParseContractSnapshot(
        engine: operationalEngine,
        status: .accepted,
        tree: .production(
            nonterminal: "S", productionID: .init(rawValue: "engine-local-row-7"),
            span: span, children: [.token(label: "a", span: span)]
        )
    )

    #expect(throws: ParseOperationalContractError.invalidResultEvidence) {
        try ParseOperationalSnapshot(
            engine: operationalEngine,
            capabilities: operationalCapabilities,
            disposition: .completed,
            result: drifted,
            normalization: normalization,
            measurements: [
                .init(.inputTokens, 1), .init(.workItems, 1),
                .init(.replayEvents, 0), .init(.diagnostics, 0),
            ]
        )
    }
}

@Test func operationalSchemaAndDecoderRejectFutureVersions() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let schemaData = try Data(
        contentsOf: root.appendingPathComponent("Schemas/ParserOperationalContract.schema.json")
    )
    let schema = try #require(JSONSerialization.jsonObject(with: schemaData) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let version = try #require(properties["schemaVersion"] as? [String: Any])
    #expect(version["const"] as? Int == ParseOperationalSnapshot.currentSchemaVersion)
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let feature = try #require(definitions["feature"] as? [String: Any])
    let counter = try #require(definitions["counter"] as? [String: Any])
    #expect(Set(feature["enum"] as? [String] ?? []) == Set(
        ParseOperationalFeature.allCases.map(\.rawValue)
    ))
    #expect(Set(counter["enum"] as? [String] ?? []) == Set(
        ParseOperationalCounter.allCases.map(\.rawValue)
    ))

    let operation = try ParseOperationalSnapshot(
        engine: operationalEngine,
        capabilities: .init(),
        disposition: .unsupported
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as? [String: Any]
    )
    object["schemaVersion"] = 2
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: ParseOperationalContractError.unsupportedSchema(2)) {
        try JSONDecoder().decode(ParseOperationalSnapshot.self, from: data)
    }
}
