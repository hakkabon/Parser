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
