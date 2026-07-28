import Foundation
import Grammar

/// A parser-independent description of a problem found while tokenizing,
/// parsing, or recovering an input document.
public struct ParseDiagnostic: Error, CustomStringConvertible {
    public enum Severity: String, Sendable, Equatable {
        case warning
        case error
    }

    public enum Reason: String, Sendable, Equatable {
        case missingToken
        case extraToken
        case noViableAlternative
        case invalidToken
        case prematureEndOfInput
        case emptyNotAllowed
        case unknownToken
        case unmatchedPattern
        case unexpectedToken
        case grammarConflict
        case internalError
    }

    public let severity: Severity
    public let reason: Reason
    public let message: String
    public let range: Range<String.Index>?
    public let source: String
    public let context: [NonTerminal]
    public let expected: [Terminal]
    public let found: Terminal?

    /// An algorithm-specific numeric state, such as an LR automaton state.
    public let parserState: Int?

    public let line: Int
    public let column: Int

    public init(
        severity: Severity = .error,
        reason: Reason,
        message: String,
        range: Range<String.Index>? = nil,
        context: [NonTerminal] = [],
        expected: [Terminal] = [],
        found: Terminal? = nil,
        parserState: Int? = nil,
        source: String
    ) {
        self.severity = severity
        self.reason = reason
        self.message = message
        self.range = range
        self.source = source
        self.context = context
        self.expected = expected.sorted { $0.description < $1.description }
        self.found = found
        self.parserState = parserState
        (line, column) = source.parseLineAndColumn(at: range?.lowerBound ?? source.endIndex)
    }

    public var description: String {
        let main = "[\(line):\(column)] \(severity == .error ? "Error" : "Warning"): \(message)"
        guard !context.isEmpty else { return main }
        return "\(main) (while parsing \(context.map(\.description).joined(separator: " > ")))"
    }
}

extension ParseDiagnostic.Reason: CustomStringConvertible {
    public var description: String { rawValue }
}

private extension String {
    func parseLineAndColumn(at index: String.Index) -> (line: Int, column: Int) {
        var line = 1
        var column = 1
        var cursor = startIndex
        while cursor < index && cursor < endIndex {
            if self[cursor].isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }
            cursor = self.index(after: cursor)
        }
        return (line, column)
    }
}
