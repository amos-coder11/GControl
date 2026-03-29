import Foundation
import Supabase
import UIKit

/// Lectura de perfil Supabase (`profiles`) y descarga del avatar (Storage o URL).
enum UserProfileService {
    private struct ProfileAvatarRow: Decodable {
        let avatarUrl: String?
        enum CodingKeys: String, CodingKey {
            case avatarUrl = "avatar_url"
        }
    }

    /// Referencia a imagen: URL absoluta o ruta dentro del bucket de avatares.
    static func resolveAvatarRef(user: User, client: SupabaseClient) async -> String? {
        if let fromTable = await fetchAvatarURLFromProfiles(userId: user.id, client: client) {
            return fromTable
        }
        return avatarRefFromUserMetadata(user)
    }

    private static func fetchAvatarURLFromProfiles(userId: UUID, client: SupabaseClient) async -> String? {
        do {
            let row: ProfileAvatarRow = try await client
                .from(SupabaseClientProvider.profilesTableName)
                .select("avatar_url")
                .eq("id", value: userId.uuidString.lowercased())
                .single()
                .execute()
                .value
            let s = row.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s, !s.isEmpty { return s }
        } catch {}

        do {
            let row: ProfileAvatarRow = try await client
                .from(SupabaseClientProvider.profilesTableName)
                .select("avatar_url")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            let s = row.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s, !s.isEmpty { return s }
        } catch {}

        return nil
    }

    private static func avatarRefFromUserMetadata(_ user: User) -> String? {
        let keys = ["avatar_url", "picture", "photo_url", "avatarUrl"]
        for k in keys {
            if let s = user.userMetadata[k]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    @MainActor
    static func loadProfileAvatarImage(
        avatarRef: String?,
        userId: UUID,
        client: SupabaseClient,
        accessToken: String?
    ) async -> UIImage? {
        guard let ref = avatarRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }

        let cacheKey = "profileAvatar:\(userId.uuidString.lowercased()):\(ref)"
        if let cached = ImageCacheService.shared.image(forKey: cacheKey) {
            return cached
        }

        let image: UIImage?
        let lower = ref.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            image = await downloadHTTP(urlString: ref, accessToken: accessToken)
        } else {
            var fromStorage = await downloadFromStorage(path: ref, client: client, accessToken: accessToken)
            if fromStorage == nil {
                fromStorage = await downloadHTTP(
                    urlString: SupabaseClientProvider.publicStorageObjectURL(
                        bucket: SupabaseClientProvider.userAvatarBucket,
                        path: ref
                    ),
                    accessToken: accessToken
                )
            }
            image = fromStorage
        }

        if let image {
            ImageCacheService.shared.store(image, forKey: cacheKey)
        }
        return image
    }

    @MainActor
    private static func downloadHTTP(urlString: String, accessToken: String?) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        let isSupabaseURL = url.host?.contains("supabase") == true
        if isSupabaseURL {
            request.setValue(SupabaseClientProvider.anonKey, forHTTPHeaderField: "apikey")
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

    @MainActor
    private static func downloadFromStorage(path: String, client: SupabaseClient, accessToken: String?) async -> UIImage? {
        let bucket = SupabaseClientProvider.userAvatarBucket
        do {
            let data = try await client.storage.from(bucket).download(path: path)
            if let ui = UIImage(data: data), ui.size.width > 0 { return ui }
        } catch {}

        do {
            let signed = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
            return await downloadHTTP(urlString: signed.absoluteString, accessToken: accessToken)
        } catch {}

        return nil
    }
}
