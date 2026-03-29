import Foundation
import Supabase
import UIKit

/// Carga la imagen de un `Car` desde base64, Storage o URL (misma lógica que la miniatura).
enum CarUIImageLoader {
    @MainActor
    static func load(car: Car, auth: AuthViewModel) async -> UIImage? {
        guard let first = car.resolvedImageSlots.first else { return nil }
        return await load(payload: first.payload, auth: auth)
    }

    @MainActor
    static func load(payload: CarImageSlot.Payload, auth: AuthViewModel) async -> UIImage? {
        switch payload {
        case let .base64(b64):
            guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]),
                  let ui = UIImage(data: data),
                  ui.size.width > 0 else { return nil }
            return ui

        case let .publicVehiclesFile(path):
            do {
                let data = try await SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .download(path: path)
                if let ui = UIImage(data: data), ui.size.width > 0 { return ui }
            } catch {}

            do {
                let url = try SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .getPublicURL(path: path)
                return await loadFromRemoteURL(url, auth: auth)
            } catch {}
            return nil

        case let .signed(bucket, path):
            do {
                let data = try await SupabaseClientProvider.shared.storage.from(bucket).download(path: path)
                if let ui = UIImage(data: data), ui.size.width > 0 { return ui }
            } catch {}

            do {
                let signed = try await SupabaseClientProvider.shared.storage
                    .from(bucket)
                    .createSignedURL(path: path, expiresIn: 3600)
                return await loadFromRemoteURL(signed, auth: auth)
            } catch {}

            do {
                let data = try await SupabaseClientProvider.shared.storage
                    .from(SupabaseClientProvider.publicVehiclesBucket)
                    .download(path: path)
                if let ui = UIImage(data: data), ui.size.width > 0 { return ui }
            } catch {}
            return nil

        case let .url(s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: t),
                  let scheme = u.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return await loadFromRemoteURL(u, auth: auth)
        }
    }

    @MainActor
    private static func loadFromRemoteURL(_ url: URL, auth: AuthViewModel) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

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
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
            guard let ui = UIImage(data: data), ui.size.width > 0 else { return nil }
            return ui
        } catch {
            return nil
        }
    }
}
