import Foundation

/// Serializa el enriquecimiento (fotos URL + teléfonos) fuera de la ruta crítica.
actor ContactEnrichmentService {
    static let shared = ContactEnrichmentService()

    private var running = false
    private var skipped = 0

    /// Re-escaneo de teléfono como mínimo cada 24 h si sigue unknown.
    static let phoneRecheckInterval: TimeInterval = 24 * 60 * 60

    func beginEnrichment() -> Bool {
        if running {
            skipped += 1
            ChatPerfLog.enrichment("skip duplicate enrichment")
            return false
        }
        running = true
        return true
    }

    func endEnrichment() {
        running = false
    }
}
