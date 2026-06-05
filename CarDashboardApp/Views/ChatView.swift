import SwiftUI
import Supabase
import UIKit

// MARK: - Lista de chat (fondo Revolut / liquid glass como Inicio)

private enum ChatInboxListSegment: Int, CaseIterable {
    case team
    case general

    var title: String {
        switch self {
        case .team: return "Equipo"
        case .general: return "Generales"
        }
    }
}

private enum ChatListChromeTheme {
    static let listBackground = Color.clear
    static let rowBackground = Color.clear
    static let rowSeparator = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color.white
    static let accentBlue = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let readGreen = Color(red: 0.45, green: 0.88, blue: 0.62)
}

struct ChatView: View {
    @Binding var searchText: String

    @EnvironmentObject private var inbox: ChatInboxStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var moderation: UserModerationStore
    @State private var path = NavigationPath()
    @State private var listSegment: ChatInboxListSegment = .team
    @FocusState private var chatSearchFieldFocused: Bool
    @State private var teamDirectInboxChannel: RealtimeChannelV2?
    @State private var teamGroupInboxChannel: RealtimeChannelV2?

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredThreads: [ChatThread] {
        let base = inbox.liveThreads
        guard !searchQuery.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(searchQuery) || $0.preview.lowercased().contains(searchQuery)
        }
    }

    private var teamSectionThreads: [ChatThread] {
        var list: [ChatThread] = []
        if let g = inbox.teamGroupChatThread { list.append(g) }
        list.append(contentsOf: inbox.teamDirectChatThreads)
        return list
    }

    private var filteredTeamSectionThreads: [ChatThread] {
        guard !searchQuery.isEmpty else { return teamSectionThreads }
        return teamSectionThreads.filter {
            $0.title.lowercased().contains(searchQuery) || $0.preview.lowercased().contains(searchQuery)
        }
    }

    private var searchPrompt: Text {
        switch listSegment {
        case .team:
            return Text("Buscar en equipo…").foregroundStyle(.white)
        case .general:
            return Text("Buscar en plataformas…").foregroundStyle(.white)
        }
    }

    private var teamEmptyFootnote: String {
        if !searchQuery.isEmpty {
            return "No hay coincidencias. Prueba otro término o cambia a Generales."
        }
        let others = communityVM.directory.filter { $0.userId != auth.session?.user.id }
        if others.isEmpty {
            return "Cuando haya más personas en el directorio, verás aquí el grupo y los chats privados del equipo (tú no apareces en la lista)."
        }
        return "Abre un chat desde Inicio o espera a que el directorio se actualice."
    }

    private var generalEmptyFootnote: String {
        if !searchQuery.isEmpty {
            return "No hay coincidencias. Prueba otro término o cambia a Equipo."
        }
        return "Los leads de Instagram, WhatsApp y otras plataformas aparecen aquí."
    }

    var body: some View {
        RevolutChromeContainer {
            NavigationStack(path: $path) {
                VStack(spacing: 0) {
                    AppChromeHeaderRow(
                        initials: auth.userInitials,
                        searchText: $searchText,
                        prompt: searchPrompt,
                        showsSearchClearButton: true,
                        searchFieldFocused: $chatSearchFieldFocused
                    ) {
                        HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                            AppChromeHeaderCircleIconButton(
                                systemName: "chart.bar.fill",
                                accessibilityLabel: "Estadísticas",
                                action: {}
                            )
                            AppChromeHeaderCircleIconButton(
                                systemName: "bell.fill",
                                accessibilityLabel: "Notificaciones",
                                action: {}
                            )
                        }
                    }
                    .appChromeHeaderOuterPadding()

                    chatInboxSegmentBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    List {
                        if listSegment == .team {
                            if filteredTeamSectionThreads.isEmpty {
                                Section {
                                    chatEmptyPlaceholder(
                                        title: "Equipo",
                                        systemImage: "person.3.fill",
                                        footnote: teamEmptyFootnote
                                    )
                                }
                            } else {
                                Section {
                                    ForEach(filteredTeamSectionThreads) { thread in
                                        teamOrLeadChatRow(thread)
                                    }
                                }
                            }
                        } else {
                            if filteredThreads.isEmpty {
                                Section {
                                    chatEmptyPlaceholder(
                                        title: "Generales",
                                        systemImage: "bubble.left.and.bubble.right.fill",
                                        footnote: generalEmptyFootnote
                                    )
                                }
                            } else {
                                Section {
                                    ForEach(filteredThreads) { thread in
                                        teamOrLeadChatRow(thread)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(ChatListChromeTheme.listBackground)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        LiquidGlassKeyboardAccessoryBar {
                            chatSearchFieldFocused = false
                        }
                    }
                }
                .navigationDestination(for: ChatThread.self) { thread in
                    ChatConversationView(thread: thread)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        .accentColor(.white)
        .task(id: auth.session?.user.id) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await subscribeTeamDirectInboxIfNeeded() }
                group.addTask { await subscribeTeamGroupInboxIfNeeded() }
            }
        }
        .onAppear {
            syncTeamThreadsFromDirectory()
            openPendingChatNavigation()
        }
        .onChange(of: communityVM.directory) { _, _ in
            syncTeamThreadsFromDirectory()
        }
        .onChange(of: moderation.blockedUserIds) { _, _ in
            syncTeamThreadsFromDirectory()
        }
        .onChange(of: chatNav.threadToOpen?.id) { _, _ in
            openPendingChatNavigation()
        }
    }

    private func syncTeamThreadsFromDirectory() {
        inbox.syncTeamThreads(
            from: communityVM.directory,
            currentUserId: auth.session?.user.id,
            blockedUserIds: moderation.blockedUserIds
        )
    }

    private func openPendingChatNavigation() {
        guard let t = chatNav.threadToOpen else { return }
        if t.kind == .teamGroup || t.kind == .teamDirect {
            listSegment = .team
        } else {
            listSegment = .general
        }
        path.append(t)
        chatNav.threadToOpen = nil
    }

    /// Avisos de nuevos mensajes DM (destinatario = yo) cuando no estás en la conversación.
    private func subscribeTeamDirectInboxIfNeeded() async {
        guard let uid = auth.session?.user.id else {
            if let ch = teamDirectInboxChannel {
                await SupabaseClientProvider.shared.removeChannel(ch)
                await MainActor.run { teamDirectInboxChannel = nil }
            }
            return
        }
        if let existing = teamDirectInboxChannel {
            await SupabaseClientProvider.shared.removeChannel(existing)
            await MainActor.run { teamDirectInboxChannel = nil }
        }
        let client = SupabaseClientProvider.shared
        let channel = client.channel("dm-inbox-global-\(uid.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamDirectMessagesService.tableName,
            filter: RealtimePostgresFilter.eq("recipient_id", value: uid)
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        await MainActor.run { teamDirectInboxChannel = channel }
        for await action in inserts {
            guard let row = try? TeamDirectMessagesService.decodeInsert(action) else { continue }
            guard row.senderId != uid else { continue }
            let date = TeamDirectMessagesService.parseCreatedAt(row.createdAt) ?? Date()
            await MainActor.run {
                inbox.applyTeamDirectIncoming(fromPeer: row.senderId, body: row.body, date: date)
            }
        }
    }

    private func subscribeTeamGroupInboxIfNeeded() async {
        guard let uid = auth.session?.user.id else {
            if let ch = teamGroupInboxChannel {
                await SupabaseClientProvider.shared.removeChannel(ch)
                await MainActor.run { teamGroupInboxChannel = nil }
            }
            return
        }
        if let existing = teamGroupInboxChannel {
            await SupabaseClientProvider.shared.removeChannel(existing)
            await MainActor.run { teamGroupInboxChannel = nil }
        }
        let client = SupabaseClientProvider.shared
        let channel = client.channel("team-group-inbox-\(uid.uuidString.lowercased())")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: TeamGroupMessagesService.tableName
        )
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        await MainActor.run { teamGroupInboxChannel = channel }
        for await action in inserts {
            guard let row = try? TeamGroupMessagesService.decodeInsert(action) else { continue }
            guard row.senderId != uid else { continue }
            let date = TeamGroupMessagesService.parseCreatedAt(row.createdAt) ?? Date()
            await MainActor.run {
                inbox.applyTeamGroupIncoming(
                    fromSender: row.senderId,
                    body: row.body,
                    date: date,
                    currentUserId: uid
                )
            }
        }
    }

    private var chatInboxSegmentBar: some View {
        HStack(spacing: 0) {
            ForEach(ChatInboxListSegment.allCases, id: \.rawValue) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        listSegment = segment
                    }
                } label: {
                    Text(segment.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(listSegment == segment ? .white : .white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if listSegment == segment {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                }
        }
    }

    private func chatEmptyPlaceholder(title: String, systemImage: String, footnote: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(footnote)
        }
        .foregroundStyle(.white)
        .symbolRenderingMode(.hierarchical)
        .tint(.white.opacity(0.85))
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .listRowBackground(ChatListChromeTheme.rowBackground)
    }

    @ViewBuilder
    private func teamOrLeadChatRow(_ thread: ChatThread) -> some View {
        Button {
            path.append(thread)
        } label: {
            chatListRow(thread)
        }
        .buttonStyle(ChromeRowPressButtonStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(ChatListChromeTheme.rowBackground)
        .listRowSeparatorTint(ChatListChromeTheme.rowSeparator)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                archiveThread(thread)
            } label: {
                Label("Archivar", systemImage: "archivebox.fill")
            }
            .tint(Color(white: 0.55))

            Button(role: .destructive) {
                deleteThread(thread)
            } label: {
                Label("Eliminar", systemImage: "trash.fill")
            }

            Button {
                muteThread(thread)
            } label: {
                Label("Silenciar", systemImage: "speaker.slash.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                markUnread(thread)
            } label: {
                Label("No leído", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tint(.white)

            Button {
                togglePin(thread)
            } label: {
                Label("Fijar", systemImage: "pin.fill")
            }
            .tint(Color(red: 0.2, green: 0.78, blue: 0.35))
        }
    }

    // MARK: - Acciones swipe (orden: el primero es el del deslizamiento completo)

    private func archiveThread(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inbox.archiveThread(thread)
    }

    private func deleteThread(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        inbox.deleteThread(thread)
    }

    private func muteThread(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func markUnread(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inbox.markUnread(thread)
    }

    private func togglePin(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        inbox.togglePin(thread)
    }

    // MARK: - Fila

    private func effectivePinned(_ thread: ChatThread) -> Bool {
        inbox.effectivePinned(thread)
    }

    private func effectiveUnread(_ thread: ChatThread) -> Int? {
        inbox.effectiveUnread(thread)
    }

    private func chatListRow(_ thread: ChatThread) -> some View {
        let pinned = effectivePinned(thread)
        let unread = effectiveUnread(thread)

        return HStack(alignment: .top, spacing: 12) {
            avatar(for: thread)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ChatListChromeTheme.primaryText)
                        .lineLimit(1)

                    if thread.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ChatListChromeTheme.accentBlue)
                    }

                    Spacer(minLength: 8)

                    Text(thread.time)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ChatListChromeTheme.secondaryText)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChatListChromeTheme.secondaryText)
                            .rotationEffect(.degrees(35))
                    }

                    Text(thread.preview)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ChatListChromeTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    trailingStatus(thread, unread: unread)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func avatar(for thread: ChatThread) -> some View {
        ChatInboxListAvatarView(
            thread: thread,
            directory: communityVM.directory,
            accessToken: auth.session?.accessToken,
            currentUserId: auth.session?.user.id,
            localProfileImage: auth.profileAvatarImage,
            localInitials: auth.userInitials,
            diameter: 56
        )
    }

    @ViewBuilder
    private func trailingStatus(_ thread: ChatThread, unread: Int?) -> some View {
        if thread.showOpenButton {
            Text("ABRIR")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(ChatListChromeTheme.accentBlue)
                }
        } else if let n = unread, n > 0 {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 22, minHeight: 22)
                .background {
                    Circle()
                        .fill(ChatListChromeTheme.accentBlue)
                }
        } else {
            readReceiptView(thread.readReceipt)
        }
    }

    @ViewBuilder
    private func readReceiptView(_ state: ChatThread.ReadReceipt) -> some View {
        switch state {
        case .none:
            Color.clear.frame(width: 1, height: 1)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ChatListChromeTheme.accentBlue)
        case .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(ChatListChromeTheme.readGreen)
        }
    }
}

#Preview {
    ChatView(searchText: .constant(""))
        .environmentObject(ChatInboxStore())
        .environmentObject(AuthViewModel())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(ChatNavigationCoordinator())
}
