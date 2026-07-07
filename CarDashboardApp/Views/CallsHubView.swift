import SwiftUI

/// Pestaña «Llamada»: contactos del CRM con teléfono para llamar o abrir chat.
struct CallsHubView: View {
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var callableThreads: [ChatThread] {
        chatInbox.liveThreads.filter { thread in
            thread.kind == .lead && chatInbox.canCallLead(thread)
        }
    }

    private var filteredThreads: [ChatThread] {
        guard !searchQuery.isEmpty else { return callableThreads }
        return callableThreads.filter {
            $0.title.lowercased().contains(searchQuery)
                || (chatInbox.contactPhoneDisplay(for: $0) ?? "").lowercased().contains(searchQuery)
        }
    }

    var body: some View {
        RevolutChromeContainer {
            NavigationStack {
                VStack(spacing: 0) {
                    AppChromeSearchCapsuleField(
                        text: $searchText,
                        prompt: Text("Buscar contacto…").foregroundStyle(.white),
                        showsClearButton: true,
                        isSearchFocused: $searchFocused
                    )
                    .appChromeHeaderOuterPadding()
                    .padding(.bottom, 8)

                    if filteredThreads.isEmpty {
                        Spacer(minLength: 24)
                        VStack(spacing: 12) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(emptyTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .multilineTextAlignment(.center)
                            Text(emptySubtitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredThreads) { thread in
                                callRow(thread)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        LiquidGlassKeyboardAccessoryBar {
                            searchFocused = false
                        }
                    }
                }
            }
        }
        .accentColor(.white)
        .task(id: auth.session?.accessToken) {
            if let token = auth.session?.accessToken {
                await chatInbox.refreshCrmConversations(accessToken: token)
            }
        }
    }

    private var emptyTitle: String {
        if !searchQuery.isEmpty { return "Sin resultados" }
        return "Sin contactos para llamar"
    }

    private var emptySubtitle: String {
        if !searchQuery.isEmpty {
            return "Prueba otro nombre o número."
        }
        return "Los leads de WhatsApp con teléfono aparecerán aquí para llamar rápido."
    }

    private func callRow(_ thread: ChatThread) -> some View {
        let phone = chatInbox.contactPhone(for: thread)
        let phoneLabel = chatInbox.contactPhoneDisplay(for: thread)
        let tint = callTint(for: thread)

        return HStack(alignment: .center, spacing: 12) {
            ChatThreadAvatarView(
                thread: thread,
                accessToken: auth.session?.accessToken,
                diameter: 48
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let phoneLabel {
                    Text(phoneLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Text(thread.preview.isEmpty ? "Lead comercial" : thread.preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    openChat(thread)
                } label: {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(red: 0.12, green: 0.72, blue: 0.38), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir chat")

                if let phone {
                    Button {
                        PhoneCallLauncher.call(phone)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(tint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Llamar")
                }
            }
        }
        .padding(14)
        .background {
            DashboardChromeCardBackground(cornerRadius: 18)
        }
    }

    private func callTint(for thread: ChatThread) -> Color {
        switch thread.socialSource {
        case .instagram:
            return Color(red: 0.79, green: 0.38, blue: 0.92)
        case .whatsApp:
            return Color(red: 0.12, green: 0.72, blue: 0.38)
        default:
            return .cyan
        }
    }

    private func openChat(_ thread: ChatThread) {
        chatNav.threadToOpen = thread
        tabRouter.selected = .chat
    }
}

#Preview {
    CallsHubView()
        .environmentObject(ChatInboxStore())
        .environmentObject(AuthViewModel())
        .environmentObject(ChatNavigationCoordinator())
        .environmentObject(MainTabRouter())
}
