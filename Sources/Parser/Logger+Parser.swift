//
//  Logger+Parser.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
#if canImport(OSLog)
import OSLog
#endif

#if canImport(OSLog)
extension Logger {
    /// Logger for BSR-related operations
    public static let bsr = Logger(subsystem: "com.hakkabon.Parser", category: "BSR")
    
    /// Logger for SPPF-related operations
    public static let sppf = Logger(subsystem: "com.hakkabon.Parser", category: "SPPF")
}
#endif

enum ParserDiagnostics {
    #if canImport(OSLog)
    static func traceBSR(_ message: @autoclosure () -> String) {
        let text = message()
        Logger.bsr.trace("\(text)")
    }

    static func traceSPPF(_ message: @autoclosure () -> String) {
        let text = message()
        Logger.sppf.trace("\(text)")
    }
    #else
    static func traceBSR(_ message: @autoclosure () -> String) {}

    static func traceSPPF(_ message: @autoclosure () -> String) {}
    #endif
}
