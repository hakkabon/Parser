//
//  ExtractSPPF.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2025/08/23.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import Foundation

public class SPPFGraph<Label: Hashable & Codable & CustomStringConvertible> {
    private var graph: [SPPFNode<Label>: Set<SPPFNode<Label>>] = [:]
    
    public init() {}
    
    /// Add a node to the graph.
    /// - parameter node: The node to be added.
    public func add(_ node: SPPFNode<Label>) {
        guard graph.index(forKey: node) == nil else { return }
        graph[node] = []
    }
    
    public func addEdge(from parent: SPPFNode<Label>, to child: SPPFNode<Label>) {
        graph[parent, default: []].insert(child)
        add(child)
    }
    
    public func getChildren(of node: SPPFNode<Label>) -> Set<SPPFNode<Label>> {
        return graph[node] ?? Set()
    }
    
    public func getAllNodes() -> [SPPFNode<Label>] {
        return Array(graph.keys)
    }

    // Get nodes that can be expanded (non-terminals and intermediates not yet processed)
    public func getExtendableNodes() -> [SPPFNode<Label>] {
        graph.keys.filter { node in
            switch node {
            case .leaf(_,_,_):
                return false
            case .symbol(_,_,_):
                return getChildren(of: node).isEmpty
            case .intermediate(_,_,_):
                return getChildren(of: node).isEmpty
            case .packed(_,_,_,_):
                return false
            }
        }
    }
    
    public func printGraph() {
        ParserDiagnostics.traceSPPF("SPPF Graph: \n")

        let nodes = graph.keys.sorted()
        for node in nodes {
            ParserDiagnostics.traceSPPF("  \(node.description)")
            let chidren = graph[node]!
            for child in chidren {
                ParserDiagnostics.traceSPPF("    -> \(child.description)")
            }
        }
    }
    
    public func cleanup() {
        var productive = Set<SPPFNode<Label>>()
        
        for node in graph.keys {
            if case .leaf = node {
                productive.insert(node)
            }
        }
        
        var changed = true
        while changed {
            changed = false
            for (node, children) in graph {
                if productive.contains(node) { continue }
                
                switch node {
                case .leaf:
                    break
                case .symbol, .intermediate:
                    let hasProductiveChild = children.contains { productive.contains($0) }
                    if hasProductiveChild {
                        productive.insert(node)
                        changed = true
                    }
                case .packed:
                    // A packed node is productive if every one of its children is productive.
                    // Note: epsilon packed nodes are given exactly one `.leaf` child by
                    // `expandSymbolNode` (see ExtractSPPF.swift), so `children` is never
                    // empty for a well-formed epsilon derivation. `allSatisfy` on a non-empty
                    // set is the ordinary case; it is only vacuously true on an empty set,
                    // which would indicate an orphaned packed node — those are pruned away.
                    let allChildrenProductive = children.allSatisfy { productive.contains($0) }
                    if allChildrenProductive {
                        productive.insert(node)
                        changed = true
                    }
                }
            }
        }
        
        var newGraph: [SPPFNode<Label>: Set<SPPFNode<Label>>] = [:]
        for (node, children) in graph {
            if productive.contains(node) {
                let productiveChildren = children.filter { productive.contains($0) }
                newGraph[node] = productiveChildren
            }
        }
        self.graph = newGraph
    }
}
