import SwiftUI
import UIKit

// MARK: - Payload (modelo → JSON al final de la respuesta de Viera)

struct VieraCardPayload: Codable, Equatable {
    var team: [String]?
    var cars: [String]?

    enum CodingKeys: String, CodingKey {
        case team
        case cars
    }
}

enum VieraCardsParser {
    private static let openTag = "<<<VIERA_CARDS"
    private static let closeTag = ">>>"

    /// Texto visible (oculta el bloque `<<<VIERA_CARDS`…`>>>` aunque venga a medias en el stream).
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

// MARK: - Contexto para el modelo (equipo + stock)

enum VieraChatContextBuilder {
    static func build(
        directory: [CommunityProfilesService.DirectoryRow],
        cars: [Car],
        currentUserId: UUID?,
        maxCars: Int = 24
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
            lines.append(
                "COMERCIAL_DEL_EQUIPO_SUGERIDO (ofertas y seguimiento con cliente: incluye este user_id en \"team\" junto con \"cars\" cuando el usuario quiera enviar oferta al comercial):"
            )
            lines.append("- \(suggested.userId.uuidString.lowercased()) — \(suggested.resolvedDisplayName)")
        } else {
            lines.append("COMERCIAL_DEL_EQUIPO_SUGERIDO: (no hay otro compañero en el directorio)")
        }
        lines.append("")
        lines.append("VEHÍCULOS EN INVENTARIO (usa estos id en el array \"cars\"):")
        let slice = Array(cars.prefix(maxCars))
        if slice.isEmpty {
            lines.append("(sin vehículos cargados)")
        } else {
            for c in slice {
                let brand = (c.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let label = "\(brand) \(c.model)".trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- \(c.id.uuidString.lowercased()) — \(label) · matrícula \(c.plate)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Coches citados en el texto (sin depender solo del JSON del modelo)

enum VieraCarMentionResolver {
    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    private static func plateKey(_ plate: String) -> String {
        norm(plate).filter { $0.isLetter || $0.isNumber }
    }

    /// Detecta vehículos del inventario citados por matrícula, marca+modelo, nombre o modelo único.
    static func carsMentioned(in text: String, inventory: [Car], maxCount: Int = 8) -> [Car] {
        let t = norm(text)
        guard t.count >= 2 else { return [] }

        var hits: [Car] = []
        var seen = Set<UUID>()

        for car in inventory {
            let pk = plateKey(car.plate)
            if pk.count >= 4, t.contains(pk) {
                if seen.insert(car.id).inserted { hits.append(car) }
                continue
            }

            let brand = norm(car.brandName ?? "")
            let model = norm(car.model)
            let brandModel = [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
            if brandModel.count >= 6, t.contains(brandModel) {
                if seen.insert(car.id).inserted { hits.append(car) }
                continue
            }

            let nick = norm(car.name)
            if nick.count >= 4, nick != model, nick != brand, t.contains(nick) {
                if seen.insert(car.id).inserted { hits.append(car) }
            }
        }

        for car in inventory {
            guard !seen.contains(car.id) else { continue }
            let model = norm(car.model)
            guard model.count >= 3 else { continue }
            let sameModel = inventory.filter { norm($0.model) == model }
            guard sameModel.count == 1, t.contains(model) else { continue }
            if seen.insert(car.id).inserted { hits.append(car) }
        }

        // Marca o modelo citados por palabra (p. ej. «Ferrari», «mercedes» con marca «Mercedes-Benz», «A3»).
        for car in inventory {
            guard !seen.contains(car.id) else { continue }
            let brand = norm(car.brandName ?? "")
            let model = norm(car.model)
            if matchesNormalizedBrand(brand, inFullText: t) {
                if seen.insert(car.id).inserted { hits.append(car) }
                continue
            }
            if matchesNormalizedModel(model, inFullText: t) {
                if seen.insert(car.id).inserted { hits.append(car) }
            }
        }

        return Array(hits.prefix(maxCount))
    }

    /// Coincidencia por marca: texto contiene la marca o una parte significativa (p. ej. «mercedes» ↔ «mercedes-benz»).
    private static func matchesNormalizedBrand(_ brandNorm: String, inFullText t: String) -> Bool {
        guard brandNorm.count >= 2 else { return false }
        if brandNorm.count >= 3, t.contains(brandNorm) { return true }
        let parts = brandNorm.split { $0 == "-" || $0 == " " }.map(String.init)
        for p in parts {
            let q = p.trimmingCharacters(in: .whitespaces)
            if q.count >= 3, t.contains(q) { return true }
        }
        return false
    }

    /// Coincidencia por modelo: frase completa o palabras (p. ej. «a3 cabrio» → «a3»).
    private static func matchesNormalizedModel(_ modelNorm: String, inFullText t: String) -> Bool {
        guard modelNorm.count >= 2 else { return false }
        if modelNorm.count >= 3, t.contains(modelNorm) { return true }
        let parts = modelNorm.split { $0 == "-" || $0 == " " }.map(String.init)
        for p in parts {
            let q = p.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { continue }
            if q.count >= 3, t.contains(q) { return true }
            // Tokens cortos tipo A3, X5: exigir al menos un dígito para no confundir con «el», «un», etc.
            if q.count == 2, q.contains(where: { $0.isNumber }), t.contains(q) { return true }
        }
        return false
    }

    private static func alphanumericTokens(from normalizedScan: String) -> Set<String> {
        let parts = normalizedScan.split { ch in
            !ch.isLetter && !ch.isNumber
        }
        return Set(parts.map { String($0) }.filter { !$0.isEmpty })
    }

    /// Marcas que el usuario puede citar solas; si no hay ninguna en inventario, no mostramos otros coches del JSON.
    private static let standaloneBrandMentionTokens: Set<String> = [
        "ferrari", "lamborghini", "porsche", "maserati", "bentley", "bugatti", "mclaren", "pagani",
        "koenigsegg", "astonmartin", "aston", "martin", "rollsroyce", "rolls", "royce",
        "mercedes", "bmw", "audi", "volkswagen", "vw", "opel", "seat", "cupra", "skoda",
        "renault", "peugeot", "citroen", "ds", "alpine", "ford", "tesla", "fiat", "abarth",
        "alfa", "romeo", "alfaromeo", "jaguar", "landrover", "land", "rover", "mini", "smart",
        "volvo", "toyota", "lexus", "honda", "acura", "nissan", "infiniti", "mazda", "subaru",
        "mitsubishi", "suzuki", "hyundai", "genesis", "kia", "byd", "mg", "polestar", "rivian", "lucid",
        "dacia", "lada", "iveco", "scania",
    ]

    /// Si el usuario nombra una marca concreta y no hay ningún coche que encaje, ocultamos tarjetas aunque el modelo devolviera otros UUID.
    static func shouldSuppressPayloadCars(scan: String, inventory: [Car]) -> Bool {
        let t = norm(scan)
        guard t.count >= 2 else { return false }
        if !carsMentioned(in: scan, inventory: inventory).isEmpty { return false }
        let tokens = alphanumericTokens(from: t)
        for tok in tokens where standaloneBrandMentionTokens.contains(tok) {
            if carsMentioned(in: tok, inventory: inventory).isEmpty {
                return true
            }
        }
        return false
    }
}

// MARK: - Equipo nombrado en la conversación

enum VieraTeamMentionResolver {
    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    /// Habla del conjunto del equipo → mostrar todos los compañeros del directorio.
    static func suggestsWholeTeam(_ text: String) -> Bool {
        let t = norm(text)
        if t.contains("todo") && t.contains("equipo") { return true }
        if t.contains("todos"),
           t.contains("equipo") || t.contains("comercial") || t.contains("compañero") || t.contains("compañeros") {
            return true
        }
        let phrases = [
            "equipo completo", "todo el equipo", "todos en el equipo", "todo tu equipo",
            "el equipo entero", "a los del equipo", "a mi equipo", "nuestro equipo",
            "mis compañeros", "los comerciales", "avisar al equipo", "pasarlo al equipo",
            "comentar al equipo", "comentarselo al equipo",
        ]
        return phrases.contains { t.contains($0) }
    }

    /// Personas citadas por nombre (tiene prioridad sobre «todo el equipo»).
    static func membersMentioned(
        in text: String,
        directory: [CommunityProfilesService.DirectoryRow],
        excludeUserId: UUID?
    ) -> [CommunityProfilesService.DirectoryRow] {
        let t = norm(text)
        guard t.count >= 2 else { return [] }
        var hits: [CommunityProfilesService.DirectoryRow] = []
        var seen = Set<UUID>()
        let rows = directory
            .filter { excludeUserId == nil || $0.userId != excludeUserId }
            .sorted { norm($0.resolvedDisplayName).count > norm($1.resolvedDisplayName).count }

        for row in rows {
            let name = norm(row.resolvedDisplayName)
            guard name.count >= 3 else { continue }
            var matched = false
            if name.count >= 5, t.contains(name) { matched = true }
            if !matched {
                let parts = name.split(separator: " ").map(String.init).filter { $0.count >= 4 }
                for p in parts where t.contains(p) {
                    matched = true
                    break
                }
            }
            if matched, seen.insert(row.userId).inserted {
                hits.append(row)
            }
        }
        return hits.sorted {
            $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
        }
    }
}

// MARK: - Horario / lugar desde el texto

enum VieraScheduleHint {
    static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES")).lowercased()
            if lower.range(of: "\\d{1,2}[:.]\\d{2}", options: .regularExpression) != nil {
                return line.count > 220 ? String(line.prefix(220)) : line
            }
            if lower.contains("a las"), lower.range(of: "\\d", options: .regularExpression) != nil {
                return line.count > 220 ? String(line.prefix(220)) : line
            }
            let hints = [
                "mañana", "hoy", "tarde", "mediodia", "pasado mañana",
                "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
                "entrega", "recogida", "cita", "horario",
            ]
            if hints.contains(where: { lower.contains($0) }), line.count >= 8 {
                return line.count > 220 ? String(line.prefix(220)) : line
            }
        }

        if let range = trimmed.range(of: "\\d{1,2}[:.]\\d{2}", options: .regularExpression) {
            let lo = trimmed.index(range.lowerBound, offsetBy: -35, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
            let hi = trimmed.index(range.upperBound, offsetBy: 50, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let slice = String(trimmed[lo..<hi]).trimmingCharacters(in: .whitespacesAndNewlines)
            return slice.count >= 4 ? slice : nil
        }
        return nil
    }
}

// MARK: - UI: franjas horizontales estilo ChatGPT

struct VieraAssistantRichCardsView: View {
    let payload: VieraCardPayload
    let directory: [CommunityProfilesService.DirectoryRow]
    let cars: [Car]
    /// Texto visible de Viera (y opcionalmente el último mensaje del usuario) para mostrar coches citados aunque falte el JSON.
    var mentionSourceText: String? = nil
    var mentionExtraUserText: String? = nil

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel

    @State private var isSendingOffer = false
    @State private var offerSendError: String?
    /// Coche que el comercial debe usar en la tarea (eliges tú).
    @State private var selectedOfferCarId: UUID?
    /// Si hay varios en el equipo, quién recibe el DM y la tarea.
    @State private var selectedRecipientUserId: UUID?
    /// Horario, lugar o instrucciones de entrega / recogida.
    @State private var scheduleInstructions: String = ""
    /// Si el comercial debe llevar o trasladar ese vehículo del stock.
    @State private var commercialMustTransportCar: Bool = true
    /// Plazo por defecto: 2 h desde ahora (editable antes de enviar).
    @State private var coordinatorTaskDeadline: Date =
        Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
    /// El usuario confirma haber revisado destinatario, coche, instrucciones, plazo y traslado.
    @State private var userVerifiedTaskForm = false

    private var accessToken: String? { auth.session?.accessToken }
    private var myUserId: UUID? { auth.session?.user.id }

    /// ~2 tarjetas visibles a la vez, estilo carrusel ChatGPT.
    private var galleryCardWidth: CGFloat {
        let w: CGFloat
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            w = scene.screen.bounds.width
        } else {
            w = 390
        }
        return min(320, max(158, w * 0.46))
    }

    private var galleryImageHeight: CGFloat {
        let inner = galleryCardWidth - 8
        return inner * 0.68
    }

    /// Filas del JSON del modelo (team).
    private var teamRowsFromPayload: [CommunityProfilesService.DirectoryRow] {
        let ids = Set((payload.team ?? []).map { $0.lowercased() })
        guard !ids.isEmpty else { return [] }
        return directory.filter { ids.contains($0.userId.uuidString.lowercased()) }
    }

    /// Primer compañero distinto de mí (orden alfabético), si no nombraste a nadie ni al equipo.
    private var defaultCommercialRow: CommunityProfilesService.DirectoryRow? {
        allPeersSorted.first
    }

    private var allPeersSorted: [CommunityProfilesService.DirectoryRow] {
        directory
            .filter { myUserId == nil || $0.userId != myUserId }
            .sorted { $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending }
    }

    /// Texto usuario + Viera para detectar nombres, «todo el equipo» y horarios.
    private var conversationScan: String {
        [mentionExtraUserText, mentionSourceText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Avatares: JSON del modelo; si no, quien cites por nombre; si pides todo el equipo, todos; si no, comercial por defecto con coches.
    private var teamRowsForDisplay: [CommunityProfilesService.DirectoryRow] {
        if !teamRowsFromPayload.isEmpty { return teamRowsFromPayload }
        let scan = conversationScan
        let mentioned = VieraTeamMentionResolver.membersMentioned(
            in: scan,
            directory: directory,
            excludeUserId: myUserId
        )
        if !mentioned.isEmpty { return mentioned }
        if VieraTeamMentionResolver.suggestsWholeTeam(scan) { return allPeersSorted }
        if mergedCarsForStrip.isEmpty { return [] }
        if let row = defaultCommercialRow { return [row] }
        return []
    }

    private var teamSectionHeaderTitle: String {
        if teamRowsFromPayload.isEmpty, VieraTeamMentionResolver.suggestsWholeTeam(conversationScan) {
            return "Tu equipo"
        }
        if teamRowsForDisplay.count > 1 { return "Equipo" }
        return "Comercial"
    }

    /// Destinatario de la tarea (si hay varios, el que eliges en la tira).
    private var offerRecipientRow: CommunityProfilesService.DirectoryRow? {
        let rows = teamRowsForDisplay
        guard !rows.isEmpty else { return nil }
        if rows.count == 1 { return rows.first }
        guard let id = selectedRecipientUserId else { return nil }
        return rows.first { $0.userId == id }
    }

    /// Puede mostrarse el formulario de tarea (hay comercial, coches y sesión).
    private var canComposeOffer: Bool {
        offerRecipientRow != nil
            && !mergedCarsForStrip.isEmpty
            && myUserId != nil
            && offerRecipientRow?.userId != myUserId
    }

    private var selectedOfferCar: Car? {
        guard let id = selectedOfferCarId else { return nil }
        return mergedCarsForStrip.first { $0.id == id }
    }

    private var trimmedScheduleInstructions: String {
        scheduleInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Instrucciones con sustancia (no basta con 4 caracteres).
    private var scheduleInstructionsValid: Bool {
        trimmedScheduleInstructions.count >= 18
    }

    /// Al menos ~1 minuto en el futuro (evita plazos ya pasados por error).
    private var taskDeadlineValid: Bool {
        coordinatorTaskDeadline > Date().addingTimeInterval(60)
    }

    private var canSubmitOfferTask: Bool {
        guard canComposeOffer, offerRecipientRow != nil else { return false }
        guard selectedOfferCar != nil else { return false }
        guard scheduleInstructionsValid else { return false }
        guard taskDeadlineValid else { return false }
        guard userVerifiedTaskForm else { return false }
        return true
    }

    private var missingTaskRequirements: [String] {
        var lines: [String] = []
        if teamRowsForDisplay.count > 1, selectedRecipientUserId == nil {
            lines.append("Elige al comercial tocando su avatar.")
        }
        if !canComposeOffer {
            return lines
        }
        if selectedOfferCar == nil {
            lines.append("Selecciona un vehículo en la tira.")
        }
        if !scheduleInstructionsValid {
            lines.append("Escribe instrucciones claras (mínimo 18 caracteres).")
        }
        if !taskDeadlineValid {
            lines.append("Ajusta el plazo: debe ser posterior a ahora.")
        }
        if canSubmitOfferTask == false, lines.isEmpty, !userVerifiedTaskForm {
            lines.append("Marca «He revisado todo» para poder enviar.")
        }
        return lines
    }

    private var mergedCarsSelectionToken: String {
        mergedCarsForStrip.map(\.id.uuidString).joined(separator: ",")
    }

    private var carsFromPayloadIds: [Car] {
        let ids = Set((payload.cars ?? []).map { $0.lowercased() })
        guard !ids.isEmpty else { return [] }
        return cars.filter { ids.contains($0.id.uuidString.lowercased()) }
    }

    private var mergedCarsForStrip: [Car] {
        let scan = conversationScan

        let mentionHits = scan.isEmpty ? [] : VieraCarMentionResolver.carsMentioned(in: scan, inventory: cars)

        if !mentionHits.isEmpty {
            var ordered: [Car] = []
            var seen = Set<UUID>()
            let mentionIds = Set(mentionHits.map(\.id))
            for c in carsFromPayloadIds where mentionIds.contains(c.id) {
                if seen.insert(c.id).inserted { ordered.append(c) }
            }
            for c in mentionHits {
                if seen.insert(c.id).inserted { ordered.append(c) }
            }
            return ordered
        }

        if !scan.isEmpty, VieraCarMentionResolver.shouldSuppressPayloadCars(scan: scan, inventory: cars) {
            return []
        }
        return carsFromPayloadIds
    }

    var body: some View {
        Group {
            if teamRowsForDisplay.isEmpty, mergedCarsForStrip.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !teamRowsForDisplay.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(teamSectionHeaderTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                            if teamRowsForDisplay.count > 1 {
                                Text("Toca quién debe recibir la tarea")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.42))
                                selectableTeamAvatarsStrip
                            } else {
                                teamAvatarsStrip
                            }
                        }
                    }
                    if !mergedCarsForStrip.isEmpty {
                        if canComposeOffer, let row = offerRecipientRow {
                            vieraTaskComposerBlock(recipient: row)
                        } else {
                            carImagesStrip
                        }
                    }
                }
                .task(id: mergedCarsSelectionToken) {
                    syncSelectedOfferCarWithInventory()
                }
                .task(id: teamRowsForDisplay.map(\.userId.uuidString).joined(separator: ",")) {
                    syncRecipientWithTeamDisplay()
                }
                .task(id: conversationScan) {
                    fillScheduleFromConversationIfEmpty()
                }
                .alert("No se pudo enviar", isPresented: Binding(
                    get: { offerSendError != nil },
                    set: { if !$0 { offerSendError = nil } }
                )) {
                    Button("OK", role: .cancel) { offerSendError = nil }
                } message: {
                    Text(offerSendError ?? "")
                }
            }
        }
    }

    private func vieraTaskComposerBlock(recipient: CommunityProfilesService.DirectoryRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tarea para \(recipient.resolvedDisplayName)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))

            Text("Selecciona el coche que debe llevar o gestionar en esta tarea")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))

            selectableCarImagesStrip

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Horario, lugar o instrucciones de entrega")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer(minLength: 8)
                    Text("\(trimmedScheduleInstructions.count)/18+")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(
                            scheduleInstructionsValid ? Color.green.opacity(0.85) : Color.white.opacity(0.4)
                        )
                }
                TextField(
                    "Ej.: mañana 10:00, entrega en sala de ventas; cliente recoge en taller…",
                    text: $scheduleInstructions,
                    axis: .vertical
                )
                .lineLimit(2 ... 5)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }

            Toggle(isOn: $commercialMustTransportCar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debe llevar o trasladar este vehículo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                    Text("Desactiva si solo coordina cita sin mover unidad de stock.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .tint(Color(red: 0.32, green: 0.62, blue: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text("Plazo para completar la tarea")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                DatePicker(
                    "",
                    selection: $coordinatorTaskDeadline,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
                .tint(Color(red: 0.32, green: 0.62, blue: 1))
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }

            Text("Al enviar, \(recipient.resolvedDisplayName) verá la tarea con la foto del coche, podrá aceptarla y subir las fotos que se piden en cada paso.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)

            if !missingTaskRequirements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Para enviar, completa:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    ForEach(missingTaskRequirements, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.orange.opacity(0.75))
                                .padding(.top, 5)
                            Text(line)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                }
            }

            Toggle(isOn: $userVerifiedTaskForm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("He revisado todo y es correcto")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text("Destinatario, vehículo, instrucciones, si debe trasladar el coche y la fecha límite.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .tint(Color(red: 0.32, green: 0.62, blue: 1))
            .disabled(!recipientCarAndScheduleReadyForVerification(recipient: recipient))

            Button {
                sendCoordinatorTaskToCommercial(recipient: recipient)
            } label: {
                HStack(spacing: 8) {
                    if isSendingOffer {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(isSendingOffer ? "Enviando tarea…" : "Enviar tarea al comercial")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.32, green: 0.62, blue: 1).opacity(canSubmitOfferTask ? 0.4 : 0.18))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSendingOffer || !canSubmitOfferTask)
        }
        .padding(.top, 4)
        .onChange(of: scheduleInstructions) { _, _ in userVerifiedTaskForm = false }
        .onChange(of: coordinatorTaskDeadline) { _, _ in userVerifiedTaskForm = false }
        .onChange(of: commercialMustTransportCar) { _, _ in userVerifiedTaskForm = false }
        .onChange(of: selectedOfferCarId) { _, _ in userVerifiedTaskForm = false }
        .onChange(of: selectedRecipientUserId) { _, _ in userVerifiedTaskForm = false }
    }

    /// Todo lo necesario para que el usuario pueda marcar la verificación (sin el toggle en sí).
    private func recipientCarAndScheduleReadyForVerification(recipient: CommunityProfilesService.DirectoryRow) -> Bool {
        guard canComposeOffer, recipient.userId == offerRecipientRow?.userId else { return false }
        guard selectedOfferCar != nil else { return false }
        guard scheduleInstructionsValid else { return false }
        guard taskDeadlineValid else { return false }
        return true
    }

    private func syncSelectedOfferCarWithInventory() {
        guard !mergedCarsForStrip.isEmpty else {
            selectedOfferCarId = nil
            return
        }
        if selectedOfferCarId == nil || mergedCarsForStrip.first(where: { $0.id == selectedOfferCarId }) == nil {
            selectedOfferCarId = mergedCarsForStrip.first?.id
        }
    }

    private func syncRecipientWithTeamDisplay() {
        let rows = teamRowsForDisplay
        if rows.isEmpty {
            selectedRecipientUserId = nil
            return
        }
        if let id = selectedRecipientUserId, rows.contains(where: { $0.userId == id }) {
            return
        }
        // Un solo comercial: se elige solo. Varios: hay que tocar un avatar (no auto-enviar al primero).
        if rows.count == 1 {
            selectedRecipientUserId = rows.first?.userId
        } else {
            selectedRecipientUserId = nil
        }
    }

    private func fillScheduleFromConversationIfEmpty() {
        guard scheduleInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let hint = VieraScheduleHint.extract(from: conversationScan), hint.count >= 4 else { return }
        scheduleInstructions = hint
    }

    private func sendCoordinatorTaskToCommercial(recipient: CommunityProfilesService.DirectoryRow) {
        guard canSubmitOfferTask else { return }
        guard let car = selectedOfferCar else { return }
        guard let senderId = auth.session?.user.id else { return }
        let peerId = recipient.userId
        let deadline = coordinatorTaskDeadline
        isSendingOffer = true
        Task {
            var refJPEG: Data?
            if let ui = await CarUIImageLoader.load(car: car, auth: auth) {
                refJPEG = ui.jpegData(compressionQuality: 0.82)
            }
            let title = vieraTaskTitle(for: car)
            let body = vieraTaskBody(
                car: car,
                recipientName: recipient.resolvedDisplayName
            )
            let steps = vieraTaskStepInstructions(mustTransport: commercialMustTransportCar)
            let dmLine = vieraTaskShortDMLine(for: car)
            do {
                try await chatInbox.createCoordinatorTaskSynced(
                    senderUserId: senderId,
                    recipientUserId: peerId,
                    title: title,
                    body: body,
                    stepInstructions: steps,
                    deadline: deadline,
                    referenceImageData: refJPEG
                )
                _ = try await TeamDirectMessagesService.send(
                    recipientId: peerId,
                    body: dmLine,
                    client: SupabaseClientProvider.shared
                )
                let now = Date()
                await MainActor.run {
                    isSendingOffer = false
                    chatInbox.syncTeamThreads(from: communityVM.directory, currentUserId: auth.session?.user.id)
                    chatInbox.applyTeamDirectOutgoing(toPeer: peerId, body: dmLine, date: now)
                    chatInbox.applyTeamCoordinatorOutreach(peerUserId: peerId, line: "Tarea Viera: \(vieraShortCarLabel(car))")
                    if let thread = chatInbox.teamDirectChatThreads.first(where: { $0.peerUserId == peerId }) {
                        chatNav.threadToOpen = thread
                        tabRouter.selected = .chat
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    isSendingOffer = false
                    offerSendError = error.localizedDescription
                }
            }
        }
    }

    private func vieraShortCarLabel(_ car: Car) -> String {
        let b = (car.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let m = car.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = b.isEmpty ? m : "\(b) \(m)"
        return "\(label) · \(car.plate)"
    }

    private func vieraTaskTitle(for car: Car) -> String {
        "Viera · \(vieraShortCarLabel(car))"
    }

    private func vieraTaskShortDMLine(for car: Car) -> String {
        "Nueva tarea de Viera: \(vieraShortCarLabel(car)). Ábrela en esta conversación y pulsa «Aceptar tarea»."
    }

    private func vieraTaskBody(car: Car, recipientName: String) -> String {
        let visible = VieraCardsParser.visibleText(from: mentionSourceText ?? "")
        let summary = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryBlock: String
        if summary.isEmpty {
            summaryBlock = "Contexto: resumen generado desde Viera en CarHub."
        } else if summary.count > 850 {
            summaryBlock = String(summary.prefix(850)) + "…"
        } else {
            summaryBlock = summary
        }
        let sched = scheduleInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let transportLine = commercialMustTransportCar
            ? "Sí: debes usar el vehículo de la foto en esta tarea (traslado, entrega o recogida según indique el horario)."
            : "No hace falta mover una unidad de stock; coordina solo lo acordado en el horario (cita, llamada, recepción de cliente, etc.)."
        return """
        Resumen (Viera):
        \(summaryBlock)

        Comercial asignado: \(recipientName)

        Vehículo elegido para esta tarea:
        \(vieraShortCarLabel(car))

        Horario e instrucciones de entrega o recogida:
        \(sched)

        ¿Llevar o trasladar este coche?
        \(transportLine)

        Pasos: tras pulsar «Aceptar tarea», completa cada punto y sube la foto que se pide en cada paso. Así queda registro de la ejecución.
        """
    }

    private func vieraTaskStepInstructions(mustTransport: Bool) -> [String] {
        var steps: [String] = [
            "Confirma que reconoces el vehículo de la foto (mismo modelo y matrícula que en el texto de la tarea).",
        ]
        if mustTransport {
            steps.append(
                "Escribe en el chat la hora exacta y el lugar donde entregarás o recogerás el vehículo, alineado con las instrucciones de arriba."
            )
            steps.append(
                "Sube una foto del vehículo en el punto acordado: matrícula y parte delantera o lateral bien visibles."
            )
            steps.append(
                "Sube una foto del interior o del documento / firma de entrega si aplica al caso."
            )
        } else {
            steps.append(
                "Escribe en el chat cómo queda concretado el horario y el contacto con el cliente o el taller."
            )
            steps.append(
                "Sube una foto o captura que acredite la acción acordada (pantalla de cita, ticket, etc.)."
            )
            steps.append(
                "Sube una segunda prueba si el responsable debe validar un paso adicional (por ejemplo confirmación por escrito)."
            )
        }
        return steps
    }

    private var teamAvatarsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(teamRowsForDisplay) { row in
                    TeamDirectoryProfileAvatar(
                        row: row,
                        accessToken: accessToken,
                        diameter: 56,
                        localAvatarImage: nil,
                        localInitialsOverride: nil
                    )
                }
            }
        }
    }

    private var selectableTeamAvatarsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(teamRowsForDisplay) { row in
                    let selected = row.userId == selectedRecipientUserId
                    Button {
                        selectedRecipientUserId = row.userId
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                TeamDirectoryProfileAvatar(
                                    row: row,
                                    accessToken: accessToken,
                                    diameter: 56,
                                    localAvatarImage: nil,
                                    localInitialsOverride: nil
                                )
                                if selected {
                                    Circle()
                                        .strokeBorder(Color(red: 0.32, green: 0.72, blue: 1), lineWidth: 3)
                                        .frame(width: 62, height: 62)
                                }
                            }
                            Text(row.resolvedDisplayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.55))
                                .lineLimit(1)
                                .frame(maxWidth: 88)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var carImagesStrip: some View {
        let iw = galleryCardWidth - 8
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mergedCarsForStrip) { car in
                    CarThumbnailView(
                        car: car,
                        width: iw,
                        height: galleryImageHeight,
                        roundedCardClip: true
                    )
                    .environmentObject(auth)
                }
            }
        }
    }

    private var selectableCarImagesStrip: some View {
        let iw = galleryCardWidth - 8
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mergedCarsForStrip) { car in
                    let selected = car.id == selectedOfferCarId
                    Button {
                        selectedOfferCarId = car.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            CarThumbnailView(
                                car: car,
                                width: iw,
                                height: galleryImageHeight,
                                roundedCardClip: true
                            )
                            .environmentObject(auth)
                            if selected {
                                RoundedRectangle(cornerRadius: min(iw, galleryImageHeight) * 0.14, style: .continuous)
                                    .strokeBorder(Color(red: 0.32, green: 0.72, blue: 1), lineWidth: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottomLeading) {
                        if selected {
                            Text("Seleccionado")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(8)
                        }
                    }
                }
            }
        }
    }
}
