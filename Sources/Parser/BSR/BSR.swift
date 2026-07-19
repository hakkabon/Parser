//
//  BSR.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2024/08/15.
//  Copyright © 2020 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import OSLog

/// Binary Subtree Representation (BSR).
/// - Derivation representation using binary subtree sets, E. Scott et al.
///
public struct BSR<Label: Hashable & Codable>: Codable {
    public let label: Label
    public let leftExtent: Int
    public let pivot: Int
    public let rightExtent: Int

    public init(label: Label, leftExtent: Int, pivot: Int, rightExtent: Int) {
        self.label = label
        self.leftExtent = leftExtent
        self.pivot = pivot
        self.rightExtent = rightExtent
    }
}

extension BSR: CustomStringConvertible where Label: CustomStringConvertible {
    public var description: String {
        return "(\(label), \(leftExtent), \(pivot), \(rightExtent))"
    }
}

extension BSR: Comparable where Label: Comparable {
    public static func < (lhs: BSR, rhs: BSR) -> Bool {
        if lhs.label != rhs.label {
            return lhs.label < rhs.label
        }
        if lhs.leftExtent != rhs.leftExtent {
            return lhs.leftExtent < rhs.leftExtent
        }
        if lhs.pivot != rhs.pivot {
            return lhs.pivot < rhs.pivot
        }
        return lhs.rightExtent < rhs.rightExtent
    }
}

extension BSR: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(leftExtent)
        hasher.combine(pivot)
        hasher.combine(rightExtent)
    }
}

extension BSR: Equatable {
    public static func == (lhs: BSR, rhs: BSR) -> Bool {
        return lhs.label == rhs.label &&
               lhs.leftExtent == rhs.leftExtent &&
               lhs.pivot == rhs.pivot &&
               lhs.rightExtent == rhs.rightExtent
    }
}

extension Set {
    public func log() where Element: CustomStringConvertible {
        Logger.bsr.trace("Binary Subtree Representation \n")
        
        let sortedElements = self.sorted { "\($0)" < "\($1)" }
        for entry in sortedElements {
            Logger.bsr.trace("  \(entry.description)")
        }
    }
}
