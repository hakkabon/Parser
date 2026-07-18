//
//  GeneralizedParser.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation

/// The outcome of a parse attempt.
public struct ParseResult<Label: Hashable & Codable & CustomStringConvertible> {
    public let isSuccessful: Bool
    public let bsr: Set<BSR<Label>>
    public let sppfGraph: SPPFGraph<Label>?

    public init(isSuccessful: Bool, bsr: Set<BSR<Label>>, sppfGraph: SPPFGraph<Label>?) {
        self.isSuccessful = isSuccessful
        self.bsr = bsr
        self.sppfGraph = sppfGraph
    }

    /// Returns `true` if any non-terminal or intermediate SPPF node has more than one
    /// packed-node child, indicating that the grammar is locally ambiguous on this input.
    ///
    /// A packed node having two children is a normal binary split, not an ambiguity.
    /// Only `.symbol` and `.intermediate` nodes with multiple children signal ambiguity.
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else { return false }
        return graph.getAllNodes().contains { node in
            switch node {
            case .symbol, .intermediate:
                return graph.getChildren(of: node).count > 1
            default:
                return false
            }
        }
    }
}

/// A parser that recognises general (including ambiguous) context-free grammars and can
/// produce every derivation of an input string as a structured parse forest.
public protocol GeneralizedParser {
    associatedtype Label: Hashable & Codable & CustomStringConvertible

    /// Run the recogniser/parser on `string` and return the raw `ParseResult`.
    ///
    /// The result exposes the BSR set and the SPPF graph from which individual syntax
    /// trees can be extracted.  Use `allSyntaxTrees(for:)` if you want ready-made trees.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: A `ParseResult` describing success, the BSR set, and the SPPF graph.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func parse(_ string: String) throws -> ParseResult<Label>

    /// Returns **all** parse trees for `string`.
    ///
    /// For unambiguous grammars this returns exactly one tree.  For ambiguous grammars it
    /// returns one tree per distinct derivation.  Duplicates are removed before returning.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: All syntax trees explaining how `string` was derived from the grammar.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
