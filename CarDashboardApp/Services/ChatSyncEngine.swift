import Foundation

enum ChatInboxSyncMode: Sendable {
    /// Lista esencial + enriquecimiento en background (prioridad baja).
    case full
    /// Solo lista esencial (polling de recuperación / foreground ligero).
    case recovery
}

/// Puerta única de sincronización del inbox CRM (single-flight + frescura).
actor ChatSyncEngine {
    static let shared = ChatSyncEngine()

    /// Intervalo mínimo del polling de recuperación (5 minutos).
    static let recoveryInterval: TimeInterval = 5 * 60

    private var inboxRunning = false
    private var skippedDuplicates = 0
    private var lastSyncAt: Date?

    var debugSkippedDuplicates: Int { skippedDuplicates }
    var debugLastSyncAt: Date? { lastSyncAt }

    /// `true` si este caller debe ejecutar el sync; `false` si ya hay uno en curso.
    func beginInboxSync() -> Bool {
        if inboxRunning {
            skippedDuplicates += 1
            ChatPerfLog.inbox("skip duplicate in-flight sync")
            return false
        }
        inboxRunning = true
        return true
    }

    func endInboxSync() {
        inboxRunning = false
        lastSyncAt = Date()
    }

    /// `true` si conviene un recovery (pasó el intervalo desde el último sync).
    func shouldRunRecovery(maxAge: TimeInterval = recoveryInterval) -> Bool {
        guard let lastSyncAt else { return true }
        return Date().timeIntervalSince(lastSyncAt) >= maxAge
    }
}
