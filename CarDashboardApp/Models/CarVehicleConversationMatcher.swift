import Foundation

/// Relaciona un `Car` con hilos del CRM / WhatsApp (pestaña Chat → Generales).
enum CarVehicleConversationMatcher {
    private static let catalogUUIDPattern =
        "(?:catalogo|stock|vehiculos?|coches?)/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"

    private static let bareUUIDPattern =
        "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"

    static func linkedVehicleIds(conversation: CrmChatService.Conversation) -> Set<String> {
        var ids = Set<String>()
        if let raw = conversation.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            ids.insert(normalizeId(raw))
        }
        for id in extractVehicleUUIDs(from: conversation.lastMessage ?? "") {
            ids.insert(id)
        }
        return ids
    }

    static func linkedVehicleIds(fromMessageTexts texts: [String]) -> Set<String> {
        var ids = Set<String>()
        for text in texts {
            for id in extractVehicleUUIDs(from: text) {
                ids.insert(id)
            }
        }
        return ids
    }

    static func matches(
        car: Car,
        linkedIds: Set<String>,
        preview: String,
        title: String
    ) -> Bool {
        let carId = normalizeId(car.id.uuidString)
        if linkedIds.contains(carId) { return true }

        let blob = [preview, title].joined(separator: " ")
        for id in extractVehicleUUIDs(from: blob) where id == carId {
            return true
        }
        return textMentionsCar(blob, car: car)
    }

    static func extractVehicleUUIDs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var found: [String] = []
        var seen = Set<String>()
        for pattern in [catalogUUIDPattern, bareUUIDPattern] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in re.matches(in: text, range: range) {
                guard match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: text) else { continue }
                let id = normalizeId(String(text[r]))
                if seen.insert(id).inserted {
                    found.append(id)
                }
            }
        }
        return found
    }

    /// Primer UUID de ficha en un mensaje (compat. con `ChatConversationView`).
    static func firstVehicleId(in text: String) -> String? {
        extractVehicleUUIDs(from: text).first
    }

    static func textMentionsCar(_ text: String, car: Car) -> Bool {
        let blob = text
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
        let tokens = [
            car.displayBrandUppercased,
            car.name,
            car.model,
            car.plate,
            car.brandName ?? "",
        ]
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { $0.count >= 3 }
        return tokens.contains { blob.contains($0) }
    }

    private static func normalizeId(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
