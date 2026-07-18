//
//  SPPFLabel.swift
//  Parser
//

import Foundation
import Grammar

/// A protocol describing the requirements for a label attached to packed and
/// intermediate nodes in an SPPF graph. It allows algorithms (like CST enumeration)
/// to access the underlying production rule, its symbols, and the dot position.
public protocol SPPFLabel: Hashable, CustomStringConvertible {
    /// The goal (left-hand side) non-terminal of the production.
    var goal: NonTerminal { get }
    /// The symbols on the right-hand side of the production.
    var symbols: [Symbol] { get }
    /// The current dot position within the right-hand side symbols.
    var position: Int { get }
}
