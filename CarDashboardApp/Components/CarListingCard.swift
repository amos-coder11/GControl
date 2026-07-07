import SwiftUI
import UIKit

/// Texto de ficha sobre fondo mesh oscuro: todo legible en blanco / gris muy claro.
private enum ListingPalette {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.82)
    static let tertiary = Color.white.opacity(0.68)
    static let tagFill = Color.white.opacity(0.12)
    static let tagStroke = Color.white.opacity(0.22)

    static let pricePillFill = Color.black.opacity(0.88)
    static let footerFill = Color(red: 0.055, green: 0.065, blue: 0.085)
    static let goldBorder = LinearGradient(
        colors: [
            Color(red: 0.76, green: 0.58, blue: 0.22),
            Color(red: 0.95, green: 0.84, blue: 0.42),
            Color(red: 0.70, green: 0.52, blue: 0.18),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum CarHeroImagePresentation {
    /// Foto completa con márgenes (detalle).
    case contain
    /// Recorte a pantalla completa del slot (grid).
    case cover
}

struct CarListingCard: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore

    let car: Car
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @State private var galleryIndex = 0

    private var imageSlots: [CarImageSlot] {
        car.resolvedImageSlots
    }

    private var interestedThreads: [ChatThread] {
        chatInbox.leadThreads(for: car)
    }

    private let cardCornerRadius: CGFloat = 22
    private let contentPadding: CGFloat = 10
    private let heroHeight: CGFloat = 148

    var body: some View {
        Button(action: onSelect) {
            listingCardInterior
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                DashboardChromeCardBackground(cornerRadius: cardCornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(car.accentSwiftUIColor.opacity(0.5), lineWidth: 1.25)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // No usar prefetchGallery aquí: dispara decenas de descargas al CDN por tarjeta (p. ej. ccdn.es)
        // y provoca -1001. La miniatura se carga en .task; el prefetch de vecinos va en CarsView.prefetch.
        .onChange(of: car.id) { _, _ in galleryIndex = 0 }
        .onChange(of: imageSlots.count) { _, newCount in
            if newCount == 0 {
                galleryIndex = 0
            } else if galleryIndex >= newCount {
                galleryIndex = newCount - 1
            }
        }
    }

    private var listingCardInterior: some View {
        VStack(alignment: .leading, spacing: 0) {
            listingHeroImage
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(car.displayBrandUppercased)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ListingPalette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !car.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(car.model)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ListingPalette.secondary)
                        .lineLimit(1)
                }

                CarListingPricePill(priceText: car.displayListPriceText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.horizontal, contentPadding)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(ListingPalette.footerFill)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listingHeroImage: some View {
        ZStack {
            Group {
                if imageSlots.isEmpty {
                    ZStack {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Image(systemName: car.icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                } else if imageSlots.count == 1, let only = imageSlots.first {
                    CarHeroImageSlotView(slot: only, presentation: .cover)
                } else {
                    TabView(selection: $galleryIndex) {
                        ForEach(Array(imageSlots.enumerated()), id: \.element.id) { idx, slot in
                            CarHeroImageSlotView(slot: slot, presentation: .cover)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if car.isInventorySold {
                CarListingSoldPhotoOverlay()
            } else if car.isInventoryReserved {
                CarListingReservedPhotoOverlay()
            }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if !interestedThreads.isEmpty {
                        CarListingInterestedStrip(threads: interestedThreads)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 6) {
                    if imageSlots.count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(min(galleryIndex + 1, max(imageSlots.count, 1)))/\(imageSlots.count)")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                    }

                    Spacer(minLength: 4)

                    if let trim = car.listingHeroTrimLabel {
                        Text(trim)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }
}

struct CarListingInterestedStrip: View {
    @EnvironmentObject private var auth: AuthViewModel

    let threads: [ChatThread]

    private let avatarSize: CGFloat = 26
    private let badgeSize: CGFloat = 11
    private let maxVisible = 3

    private var visibleThreads: [ChatThread] {
        Array(threads.prefix(maxVisible))
    }

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                interestedAvatar(for: thread)
                    .zIndex(Double(index))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(threads.count) interesados")
    }

    @ViewBuilder
    private func interestedAvatar(for thread: ChatThread) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = thread.avatarCarURL {
                    ChatAsyncContactPhoto(
                        url: url,
                        accessToken: auth.session?.accessToken,
                        fallbackInitial: thread.avatarInitial,
                        fallbackColor: thread.avatarColor,
                        diameter: avatarSize
                    )
                } else {
                    initialsAvatar(for: thread)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            }

            if let source = thread.socialSource {
                Circle()
                    .fill(source == .whatsApp
                        ? Color(red: 0.12, green: 0.72, blue: 0.38)
                        : Color(red: 0.69, green: 0.28, blue: 0.82))
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay {
                        Image(systemName: source == .whatsApp ? "message.fill" : "camera.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle().strokeBorder(Color.white, lineWidth: 0.75)
                    }
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 0.5)
    }

    private func initialsAvatar(for thread: ChatThread) -> some View {
        Circle()
            .fill(thread.avatarColor.opacity(0.85))
            .overlay {
                Text(thread.avatarInitial ?? String(thread.title.prefix(1)).uppercased())
                    .font(.system(size: avatarSize * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

struct CarListingSoldPhotoOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.62, blue: 0.28).opacity(0.52)

            VStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("VENDIDO")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.1)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct CarListingReservedPhotoOverlay: View {
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.42, blue: 0.92).opacity(0.52)

            VStack(spacing: 4) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("RESERVADO")
                    .font(.system(size: 12, weight: .black))
                    .tracking(0.9)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct CarListingLeadFooter: View {
    let stats: CarLeadStats

    var body: some View {
        HStack(spacing: 0) {
            footerCell(icon: "calendar", value: stats.appointments, label: "CITAS", tint: Color(red: 0.62, green: 0.45, blue: 0.98))
            footerDivider
            footerCell(icon: "person.3.fill", value: stats.leads, label: "LEADS", tint: .cyan)
            footerDivider
            footerCell(icon: "trophy.fill", value: stats.won, label: "GANADOS", tint: .green)
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    private func footerCell(icon: String, value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Formato compartido listado + detalle

extension Car {
    var displayBrandUppercased: String {
        let brand = brandName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brand, !brand.isEmpty { return brand.uppercased() }
        return name.uppercased()
    }

    var displayListPriceText: String {
        guard let p = listPriceEUR else { return "Consultar" }
        let n = Int(p.rounded()).formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
        return "\(n) €"
    }

    var listingHeroTrimLabel: String? {
        if let eq = equipmentSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !eq.isEmpty {
            let line = eq.split(separator: "\n").first.map(String.init) ?? eq
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 4 { return trimmed.uppercased() }
        }
        if let dgt = dgtLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !dgt.isEmpty {
            return dgt.uppercased()
        }
        return nil
    }
}

struct CarListingPricePill: View {
    let priceText: String

    var body: some View {
        Text(priceText)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.55, blue: 0.18),
                                Color(red: 0.98, green: 0.72, blue: 0.28),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.2
                    )
            }
    }
}

struct CarListingSpecIconRow: View {
    let car: Car

    var body: some View {
        HStack(spacing: 14) {
            if let km = car.mileageKm, km > 0 {
                specItem(icon: "speedometer", text: "\(formatInt(km)) km")
            }
            if let fuel = car.fuelType?.trimmingCharacters(in: .whitespacesAndNewlines), !fuel.isEmpty {
                specItem(icon: "fuelpump.fill", text: fuel.uppercased())
            }
            if let cv = car.powerCv, cv > 0 {
                specItem(icon: "engine.combustion.fill", text: "\(cv) CV")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func specItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.72))
    }

    private func formatInt(_ v: Int) -> String {
        v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }
}

struct CarListingTagRow: View {
    let car: Car

    var body: some View {
        FlowTagRow {
            if let t = car.transmission?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                tagPill(t.uppercased())
            }
            if let bt = car.bodyType?.trimmingCharacters(in: .whitespacesAndNewlines), !bt.isEmpty {
                tagPill(bt.uppercased())
            }
            if let c = car.exteriorColorLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(Color.white.opacity(0.35)).frame(width: 7, height: 7)
                    tagPill(c.uppercased())
                }
            }
            if let loc = car.locationText?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .semibold))
                    tagPill(loc)
                }
            }
        }
    }

    private func tagPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: Capsule())
    }
}

// MARK: - Imagen de slot (miniatura o página de galería)

struct CarHeroImageSlotView: View {
    @EnvironmentObject private var auth: AuthViewModel
    let slot: CarImageSlot
    var presentation: CarHeroImagePresentation = .contain

    @State private var image: UIImage?
    @State private var loadFinishedWithoutImage = false
    /// Si la fila sale del `LazyVStack`, SwiftUI cancela `.task` y puede quedar el spinner para siempre sin esto.
    @State private var needsReloadAfterVisibility = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))

            if let ui = image {
                switch presentation {
                case .cover:
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .contain:
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 18)
                        .overlay(Color.black.opacity(0.34))
                        .clipped()

                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(6)
                        .clipped()
                }
            } else if loadFinishedWithoutImage {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: slot.id) {
            await loadImageForSlot(resetState: true)
        }
        .onAppear {
            guard needsReloadAfterVisibility else { return }
            needsReloadAfterVisibility = false
            Task { await loadImageForSlot(resetState: false) }
        }
        .onDisappear {
            if image == nil {
                needsReloadAfterVisibility = true
            }
        }
    }

    private func loadImageForSlot(resetState: Bool) async {
        if resetState {
            await MainActor.run {
                image = nil
                loadFinishedWithoutImage = false
            }
        }
        let loaded = await CarUIImageLoader.load(payload: slot.payload, auth: auth)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            if let loaded {
                image = loaded
                loadFinishedWithoutImage = false
            } else {
                loadFinishedWithoutImage = true
            }
        }
    }
}

// MARK: - Flow tags (simple wrap)

private struct FlowTagRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content() }
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 20) {
                CarListingCard(car: MockData.cars[0], isSelected: true)
                CarListingCard(car: MockData.cars[1], isSelected: false)
            }
            .padding()
        }
    }
    .environmentObject(AuthViewModel())
    .environmentObject(ChatInboxStore())
}
