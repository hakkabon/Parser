import Parser
import Testing

@Test func generalizedRecoveryReturnsMinimumCostDeterministically() {
    let search = GeneralizedRecoverySearch<String>()
    let result = search.recover(
        ["begin", "name", "end"],
        insertionCandidates: [";", "."],
        policy: .init(maximumEditCost: 2, maximumExploredStates: 100)
    ) { $0 == ["begin", "name", ";", "end", "."] }

    #expect(result.repairedInput == ["begin", "name", ";", "end", "."])
    #expect(result.edits == [.insert(";", at: 2), .insert(".", at: 4)])
    #expect(!result.reachedSearchLimit)
}

@Test func generalizedRecoveryPrefersDeletionForAnExtraToken() {
    let search = GeneralizedRecoverySearch<String>()
    let result = search.recover(
        ["begin", "noise", "end"], insertionCandidates: ["begin", "end"]
    ) { $0 == ["begin", "end"] }

    #expect(result.edits == [.delete("noise", at: 1)])
}

@Test func generalizedRecoveryStopsAtItsStateBudget() {
    let result = GeneralizedRecoverySearch<Int>().recover(
        [1, 2, 3],
        insertionCandidates: [4, 5, 6],
        policy: .init(maximumEditCost: 3, maximumExploredStates: 4)
    ) { _ in false }

    #expect(result.repairedInput == nil)
    #expect(result.exploredStates == 4)
    #expect(result.reachedSearchLimit)
}

@Test func generalizedRecoveryQualityReportsExactRepairFacts() {
    let result = GeneralizedRecoverySearch<String>().recover(
        ["begin", "name", "end"], insertionCandidates: [";", "."],
        policy: .init(maximumEditCost: 2, maximumExploredStates: 100)
    ) { $0 == ["begin", "name", ";", "end", "."] }

    #expect(result.quality.editCost == 2)
    #expect(result.quality.insertionCount == 2)
    #expect(result.quality.deletionCount == 0)
    #expect(result.quality.exploredStates == result.exploredStates)
    #expect(result.quality.resumedStates == 0)
}

@Test func generalizedRecoverySessionContinuesAfterBudgetExhaustion() {
    let session = GeneralizedRecoverySearchSession<String>()
    var recognitions = 0
    let recognize: ([String]) -> Bool = {
        recognitions += 1
        return $0 == ["a", "b", "c"]
    }
    let first = session.recover(
        ["a"], insertionCandidates: ["b", "c"],
        policy: .init(maximumEditCost: 2, maximumExploredStates: 2),
        recognizes: recognize)
    #expect(first.reachedSearchLimit)
    #expect(recognitions == 2)

    let second = session.recover(
        ["a"], insertionCandidates: ["b", "c"],
        policy: .init(maximumEditCost: 2, maximumExploredStates: 100),
        recognizes: recognize)
    #expect(second.repairedInput == ["a", "b", "c"])
    #expect(second.quality.resumedStates == 2)
    #expect(recognitions == second.exploredStates)

    let recognitionCount = recognitions
    let repeated = session.recover(
        ["a"], insertionCandidates: ["b", "c"],
        policy: .init(maximumEditCost: 2, maximumExploredStates: 100),
        recognizes: recognize)
    #expect(repeated.repairedInput == second.repairedInput)
    #expect(recognitions == recognitionCount)
}

@Test func generalizedRecoverySessionRestartsForChangedInput() {
    let session = GeneralizedRecoverySearchSession<String>()
    _ = session.recover(
        ["a"], insertionCandidates: ["b"],
        policy: .init(maximumEditCost: 1, maximumExploredStates: 1)) { _ in false }
    let changed = session.recover(
        ["x"], insertionCandidates: ["y"],
        policy: .init(maximumEditCost: 1, maximumExploredStates: 4)) {
            $0 == ["x", "y"]
        }
    #expect(changed.repairedInput == ["x", "y"])
    #expect(changed.quality.resumedStates == 0)
}
