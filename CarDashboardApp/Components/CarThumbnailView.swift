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

    @State private var loadedImage: UIImage?

    var body: some View {
        let accent = car.accentSwiftUIColor
        ZStack {
            Circle()
                .fill(accent.opacity(0.15))
                .frame(width: size, height: size)

            if let ui = loadedImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .clipShape(Circle())
            } else if car.hasImagePayload {
                ProgressView()
                    .scaleEffect(0.65)
            } else {
                fallbackIcon(accent: accent)
            }
        }
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
        Image(systemName: car.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
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
