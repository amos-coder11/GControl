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

    /// Primer compañero distinto de mí (orden alfabético), para ofertas y avatares si el modelo no envió "team".
    private var defaultCommercialRow: CommunityProfilesService.DirectoryRow? {
        directory
            .filter { myUserId == nil || $0.userId != myUserId }
            .sorted { $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending }
            .first
    }

    /// Avatares: payload o, si hay coches en pantalla, al menos el comercial sugerido.
    private var teamRowsForDisplay: [CommunityProfilesService.DirectoryRow] {
        if !teamRowsFromPayload.isEmpty { return teamRowsFromPayload }
        if mergedCarsForStrip.isEmpty { return [] }
        if let row = defaultCommercialRow { return [row] }
        return []
    }

    /// Destinatario del DM de oferta: explícito en JSON o comercial sugerido.
    private var offerRecipientRow: CommunityProfilesService.DirectoryRow? {
        if let first = teamRowsFromPayload.first { return first }
        return defaultCommercialRow
    }

    private var canSendOffer: Bool {
        offerRecipientRow != nil
            && !mergedCarsForStrip.isEmpty
            && myUserId != nil
            && offerRecipientRow?.userId != myUserId
    }

    private var carsFromPayloadIds: [Car] {
        let ids = Set((payload.cars ?? []).map { $0.lowercased() })
        guard !ids.isEmpty else { return [] }
        return cars.filter { ids.contains($0.id.uuidString.lowercased()) }
    }

    private var mergedCarsForStrip: [Car] {
        let scan = [mentionExtraUserText, mentionSourceText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

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
                            Text("Comercial del equipo")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                            teamAvatarsStrip
                        }
                    }
                    if !mergedCarsForStrip.isEmpty {
                        carImagesStrip
                    }
                    if canSendOffer, let row = offerRecipientRow {
                        vieraOfferActionBlock(recipient: row)
                    }
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

    private func vieraOfferActionBlock(recipient: CommunityProfilesService.DirectoryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oferta para \(recipient.resolvedDisplayName)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
            Button {
                sendOfferToCommercial(recipient: recipient)
            } label: {
                HStack(spacing: 8) {
                    if isSendingOffer {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(isSendingOffer ? "Enviando…" : "Aceptar y enviar oferta")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.32, green: 0.62, blue: 1).opacity(0.35))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSendingOffer)
        }
        .padding(.top, 4)
    }

    private func sendOfferToCommercial(recipient: CommunityProfilesService.DirectoryRow) {
        let peerId = recipient.userId
        let body = composeOfferMessageBody()
        isSendingOffer = true
        Task {
            do {
                _ = try await TeamDirectMessagesService.send(
                    recipientId: peerId,
                    body: body,
                    client: SupabaseClientProvider.shared
                )
                let now = Date()
                await MainActor.run {
                    isSendingOffer = false
                    chatInbox.syncTeamThreads(from: communityVM.directory, currentUserId: auth.session?.user.id)
                    chatInbox.applyTeamDirectOutgoing(toPeer: peerId, body: body, date: now)
                    chatInbox.applyTeamCoordinatorOutreach(peerUserId: peerId, line: "Oferta desde Viera")
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

    private func composeOfferMessageBody() -> String {
        let visible = VieraCardsParser.visibleText(from: mentionSourceText ?? "")
        let summary = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        let head: String
        if summary.isEmpty {
            head = "Resumen enviado desde Viera (CarHub)."
        } else if summary.count > 900 {
            head = String(summary.prefix(900)) + "…"
        } else {
            head = summary
        }
        let lines = mergedCarsForStrip.map { carOfferLine($0) }
        let carsBlock = lines.isEmpty ? "" : "\n\nVehículos:\n" + lines.joined(separator: "\n")
        return "Oferta / seguimiento (Viera)\n\n\(head)\(carsBlock)"
    }

    private func carOfferLine(_ car: Car) -> String {
        let b = (car.brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let m = car.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = b.isEmpty ? m : "\(b) \(m)"
        var parts = ["· \(label)", "mat. \(car.plate)"]
        if let p = car.listPriceEUR {
            parts.append(String(format: "%.0f €", p))
        }
        return parts.joined(separator: " ")
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
}
