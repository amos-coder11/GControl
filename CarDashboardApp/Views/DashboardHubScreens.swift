import SwiftUI

// MARK: - Ranking comerciales

struct CommercialRankingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profiles: [CommunityProfilesService.DirectoryRow]

    private var ranked: [(profile: CommunityProfilesService.DirectoryRow, sales: Int)] {
        profiles.map { p in
            (p, Self.syntheticSales(for: p.id))
        }
        .sorted { $0.sales > $1.sales }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ranking por ventas (referencia)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4)

                        if ranked.isEmpty {
                            Text("No hay perfiles en el directorio. Cuando existan usuarios en `profiles`, aparecerán aquí ordenados.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.top, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(ranked.enumerated()), id: \.element.profile.id) { index, row in
                                    rankingRow(rank: index + 1, name: row.profile.resolvedDisplayName, sales: row.sales)
                                    if index < ranked.count - 1 {
                                        Divider().background(Color.white.opacity(0.1))
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .background {
                                DashboardChromeCardBackground(cornerRadius: 22)
                            }
                        }

                        Text("Los valores de ventas son ilustrativos hasta conectar una vista SQL con ventas reales por usuario.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Ranking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rankingRow(rank: Int, name: String, sales: Int) -> some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? Color.yellow : .white.opacity(0.5))
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Ventas (demo)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Text("\(sales)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private static func syntheticSales(for id: UUID) -> Int {
        var hasher = Hasher()
        hasher.combine(id)
        return 3 + abs(hasher.finalize()) % 48
    }
}

// MARK: - Blitz (accesos rápidos)

struct BlitzHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabRouter: MainTabRouter

    private let visitMocks: [(platform: String, detail: String, time: String)] = [
        ("Instagram", "Visita al perfil de producto", "Hoy"),
        ("TikTok", "Clic en enlace de bio", "Ayer"),
        ("Facebook", "Consulta desde anuncio", "Hace 3 d"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.06, blue: 0.35),
                        Color.black,
                        Color(red: 0.15, green: 0.08, blue: 0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, Color.orange.opacity(0.9)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            Text("Blitz")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 4)

                        blitzSectionTitle("Catálogo de productos")
                        VStack(spacing: 0) {
                            Text("El catálogo de productos estará disponible pronto.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.yellow.opacity(0.25), lineWidth: 0.8)
                                }
                        }

                        blitzSectionTitle("Historial de visitas (plataformas)")
                        VStack(spacing: 0) {
                            ForEach(visitMocks.indices, id: \.self) { i in
                                visitRow(visitMocks[i])
                                if i < visitMocks.count - 1 {
                                    Divider().background(Color.white.opacity(0.1))
                                }
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }

                        Button {
                            dismiss()
                            tabRouter.selected = .chat
                        } label: {
                            Label("Abrir catálogo de productos", systemImage: "shippingbox.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.yellow.opacity(0.92)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func blitzSectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
    }


    private func visitRow(_ v: (platform: String, detail: String, time: String)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(v.platform)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(v.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Text(v.time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Notificaciones

@MainActor
final class DashboardNotificationsStore: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var body: String
        let date: Date
        var isRead: Bool
    }

    @Published private(set) var items: [Item] = []

    private let key = "Drflow.dashboardNotifications.v1"

    init() {
        load()
        if items.isEmpty { seed(); save() }
    }

    func markRead(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isRead = true
        save()
    }

    func markAllRead() {
        for i in items.indices { items[i].isRead = true }
        save()
    }

    private func seed() {
        items = [
            Item(id: UUID(), title: "Catálogo actualizado", body: "Se sincronizaron productos desde el servidor.", date: Date().addingTimeInterval(-3600), isRead: false),
            Item(id: UUID(), title: "Lead nuevo", body: "Un comprador ha visto uno de tus anuncios destacados.", date: Date().addingTimeInterval(-86400 * 2), isRead: true),
            Item(id: UUID(), title: "Recordatorio", body: "Comparte tu enlace de afiliado con tu red esta semana.", date: Date().addingTimeInterval(-2000), isRead: false),
        ]
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Item].self, from: d) else { return }
        items = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}

struct DashboardNotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DashboardNotificationsStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(store.items) { item in
                            Button {
                                store.markRead(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(item.isRead ? Color.white.opacity(0.15) : Color.cyan.opacity(0.65))
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(item.body)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .background {
                                    DashboardChromeCardBackground(cornerRadius: 18)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Notificaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Marcar leídas") {
                        store.markAllRead()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
