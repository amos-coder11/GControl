import SwiftUI

// MARK: - Payload (modelo → JSON al final de la respuesta de Viera)

struct VieraCardPayload: Codable, Equatable {
    var team: [String]?
    /// Legacy field from older prompts; ignored (no vehicle inventory in Groo).
    var cars: [String]?
}

enum VieraCardsParser {
    private static let openTag = "<<<VIERA_CARDS"
    private static let closeTag = ">>>"

    static func visibleText(from raw: String) -> String {
        guard let r = raw.range(of: openTag) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parsedPayload(from raw: String) -> VieraCardPayload? {
        guard let openR = raw.range(of: openTag) else { return nil }
        var rest = String(raw[openR.upperBound...])
        if rest.first == "\n" || rest.first == "\r" { rest.removeFirst() }
        if rest.first == "\r" { rest.removeFirst() }
        guard let closeR = rest.range(of: closeTag) else { return nil }
        let jsonPart = String(rest[..<closeR.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonPart.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VieraCardPayload.self, from: data)
    }

    static func split(raw: String) -> (visible: String, payload: VieraCardPayload?) {
        (visibleText(from: raw), parsedPayload(from: raw))
    }
}

// MARK: - Contexto para el modelo (equipo)

enum VieraChatContextBuilder {
    static func build(
        directory: [CommunityProfilesService.DirectoryRow],
        currentUserId: UUID?
    ) -> String {
        var lines: [String] = []
        lines.append("EQUIPO (usa estos user_id en el array \"team\" del bloque JSON):")
        if directory.isEmpty {
            lines.append("(sin miembros en directorio)")
        } else {
            for r in directory {
                lines.append("- \(r.userId.uuidString.lowercased()) — \(r.resolvedDisplayName)")
            }
        }
        lines.append("")
        let peers = directory
            .filter { currentUserId == nil || $0.userId != currentUserId }
            .sorted { $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending }
        if let suggested = peers.first {
            lines.append("COMPAÑERO_SUGERIDO:")
            lines.append("- \(suggested.userId.uuidString.lowercased()) — \(suggested.resolvedDisplayName)")
        } else {
            lines.append("COMPAÑERO_SUGERIDO: (no hay otro compañero en el directorio)")
        }
        return lines.joined(separator: "\n")
    }
}

enum VieraTeamMentionResolver {
    static func membersMentioned(
        in text: String,
        directory: [CommunityProfilesService.DirectoryRow]
    ) -> [CommunityProfilesService.DirectoryRow] {
        let lower = text.lowercased()
        return directory.filter { row in
            let name = row.resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return false }
            return lower.contains(name.lowercased())
        }
    }

    static func suggestsWholeTeam(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("todo el equipo")
            || lower.contains("al equipo")
            || lower.contains("equipo completo")
    }
}

/// Tarjetas de equipo bajo la respuesta del asistente (sin inventario de vehículos).
struct VieraAssistantRichCardsView: View {
    let payload: VieraCardPayload
    let directory: [CommunityProfilesService.DirectoryRow]
    let mentionSourceText: String?
    let mentionExtraUserText: String?

    private var conversationScan: String {
        [mentionSourceText, mentionExtraUserText]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var teamRows: [CommunityProfilesService.DirectoryRow] {
        let ids = Set((payload.team ?? []).map { $0.lowercased() })
        var fromPayload = directory.filter { ids.contains($0.userId.uuidString.lowercased()) }
        if fromPayload.isEmpty {
            fromPayload = VieraTeamMentionResolver.membersMentioned(in: conversationScan, directory: directory)
        }
        if fromPayload.isEmpty, VieraTeamMentionResolver.suggestsWholeTeam(conversationScan) {
            return directory
        }
        return fromPayload
    }

    var body: some View {
        if !teamRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Equipo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(teamRows, id: \.userId) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(GrooBrand.purple.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(String(row.resolvedDisplayName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        Text(row.resolvedDisplayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}
