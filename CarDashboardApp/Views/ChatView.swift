import SwiftUI
import UIKit

// MARK: - Lista mensajería clara (estilo Telegram iOS)

private enum ChatListLightTheme {
    static let background = Color(white: 0.96)
    static let rowSeparator = Color.black.opacity(0.08)
    static let primaryText = Color.black
    static let secondaryText = Color(red: 0.56, green: 0.56, blue: 0.58)
    static let accentBlue = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let readGreen = Color(red: 0.31, green: 0.78, blue: 0.47)
}

struct ChatView: View {
    @Binding var searchText: String

    @EnvironmentObject private var inbox: ChatInboxStore
    @State private var path = NavigationPath()

    private var filteredThreads: [ChatThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = inbox.liveThreads
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) || $0.preview.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filteredThreads) { thread in
                    Button {
                        path.append(thread)
                    } label: {
                        telegramLightRow(thread)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(ChatListLightTheme.background)
                    .listRowSeparatorTint(ChatListLightTheme.rowSeparator)
                    // Deslizar izquierda: corto → Silenciar + Eliminar; largo (full swipe) → Archivar (1.º en el closure).
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
                    // Deslizar derecha: corto → Fijar + No leído; largo (full swipe) → No leído (1.º en el closure).
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            markUnread(thread)
                        } label: {
                            Label("No leído", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .tint(Color(red: 0.0, green: 0.48, blue: 1.0))

                        Button {
                            togglePin(thread)
                        } label: {
                            Label("Fijar", systemImage: "pin.fill")
                        }
                        .tint(Color(red: 0.2, green: 0.78, blue: 0.35))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ChatListLightTheme.background)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Buscar coches…")
            .navigationDestination(for: ChatThread.self) { thread in
                ChatConversationView(thread: thread)
                    .toolbar(.hidden, for: .tabBar)
            }
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

    private func telegramLightRow(_ thread: ChatThread) -> some View {
        let pinned = effectivePinned(thread)
        let unread = effectiveUnread(thread)

        return HStack(alignment: .top, spacing: 12) {
            avatar(for: thread)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thread.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ChatListLightTheme.primaryText)
                        .lineLimit(1)

                    if thread.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ChatListLightTheme.accentBlue)
                    }

                    Spacer(minLength: 8)

                    Text(thread.time)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ChatListLightTheme.secondaryText)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChatListLightTheme.secondaryText)
                            .rotationEffect(.degrees(35))
                    }

                    Text(thread.preview)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ChatListLightTheme.secondaryText)
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
        ChatThreadAvatarView(thread: thread, diameter: 56)
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
                        .fill(ChatListLightTheme.accentBlue)
                }
        } else if let n = unread, n > 0 {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 22, minHeight: 22)
                .background {
                    Circle()
                        .fill(ChatListLightTheme.accentBlue)
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
                .foregroundStyle(ChatListLightTheme.accentBlue)
        case .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(ChatListLightTheme.readGreen)
        }
    }
}

#Preview {
    ChatView(searchText: .constant(""))
        .environmentObject(ChatInboxStore())
}
