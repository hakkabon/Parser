import Foundation
import OSLog

extension Logger {
    /// Logger for BSR-related operations
    public static let bsr = Logger(subsystem: "com.hakkabon.Parser", category: "BSR")
    
    /// Logger for SPPF-related operations
    public static let sppf = Logger(subsystem: "com.hakkabon.Parser", category: "SPPF")
}
