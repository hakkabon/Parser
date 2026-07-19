//
//  AnalyzeSPPF.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation
import OSLog

// MARK: - Additional Debugging Methods

public extension SPPFGraph {
    
    func log() {
        print("SPPF Graph Debug")
        let allNodes = getAllNodes().sorted()
        
        for node in allNodes {
            print("\(node)")
            let children = getChildren(of: node)
            if children.isEmpty {
                print("  No children (leaf)")
            } else {
                for child in children.sorted() {
                    print("    -> \(child)")
                }
            }
        }
        
        // Analyze potential issues
        print("Potential Issues")
        
        // Check for nodes with excessive children
        for node in allNodes {
            let childCount = getChildren(of: node).count
            if childCount > 5 {
                print("⚠️  Node \(node) has \(childCount) children (potential explosion)")
            }
        }
        
        // Check for cycles (simplified)
        var visited: Set<SPPFNode<Label>> = []
        var inPath: Set<SPPFNode<Label>> = []
        
        func hasCycle(_ node: SPPFNode<Label>) -> Bool {
            if inPath.contains(node) {
                print("⚠️  Cycle detected at node: \(node)")
                return true
            }
            if visited.contains(node) {
                return false
            }
            
            visited.insert(node)
            inPath.insert(node)
            
            for child in getChildren(of: node) {
                if hasCycle(child) {
                    return true
                }
            }
            
            inPath.remove(node)
            return false
        }
        
        for rootNode in allNodes {
            if case .symbol = rootNode {
                _ = hasCycle(rootNode)
            }
        }
    }
}
