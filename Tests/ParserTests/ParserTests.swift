import Testing
@testable import Parser

@Test func parseDiagnosticComputesOneBasedLocation() {
    let source = "first\nsecond"
    let start = source.index(after: source.firstIndex(of: "\n")!)
    let diagnostic = ParseDiagnostic(
        reason: .unexpectedToken,
        message: "Unexpected token.",
        range: start..<source.index(after: start),
        source: source
    )

    #expect(diagnostic.line == 2)
    #expect(diagnostic.column == 1)
    #expect(diagnostic.description == "[2:1] Error: Unexpected token.")
}

@Test func diagnosticReporterRendersSourceContext() {
    let source = "abc"
    let diagnostic = ParseDiagnostic(
        reason: .unexpectedToken,
        message: "Unexpected token.",
        range: source.startIndex..<source.index(after: source.startIndex),
        source: source
    )

    let report = DiagnosticReporter().string(for: [diagnostic])
    #expect(report.contains("Found 1 error:"))
    #expect(report.contains("1 | abc"))
    #expect(report.contains("^"))
}

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
