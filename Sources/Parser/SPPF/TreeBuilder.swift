//
//  TreeBuilder.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/26.
//  Copyright © 2026 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

public extension SPPFGraph where Label: SPPFLabel {

    /// Builds a single parse tree for the given start symbol and token ranges.
    func buildParseTree(startSymbol: String, ranges: [Range<String.Index>], string: String) -> ParseTree {
        return buildAllParseTrees(startSymbol: startSymbol, ranges: ranges, string: string).first ?? .empty
    }

    /// Builds all possible parse trees for the given start symbol and token ranges.
    func buildAllParseTrees(startSymbol: String, ranges: [Range<String.Index>], string: String) -> [ParseTree] {
        let n = ranges.count

        let rootNodes = self.getAllNodes().filter { node in
            if case let .symbol(label, leftExtent, rightExtent) = node {
                return label == startSymbol && leftExtent == 0 && rightExtent == n
            }
            return false
        }

        var allTrees: [ParseTree] = []
        for rootNode in rootNodes {
            // Fresh memo table per root: avoids cross-root contamination while still
            // sharing memoised sub-results within a single root's sub-forest.
            var memo: [SPPFNode<Label>: [[ParseTree]]?] = [:]
            let alts = self.extractNodeAlternatives(
                node: rootNode,
                ranges: ranges, string: string, memo: &memo)
            for alt in alts {
                if let first = alt.first {
                    allTrees.append(first)
                }
            }
        }
        return deduplicateParseTrees(allTrees)
    }
}
