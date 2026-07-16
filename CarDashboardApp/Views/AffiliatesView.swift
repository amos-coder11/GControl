import SwiftUI
import UIKit

/// Pestaña Afiliados: panel administrativo de red y enlace personal.
struct AffiliatesView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter

    @State private var didCopyAffiliateLink = false
    @State private var searchText = ""

    private let corner: CGFloat = 20

    private var affiliateLinkText: String? {
        guard let uid = auth.session?.user.id else { return nil }
        return AffiliateLink.urlString(for: uid)
    }

    private var orderedTeam: [CommunityProfilesService.DirectoryRow] {
        let members = communityVM.directory
        guard let uid = auth.session?.user.id else {
            return members.sorted {
                $0.resolvedDisplayName.localizedCaseInsensitiveCompare($1.resolvedDisplayName) == .orderedAscending
            }
        }
        let me = members.filter { $0.userId == uid }
        let others = members.filter { $0.userId != uid }.sorted {
            mockSales(for: $0.userId) > mockSales(for: $1.userId)
        }
        return me + others
    }

    private var filteredTeam: [CommunityProfilesService.DirectoryRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return orderedTeam }
        return orderedTeam.filter { row in
            row.resolvedDisplayName.lowercased().contains(query)
                || affiliateHandle(for: row).lowercased().contains(query)
        }
    }

    private var networkCount: Int {
        max(communityVM.directory.count, 1)
    }

    var body: some View {
        RevolutChromeContainer {
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        statsRow

                        if let link = affiliateLinkText {
                            affiliateLinkHero(link)
                        }

                        networkSection

                        quickActions
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
                .navigationDestination(for: AffiliateDetailRoute.self) { route in
                    affiliateDetailDestination(for: route)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Afiliados")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)

            Text("Gestiona tu enlace y el rendimiento de tu red.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Métricas

    private var statsRow: some View {
        HStack(spacing: 10) {
            statPill(
                title: "Comisiones",
                value: "$6,400",
                accent: DrflowTheme.positive
            )
            statPill(
                title: "Ventas red",
                value: "$32,000",
                accent: PremiumAccent.tabActive
            )
            statPill(
                title: "En red",
                value: "\(networkCount)",
                accent: Color(red: 0.62, green: 0.45, blue: 0.98)
            )
        }
    }

    private func statPill(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            DashboardChromeCardBackground(cornerRadius: 16)
        }
    }

    // MARK: - Enlace de afiliado

    private func affiliateLinkHero(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PremiumAccent.tabActive.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PremiumAccent.tabActive)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Tu enlace de afiliado")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Text("Compártelo en TikTok, Instagram o WhatsApp.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }

            Text(link)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DrflowTheme.surfaceMuted)
                }

            HStack(spacing: 10) {
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(didCopyAffiliateLink ? DrflowTheme.positive : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(didCopyAffiliateLink ? DrflowTheme.positive.opacity(0.14) : PremiumAccent.tabActive)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    shareLink(link)
                } label: {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PremiumAccent.tabActive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            Capsule()
                                .strokeBorder(PremiumAccent.tabActive.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: corner)
        }
    }

    // MARK: - Red

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Red de afiliados")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Spacer()
                Text("\(filteredTeam.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(DrflowTheme.surfaceMuted)
                    }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DrflowTheme.textTertiary)
                TextField("Buscar afiliado", text: $searchText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                DashboardChromeSearchCapsuleBackground()
            }

            if filteredTeam.isEmpty {
                ContentUnavailableView {
                    Label("Sin afiliados", systemImage: "person.2")
                } description: {
                    Text(
                        communityVM.directory.isEmpty
                            ? "Aún no hay perfiles en el directorio."
                            : "No hay resultados para tu búsqueda."
                    )
                }
                .foregroundStyle(DrflowTheme.textSecondary)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredTeam.enumerated()), id: \.element.id) { index, row in
                        affiliateRow(row, rank: index + 1)
                        if index < filteredTeam.count - 1 {
                            Divider().overlay(DrflowTheme.separator)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: corner)
        }
    }

    private func affiliateRow(_ row: CommunityProfilesService.DirectoryRow, rank: Int) -> some View {
        let isSelf = row.userId == auth.session?.user.id
        let sales = mockSales(for: row.userId)
        let commission = sales * 0.20

        return NavigationLink(value: AffiliateDetailRoute(userId: row.userId, rank: rank)) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? PremiumAccent.tabActive : DrflowTheme.textMuted)
                    .frame(width: 20)

                DashboardConnectedMemberCell(
                    row: row,
                    size: 48,
                    accessToken: auth.session?.accessToken,
                    isSelf: isSelf,
                    localAvatarImage: isSelf ? auth.profileAvatarImage : nil,
                    localInitialsOverride: isSelf ? auth.userInitials : nil,
                    showsNameBelowAvatar: false
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.resolvedDisplayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .lineLimit(1)

                        if isSelf {
                            Text("Tú")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PremiumAccent.tabActive)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background {
                                    Capsule().fill(PremiumAccent.tabActive.opacity(0.12))
                                }
                        } else if rank == 1 {
                            topAffiliateBadge
                        }
                    }

                    Text(affiliateHandle(for: row))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(DealershipStatsViewModel.formatUSD(commission))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Text(DealershipStatsViewModel.formatUSD(sales))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DrflowTheme.textMuted)

                    HStack(spacing: 3) {
                        Text("Perfil")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(PremiumAccent.tabActive)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var topAffiliateBadge: some View {
        Text("Top")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 0.98))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .strokeBorder(Color(red: 0.62, green: 0.45, blue: 0.98).opacity(0.45), lineWidth: 0.8)
            }
    }

    // MARK: - Acciones

    private var quickActions: some View {
        Button {
            tabRouter.selected = .chat
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Ver pedidos de la red")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(PremiumAccent.tabActive)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func affiliateDetailDestination(for route: AffiliateDetailRoute) -> some View {
        if let row = communityVM.directory.first(where: { $0.userId == route.userId }) {
            let profile = DrflowAffiliateCatalog.profile(for: row, rank: route.rank)
            AffiliateDetailView(
                profile: profile,
                directoryRow: row,
                accessToken: auth.session?.accessToken,
                isSelf: row.userId == auth.session?.user.id,
                localAvatarImage: row.userId == auth.session?.user.id ? auth.profileAvatarImage : nil
            )
        } else {
            ContentUnavailableView("Afiliado no encontrado", systemImage: "person.crop.circle.badge.xmark")
        }
    }

    private func affiliateHandle(for row: CommunityProfilesService.DirectoryRow) -> String {
        let base = row.resolvedDisplayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return "@\(base.isEmpty ? "afiliado" : base)"
    }

    private func mockSales(for userId: UUID) -> Double {
        let seed = abs(userId.hashValue)
        return Double(1_200 + (seed % 28_800))
    }

    private func shareLink(_ link: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController
        else { return }

        let controller = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        root.present(controller, animated: true)
    }
}

#Preview {
    AffiliatesView()
        .environmentObject(AuthViewModel())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(MainTabRouter())
}
