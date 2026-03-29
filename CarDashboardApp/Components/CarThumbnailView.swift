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
        [
            id.uuidString,
            imageURLString ?? "",
            imagePublicVehiclesFileName ?? "",
            imageSignedStoragePath ?? "",
            imageSignedStorageBucket ?? "",
            imageBase64.map { String($0.prefix(64)) } ?? "",
        ].joined(separator: "\u{1e}")
    }

    var hasImagePayload: Bool {
        imageBase64 != nil
            || imageURLString != nil
            || imagePublicVehiclesFileName != nil
            || imageSignedStoragePath != nil
    }

    var imageURL: URL? {
        guard let s = imageURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return u
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
        loadedImage = nil
        print("🖼️ [\(car.name)] loadImage START — hasPayload=\(car.hasImagePayload) | b64=\(car.imageBase64 != nil) | publicFile=\(car.imagePublicVehiclesFileName ?? "nil") | signedPath=\(car.imageSignedStoragePath ?? "nil") | url=\(car.imageURLString ?? "nil")")

        // 1) Base64
        if let b64 = car.imageBase64,
           let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]),
           let ui = UIImage(data: data),
           ui.size.width > 0 {
            print("🖼️ [\(car.name)] ✅ loaded from base64")
            loadedImage = ui
            return
        }

        // 2) Public bucket file name
        if let path = car.imagePublicVehiclesFileName {
            print("🖼️ [\(car.name)] trying public bucket '\(SupabaseClientProvider.publicVehiclesBucket)' path='\(path)'")
            do {
                let data = try await SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .download(path: path)
                print("🖼️ [\(car.name)] public download got \(data.count) bytes")
                if let ui = UIImage(data: data), ui.size.width > 0 {
                    print("🖼️ [\(car.name)] ✅ loaded from public bucket download")
                    loadedImage = ui
                    return
                } else {
                    print("🖼️ [\(car.name)] ⚠️ public download data could not be decoded as image")
                }
            } catch {
                print("🖼️ [\(car.name)] ❌ public bucket download error: \(error)")
            }
            // Fallback: try getPublicURL
            do {
                let url = try SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .getPublicURL(path: path)
                print("🖼️ [\(car.name)] trying public URL fallback: \(url)")
                await loadFromRemoteURL(url)
                if loadedImage != nil {
                    print("🖼️ [\(car.name)] ✅ loaded from public URL fallback")
                    return
                }
            } catch {
                print("🖼️ [\(car.name)] ❌ getPublicURL error: \(error)")
            }
            return
        }

        // 3) Signed/private storage
        if let path = car.imageSignedStoragePath {
            let bucket = car.imageSignedStorageBucket ?? SupabaseClientProvider.vehicleMediaBucket
            print("🖼️ [\(car.name)] trying signed storage bucket='\(bucket)' path='\(path)'")
            do {
                let data = try await SupabaseClientProvider.shared.storage.from(bucket).download(path: path)
                print("🖼️ [\(car.name)] signed download got \(data.count) bytes")
                if let ui = UIImage(data: data), ui.size.width > 0 {
                    print("🖼️ [\(car.name)] ✅ loaded from signed bucket download")
                    loadedImage = ui
                    return
                } else {
                    print("🖼️ [\(car.name)] ⚠️ signed download data could not be decoded as image")
                }
            } catch {
                print("🖼️ [\(car.name)] ❌ signed bucket download error: \(error)")
            }
            // Fallback: signed URL
            do {
                let signed = try await SupabaseClientProvider.shared.storage
                    .from(bucket)
                    .createSignedURL(path: path, expiresIn: 3600)
                print("🖼️ [\(car.name)] trying signed URL fallback: \(signed)")
                await loadFromRemoteURL(signed)
                if loadedImage != nil {
                    print("🖼️ [\(car.name)] ✅ loaded from signed URL fallback")
                    return
                }
            } catch {
                print("🖼️ [\(car.name)] ❌ createSignedURL error: \(error)")
            }

            // 🆕 Fallback: also try the public bucket in case the path was misclassified
            print("🖼️ [\(car.name)] trying cross-bucket fallback with public bucket for path='\(path)'")
            do {
                let data = try await SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .download(path: path)
                if let ui = UIImage(data: data), ui.size.width > 0 {
                    print("🖼️ [\(car.name)] ✅ loaded from cross-bucket fallback (public)")
                    loadedImage = ui
                    return
                }
            } catch {
                print("🖼️ [\(car.name)] ❌ cross-bucket fallback error: \(error)")
            }
            return
        }

        // 4) Direct URL
        if let u = car.imageURL {
            print("🖼️ [\(car.name)] trying direct URL: \(u)")
            await loadFromRemoteURL(u)
            if loadedImage != nil {
                print("🖼️ [\(car.name)] ✅ loaded from direct URL")
            } else {
                print("🖼️ [\(car.name)] ❌ direct URL failed")
            }
            return
        }

        print("🖼️ [\(car.name)] ⚠️ no image source available — showing fallback icon")
    }

    @MainActor
    private func loadFromRemoteURL(_ url: URL) async {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        // Only add Supabase headers for Supabase URLs
        let isSupabaseURL = url.host?.contains("supabase") == true
        if isSupabaseURL {
            request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
            if let token = auth.session?.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("Bearer \(SupabaseClientProvider.anonKey)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("🖼️ [\(car.name)] loadFromRemoteURL: not an HTTP response")
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                let body = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
                print("🖼️ [\(car.name)] loadFromRemoteURL HTTP \(http.statusCode) for \(url) — body: \(body)")
                return
            }
            guard let ui = UIImage(data: data), ui.size.width > 0 else {
                print("🖼️ [\(car.name)] loadFromRemoteURL: \(data.count) bytes but not a valid image")
                return
            }
            loadedImage = ui
        } catch {
            print("🖼️ [\(car.name)] loadFromRemoteURL error for \(url): \(error)")
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
