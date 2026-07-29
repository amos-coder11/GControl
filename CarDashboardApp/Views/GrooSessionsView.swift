import SwiftUI

/// Pestaña "Sessions": historial de conversaciones del mentor.
/// Al tocar una sesión la selecciona y salta a la pestaña de chat.
struct GrooSessionsView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var query = ""

    private var sessions: [GrooChatSession] {
        groo.filteredSessions(query: query)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()

                if groo.sessions.isEmpty {
                    ContentUnavailableView(
                        "Sessions",
                        systemImage: "doc.text",
                        description: Text("Aquí aparecerán tus conversaciones con \(GrooBrand.appName).")
                    )
                } else if sessions.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(sessions) { session in
                            Button {
                                open(session)
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Sessions")
            .searchable(text: $query, prompt: "Buscar en tus sesiones")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let id = groo.startNewSession()
                        groo.selectSession(id)
                        tabRouter.selected = .chat
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: GrooChatSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .frame(width: 34, height: 34)
                .background(Circle().fill(GrooBrand.purpleSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text(session.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .lineLimit(2)

                Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary.opacity(0.8))
            }

            Spacer(minLength: 0)

            if session.id == groo.activeSessionId {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GrooBrand.purple)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func open(_ session: GrooChatSession) {
        groo.selectSession(session.id)
        tabRouter.selected = .chat
    }
}
