import Foundation
import Supabase
import UIKit

/// Lectura de perfil Supabase (`profiles`) y descarga del avatar (Storage o URL).
enum UserProfileService {
    private struct NotifyTeamPushRow: Decodable {
        let notifyTeamPush: Bool?
        enum CodingKeys: String, CodingKey {
            case notifyTeamPush = "notify_team_push"
        }
    }

    private struct NotifyTeamPushUpdate: Encodable {
        let notifyTeamPush: Bool
        enum CodingKeys: String, CodingKey {
            case notifyTeamPush = "notify_team_push"
        }
    }

    /// Preferencia de push de equipo (mensajes/tareas). Si no hay fila o la columna es null, se asume activado.
    static func fetchNotifyTeamPush(userId: UUID, client: SupabaseClient) async -> Bool {
        for value in [userId.uuidString.lowercased(), userId.uuidString] {
            do {
                let rows: [NotifyTeamPushRow] = try await client
                    .from(SupabaseClientProvider.profilesTableName)
                    .select("notify_team_push")
                    .eq("user_id", value: value)
                    .limit(1)
                    .execute()
                    .value
                if let v = rows.first?.notifyTeamPush { return v }
            } catch {}
        }
        return true
    }

    static func setNotifyTeamPush(_ enabled: Bool, userId: UUID, client: SupabaseClient) async throws {
        let payload = NotifyTeamPushUpdate(notifyTeamPush: enabled)
        try await client
            .from(SupabaseClientProvider.profilesTableName)
            .update(payload)
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
    }

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
        for value in [userId.uuidString.lowercased(), userId.uuidString] {
            do {
                let row: ProfileAvatarRow = try await client
                    .from(SupabaseClientProvider.profilesTableName)
                    .select("avatar_url")
                    .eq("user_id", value: value)
                    .single()
                    .execute()
                    .value
                let s = row.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let s, !s.isEmpty { return s }
            } catch {}
        }
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

    // MARK: - Avatar local + subida

    enum AvatarUploadError: LocalizedError {
        case encodingFailed
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Could not process the image."
            case .notAuthenticated: return "Sign in to save your photo."
            }
        }
    }

    private struct ProfileAvatarUpsert: Encodable {
        let userId: String
        let avatarUrl: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case avatarUrl = "avatar_url"
        }
    }

    static func localAvatarFileURL(userId: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("groo-avatar-\(userId.uuidString.lowercased()).jpg")
    }

    static func saveLocalAvatar(_ image: UIImage, userId: UUID) {
        let resized = resizeAvatar(image)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        let url = localAvatarFileURL(userId: userId)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func loadLocalAvatar(userId: UUID) -> UIImage? {
        let url = localAvatarFileURL(userId: userId)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data), image.size.width > 0 else {
            return nil
        }
        return image
    }

    static func uploadProfileAvatar(
        image: UIImage,
        userId: UUID,
        client: SupabaseClient
    ) async throws -> String {
        let resized = resizeAvatar(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else {
            throw AvatarUploadError.encodingFailed
        }

        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        let bucket = SupabaseClientProvider.userAvatarBucket

        _ = try await client.storage
            .from(bucket)
            .upload(
                path,
                data: jpeg,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        let payload = ProfileAvatarUpsert(userId: userId.uuidString.lowercased(), avatarUrl: path)
        try await client
            .from(SupabaseClientProvider.profilesTableName)
            .upsert(payload)
            .execute()

        ImageCacheService.shared.remove(forKey: "profileAvatar:\(userId.uuidString.lowercased()):\(path)")
        return path
    }

    private static func resizeAvatar(_ image: UIImage, maxSide: CGFloat = 512) -> UIImage {
        let size = image.size
        guard size.width > maxSide || size.height > maxSide else { return image }
        let scale = min(maxSide / size.width, maxSide / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
