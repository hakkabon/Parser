import Grammar

/// Resource limits for engine-independent recovery of generalized parses.
///
/// The search is deliberately bounded: recovery must remain responsive even
/// for ambiguous grammars or an insertion vocabulary with many terminals.
public struct GeneralizedRecoveryPolicy: Hashable, Codable, Sendable {
    public var maximumEditCost: Int
    public var maximumExploredStates: Int

    public init(maximumEditCost: Int = 2, maximumExploredStates: Int = 512) {
        self.maximumEditCost = max(0, maximumEditCost)
        self.maximumExploredStates = max(1, maximumExploredStates)
    }
}

/// One edit in a repaired token sequence. Positions refer to the sequence as
/// it exists immediately before that edit is applied, which makes an edit
/// script directly replayable in order.
public enum GeneralizedRepairEdit<Element: Hashable>: Hashable {
    case insert(Element, at: Int)
    case delete(Element, at: Int)
}

/// Evidence produced by a bounded generalized-recovery search.
public struct GeneralizedRepairSearchResult<Element: Hashable> {
    public let repairedInput: [Element]?
    public let edits: [GeneralizedRepairEdit<Element>]
    public let exploredStates: Int
    public let reachedSearchLimit: Bool

    public var recovered: Bool { repairedInput != nil && !edits.isEmpty }

    public init(
        repairedInput: [Element]?,
        edits: [GeneralizedRepairEdit<Element>],
        exploredStates: Int,
        reachedSearchLimit: Bool
    ) {
        self.repairedInput = repairedInput
        self.edits = edits
        self.exploredStates = exploredStates
        self.reachedSearchLimit = reachedSearchLimit
    }
}

/// A deterministic, breadth-first repair search shared by generalized parser
/// engines. The caller supplies its recognizer and an ordered insertion
/// vocabulary; the first accepted minimum-cost repair is returned.
public struct GeneralizedRecoverySearch<Element: Hashable> {
    private struct State {
        let input: [Element]
        let edits: [GeneralizedRepairEdit<Element>]
    }

    public init() {}

    public func recover(
        _ input: [Element],
        insertionCandidates: [Element],
        policy: GeneralizedRecoveryPolicy = .init(),
        recognizes: ([Element]) throws -> Bool
    ) rethrows -> GeneralizedRepairSearchResult<Element> {
        var explored = 1
        if try recognizes(input) {
            return .init(
                repairedInput: input, edits: [], exploredStates: explored,
                reachedSearchLimit: false
            )
        }
        guard policy.maximumEditCost > 0,
              explored < policy.maximumExploredStates else {
            return .init(
                repairedInput: nil, edits: [], exploredStates: explored,
                reachedSearchLimit: true
            )
        }

        var uniqueCandidates: [Element] = []
        var candidateSet = Set<Element>()
        for candidate in insertionCandidates where candidateSet.insert(candidate).inserted {
            uniqueCandidates.append(candidate)
        }

        var visited: Set<[Element]> = [input]
        var frontier = [State(input: input, edits: [])]

        for _ in 1...policy.maximumEditCost {
            var next: [State] = []
            for state in frontier {
                // Deletions precede insertions to keep the result stable and
                // to avoid multiplying candidates for a plainly extra token.
                for position in state.input.indices {
                    var repaired = state.input
                    let removed = repaired.remove(at: position)
                    guard visited.insert(repaired).inserted else { continue }
                    explored += 1
                    let edits = state.edits + [.delete(removed, at: position)]
                    if try recognizes(repaired) {
                        return .init(
                            repairedInput: repaired, edits: edits,
                            exploredStates: explored, reachedSearchLimit: false
                        )
                    }
                    if explored >= policy.maximumExploredStates {
                        return .init(
                            repairedInput: nil, edits: [], exploredStates: explored,
                            reachedSearchLimit: true
                        )
                    }
                    next.append(.init(input: repaired, edits: edits))
                }

                for position in 0...state.input.count {
                    for candidate in uniqueCandidates {
                        var repaired = state.input
                        repaired.insert(candidate, at: position)
                        guard visited.insert(repaired).inserted else { continue }
                        explored += 1
                        let edits = state.edits + [.insert(candidate, at: position)]
                        if try recognizes(repaired) {
                            return .init(
                                repairedInput: repaired, edits: edits,
                                exploredStates: explored, reachedSearchLimit: false
                            )
                        }
                        if explored >= policy.maximumExploredStates {
                            return .init(
                                repairedInput: nil, edits: [], exploredStates: explored,
                                reachedSearchLimit: true
                            )
                        }
                        next.append(.init(input: repaired, edits: edits))
                    }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }

        return .init(
            repairedInput: nil, edits: [], exploredStates: explored,
            reachedSearchLimit: false
        )
    }
}

public extension GeneralizedRepairEdit where Element == Terminal {
    /// The existing portable parser edit used by diagnostics, incremental
    /// replay and front-end adapters.
    var parserRecoveryEdit: RecoveryEdit {
        switch self {
        case .insert(let terminal, let position):
            return .insert(terminal: terminal, atToken: position)
        case .delete(let terminal, let position):
            return .delete(terminal: terminal, atToken: position)
        }
    }
}
