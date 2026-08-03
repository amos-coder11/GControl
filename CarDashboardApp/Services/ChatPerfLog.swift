import Foundation

/// Logging de rendimiento de chat (solo DEBUG; sin datos sensibles).
enum ChatPerfLog {
    static func inbox(_ message: String) {
        #if DEBUG
        print("[ChatSync][inbox] \(message)")
        #endif
    }

    static func conversation(_ message: String) {
        #if DEBUG
        print("[ChatSync][conversation] \(message)")
        #endif
    }

    static func realtime(_ message: String) {
        #if DEBUG
        print("[ChatSync][realtime] \(message)")
        #endif
    }

    static func avatar(_ message: String) {
        #if DEBUG
        print("[ChatSync][avatar] \(message)")
        #endif
    }

    static func enrichment(_ message: String) {
        #if DEBUG
        print("[ChatSync][enrich] \(message)")
        #endif
    }
}
