import SwiftUI
import UIKit

// MARK: - Contenido compartido del chat

enum ChatPeerProfileTab: String, CaseIterable, Identifiable {
    case media = "Media"
    case files = "Archivos"
    case music = "Música"
    case voice = "Voz"
    case links = "Enlaces"

    var id: String { rawValue }
}

struct ChatPeerMediaItem: Identifiable {
    let id: UUID
    var remoteURL: URL?
    var localImage: UIImage?
    var timeLabel: String
}

struct ChatPeerFileItem: Identifiable {
    let id: UUID
    var title: String
    var timeLabel: String
}

struct ChatPeerVoiceItem: Identifiable {
    let id: UUID
    var remoteURL: URL?
    var storagePath: String?
    var timeLabel: String
    var isOutgoing: Bool
}

struct ChatPeerLinkItem: Identifiable {
    let id: UUID
    var url: URL
    var title: String
    var timeLabel: String
}

struct ChatPeerMemberItem: Identifiable {
    let id: UUID
    var name: String
    var avatarURL: URL?
    var isOwner: Bool
    var isOnline: Bool
    var isSelf: Bool
}

struct ChatPeerSharedLibrary {
    var media: [ChatPeerMediaItem] = []
    var files: [ChatPeerFileItem] = []
    var voices: [ChatPeerVoiceItem] = []
    var links: [ChatPeerLinkItem] = []
}

// MARK: - Perfil Telegram (foto con animación Dynamic Island como Settings)

struct ChatPeerProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthViewModel

    let thread: ChatThread
    var subtitle: String
    var members: [ChatPeerMemberItem]
    var library: ChatPeerSharedLibrary
    var accessToken: String?

    @State private var scrollProgress: CGFloat = 0
    @State private var textHeaderOffset: CGFloat = 0
    @State private var selectedTab: ChatPeerProfileTab = .media
    @State private var isMuted = false
    @State private var lightboxItem: GrooChatImageLightboxItem?

    private static let screenBackground = Color(red: 0.949, green: 0.949, blue: 0.969)
    private static let telegramBlue = Color(red: 0.22, green: 0.48, blue: 0.98)
    private static let scrollSpace = "PEER_PROFILE_SCROLL"

    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            profileScroll(safeArea: safeArea)
                .ignoresSafeArea()
        }
        .background(Self.screenBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .enableSwipeBackToPop()
        .fullScreenCover(item: $lightboxItem) { item in
            GrooChatImageLightbox(item: item)
        }
    }

    @ViewBuilder
    private func profileScroll(safeArea: EdgeInsets) -> some View {
        let isHavingNotch = safeArea.bottom != 0
        let fixedTop: CGFloat = safeArea.top + 3
        let isNamePinned = textHeaderOffset < fixedTop

        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                profileHeaderPhoto
                    .frame(
                        width: 130 - (75 * scrollProgress),
                        height: 130 - (75 * scrollProgress)
                    )
                    .opacity(1 - scrollProgress)
                    .blur(radius: scrollProgress * 10, opaque: true)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity)
                    .anchorPreference(key: PeerProfileAnchorKey.self, value: .bounds, transform: {
                        ["HEADER": $0]
                    })
                    .padding(.top, safeArea.top + 15)
                    .peerProfileOffsetExtractor(coordinateSpace: Self.scrollSpace) { scrollRect in
                        guard isHavingNotch else { return }
                        let progress = -scrollRect.minY / 25
                        scrollProgress = min(max(progress, 0), 1)
                    }

                VStack(spacing: isNamePinned ? 0 : 4) {
                    Text(displayTitle)
                        .font(.system(size: isNamePinned ? 17 : 22, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)

                    Text(subtitle.isEmpty ? " " : subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .opacity(isNamePinned ? 0 : 1)
                        .frame(height: isNamePinned ? 0 : nil)
                        .clipped()
                }
                .padding(.vertical, isNamePinned ? 10 : 15)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.18), value: isNamePinned)
                .offset(y: isNamePinned ? -(textHeaderOffset - fixedTop) : 0)
                .peerProfileNameOffsetExtractor(coordinateSpace: Self.scrollSpace) {
                    textHeaderOffset = $0.minY
                }
                .zIndex(1000)

                if !isNamePinned {
                    actionButtonsRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                if thread.kind == .teamGroup || !members.isEmpty {
                    membersCard
                        .padding(.horizontal, 16)
                }

                contentTabs
                    .padding(.horizontal, 16)

                tabContent
                    .padding(.horizontal, selectedTab == .media ? 0 : 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, safeArea.bottom + 28)
        }
        .scrollContentBackground(.hidden)
        .backgroundPreferenceValue(PeerProfileAnchorKey.self) { pref in
            GeometryReader { proxy in
                if let anchor = pref["HEADER"], isHavingNotch {
                    let frameRect = proxy[anchor]
                    let isHavingDynamicIsland = safeArea.top > 51
                    let capsuleHeight = isHavingDynamicIsland ? 37 : (safeArea.top - 15)

                    Canvas { out, canvasSize in
                        out.addFilter(.alphaThreshold(min: 0.5))
                        out.addFilter(.blur(radius: 12))
                        out.drawLayer { ctx in
                            if let headerView = out.resolveSymbol(id: 0) {
                                ctx.draw(headerView, in: frameRect)
                            }
                            if let dynamicIsland = out.resolveSymbol(id: 1) {
                                let rect = CGRect(
                                    x: (canvasSize.width - 120) / 2,
                                    y: isHavingDynamicIsland ? 11 : 0,
                                    width: 120,
                                    height: capsuleHeight
                                )
                                ctx.draw(dynamicIsland, in: rect)
                            }
                        }
                    } symbols: {
                        Circle()
                            .fill(.black)
                            .frame(width: frameRect.width, height: frameRect.height)
                            .tag(0)
                            .id(0)
                        Capsule()
                            .fill(.black)
                            .frame(width: 120, height: capsuleHeight)
                            .tag(1)
                            .id(1)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            GrooChatTheme.floatingBlurChrome()
                .frame(height: safeArea.top + 56)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) {
            topChrome(safeArea: safeArea)
        }
        .coordinateSpace(name: Self.scrollSpace)
    }

    private var displayTitle: String {
        let t = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Chat" : t
    }

    private var profileHeaderPhoto: some View {
        ChatInboxListAvatarView(
            thread: thread,
            accessToken: accessToken,
            currentUserId: auth.session?.user.id,
            localProfileImage: auth.profileAvatarImage,
            localInitials: auth.userInitials,
            diameter: 130,
            showsSocialBadge: false
        )
    }

    private func topChrome(safeArea: EdgeInsets) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.white.opacity(0.7)))
                    }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, safeArea.top + 8)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            actionButton(icon: "doc.text.fill", title: "Historial del paciente")
            actionButton(
                icon: isMuted ? "bell.fill" : "bell.slash.fill",
                title: isMuted ? "Sonido" : "Activar"
            ) {
                isMuted.toggle()
            }
            actionButton(icon: "magnifyingglass", title: "Buscar") {
                selectedTab = .media
            }
            Menu {
                Button("Silenciar", systemImage: isMuted ? "bell" : "bell.slash") {
                    isMuted.toggle()
                }
                Button("Compartir contacto", systemImage: "square.and.arrow.up") {}
            } label: {
                actionButtonLabel(icon: "ellipsis", title: "Más")
            }
        }
    }

    private func actionButton(
        icon: String,
        title: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            actionButtonLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.telegramBlue)
                .frame(height: 22)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.telegramBlue)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        }
    }

    private var membersCard: some View {
        VStack(spacing: 0) {
            if thread.kind == .teamGroup {
                Button { } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.badge.plus.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Self.telegramBlue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Añadir miembros")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Self.telegramBlue)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if !members.isEmpty {
                    Divider().padding(.leading, 64)
                }
            }

            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                HStack(spacing: 12) {
                    memberAvatar(member)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.isSelf ? "Yo" : member.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                        Text(member.isOnline ? "en línea" : "hace poco")
                            .font(.system(size: 13))
                            .foregroundStyle(member.isOnline ? Self.telegramBlue : Color.black.opacity(0.35))
                    }
                    Spacer()
                    if member.isOwner {
                        Text("propietario")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if index < members.count - 1 {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        }
    }

    private func memberAvatar(_ member: ChatPeerMemberItem) -> some View {
        Group {
            if let url = member.avatarURL {
                ChatAsyncContactPhoto(
                    url: url,
                    accessToken: accessToken,
                    fallbackInitial: GrooAvatarPalette.initial(from: member.name),
                    colorSeed: member.name,
                    diameter: 44
                )
            } else {
                GrooLetterAvatar(name: member.name, size: 44)
            }
        }
        .clipShape(Circle())
    }

    private var contentTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChatPeerProfileTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? Color.black : Color.black.opacity(0.45))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .fill(selectedTab == tab ? Color.white : Color.clear)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.06))
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .media:
            mediaGrid
        case .files:
            listSection(empty: "Sin archivos compartidos") {
                ForEach(library.files) { file in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(Self.telegramBlue)
                            .frame(width: 40, height: 40)
                            .background(Self.telegramBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.title)
                                .font(.system(size: 15, weight: .medium))
                            Text(file.timeLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        case .music:
            emptyState(icon: "music.note", title: "Sin música compartida")
        case .voice:
            listSection(empty: "Sin notas de voz") {
                ForEach(library.voices) { voice in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(Self.telegramBlue)
                            .frame(width: 40, height: 40)
                            .background(Self.telegramBlue.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.isOutgoing ? "Nota de voz enviada" : "Nota de voz")
                                .font(.system(size: 15, weight: .medium))
                            Text(voice.timeLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        case .links:
            listSection(empty: "Sin enlaces compartidos") {
                ForEach(library.links) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 12) {
                            Image(systemName: "link")
                                .foregroundStyle(Self.telegramBlue)
                                .frame(width: 40, height: 40)
                                .background(Self.telegramBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.black)
                                    .lineLimit(2)
                                Text(link.timeLabel)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    private var mediaGrid: some View {
        Group {
            if library.media.isEmpty {
                emptyState(icon: "photo.on.rectangle.angled", title: "Sin media compartida")
                    .padding(.horizontal, 16)
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                ]
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(library.media) { item in
                        Button {
                            if let url = item.remoteURL {
                                lightboxItem = .remote(url)
                            } else if let image = item.localImage {
                                lightboxItem = .local(image)
                            }
                        } label: {
                            mediaCell(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaCell(_ item: ChatPeerMediaItem) -> some View {
        Color.black.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = item.localImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let url = item.remoteURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ProgressView()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func listSection<Content: View>(
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isEmpty: Bool = {
            switch selectedTab {
            case .files: return library.files.isEmpty
            case .voice: return library.voices.isEmpty
            case .links: return library.links.isEmpty
            default: return true
            }
        }()
        if isEmpty {
            emptyState(icon: "tray", title: empty)
        } else {
            VStack(spacing: 10, content: content)
        }
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.25))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.65))
        }
    }
}

// MARK: - Helpers scroll / DI (como Settings)

private struct PeerProfileAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct PeerProfileAvatarOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PeerProfileNameOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    func peerProfileOffsetExtractor(
        coordinateSpace: String,
        completion: @escaping (CGRect) -> Void
    ) -> some View {
        overlay {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                Color.clear
                    .preference(key: PeerProfileAvatarOffsetKey.self, value: rect)
                    .onPreferenceChange(PeerProfileAvatarOffsetKey.self, perform: completion)
            }
        }
    }

    func peerProfileNameOffsetExtractor(
        coordinateSpace: String,
        completion: @escaping (CGRect) -> Void
    ) -> some View {
        overlay {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                Color.clear
                    .preference(key: PeerProfileNameOffsetKey.self, value: rect)
                    .onPreferenceChange(PeerProfileNameOffsetKey.self, perform: completion)
            }
        }
    }
}
