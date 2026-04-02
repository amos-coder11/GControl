import SwiftUI
import Supabase
import UIKit

extension Car {
    var accentSwiftUIColor: Color {
        switch color {
        case "orange": return .orange
        case "mint": return .mint
        default: return .cyan
        }
    }

    var imageLoadIdentity: String {
        if !resolvedImageSlots.isEmpty {
            return ([id.uuidString] + resolvedImageSlots.map(\.id)).joined(separator: "\u{1e}")
        }
        return [
            id.uuidString,
            imageURLString ?? "",
            imagePublicVehiclesFileName ?? "",
            imageSignedStoragePath ?? "",
            imageSignedStorageBucket ?? "",
            imageBase64.map { String($0.prefix(64)) } ?? "",
        ].joined(separator: "\u{1e}")
    }

    var hasImagePayload: Bool {
        !resolvedImageSlots.isEmpty
    }

    var imageURL: URL? {
        guard let s = imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return VehicleImageResolution.resolvedHTTPURL(from: s)
    }
}

/// Miniatura: base64, descarga autenticada (`storage.download`) o URL firmada / pública.
struct CarThumbnailView: View {
    @EnvironmentObject private var auth: AuthViewModel
    let car: Car
    var size: CGFloat = 52
    /// Si se definen, sustituyen el cuadrado `size` (miniaturas rectangulares en carruseles).
    var width: CGFloat?
    var height: CGFloat?
    /// Recorte redondeado tipo tarjeta de galería en lugar de círculo.
    var roundedCardClip: Bool = false

    @State private var loadedImage: UIImage?

    private var thumbW: CGFloat { width ?? size }
    private var thumbH: CGFloat { height ?? size }

    private var roundedRadius: CGFloat {
        min(thumbW, thumbH) * (roundedCardClip ? 0.14 : 0.5)
    }

    var body: some View {
        let accent = car.accentSwiftUIColor
        ZStack {
            Group {
                if roundedCardClip {
                    RoundedRectangle(cornerRadius: roundedRadius, style: .continuous)
                        .fill(accent.opacity(0.12))
                } else {
                    Circle()
                        .fill(accent.opacity(0.15))
                }
            }
            .frame(width: thumbW, height: thumbH)

            if let ui = loadedImage {
                Group {
                    if roundedCardClip {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbW, height: thumbH)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: roundedRadius, style: .continuous))
                    } else {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbW, height: thumbH)
                            .clipped()
                            .clipShape(Circle())
                    }
                }
            } else if car.hasImagePayload {
                ProgressView()
                    .scaleEffect(0.65)
            } else {
                fallbackIcon(accent: accent)
            }
        }
        .frame(width: thumbW, height: thumbH)
        .task(id: car.imageLoadIdentity) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        // No reseteamos loadedImage a nil para evitar el flash del spinner
        // si la imagen ya estaba cargada (ej. al recomponer la vista).
        if let ui = await CarUIImageLoader.load(car: car, auth: auth) {
            loadedImage = ui
        } else if loadedImage == nil {
            // Solo dejamos nil si no teníamos nada antes
            loadedImage = nil
        }
    }

    private func fallbackIcon(accent: Color) -> some View {
        let s = min(thumbW, thumbH)
        return Image(systemName: car.icon)
            .font(.system(size: s * 0.42, weight: .semibold))
            .foregroundStyle(accent)
    }
}

#Preview {
    HStack {
        CarThumbnailView(
            car: Car(name: "Demo", model: "GLA", plate: "1111-BBB", year: 2020)
        )
        CarThumbnailView(
            car: Car(
                name: "Demo",
                model: "GLA",
                plate: "1111-BBB",
                year: 2020,
                color: "orange",
                imageURLString: "https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=200"
            ),
            size: 60
        )
    }
    .padding()
    .environmentObject(AuthViewModel())
}
