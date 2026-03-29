import SwiftUI
import UIKit

enum DealershipGridMetrics {
    /// Altura mínima de la tarjeta con foto; crece si la fila es más alta (p. ej. KPI con subtítulo).
    static let imageStatMinHeight: CGFloat = 128
}

// MARK: - KPI estándar (Liquid Glass vía `GlassCard`)

struct DealershipStatCard: View {
    let icon: String
    let iconBackground: Color
    let title: String
    let value: String
    var titleUppercase: Bool = true
    var badge: String?
    var badgePositive: Bool = false
    var subtitle: String?

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.thinMaterial)
                            .frame(width: 38, height: 38)
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.6)
                            }

                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconBackground)
                    }

                    Spacer(minLength: 0)

                    if let badge {
                        GlassCapsuleBadge(text: badge, isPositive: badgePositive)
                    }
                }

                Text(titleUppercase ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(PremiumAccent.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Imagen remota (dashboard)

struct DashboardRemoteFillImage: View {
    let url: URL
    @State private var uiImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if loadFailed {
                Color(white: 0.92)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color.white.opacity(0.5)
                    .overlay { ProgressView() }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let img = UIImage(data: data)
            else {
                await MainActor.run { loadFailed = true }
                return
            }
            await MainActor.run { uiImage = img }
        } catch {
            await MainActor.run { loadFailed = true }
        }
    }
}

// MARK: - Tarjeta con imagen (marco glass + foto contenida)

struct DealershipImageStatCard: View {
    let title: String
    let value: String
    let changePercent: Int
    var imageURL: URL = RemoteAssets.carShowroomImageURL
    private let cornerRadius: CGFloat = 20

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DashboardRemoteFillImage(url: imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.02),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 34, height: 34)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                            }

                        Image(systemName: "car.side.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 0)

                    GlassPhotoBadge(text: "+ \(changePercent)%")
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: DealershipGridMetrics.imageStatMinHeight,
            maxHeight: .infinity
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color.white.opacity(0.2),
                            Color.gray.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Franja total (glass ancho)

struct DealershipWideStatCard: View {
    let icon: String
    let iconBackground: Color
    let title: String
    let value: String
    var subtitle: String?

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                        .frame(width: 46, height: 46)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.6)
                        }

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(iconBackground)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumAccent.ink)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dashboard (Liquid Glass + fotos hero)

private let dashboardTileCorner: CGFloat = 26

// MARK: - Cabecera unificada (misma geometría en Inicio, Coches, Chat, Ajustes, Buscador)

/// Avatar → Ajustes (mismo que Inicio).
struct AppChromeAvatarProfileButton: View {
    let initials: String

    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PremiumAccent.ice.opacity(0.9),
                                PremiumAccent.tabActive.opacity(0.72),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: AppChromeHeaderMetrics.avatarSize, height: AppChromeHeaderMetrics.avatarSize)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    }

                Circle()
                    .fill(Color.red.opacity(0.92))
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                    }
                    .offset(x: 3, y: -3)
            }
            .frame(width: AppChromeHeaderMetrics.avatarSize, height: AppChromeHeaderMetrics.avatarSize)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Perfil, abrir ajustes")
    }
}

/// Pastilla de búsqueda: ocupa el espacio flexible entre avatar y botones (igual ancho relativo que Inicio).
struct AppChromeSearchCapsuleField: View {
    @Binding var text: String
    var prompt: Text
    var showsClearButton: Bool
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.iconOpacity))

            TextField("", text: $text, prompt: prompt)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .tint(.white)

            if showsClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.iconClearOpacity))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            DashboardChromeSearchCapsuleBackground()
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

struct AppChromeHeaderCircleIconButton: View {
    let systemName: String
    var accessibilityLabel: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                DashboardChromeHeaderCircleBackground()
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Fila: [avatar 48] [buscador flexible] [trailing]. `trailing` debe ocupar el mismo ancho que 2× círculo + spacing (Inicio).
struct AppChromeHeaderRow<Trailing: View>: View {
    let initials: String
    @Binding var searchText: String
    var prompt: Text
    var showsSearchClearButton: Bool
    @FocusState.Binding var searchFieldFocused: Bool
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: AppChromeHeaderMetrics.hStackSpacing) {
            AppChromeAvatarProfileButton(initials: initials)
            AppChromeSearchCapsuleField(
                text: $searchText,
                prompt: prompt,
                showsClearButton: showsSearchClearButton,
                isSearchFocused: $searchFieldFocused
            )
            trailing()
        }
    }
}

/// Cabecera inicio: estadísticas + notificaciones a la derecha.
struct DashboardHomeTopBar: View {
    let initials: String
    @Binding var searchText: String
    @FocusState private var searchFieldFocused: Bool
    var onStats: () -> Void = {}
    var onNotifications: () -> Void = {}

    var body: some View {
        AppChromeHeaderRow(
            initials: initials,
            searchText: $searchText,
            prompt: Text("Buscar")
                .foregroundStyle(.white.opacity(DashboardChromeSearchFieldStyle.promptOpacity)),
            showsSearchClearButton: true,
            searchFieldFocused: $searchFieldFocused
        ) {
            HStack(spacing: AppChromeHeaderMetrics.hStackSpacing) {
                AppChromeHeaderCircleIconButton(
                    systemName: "chart.bar.fill",
                    accessibilityLabel: "Estadísticas",
                    action: onStats
                )
                AppChromeHeaderCircleIconButton(
                    systemName: "bell.fill",
                    accessibilityLabel: "Notificaciones",
                    action: onNotifications
                )
            }
        }
    }
}

/// Tarjeta KPI a pantalla con foto, texto blanco abajo y sombra suave (sin borde duro).
struct DashboardPhotoStatTile: View {
    let imageURL: URL
    let title: String
    let value: String
    let iconName: String
    var iconForeground: Color = .white
    /// Réplica referencia: número junto al icono (p. ej. stock).
    var showsValueNextToIcon: Bool = false
    var topRightBadge: String?
    var footnote: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DashboardRemoteFillImage(url: imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .black.opacity(0.22),
                    .black.opacity(0.05),
                    .clear,
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 36, height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                            }

                        Image(systemName: iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(iconForeground)
                    }

                    if showsValueNextToIcon {
                        Text(value)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.leading, 6)
                    }

                    Spacer(minLength: 0)

                    if let topRightBadge {
                        Text(topRightBadge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }

                Spacer(minLength: 10)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(2)

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(3)
                        .padding(.top, 4)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.88, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: dashboardTileCorner, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 18, x: 0, y: 10)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

/// Franja inferior ancha: total concesionario (glass claro).
struct DashboardWideLiquidEarningsCard: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PremiumAccent.mint.opacity(0.35),
                                PremiumAccent.mint.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.6)
                    }

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PremiumAccent.mint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(PremiumAccent.ink)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: dashboardTileCorner, style: .continuous)
                .fill(.ultraThinMaterial)
                .background {
                    RoundedRectangle(cornerRadius: dashboardTileCorner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.88),
                                    Color.white.opacity(0.32),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: dashboardTileCorner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    Color.white.opacity(0.28),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                }
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 8)
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
        }
    }
}

