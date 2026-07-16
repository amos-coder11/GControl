import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Tarjeta resumen financiero (toca → detalle)

struct DashboardFinancialSummaryCard: View {
    @ObservedObject var stats: DealershipStatsViewModel
    @Binding var showDetail: Bool

    private let corner: CGFloat = 24

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Información financiera")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textMuted)
                }

                AnimatedEURAmountText(
                    amount: stats.totalStockValueAmount,
                    font: .system(size: 34, weight: .bold, design: .rounded)
                )
                .animation(.easeOut(duration: 1.15), value: stats.totalStockValueAmount)
                .opacity(stats.isStockValueReady ? 1 : 0)
                .overlay {
                    if !stats.isStockValueReady {
                        DashboardSkeletonAmountPlaceholder(height: 38, maxWidth: 200)
                    }
                }

                Text("Valor stock · \(stats.periodDisplayLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)

                HStack(spacing: 14) {
                    miniPill(title: "Vendidos", value: "\(stats.carsSold)")
                    miniPill(title: "Beneficio", value: stats.salesProfit)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                DashboardChromeCardBackground(cornerRadius: corner)
            }
        }
        .buttonStyle(.plain)
    }

    private func miniPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
        }
    }
}

// MARK: - Detalle financiero (hoja)

struct DashboardFinancialDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var stats: DealershipStatsViewModel

    private let corner: CGFloat = 20

    private var categories: [(icon: String, title: String, subtitle: String, amount: String, pct: String, color: Color)] {
        [
            ("shippingbox.fill", "Stock activo", "\(stats.vehiclesInStock) unidades", stats.totalStockValue, stats.vehiclesStockBadge, .cyan),
            ("dollarsign.circle.fill", "Beneficio ventas", stats.periodDisplayLabel, stats.salesProfit, "Neto", .mint),
            ("person.2.fill", "Comisiones", stats.commissionsSubtitle, stats.commercialCommissions, "Comercial", .orange),
            ("chart.line.uptrend.xyaxis", "Ingresos concesión", stats.totalEarningsSubtitle, stats.totalDealershipEarnings, "Total", .purple),
            ("chart.line.uptrend.xyaxis", "Captación", "+\(stats.capturedChangePercent)% vs periodo", "\(stats.capturedCars) productos", "CRM", .pink),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resumen del periodo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DrflowTheme.textSecondary)
                        AnimatedEURAmountText(
                            amount: stats.totalStockValueAmount,
                            font: .system(size: 40, weight: .bold, design: .rounded)
                        )
                        .animation(.easeOut(duration: 1.15), value: stats.totalStockValueAmount)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background {
                        DashboardChromeCardBackground(cornerRadius: corner)
                    }

                    Text("Por categoría")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textPrimary)

                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.offset) { index, row in
                            financeCategoryRow(
                                icon: row.icon,
                                title: row.title,
                                subtitle: row.subtitle,
                                amount: row.amount,
                                pct: row.pct,
                                color: row.color
                            )
                            if index < categories.count - 1 {
                                Divider().background(Color.white.opacity(0.12))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .background {
                        DashboardChromeCardBackground(cornerRadius: corner)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Finanzas")
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
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func financeCategoryRow(
        icon: String,
        title: String,
        subtitle: String,
        amount: String,
        pct: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(amount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                Text(pct)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Mapa del equipo

struct DashboardTeamMapCard: View {
    @ObservedObject var community: DashboardCommunityViewModel
    @ObservedObject var locationHub: DashboardLocationHub
    var currentUserId: UUID?
    var accessToken: String?
    var currentUserProfileImage: UIImage?
    var currentUserInitials: String

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
    )
    @State private var showTeamMapPanel = false

    private let corner: CGFloat = 24

    var body: some View {
        Button {
            showTeamMapPanel = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ubicación del equipo")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textMuted)
                }

                ZStack {
                    TeamLiveMapView(
                        position: $position,
                        community: community,
                        locationHub: locationHub,
                        currentUserId: currentUserId,
                        accessToken: accessToken,
                        currentUserProfileImage: currentUserProfileImage,
                        currentUserInitials: currentUserInitials,
                        pinDiameter: 34,
                        mapCornerRadius: 20
                    )
                    .frame(height: 220)
                    .allowsHitTesting(false)

                    if locationHub.authorizationStatus == .denied || locationHub.authorizationStatus == .restricted {
                        Text("Activa la ubicación para compartir tu posición con el equipo y ver el mapa en vivo.")
                            .font(.system(size: 12, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 220)

                if community.directory.filter(\.hasCoordinate).filter({ $0.userId != currentUserId }).isEmpty,
                   locationHub.coordinate == nil,
                   !hasStoredSelfCoordinate
                {
                    Text("Cuando los usuarios compartan ubicación, aparecerán aquí. Toca para ver el mapa completo.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                } else {
                    Text("Toca para abrir el mapa con fotos y posición exacta de cada usuario.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }
            .padding(16)
            .background {
                DashboardChromeCardBackground(cornerRadius: corner)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showTeamMapPanel) {
            TeamMapDetailSheet(
                community: community,
                locationHub: locationHub,
                currentUserId: currentUserId,
                accessToken: accessToken,
                currentUserProfileImage: currentUserProfileImage,
                currentUserInitials: currentUserInitials
            )
        }
    }

    private var hasStoredSelfCoordinate: Bool {
        guard let uid = currentUserId else { return false }
        return community.directory.contains { $0.userId == uid && $0.hasCoordinate }
    }
}

// MARK: - Enlace de afiliado

enum AffiliateLink {
    static let joinBaseURL = "https://www.drflow.es/join"

    static func urlString(for userId: UUID) -> String {
        "\(joinBaseURL)?ref=\(userId.uuidString.lowercased())"
    }
}

// MARK: - Afiliados (vista previa en Inicio → pestaña Afiliados)

struct DashboardConnectedUsersStrip: View {
    let members: [CommunityProfilesService.DirectoryRow]
    var currentUserId: UUID?
    var accessToken: String?
    var currentUserProfileImage: UIImage?
    var currentUserInitials: String

    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var didCopyAffiliateLink = false

    private let avatarSize: CGFloat = 58

    private var affiliateLinkText: String? {
        guard let uid = currentUserId else { return nil }
        return AffiliateLink.urlString(for: uid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let link = affiliateLinkText {
                affiliateLinkCard(link)
            }

            Button {
                tabRouter.selected = .chat
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Afiliados")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textMuted)
                    }

                    if members.isEmpty {
                        Text("Aún no hay perfiles en el directorio o no tienes permisos de lectura.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DrflowTheme.textTertiary)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(orderedTeam) { row in
                                    DashboardConnectedMemberCell(
                                        row: row,
                                        size: avatarSize,
                                        accessToken: accessToken,
                                        isSelf: row.userId == currentUserId,
                                        localAvatarImage: row.userId == currentUserId ? currentUserProfileImage : nil,
                                        localInitialsOverride: row.userId == currentUserId ? currentUserInitials : nil
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: 24)
        }
    }

    private func affiliateLinkCard(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tu enlace de afiliado")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DrflowTheme.textSecondary)

            HStack(spacing: 10) {
                Text(link)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(DrflowTheme.textPrimary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = link
                    didCopyAffiliateLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didCopyAffiliateLink = false
                    }
                } label: {
                    Label(
                        didCopyAffiliateLink ? "Copiado" : "Copiar",
                        systemImage: didCopyAffiliateLink ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(didCopyAffiliateLink ? DrflowTheme.positive : PremiumAccent.tabActive)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(didCopyAffiliateLink ? DrflowTheme.positive.opacity(0.12) : PremiumAccent.tabActive.opacity(0.1))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
        }
    }

    private var orderedTeam: [CommunityProfilesService.DirectoryRow] {
        guard let uid = currentUserId else {
            return members.sorted {
                $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
            }
        }
        let me = members.filter { $0.userId == uid }
        let others = members.filter { $0.userId != uid }.sorted {
            $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
        }
        return me + others
    }
}

struct DashboardConnectedMemberCell: View {
    let row: CommunityProfilesService.DirectoryRow
    let size: CGFloat
    var accessToken: String?
    /// Resalta tu avatar en el carrusel.
    var isSelf: Bool = false
    var localAvatarImage: UIImage?
    var localInitialsOverride: String?
    var showsNameBelowAvatar: Bool = true

    @State private var avatarImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let img = localAvatarImage ?? avatarImage {
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
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelf ? Color.cyan.opacity(0.9) : DrflowTheme.cardBorder,
                        lineWidth: isSelf ? 2.25 : 0.75
                    )
            }

            if showsNameBelowAvatar {
                Text(row.resolvedDisplayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary.opacity(0.92))
                    .lineLimit(1)
                    .frame(width: size + 12)
            }
        }
        .task(id: row.id) {
            guard localAvatarImage == nil else {
                avatarImage = nil
                return
            }
            avatarImage = await UserProfileService.loadProfileAvatarImage(
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
