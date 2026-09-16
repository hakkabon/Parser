import Foundation
import Grammar

public enum ParseExecutableLaw: String, CaseIterable, Codable, Sendable {
    case treeStructure
    case forestStructure
    case replayStructure
    case metamorphicObservation
}

public struct ParseLawViolation: Hashable, Codable, Sendable {
    public let law: ParseExecutableLaw
    public let path: String
    public let message: String

    public init(law: ParseExecutableLaw, path: String, message: String) {
        self.law = law
        self.path = path
        self.message = message
    }
}

public struct ParseLawReport: Hashable, Codable, Sendable {
    public let engine: ParseEngineDescriptor
    public let tokenCount: Int
    public let violations: [ParseLawViolation]
    public var passed: Bool { violations.isEmpty }

    public init(
        engine: ParseEngineDescriptor,
        tokenCount: Int,
        violations: [ParseLawViolation]
    ) {
        self.engine = engine
        self.tokenCount = tokenCount
        self.violations = violations
    }
}

public struct ParseMetamorphicEvaluation: Hashable, Codable, Sendable {
    public let witnessID: String
    public let law: GrammarExecutableLaw
    public let baseline: ParseLawReport
    public let candidate: ParseLawReport
    public let observationsEquivalent: Bool
    public let violations: [ParseLawViolation]
    public var passed: Bool {
        baseline.passed && candidate.passed && observationsEquivalent && violations.isEmpty
    }
}

public enum ParseLawError: Error, Equatable, Sendable, LocalizedError {
    case invalidTokenCount(Int)
    case invalidGrammarWitness
    case unsupportedDiscrepancySchema(Int)
    case unsupportedDiscrepancyKind(String)
    case invalidDiscrepancyFingerprint
    case passingEvaluation

    public var errorDescription: String? {
        switch self {
        case .invalidTokenCount(let count): "Token count \(count) must not be negative."
        case .invalidGrammarWitness: "The grammar metamorphic witness is invalid."
        case .unsupportedDiscrepancySchema(let version):
            "Parse discrepancy schema \(version) is not supported."
        case .unsupportedDiscrepancyKind(let kind):
            "Parse discrepancy kind ‘\(kind)’ is not supported."
        case .invalidDiscrepancyFingerprint: "Parse discrepancy fingerprint is invalid."
        case .passingEvaluation: "A passing law evaluation cannot become a discrepancy."
        }
    }
}

public enum ParseLawVerifier {
    public static func validate(
        _ snapshot: ParseContractSnapshot,
        grammar: GrammarNormalizedModel,
        tokenCount: Int
    ) throws -> ParseLawReport {
        guard tokenCount >= 0 else { throw ParseLawError.invalidTokenCount(tokenCount) }
        let productions = Dictionary(uniqueKeysWithValues: grammar.productions.map { ($0.id, $0) })
        var violations: [ParseLawViolation] = []
        if let tree = snapshot.tree {
            validateTree(
                tree, path: "tree", parent: nil, tokenCount: tokenCount,
                productions: productions, violations: &violations
            )
        }
        if let forest = snapshot.forest {
            validateForest(
                forest, tokenCount: tokenCount, productions: productions,
                violations: &violations
            )
        }
        validateReplay(
            snapshot, tokenCount: tokenCount, productions: productions,
            violations: &violations
        )
        return .init(engine: snapshot.engine, tokenCount: tokenCount, violations: violations)
    }

    public static func evaluate(
        witness: GrammarLawWitness,
        input: String,
        tokenCount: Int,
        baseline: ParseContractSnapshot,
        candidate: ParseContractSnapshot
    ) throws -> ParseMetamorphicEvaluation {
        guard GrammarLawVerifier.evaluate(witness).passed else {
            throw ParseLawError.invalidGrammarWitness
        }
        let baselineReport = try validate(
            baseline, grammar: witness.baseline, tokenCount: tokenCount
        )
        let candidateReport = try validate(
            candidate, grammar: witness.candidate, tokenCount: tokenCount
        )
        let inverseRenames = Dictionary(
            uniqueKeysWithValues: witness.renames.map { ($0.to, $0.from) }
        )
        let baselineObservation = observation(baseline, inverseRenames: [:])
        let candidateObservation = observation(candidate, inverseRenames: inverseRenames)
        let equivalent = baselineObservation == candidateObservation
        let differences: [ParseLawViolation] = equivalent ? [] : [
            .init(
                law: .metamorphicObservation,
                path: "observations",
                message: "Status, tree, forest, diagnostics, recovery, or replay changed under \(witness.law.rawValue)."
            )
        ]
        _ = input // Retained by discrepancy artifacts; parsing remains engine-owned.
        return .init(
            witnessID: witness.id, law: witness.law,
            baseline: baselineReport, candidate: candidateReport,
            observationsEquivalent: equivalent, violations: differences
        )
    }

    private static func validateTree(
        _ tree: ProductionParseTree,
        path: String,
        parent: ParseInputSpan?,
        tokenCount: Int,
        productions: [GrammarProductionID: GrammarNormalizedProduction],
        violations: inout [ParseLawViolation]
    ) {
        let span = tree.span
        if span.leftToken < 0 || span.rightToken < span.leftToken
            || span.rightToken > tokenCount
            || span.lowerUTF16Offset < 0 || span.upperUTF16Offset < span.lowerUTF16Offset {
            violations.append(.init(
                law: .treeStructure, path: "\(path).span", message: "Tree span is invalid."
            ))
        }
        if let parent,
           span.leftToken < parent.leftToken || span.rightToken > parent.rightToken
            || span.lowerUTF16Offset < parent.lowerUTF16Offset
            || span.upperUTF16Offset > parent.upperUTF16Offset {
            violations.append(.init(
                law: .treeStructure, path: "\(path).span",
                message: "Child span is outside its parent."
            ))
        }
        switch tree {
        case .token:
            break
        case .production(let nonterminal, let productionID, _, let children):
            guard let production = productions[productionID] else {
                violations.append(.init(
                    law: .treeStructure, path: "\(path).productionID",
                    message: "Production identity is not in the grammar."
                ))
                return
            }
            if production.lhs != nonterminal {
                violations.append(.init(
                    law: .treeStructure, path: "\(path).nonterminal",
                    message: "Tree nonterminal does not match the production left-hand side."
                ))
            }
            for (index, child) in children.enumerated() {
                validateTree(
                    child, path: "\(path).children[\(index)]", parent: span,
                    tokenCount: tokenCount, productions: productions, violations: &violations
                )
                if index > 0, children[index - 1].span.rightToken > child.span.leftToken {
                    violations.append(.init(
                        law: .treeStructure, path: "\(path).children",
                        message: "Sibling token extents overlap or move backwards."
                    ))
                }
            }
        }
    }

    private static func validateForest(
        _ forest: ParseForestSnapshot,
        tokenCount: Int,
        productions: [GrammarProductionID: GrammarNormalizedProduction],
        violations: inout [ParseLawViolation]
    ) {
        let ids = forest.nodes.map(\.id)
        let idSet = Set(ids)
        if idSet.count != ids.count {
            violations.append(.init(
                law: .forestStructure, path: "forest.nodes", message: "Node identities are duplicated."
            ))
        }
        for (index, node) in forest.nodes.enumerated() {
            let path = "forest.nodes[\(index)]"
            if node.leftExtent < 0 || node.rightExtent < node.leftExtent
                || node.rightExtent > tokenCount
                || !(node.pivot.map { $0 >= node.leftExtent && $0 <= node.rightExtent } ?? true) {
                violations.append(.init(
                    law: .forestStructure, path: path, message: "Forest extent or pivot is invalid."
                ))
            }
            if let productionID = node.productionID, productions[productionID] == nil {
                violations.append(.init(
                    law: .forestStructure, path: "\(path).productionID",
                    message: "Production identity is not in the grammar."
                ))
            }
            if (node.kind == .packed || node.kind == .intermediate), node.productionID == nil {
                violations.append(.init(
                    law: .forestStructure, path: "\(path).productionID",
                    message: "Packed and intermediate nodes require production identity."
                ))
            }
        }
        for (index, edge) in forest.edges.enumerated() {
            if !idSet.contains(edge.parent) || !idSet.contains(edge.child) {
                violations.append(.init(
                    law: .forestStructure, path: "forest.edges[\(index)]",
                    message: "Forest edge references an unknown node."
                ))
            }
        }
        for root in forest.roots where !idSet.contains(root) {
            violations.append(.init(
                law: .forestStructure, path: "forest.roots", message: "Forest root is unknown."
            ))
        }
        let nodesByID = Dictionary(
            forest.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for ambiguity in forest.ambiguityNodes {
            guard idSet.contains(ambiguity) else {
                violations.append(.init(
                    law: .forestStructure, path: "forest.ambiguityNodes",
                    message: "Ambiguity marker is unknown."
                ))
                continue
            }
            let packedChildren = forest.edges.filter { $0.parent == ambiguity }.compactMap {
                nodesByID[$0.child]
            }.count(where: { $0.kind == .packed })
            if packedChildren < 2 {
                violations.append(.init(
                    law: .forestStructure, path: "forest.ambiguityNodes",
                    message: "Ambiguity marker has fewer than two packed alternatives."
                ))
            }
        }
    }

    private static func validateReplay(
        _ snapshot: ParseContractSnapshot,
        tokenCount: Int,
        productions: [GrammarProductionID: GrammarNormalizedProduction],
        violations: inout [ParseLawViolation]
    ) {
        guard !snapshot.replay.isEmpty else { return }
        if snapshot.replay.map(\.step) != Array(snapshot.replay.indices) {
            violations.append(.init(
                law: .replayStructure, path: "replay.step",
                message: "Replay steps are not contiguous from zero."
            ))
        }
        if snapshot.replay.first?.kind != .start {
            violations.append(.init(
                law: .replayStructure, path: "replay[0]", message: "Replay does not start with start."
            ))
        }
        let expectedTerminal: ParseReplayEventKind = snapshot.status == .rejected ? .reject : .accept
        if snapshot.replay.last?.kind != expectedTerminal {
            violations.append(.init(
                law: .replayStructure, path: "replay.last",
                message: "Replay terminal event disagrees with parse status."
            ))
        }
        let forestIDs = Set(snapshot.forest?.nodes.map(\.id) ?? [])
        for (index, event) in snapshot.replay.enumerated() {
            if let token = event.tokenIndex, token < 0 || token > tokenCount {
                violations.append(.init(
                    law: .replayStructure, path: "replay[\(index)].tokenIndex",
                    message: "Replay token index is outside the input."
                ))
            }
            if let productionID = event.productionID, productions[productionID] == nil {
                violations.append(.init(
                    law: .replayStructure, path: "replay[\(index)].productionID",
                    message: "Replay production identity is not in the grammar."
                ))
            }
            if let forestNode = event.forestNodeID, !forestIDs.contains(forestNode) {
                violations.append(.init(
                    law: .replayStructure, path: "replay[\(index)].forestNodeID",
                    message: "Replay forest reference is unknown."
                ))
            }
        }
    }

    private struct Observation: Hashable {
        let status: ParseStatus
        let tree: String?
        let forestNodes: [String]
        let forestEdges: [String]
        let roots: [String]
        let ambiguities: [String]
        let diagnostics: [String]
        let recovery: [ParseRecoveryEdit]
        let replay: [String]
    }

    private static func observation(
        _ snapshot: ParseContractSnapshot,
        inverseRenames: [String: String]
    ) -> Observation {
        let nodeSignatures = Dictionary(
            (snapshot.forest?.nodes ?? []).map {
                ($0.id, forestNodeSignature($0, inverseRenames: inverseRenames))
            },
            uniquingKeysWith: { first, _ in first }
        )
        return .init(
            status: snapshot.status,
            tree: snapshot.tree.map { treeSignature($0, inverseRenames: inverseRenames) },
            forestNodes: nodeSignatures.values.sorted(),
            forestEdges: (snapshot.forest?.edges ?? []).map {
                "\(nodeSignatures[$0.parent] ?? "?")->\(nodeSignatures[$0.child] ?? "?")"
            }.sorted(),
            roots: (snapshot.forest?.roots ?? []).map { nodeSignatures[$0] ?? "?" }.sorted(),
            ambiguities: (snapshot.forest?.ambiguityNodes ?? []).map {
                nodeSignatures[$0] ?? "?"
            }.sorted(),
            diagnostics: snapshot.diagnostics.map { diagnostic in
                let context = diagnostic.context.map { inverseRenames[$0] ?? $0 }.joined(separator: ",")
                return "\(diagnostic.severity)|\(diagnostic.reason)|\(context)|\(String(describing: diagnostic.expected))|\(String(describing: diagnostic.found))|\(diagnostic.productionID?.rawValue ?? "")|\(diagnostic.tokenIndex.map(String.init) ?? "")|\(String(describing: diagnostic.range))"
            },
            recovery: snapshot.recoveryEdits,
            replay: snapshot.replay.map {
                "\($0.step)|\($0.kind)|\($0.tokenIndex.map(String.init) ?? "")|\($0.productionID?.rawValue ?? "")|\($0.diagnosticReason.map(String.init(describing:)) ?? "")"
            }
        )
    }

    private static func treeSignature(
        _ tree: ProductionParseTree, inverseRenames: [String: String]
    ) -> String {
        switch tree {
        case .token(let label, let span):
            return "t|\(label)|\(span.leftToken):\(span.rightToken)|\(span.lowerUTF16Offset):\(span.upperUTF16Offset)"
        case .production(let nonterminal, let productionID, let span, let children):
            let name = inverseRenames[nonterminal] ?? nonterminal
            return "p|\(name)|\(productionID.rawValue)|\(span.leftToken):\(span.rightToken)|[\(children.map { treeSignature($0, inverseRenames: inverseRenames) }.joined(separator: ","))]"
        }
    }

    private static func forestNodeSignature(
        _ node: ParseForestNode, inverseRenames: [String: String]
    ) -> String {
        let label = node.label.map { inverseRenames[$0] ?? $0 } ?? ""
        return "\(node.kind)|\(label)|\(node.productionID?.rawValue ?? "")|\(node.position.map(String.init) ?? "")|\(node.leftExtent):\(node.rightExtent)|\(node.pivot.map(String.init) ?? "")"
    }
}

/// A portable, minimized-or-full witness of a failed executable parser law.
public struct ParseLawDiscrepancy: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "parser-law-discrepancy"

    public let schemaVersion: Int
    public let kind: String
    public let witness: GrammarLawWitness
    public let input: String
    public let tokenCount: Int
    public let baseline: ParseContractSnapshot
    public let candidate: ParseContractSnapshot
    public let evaluation: ParseMetamorphicEvaluation
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    public static func makeIfFailed(
        witness: GrammarLawWitness,
        input: String,
        tokenCount: Int,
        baseline: ParseContractSnapshot,
        candidate: ParseContractSnapshot
    ) throws -> Self? {
        let evaluation = try ParseLawVerifier.evaluate(
            witness: witness, input: input, tokenCount: tokenCount,
            baseline: baseline, candidate: candidate
        )
        guard !evaluation.passed else { return nil }
        return try Self(
            witness: witness, input: input, tokenCount: tokenCount,
            baseline: baseline, candidate: candidate, evaluation: evaluation
        )
    }

    private init(
        witness: GrammarLawWitness,
        input: String,
        tokenCount: Int,
        baseline: ParseContractSnapshot,
        candidate: ParseContractSnapshot,
        evaluation: ParseMetamorphicEvaluation
    ) throws {
        guard !evaluation.passed else { throw ParseLawError.passingEvaluation }
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.witness = witness
        self.input = input
        self.tokenCount = tokenCount
        self.baseline = baseline
        self.candidate = candidate
        self.evaluation = evaluation
        fingerprintAlgorithm = "fnv1a64"
        fingerprint = try Self.makeFingerprint(
            witness: witness, input: input, tokenCount: tokenCount,
            baseline: baseline, candidate: candidate, evaluation: evaluation
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, witness, input, tokenCount, baseline, candidate,
             evaluation, fingerprintAlgorithm, fingerprint
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        let kind = try values.decode(String.self, forKey: .kind)
        guard version == Self.currentSchemaVersion else {
            throw ParseLawError.unsupportedDiscrepancySchema(version)
        }
        guard kind == Self.kindIdentifier else {
            throw ParseLawError.unsupportedDiscrepancyKind(kind)
        }
        let witness = try values.decode(GrammarLawWitness.self, forKey: .witness)
        let input = try values.decode(String.self, forKey: .input)
        let tokenCount = try values.decode(Int.self, forKey: .tokenCount)
        let baseline = try values.decode(ParseContractSnapshot.self, forKey: .baseline)
        let candidate = try values.decode(ParseContractSnapshot.self, forKey: .candidate)
        let evaluation = try values.decode(ParseMetamorphicEvaluation.self, forKey: .evaluation)
        try self.init(
            witness: witness, input: input, tokenCount: tokenCount,
            baseline: baseline, candidate: candidate, evaluation: evaluation
        )
        guard try values.decode(String.self, forKey: .fingerprintAlgorithm) == fingerprintAlgorithm,
              try values.decode(String.self, forKey: .fingerprint) == fingerprint else {
            throw ParseLawError.invalidDiscrepancyFingerprint
        }
    }

    private struct FingerprintPayload: Codable {
        let witness: GrammarLawWitness
        let input: String
        let tokenCount: Int
        let baseline: ParseContractSnapshot
        let candidate: ParseContractSnapshot
        let evaluation: ParseMetamorphicEvaluation
    }

    private static func makeFingerprint(
        witness: GrammarLawWitness,
        input: String,
        tokenCount: Int,
        baseline: ParseContractSnapshot,
        candidate: ParseContractSnapshot,
        evaluation: ParseMetamorphicEvaluation
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(FingerprintPayload(
            witness: witness, input: input, tokenCount: tokenCount,
            baseline: baseline, candidate: candidate, evaluation: evaluation
        ))
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }
}
