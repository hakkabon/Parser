import Foundation
import TerminalColors

/// Renders parser-independent diagnostics with source location context.
public struct DiagnosticReporter {
    private let errorTitle = TerminalColor(fg: .red, .bold, .reversed)
    private let messageStyle = TerminalColor(.bold)
    private let metaColor = TerminalColor(fg: .blue)
    private let squiggleColor = TerminalColor(fg: .red)

    public init() {}

    public func report(diagnostics: [ParseDiagnostic]) {
        guard !diagnostics.isEmpty else { return }
        print(string(for: diagnostics))
    }

    public func string(for diagnostics: [ParseDiagnostic]) -> String {
        guard !diagnostics.isEmpty else { return "" }
        let count = diagnostics.count
        let noun: String
        if diagnostics.allSatisfy({ $0.severity == .error }) {
            noun = count == 1 ? "error" : "errors"
        } else if diagnostics.allSatisfy({ $0.severity == .warning }) {
            noun = count == 1 ? "warning" : "warnings"
        } else {
            noun = count == 1 ? "diagnostic" : "diagnostics"
        }
        let title = "Found \(count) \(noun):"
        let header = "\n\(title, color: errorTitle)\n"
        let blocks = diagnostics.enumerated()
            .map { block(for: $0.element, index: $0.offset + 1) }
            .joined(separator: "\n\n")
        return header + "\n" + blocks
    }

    public func block(for diagnostic: ParseDiagnostic, index: Int) -> String {
        let sourceLines = diagnostic.source.components(separatedBy: .newlines)
        let lineIndex = diagnostic.line - 1
        guard sourceLines.indices.contains(lineIndex) else {
            return "[\(index)] \(diagnostic)"
        }

        let tokenLength: Int = {
            guard let range = diagnostic.range else { return 1 }
            return max(1, diagnostic.source.distance(from: range.lowerBound, to: range.upperBound))
        }()
        let padding = String(repeating: " ", count: max(0, diagnostic.column - 1))
        let underline = "\(padding)\(String(repeating: "^", count: tokenLength), color: squiggleColor)"
        let gutter = "\(String(format: "%3d |", diagnostic.line), color: metaColor)"
        let emptyGutter = "\("    |", color: metaColor)"
        let arrow = "\("-->", color: metaColor)"

        return """
        \("[\(index)] \(diagnostic.message)", color: messageStyle)
           \(arrow) Line \(diagnostic.line):\(diagnostic.column)
           \(emptyGutter)
           \(gutter) \(sourceLines[lineIndex])
           \(emptyGutter) \(underline)
        """
    }
}
