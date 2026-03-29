import SwiftUI
import UIKit

/// Texto de ficha sobre fondo mesh oscuro: todo legible en blanco / gris muy claro.
private enum ListingPalette {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.82)
    static let tertiary = Color.white.opacity(0.68)
    static let accentLine = Color.white.opacity(0.5)
    static let tagFill = Color.white.opacity(0.12)
    static let tagStroke = Color.white.opacity(0.22)
}

struct CarListingCard: View {
    @EnvironmentObject private var auth: AuthViewModel

    let car: Car
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @State private var isFavorite = false
    @State private var galleryIndex = 0

    private var imageSlots: [CarImageSlot] {
        car.resolvedImageSlots
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 14) {
                    titleRow

                    priceBlock

                    specRow

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

                    Text("* Financiación orientativa. Cuota y TAE sujetas a estudio.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(ListingPalette.tertiary)
                        .padding(.top, 2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onAppear {
            // Prefetch todas las fotos de la galería de este coche
            CarUIImageLoader.prefetchGallery(car: car, auth: auth)
        }
        .onChange(of: car.id) { _, _ in galleryIndex = 0 }
        .onChange(of: imageSlots.count) { _, newCount in
            if newCount == 0 {
                galleryIndex = 0
            } else if galleryIndex >= newCount {
                galleryIndex = newCount - 1
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(1.15, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    Group {
                        if imageSlots.isEmpty {
                            heroPlaceholder
                        } else if imageSlots.count == 1, let only = imageSlots.first {
                            CarHeroImageSlotView(slot: only, car: car)
                        } else {
                            TabView(selection: $galleryIndex) {
                                ForEach(Array(imageSlots.enumerated()), id: \.element.id) { idx, slot in
                                    CarHeroImageSlotView(slot: slot, car: car)
                                        .tag(idx)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            .allowsHitTesting(false)

            if !imageSlots.isEmpty {
                Text("\(galleryIndex + 1)/\(imageSlots.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 10,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 10
                ),
                style: .continuous
            )
        )
    }

    private var heroPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))
            Image(systemName: car.icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(car.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ListingPalette.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            HStack(spacing: 14) {
                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.red : Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Marcar como vehículo activo", action: onSelect)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                }
            }
        }
    }

    private var priceBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ListingPalette.accentLine)
                    .frame(width: 36, height: 4)

                Text("Precio al contado")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ListingPalette.secondary)

                Text(listPriceText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ListingPalette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Text("IVA y gestión según anuncio")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ListingPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if let fin = car.financedPriceEUR {
                    Text("Precio financiado")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ListingPalette.secondary)
                    Text(formatEUR(fin))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ListingPalette.primary)
                }

                if let cuota = car.monthlyPaymentEUR {
                    Text("\(formatDecimalES(cuota)) €/mes*")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ListingPalette.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var listPriceText: String {
        guard let p = car.listPriceEUR else { return "Consultar" }
        return "\(formatIntegerES(Int(p.rounded()))) €"
    }

    private var specRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ListingPalette.accentLine)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(specLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ListingPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var specLine: String {
        var parts: [String] = []
        if let f = car.fuelType, !f.isEmpty { parts.append(f) }
        parts.append(String(car.year))
        if let km = car.mileageKm {
            parts.append("\(km.formatted(.number.grouping(.automatic).locale(Locale(identifier: "es_ES")))) km")
        } else {
            parts.append("Km —")
        }
        if let cv = car.powerCv { parts.append("\(cv) cv") }
        if let loc = car.locationText, !loc.isEmpty { parts.append(loc) }
        if parts.isEmpty { return "\(car.model) · \(car.plate)" }
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

// MARK: - Hero (una foto de la galería)

private struct CarHeroImageSlotView: View {
    @EnvironmentObject private var auth: AuthViewModel
    let slot: CarImageSlot
    let car: Car

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))

            if let ui = image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: slot.id) {
            // No reseteamos a nil para evitar flash del spinner si ya teníamos imagen
            let loaded = await CarUIImageLoader.load(payload: slot.payload, auth: auth)
            if let loaded {
                image = loaded
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
    ScrollView {
        CarListingCard(car: MockData.cars[0], isSelected: true)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
    .environmentObject(AuthViewModel())
}
