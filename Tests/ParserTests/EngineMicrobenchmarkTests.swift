import Foundation
import Testing
@testable import Parser

private let benchmarkEnvironment = ParserEngineMicrobenchmarkEnvironment(
    operatingSystem: "test-os", architecture: "test-arch",
    processorCount: 4, physicalMemoryBytes: 8_000_000_000
)

private func benchmarkSuite() -> ParserEngineMicrobenchmarkSuite {
    .init(
        owner: .init(repository: "Test-Parser", version: "0.1.0"),
        engineID: "test", id: "smoke", title: "Smoke suite",
        buildConfiguration: .release, warmupIterations: 1, measurementIterations: 3,
        cases: [
            .init(
                id: "recognize", title: "Recognize tokens", operation: .recognition,
                boundary: "Recognize one pre-tokenized input with a pre-built parser.",
                workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint(["S:a", "a"]),
                comparisonGroup: "single-terminal-recognition-v1", scale: 1
            )
        ]
    )
}

@Test("Engine microbenchmark reports preserve raw samples and correctness evidence")
func engineReportRoundTrip() throws {
    let evidence = ParserEngineMicrobenchmarkCodec.evidenceFingerprint(["accepted", "1"])
    let report = try ParserEngineMicrobenchmarkRunner.run(
        benchmarkSuite(), environment: benchmarkEnvironment
    ) { _ in
        .init(evidenceFingerprint: evidence, counters: ["accepted": 1])
    }
    #expect(report.results.first?.durationsNanoseconds.count == 3)
    #expect(report.results.first?.evidenceFingerprint == evidence)
    #expect(try ParserEngineMicrobenchmarkCodec.decodeReport(
        ParserEngineMicrobenchmarkCodec.encode(report)
    ) == report)

    let comparison = ParserEngineMicrobenchmarkRunner.compare(baseline: report, candidate: report)
    #expect(comparison.compatible)
    #expect(comparison.medianRatios["recognize"] == 1)
}

@Test("Correctness drift and incompatible environments never produce ratios")
func engineEvidenceAndCompatibilityFailClosed() throws {
    var invocation = 0
    #expect(throws: ParserEngineMicrobenchmarkError.self) {
        try ParserEngineMicrobenchmarkRunner.run(
            benchmarkSuite(), environment: benchmarkEnvironment
        ) { _ in
            invocation += 1
            return .init(
                evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    invocation == 1 ? "accepted" : "rejected"
                ]),
                counters: ["accepted": invocation == 1 ? 1 : 0]
            )
        }
    }

    let stable = try ParserEngineMicrobenchmarkRunner.run(
        benchmarkSuite(), environment: benchmarkEnvironment
    ) { _ in
        .init(
            evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint(["accepted"]),
            counters: ["accepted": 1]
        )
    }
    let otherEnvironment = ParserEngineMicrobenchmarkEnvironment(
        operatingSystem: "other-os", architecture: "test-arch",
        processorCount: 4, physicalMemoryBytes: 8_000_000_000
    )
    let candidate = try ParserEngineMicrobenchmarkRunner.run(
        benchmarkSuite(), environment: otherEnvironment
    ) { _ in
        .init(
            evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint(["accepted"]),
            counters: ["accepted": 1]
        )
    }
    let comparison = ParserEngineMicrobenchmarkRunner.compare(
        baseline: stable, candidate: candidate
    )
    #expect(!comparison.compatible)
    #expect(comparison.reason == "environment-mismatch")
    #expect(comparison.medianRatios.isEmpty)
}

@Test("Suite identity, ordering, and fingerprints are validated")
func engineSuiteValidation() throws {
    let encoded = try ParserEngineMicrobenchmarkCodec.encode(benchmarkSuite())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["measurementIterations"] = 2
    #expect(throws: ParserEngineMicrobenchmarkError.self) {
        try ParserEngineMicrobenchmarkCodec.decodeSuite(
            JSONSerialization.data(withJSONObject: object)
        )
    }

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let schemaData = try Data(contentsOf: root.appendingPathComponent(
        "Schemas/EngineMicrobenchmarkReport.schema.json"
    ))
    let schema = try #require(JSONSerialization.jsonObject(with: schemaData) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    #expect((properties["schemaVersion"] as? [String: Any])?["const"] as? Int
        == ParserEngineMicrobenchmarkReport.currentSchemaVersion)
    #expect((properties["kind"] as? [String: Any])?["const"] as? String
        == ParserEngineMicrobenchmarkReport.kindIdentifier)

    #expect(throws: ParserEngineMicrobenchmarkError.self) {
        try ParserEngineMicrobenchmarkCodec.decodeReport(
            Data(repeating: 0, count: ParserEngineMicrobenchmarkCodec.maximumEncodedBytes + 1)
        )
    }
}
