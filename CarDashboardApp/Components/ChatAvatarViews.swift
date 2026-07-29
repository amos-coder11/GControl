import SwiftUI
import UIKit

// MARK: - Insignia red social (assets SVG + estilos para IG / WA / FB)

struct ChatSocialBadgeView: View {
    let platform: ChatSocialPlatform

    var body: some View {
        Group {
            switch platform {
            case .instagram:
                DrflowSocialIcon(platform: .instagram, size: 9)
            case .whatsApp:
                ZStack {
                    Circle()
                        .fill(Color(red: 0.15, green: 0.78, blue: 0.41))
                    Image(systemName: "phone.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            case .facebook:
                DrflowSocialIcon(platform: .facebook, size: 9)
            }
        }
    }
}

// MARK: - Avatar lista / toolbar (foto de contacto + insignia)

struct ChatThreadAvatarView: View {
    let thread: ChatThread
    var accessToken: String?
    var diameter: CGFloat = 56

    private var badgeSize: CGFloat { max(18, diameter * 0.38) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = thread.avatarCarURL {
                    ChatAsyncContactPhoto(
                        url: url,
                        accessToken: accessToken,
                        fallbackInitial: thread.avatarInitial,
                        fallbackColor: thread.avatarColor,
                        diameter: diameter
                    )
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        thread.avatarColor.opacity(0.95),
                                        thread.avatarColor.opacity(0.62),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .frame(width: diameter, height: diameter)
                            .shadow(color: thread.avatarColor.opacity(0.45), radius: diameter * 0.10, x: 0, y: 1)
                        if let initial = thread.avatarInitial, let ch = initial.first {
                            Text(String(ch).uppercased())
                                .font(.system(size: diameter * 0.40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        } else if let icon = thread.avatarIcon {
                            Image(systemName: icon)
                                .font(.system(size: diameter * 0.42, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            // La insignia de la red (WhatsApp / Instagram…) se muestra SIEMPRE que el
            // hilo tenga red de origen, haya foto o solo inicial.
            if let platform = thread.socialSource {
                ChatSocialBadgeView(platform: platform)
                    .frame(width: badgeSize - 4, height: badgeSize - 4)
                    .padding(2)
                    .background(Circle().fill(Color.white))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 1.5)
                    }
                    .offset(x: diameter * 0.06, y: diameter * 0.06)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Lista Chat: equipo con fotos del directorio (como en Inicio)

/// Foto de perfil de una fila del directorio (misma carga que el carrusel «Mi equipo»).
struct TeamDirectoryProfileAvatar: View {
    let row: CommunityProfilesService.DirectoryRow
    var accessToken: String?
    var diameter: CGFloat
    var localAvatarImage: UIImage?
    var localInitialsOverride: String?

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            if let img = localAvatarImage ?? loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.45, blue: 0.95),
                                Color(red: 0.45, green: 0.25, blue: 0.85),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(initials(for: row.resolvedDisplayName))
                    .font(.system(size: diameter * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: row.id) {
            guard localAvatarImage == nil else {
                loadedImage = nil
                return
            }
            loadedImage = await UserProfileService.loadProfileAvatarImage(
                avatarRef: row.avatarUrl,
                userId: row.userId,
                client: SupabaseClientProvider.shared,
                accessToken: accessToken
            )
        }
    }

    private func initials(for name: String) -> String {
        if let o = localInitialsOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty {
            return String(o.prefix(2)).uppercased()
        }
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        if let f = name.first { return String(f).uppercased() }
        return "?"
    }
}

/// Varias caras del equipo (sin el usuario actual) para el hilo de grupo.
struct TeamGroupChatListAvatar: View {
    let peers: [CommunityProfilesService.DirectoryRow]
    var accessToken: String?
    var diameter: CGFloat

    private var shown: [CommunityProfilesService.DirectoryRow] {
        Array(peers.prefix(3))
    }

    private var smallD: CGFloat { max(22, diameter * 0.48) }

    var body: some View {
        Group {
            if shown.isEmpty {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.62, blue: 0.92))
                    Image(systemName: "person.3.fill")
                        .font(.system(size: diameter * 0.38, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: diameter, height: diameter)
            } else {
                ZStack {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        TeamDirectoryProfileAvatar(
                            row: row,
                            accessToken: accessToken,
                            diameter: smallD,
                            localAvatarImage: nil,
                            localInitialsOverride: nil
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(Color(red: 0.06, green: 0.07, blue: 0.1), lineWidth: 1.5)
                        }
                        .offset(groupOffset(index: index, total: shown.count))
                    }
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }

    private func groupOffset(index: Int, total: Int) -> CGSize {
        switch total {
        case 1:
            return .zero
        case 2:
            return index == 0 ? CGSize(width: -smallD * 0.22, height: 2) : CGSize(width: smallD * 0.22, height: -2)
        default:
            switch index {
            case 0: return CGSize(width: -smallD * 0.28, height: smallD * 0.12)
            case 1: return CGSize(width: smallD * 0.26, height: -smallD * 0.2)
            default: return CGSize(width: smallD * 0.2, height: smallD * 0.28)
            }
        }
    }
}

/// Avatar en la lista de Chat: leads con coche/insignia; equipo con fotos reales del directorio.
struct ChatInboxListAvatarView: View {
    let thread: ChatThread
    let directory: [CommunityProfilesService.DirectoryRow]
    var accessToken: String?
    var currentUserId: UUID?
    var localProfileImage: UIImage?
    var localInitials: String?
    var diameter: CGFloat = 56

    private var teamPeersExcludingSelf: [CommunityProfilesService.DirectoryRow] {
        directory
            .filter { $0.userId != currentUserId }
            .sorted {
                $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
            }
    }

    var body: some View {
        switch thread.kind {
        case .teamDirect:
            if let row = directory.first(where: { $0.userId == thread.peerUserId }) {
                TeamDirectoryProfileAvatar(
                    row: row,
                    accessToken: accessToken,
                    diameter: diameter,
                    localAvatarImage: row.userId == currentUserId ? localProfileImage : nil,
                    localInitialsOverride: row.userId == currentUserId ? localInitials : nil
                )
            } else {
                ChatThreadAvatarView(thread: thread, diameter: diameter)
            }
        case .teamGroup:
            TeamGroupChatListAvatar(
                peers: teamPeersExcludingSelf,
                accessToken: accessToken,
                diameter: diameter
            )
        case .lead:
            ChatThreadAvatarView(thread: thread, accessToken: accessToken, diameter: diameter)
        }
    }
}

// MARK: - Miniatura remota (misma idea que el showroom del dashboard)

// MARK: - Miniatura remota (coche en muestras / leads sin foto de contacto)

/// Foto de perfil de contacto WhatsApp/Instagram (con auth al CRM si hace falta).
struct ChatAsyncContactPhoto: View {
    let url: URL
    var accessToken: String?
    var fallbackInitial: String?
    var fallbackColor: Color
    var diameter: CGFloat

    @State private var uiImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                fallbackCircle
            } else {
                Color(white: 0.94)
                    .overlay { ProgressView() }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        "\(url.absoluteString)|\(accessToken ?? "")"
    }

    private var fallbackCircle: some View {
        let seed = fallbackInitial ?? "?"
        let color = GrooAvatarPalette.color(for: seed)
        return Circle()
            .fill(color)
            .overlay {
                if let initial = fallbackInitial?.first {
                    Text(String(initial).uppercased())
                        .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.55, green: 0.12, blue: 0.72))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
    }

    private func load() async {
        loadFailed = false
        uiImage = nil
        let img = await CrmContactPhotoLoader.load(url: url, accessToken: accessToken)
        await MainActor.run {
            if let img {
                uiImage = img
            } else {
                loadFailed = true
            }
        }
    }
}
