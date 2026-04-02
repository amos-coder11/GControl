import Foundation
import os.log

/// Structured logging for VoiceApp. Never log API keys or ephemeral tokens.
enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "VoiceApp"

    private static let debugLog = OSLog(subsystem: subsystem, category: "debug")
    private static let infoLog = OSLog(subsystem: subsystem, category: "info")
    private static let errorLog = OSLog(subsystem: subsystem, category: "error")

    /// Debug-level diagnostic (disabled in release builds via compiler optimization where possible).
    static func debug(_ message: String, file: String = #fileID, line: Int = #line) {
        os_log("%{public}@:%d %{public}@", log: debugLog, type: .debug, file, line, message)
    }

    /// Informational lifecycle events (no secrets).
    static func info(_ message: String, file: String = #fileID, line: Int = #line) {
        os_log("%{public}@:%d %{public}@", log: infoLog, type: .info, file, line, message)
    }

    /// Errors and failures (no secrets).
    static func error(_ message: String, file: String = #fileID, line: Int = #line) {
        os_log("%{public}@:%d %{public}@", log: errorLog, type: .error, file, line, message)
    }
}
