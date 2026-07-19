//
//  Logger+Parser.swift
//  Parser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import OSLog

extension Logger {
    /// Logger for BSR-related operations
    public static let bsr = Logger(subsystem: "com.hakkabon.Parser", category: "BSR")
    
    /// Logger for SPPF-related operations
    public static let sppf = Logger(subsystem: "com.hakkabon.Parser", category: "SPPF")
}
