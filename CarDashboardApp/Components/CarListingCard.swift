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

struct CarListingCard: View {
    @EnvironmentObject private var auth: AuthViewModel

    let car: Car
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @State private var galleryIndex = 0

    private var imageSlots: [CarImageSlot] {
        car.resolvedImageSlots
    }

    private let cardCornerRadius: CGFloat = 18
    private let horizontalPadding: CGFloat = 11

    var body: some View {
        Button(action: onSelect) {
            listingCardInterior
            .padding(.vertical, 2)
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
            listingCardMainRow

            VStack(alignment: .leading, spacing: 6) {
                tagsRow

                if car.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ListingPalette.secondary)
                        Text("Vehículo conectado en tu cuenta")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ListingPalette.tertiary)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listingCardMainRow: some View {
        HStack(alignment: .top, spacing: 0) {
            listingThumbnailFlushLeft

            VStack(alignment: .leading, spacing: 5) {
                Text(car.name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(ListingPalette.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !car.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(car.model)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ListingPalette.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

                goldPricePill

                secondaryPriceLine

                if let meta = metaDetailLine {
                    Text(meta)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ListingPalette.tertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, horizontalPadding)
        }
    }

    // MARK: - Miniatura a ras del borde izquierdo; ancho ~52 %; alto = fila de texto

    private var listingThumbnailFlushLeft: some View {
        listingThumbnailCore
            .containerRelativeFrame(.horizontal) { width, _ in
                let w = (width.isFinite && width > 1) ? width : 320
                return min(210, max(132, w * 0.52))
            }
            .aspectRatio(1 / 0.66, contentMode: .fit)
            // Evita CAMetalLayer drawable 0×0 cuando el layout aún no propaga tamaño (LazyVStack).
            .frame(minWidth: 160, minHeight: 104)
            .clipped()
    }

    private var listingThumbnailCore: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if imageSlots.isEmpty {
                    ZStack {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Image(systemName: car.icon)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                } else if imageSlots.count == 1, let only = imageSlots.first {
                    CarHeroImageSlotView(slot: only)
                } else {
                    TabView(selection: $galleryIndex) {
                        ForEach(Array(imageSlots.enumerated()), id: \.element.id) { idx, slot in
                            CarHeroImageSlotView(slot: slot)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if imageSlots.count > 1 {
                Text("\(galleryIndex + 1)/\(imageSlots.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(4)
            }
        }
    }

    // MARK: - Precio (pastilla negra + borde dorado)

    private var goldPricePill: some View {
        Text(listPriceText)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(ListingPalette.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(ListingPalette.pricePillFill, in: Capsule())
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(ListingPalette.goldBorder, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var secondaryPriceLine: some View {
        if let cuota = car.monthlyPaymentEUR {
            Text("\(formatDecimalES(cuota)) €/mes*")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ListingPalette.secondary)
        } else if let fin = car.financedPriceEUR {
            Text("Financiado \(formatEUR(fin))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ListingPalette.tertiary)
        }
    }

    private var listPriceText: String {
        guard let p = car.listPriceEUR else { return "Consultar" }
        return "\(formatIntegerES(Int(p.rounded()))) €"
    }

    /// Transmisión, color exterior y ubicación cuando existan en datos.
    private var metaDetailLine: String? {
        var parts: [String] = []
        if let t = car.transmission?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            parts.append(t)
        }
        if let c = car.exteriorColorLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            parts.append(c)
        }
        if let loc = car.locationText?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            parts.append(loc)
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var tagsRow: some View {
        FlowTagRow {
            if car.isReservable == true {
                tagPill("Reservable", fill: ListingPalette.tagFill, foreground: ListingPalette.primary)
            }
            if let sk = car.sellerKind, !sk.isEmpty {
                HStack(spacing: 4) {
                    Text(sk)
                        .font(.system(size: 12, weight: .semibold))
                    if let r = car.sellerRating {
                        Text(String(format: "%.1f", r))
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                    }
                }
                .foregroundStyle(ListingPalette.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ListingPalette.tagFill, in: Capsule())
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(ListingPalette.tagStroke, lineWidth: 0.5)
                }
            }
            if let dgt = car.dgtLabel, !dgt.isEmpty {
                tagPill("DGT \(dgt)", fill: ListingPalette.tagFill, foreground: ListingPalette.secondary)
            }
        }
    }

    private func tagPill(_ text: String, fill: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(ListingPalette.tagStroke, lineWidth: 0.5)
            }
    }

    private func formatEUR(_ value: Double) -> String {
        "\(formatIntegerES(Int(value.rounded()))) €"
    }

    private func formatIntegerES(_ v: Int) -> String {
        v.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))
    }

    private func formatDecimalES(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "es_ES")
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        return nf.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}

// MARK: - Imagen de slot (miniatura o página de galería)

private struct CarHeroImageSlotView: View {
    @EnvironmentObject private var auth: AuthViewModel
    let slot: CarImageSlot

    @State private var image: UIImage?
    @State private var loadFinishedWithoutImage = false
    /// Si la fila sale del `LazyVStack`, SwiftUI cancela `.task` y puede quedar el spinner para siempre sin esto.
    @State private var needsReloadAfterVisibility = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))

            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
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
}
