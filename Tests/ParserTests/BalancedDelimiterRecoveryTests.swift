import IncrementalParsing
@testable import Parser
import Testing

@Suite("Balanced delimiter recovery")
struct BalancedDelimiterRecoveryTests {
    @Test func retainsNestingAndRepairsMissingAndUnexpectedClosers() {
        let validator = BalancedDelimiterRecovery<String, Int>(pairs: [
            .init(open: "{", close: "}"),
            .init(open: "[", close: "]"),
        ])
        let result = validator.validate([
            .init(id: 1, kind: "{", range: .init(location: 0, length: 1)),
            .init(id: 2, kind: "[", range: .init(location: 1, length: 1)),
            .init(id: 3, kind: "}", range: .init(location: 2, length: 1)),
            .init(id: 4, kind: "]", range: .init(location: 3, length: 1)),
        ], endOffset: 4)

        #expect(result.diagnostics.count == 2)
        #expect(result.diagnostics[0].expected == ["]"])
        #expect(result.repairs.count == 2)
    }
}
