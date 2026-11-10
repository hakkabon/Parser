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
    /// Exact search and repair measurements. This deliberately avoids a
    /// weighted "quality score" whose meaning would vary between languages.
    public let quality: GeneralizedRepairQuality

    public var recovered: Bool { repairedInput != nil && !edits.isEmpty }

    public init(
        repairedInput: [Element]?,
        edits: [GeneralizedRepairEdit<Element>],
        exploredStates: Int,
        reachedSearchLimit: Bool,
        resumedStates: Int = 0
    ) {
        self.repairedInput = repairedInput
        self.edits = edits
        self.exploredStates = exploredStates
        self.reachedSearchLimit = reachedSearchLimit
        self.quality = .init(
            editCost: edits.count,
            insertionCount: edits.reduce(0) {
                if case .insert = $1 { return $0 + 1 }; return $0
            },
            deletionCount: edits.reduce(0) {
                if case .delete = $1 { return $0 + 1 }; return $0
            },
            exploredStates: exploredStates,
            resumedStates: resumedStates,
            reachedSearchLimit: reachedSearchLimit)
    }
}

/// Comparable facts about one recovery attempt. Lower repair cost is better;
/// search work and resumption are reported separately from repair quality.
public struct GeneralizedRepairQuality: Hashable, Codable, Sendable {
    public let editCost: Int
    public let insertionCount: Int
    public let deletionCount: Int
    public let exploredStates: Int
    public let resumedStates: Int
    public let reachedSearchLimit: Bool

    public init(
        editCost: Int, insertionCount: Int, deletionCount: Int,
        exploredStates: Int, resumedStates: Int = 0,
        reachedSearchLimit: Bool
    ) {
        self.editCost = editCost
        self.insertionCount = insertionCount
        self.deletionCount = deletionCount
        self.exploredStates = exploredStates
        self.resumedStates = resumedStates
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

/// Stateful counterpart to ``GeneralizedRecoverySearch``. When a search hits
/// its state budget, another call for the same input, candidates, and edit-cost
/// bound continues the retained breadth-first queue. Raising only the state
/// budget therefore performs new work instead of replaying old recognizer
/// calls. A changed request starts a fresh checkpoint.
public final class GeneralizedRecoverySearchSession<Element: Hashable> {
    private struct State {
        let input: [Element]
        let edits: [GeneralizedRepairEdit<Element>]
    }

    private struct Request: Equatable {
        let input: [Element]
        let candidates: [Element]
        let maximumEditCost: Int
    }

    private var request: Request?
    private var queue: [State] = []
    private var cursor = 0
    private var visited: Set<[Element]> = []
    private var explored = 0
    private var completed: State?
    private var exhausted = false

    public init() {}

    public func reset() {
        request = nil; queue = []; cursor = 0; visited = []
        explored = 0; completed = nil; exhausted = false
    }

    public func recover(
        _ input: [Element],
        insertionCandidates: [Element],
        policy: GeneralizedRecoveryPolicy = .init(),
        recognizes: ([Element]) throws -> Bool
    ) rethrows -> GeneralizedRepairSearchResult<Element> {
        var candidates: [Element] = []
        var candidateSet = Set<Element>()
        for candidate in insertionCandidates where candidateSet.insert(candidate).inserted {
            candidates.append(candidate)
        }
        let nextRequest = Request(
            input: input, candidates: candidates,
            maximumEditCost: policy.maximumEditCost)
        let isResume = request == nextRequest
        let resumedAt = isResume ? explored : 0
        if !isResume {
            request = nextRequest
            queue = [State(input: input, edits: [])]
            cursor = 0
            visited = [input]
            explored = 0
            completed = nil
            exhausted = false
        } else if let completed {
            return .init(repairedInput: completed.input, edits: completed.edits,
                         exploredStates: explored, reachedSearchLimit: false,
                         resumedStates: resumedAt)
        } else if exhausted {
            return .init(repairedInput: nil, edits: [],
                         exploredStates: explored, reachedSearchLimit: false,
                         resumedStates: resumedAt)
        }

        while cursor < queue.count {
            if explored >= policy.maximumExploredStates {
                return .init(repairedInput: nil, edits: [],
                             exploredStates: explored, reachedSearchLimit: true,
                             resumedStates: resumedAt)
            }
            let state = queue[cursor]
            cursor += 1
            explored += 1
            if try recognizes(state.input) {
                completed = state
                return .init(repairedInput: state.input, edits: state.edits,
                             exploredStates: explored, reachedSearchLimit: false,
                             resumedStates: resumedAt)
            }
            guard state.edits.count < policy.maximumEditCost else { continue }

            var successors: [State] = []
            for position in state.input.indices {
                var repaired = state.input
                let removed = repaired.remove(at: position)
                successors.append(State(
                    input: repaired,
                    edits: state.edits + [.delete(removed, at: position)]))
            }
            for position in 0...state.input.count {
                for candidate in candidates {
                    var repaired = state.input
                    repaired.insert(candidate, at: position)
                    successors.append(State(
                        input: repaired,
                        edits: state.edits + [.insert(candidate, at: position)]))
                }
            }

            for successor in successors where visited.insert(successor.input).inserted {
                queue.append(successor)
            }
        }

        exhausted = true
        return .init(repairedInput: nil, edits: [], exploredStates: explored,
                     reachedSearchLimit: false, resumedStates: resumedAt)
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
