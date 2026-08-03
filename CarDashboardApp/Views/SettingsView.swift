import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var moderation: UserModerationStore
    @EnvironmentObject var communityVM: DashboardCommunityViewModel

    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showTermsSheet = false
    @State private var showProfileDetail = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var scrollProgress: CGFloat = 0
    @State private var textHeaderOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private static let screenBackground = Color(red: 0.949, green: 0.949, blue: 0.969) // #F2F2F7
    private static let telegramBlue = Color(red: 0.22, green: 0.48, blue: 0.98)
    private static let scrollSpace = "SCROLLVIEW"

    var body: some View {
        /// Igual que ContentView del ZIP: leer safeArea ANTES de ignoresSafeArea.
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets

            settingsScroll(safeArea: safeArea)
                .ignoresSafeArea()
        }
        .background(Self.screenBackground.ignoresSafeArea())
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: auth.session?.user.id) {
            guard let uid = auth.session?.user.id else { return }
            await settingsVM.loadNotifyTeamPush(
                client: SupabaseClientProvider.shared,
                userId: uid
            )
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                isSavingPhoto = true
                defer { isSavingPhoto = false }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await auth.updateProfileAvatar(with: image)
                }
                selectedPhoto = nil
            }
        }
        .confirmationDialog(
            "Eliminar cuenta",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar cuenta", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    defer { isDeletingAccount = false }
                    do {
                        try await auth.deleteCurrentAccount()
                    } catch {
                        deleteAccountError = error.localizedDescription
                    }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción elimina tu cuenta de forma permanente y no se puede deshacer.")
        }
        .alert("No se pudo eliminar la cuenta", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .sheet(isPresented: $showTermsSheet) {
            UGCTermsView()
        }
        .sheet(isPresented: $showProfileDetail) {
            SettingsProfileDetailSheet()
                .environmentObject(auth)
        }
    }

    // MARK: - Scroll + Dynamic Island (TelegramDynamicIslandHeader / Home.swift)

    @ViewBuilder
    private func settingsScroll(safeArea: EdgeInsets) -> some View {
        let isHavingNotch = safeArea.bottom != 0

        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                profileHeaderPhoto
                    /// Adding Blur and Reducing Size based on Scroll Progress
                    .frame(width: 130 - (75 * scrollProgress), height: 130 - (75 * scrollProgress))
                    /// Hiding Main View so that the Dynamic Island Metaball Effect will be Visible
                    .opacity(1 - scrollProgress)
                    .blur(radius: scrollProgress * 10, opaque: true)
                    .clipShape(Circle())
                    .anchorPreference(key: SettingsAnchorKey.self, value: .bounds, transform: {
                        ["HEADER": $0]
                    })
                    .padding(.top, safeArea.top + 15)
                    .settingsOffsetExtractor(coordinateSpace: Self.scrollSpace) { scrollRect in
                        guard isHavingNotch else { return }
                        let progress = -scrollRect.minY / 25
                        scrollProgress = min(max(progress, 0), 1)
                    }

                let fixedTop: CGFloat = safeArea.top + 3
                let isNamePinned = textHeaderOffset < fixedTop
                VStack(spacing: isNamePinned ? 0 : 4) {
                    Text(auth.shortGreetingName)
                        .font(.system(size: isNamePinned ? 17 : 22, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)

                    /// Al hacer scroll solo queda el nombre como header.
                    Text(profileSubtitle.isEmpty ? " " : profileSubtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .opacity(isNamePinned ? 0 : 1)
                        .frame(height: isNamePinned ? 0 : nil)
                        .clipped()
                        .allowsHitTesting(false)
                }
                .padding(.vertical, isNamePinned ? 10 : 15)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.18), value: isNamePinned)
                .offset(y: isNamePinned ? -(textHeaderOffset - fixedTop) : 0)
                .settingsNameOffsetExtractor(coordinateSpace: Self.scrollSpace) {
                    textHeaderOffset = $0.minY
                }
                .zIndex(1000)

                if isSavingPhoto {
                    ProgressView()
                        .tint(Self.telegramBlue)
                }
                changePhotoCard
                    .padding(.horizontal, 15)

                settingsContentStack
                    .padding(.horizontal, 15)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, safeArea.bottom + 15)
        }
        /// iOS moderno pinta el ScrollView opaco; sin esto el Canvas metaball no se ve.
        .scrollContentBackground(.hidden)
        .backgroundPreferenceValue(SettingsAnchorKey.self) { pref in
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
                        settingsHeaderView(frameRect)
                            .tag(0)
                            .id(0)

                        settingsDynamicIslandCapsule(capsuleHeight)
                            .tag(1)
                            .id(1)
                    }
                }
            }
        }
        /// Blur blanco difuminado como el header de Inicio
        .overlay(alignment: .top) {
            GrooChatTheme.floatingBlurChrome()
                .frame(height: safeArea.top + 56)
                .ignoresSafeArea(edges: .top)
        }
        .coordinateSpace(name: Self.scrollSpace)
    }

    @ViewBuilder
    private var profileHeaderPhoto: some View {
        if let photo = auth.profileAvatarImage {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle()
                    .fill(Self.telegramBlue)
                Text(auth.userInitials)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func settingsHeaderView(_ frameRect: CGRect) -> some View {
        Circle()
            .fill(.black)
            .frame(width: frameRect.width, height: frameRect.height)
    }

    @ViewBuilder
    private func settingsDynamicIslandCapsule(_ height: CGFloat = 37) -> some View {
        Capsule()
            .fill(.black)
            .frame(width: 120, height: height)
    }

    private var settingsContentStack: some View {
        VStack(spacing: 16) {
            miPerfilRow
            if auth.isAuthenticated {
                mainMenuGroup
            }
            accountGroup
            aboutGroup
        }
    }

    private var profileSubtitle: String {
        var parts: [String] = []
        if let email = auth.userEmail, !email.isEmpty {
            parts.append(email)
        }
        let handle = profileHandle
        if !handle.isEmpty {
            parts.append(handle)
        }
        return parts.joined(separator: " · ")
    }

    private var profileHandle: String {
        guard let email = auth.userEmail,
              let at = email.firstIndex(of: "@")
        else { return "" }
        let local = String(email[..<at])
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
        guard !local.isEmpty else { return "" }
        return "@\(local)"
    }

    // MARK: - Tarjetas de acción

    private var changePhotoCard: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.telegramBlue)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Self.telegramBlue.opacity(0.12))
                    }

                Text("Cambiar foto del perfil")
                    .font(.system(size: 17))
                    .foregroundStyle(Self.telegramBlue)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(telegramCardBackground)
        }
        .buttonStyle(.plain)
        .disabled(isSavingPhoto)
    }

    // MARK: - Menú

    private var miPerfilRow: some View {
        Button {
            showProfileDetail = true
        } label: {
            TelegramSettingsRow(
                icon: "person.fill",
                iconColor: Color(red: 0.95, green: 0.38, blue: 0.38),
                title: "Mi perfil"
            )
        }
        .buttonStyle(.plain)
        .background(telegramCardBackground)
    }

    private var mainMenuGroup: some View {
        TelegramSettingsGroup {
            TelegramSettingsRow(
                icon: "bell.fill",
                iconColor: Color(red: 0.22, green: 0.48, blue: 0.98),
                title: "Alertas del equipo",
                showChevron: false
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { settingsVM.notifyTeamPushEnabled },
                        set: { new in
                            settingsVM.notifyTeamPushEnabled = new
                            if let uid = auth.session?.user.id {
                                Task {
                                    await settingsVM.persistNotifyTeamPush(
                                        new,
                                        client: SupabaseClientProvider.shared,
                                        userId: uid
                                    )
                                }
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(Self.telegramBlue)
            }

            TelegramSettingsRow(
                icon: "clock.badge.checkmark.fill",
                iconColor: Color(red: 0.18, green: 0.72, blue: 0.42),
                title: "Jornada laboral",
                detail: "Activa"
            )

            Button {
                showTermsSheet = true
            } label: {
                TelegramSettingsRow(
                    icon: "bookmark.fill",
                    iconColor: Color(red: 0.22, green: 0.48, blue: 0.98),
                    title: "Términos de uso"
                )
            }
            .buttonStyle(.plain)

            TelegramSettingsRow(
                icon: "iphone.gen2",
                iconColor: Color(red: 0.98, green: 0.58, blue: 0.18),
                title: "Dispositivos",
                detail: "1"
            )

            TelegramSettingsRow(
                icon: "folder.fill",
                iconColor: Color(red: 0.52, green: 0.72, blue: 0.92),
                title: "Moderación",
                detail: "24 h",
                showChevron: false
            )

            if !moderation.blockedUserIds.isEmpty {
                ForEach(Array(moderation.blockedUserIds).sorted { $0.uuidString < $1.uuidString }, id: \.self) { uid in
                    let name = communityVM.directory.first(where: { $0.userId == uid })?.resolvedDisplayName ?? "Usuario"
                    HStack(spacing: 14) {
                        telegramIconBadge(
                            icon: "hand.raised.fill",
                            color: Color(red: 0.95, green: 0.38, blue: 0.38)
                        )
                        Text(name)
                            .font(.system(size: 16))
                            .foregroundStyle(.black)
                        Spacer()
                        Button("Desbloquear") {
                            Task { await moderation.unblockUser(uid) }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Self.telegramBlue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private var accountGroup: some View {
        TelegramSettingsGroup {
            Button {
                Task { await auth.signOut() }
            } label: {
                TelegramSettingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    iconColor: Color(red: 0.98, green: 0.58, blue: 0.18),
                    title: "Cerrar sesión",
                    showChevron: false
                )
            }
            .buttonStyle(.plain)

            Button {
                showDeleteAccountConfirm = true
            } label: {
                HStack(spacing: 14) {
                    telegramIconBadge(icon: "trash.fill", color: Color(red: 0.95, green: 0.38, blue: 0.38))
                    Text(isDeletingAccount ? "Eliminando cuenta…" : "Eliminar cuenta")
                        .font(.system(size: 16))
                        .foregroundStyle(.black)
                    Spacer()
                    if isDeletingAccount {
                        ProgressView().tint(Self.telegramBlue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
        }
    }

    private var aboutGroup: some View {
        TelegramSettingsGroup {
            TelegramSettingsRow(
                icon: "info.circle.fill",
                iconColor: Color(red: 0.55, green: 0.55, blue: 0.58),
                title: "Versión",
                detail: settingsVM.appVersion,
                showChevron: false
            )
        }
    }

    // MARK: - Helpers

    private var telegramCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
    }

    @ViewBuilder
    private func telegramIconBadge(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Dynamic Island header helpers (AnchorKey + OffsetHelper del ZIP)

private struct SettingsAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct SettingsAvatarOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SettingsNameOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    /// Offset de la foto → scrollProgress (metaball).
    @ViewBuilder
    func settingsOffsetExtractor(coordinateSpace: String, completion: @escaping (CGRect) -> Void) -> some View {
        overlay {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                Color.clear
                    .preference(key: SettingsAvatarOffsetKey.self, value: rect)
                    .onPreferenceChange(SettingsAvatarOffsetKey.self, perform: completion)
            }
        }
    }

    /// Offset del nombre sticky.
    @ViewBuilder
    func settingsNameOffsetExtractor(coordinateSpace: String, completion: @escaping (CGRect) -> Void) -> some View {
        overlay {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(coordinateSpace))
                Color.clear
                    .preference(key: SettingsNameOffsetKey.self, value: rect)
                    .onPreferenceChange(SettingsNameOffsetKey.self, perform: completion)
            }
        }
    }
}

// MARK: - Componentes estilo Telegram

private struct TelegramSettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        }
    }
}

private struct TelegramSettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var detail: String? = nil
    var showChevron: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String? = nil,
        showChevron: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.detail = detail
        self.showChevron = showChevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.black)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.black.opacity(0.35))
            }

            trailing()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Detalle perfil

private struct SettingsProfileDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileBlock
                    infoCard(title: "Nombre", value: auth.shortGreetingName)
                    if let email = auth.userEmail {
                        infoCard(title: "Correo", value: email)
                    }
                    Text("Los cambios de correo se gestionan desde tu cuenta de Supabase.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.38))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(red: 0.949, green: 0.949, blue: 0.969).ignoresSafeArea())
            .navigationTitle("Mi perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    private var profileBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                if let photo = auth.profileAvatarImage {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.55, blue: 0.98))
                    Text(auth.userInitials)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())

            Text(auth.shortGreetingName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        }
    }

    private func infoCard(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.black)
            Spacer()
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(Color.black.opacity(0.38))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AuthViewModel())
        .environmentObject(UserModerationStore())
        .environmentObject(DashboardCommunityViewModel())
}
