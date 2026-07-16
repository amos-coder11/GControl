import Combine
import Foundation

/// Historial local de documentos / notas generados en la app.
@MainActor
final class InvoiceHistoryStore: ObservableObject {
    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let createdAt: Date
        let documentKindRaw: String
        let title: String
        let subtitle: String
    }

    @Published private(set) var entries: [Entry] = []

    private let storageKey = "Groo.invoiceHistory.v1"

    init() {
        load()
    }

    func record(title: String, subtitle: String, kind: String = "note") {
        let e = Entry(
            id: UUID(),
            createdAt: Date(),
            documentKindRaw: kind,
            title: title,
            subtitle: subtitle
        )
        entries.insert(e, at: 0)
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
