import SwiftUI
import UIKit

/// Perfil completo de un afiliado: comisiones, enlaces, productos y certificados.
struct AffiliateDetailView: View {
    let profile: DrflowAffiliateProfile
    let directoryRow: CommunityProfilesService.DirectoryRow?
    let accessToken: String?
    let isSelf: Bool
    let localAvatarImage: UIImage?

    @State private var copiedLinkId: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                commissionCard
                activityRow
                privateLinksCard
                productsCard
                certificatesCard

                NavigationLink(value: AffiliateStatsRoute(profile: profile)) {
                    statisticsCTA
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(for: AffiliateStatsRoute.self) { route in
            AffiliateStatisticsView(profile: route.profile)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let row = directoryRow {
                    DashboardConnectedMemberCell(
                        row: row,
                        size: 64,
                        accessToken: accessToken,
                        isSelf: isSelf,
                        localAvatarImage: localAvatarImage,
                        showsNameBelowAvatar: false
                    )
                } else {
                    avatarPlaceholder
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(DrflowTheme.textPrimary)

                        if isSelf {
                            Text("Tú")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PremiumAccent.tabActive)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background { Capsule().fill(PremiumAccent.tabActive.opacity(0.12)) }
                        }
                    }

                    Text(profile.handle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)

                    HStack(spacing: 8) {
                        tierBadge
                        Text("#\(profile.rank) en la red")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: 22) }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(PremiumAccent.tabActive.opacity(0.15))
            .frame(width: 64, height: 64)
            .overlay {
                Text(String(profile.displayName.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PremiumAccent.tabActive)
            }
    }

    private var tierBadge: some View {
        Text(profile.tier)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background { Capsule().fill(PremiumAccent.tabActive) }
    }

    // MARK: - Comisiones

    private var commissionCard: some View {
        sectionCard(title: "Comisiones", icon: "dollarsign.circle.fill") {
            HStack(spacing: 0) {
                commissionMetric(title: "Este mes", value: DrflowAffiliateProfile.formatUSD(profile.monthlyCommission), accent: DrflowTheme.positive)
                miniDivider
                commissionMetric(title: "Proyección", value: DrflowAffiliateProfile.formatUSD(profile.projectedPayout), accent: PremiumAccent.tabActive)
                miniDivider
                commissionMetric(title: "Tasa", value: "\(profile.commissionRatePercent)%", accent: DrflowTheme.textPrimary)
            }

            VStack(spacing: 0) {
                infoRow(label: "Ventas del mes", value: DrflowAffiliateProfile.formatUSD(profile.monthlySales))
                infoRow(label: "Pendiente de liquidar", value: DrflowAffiliateProfile.formatUSD(profile.pendingCommission))
                infoRow(label: "Próximo pago", value: profile.nextPayoutDate, isLast: true)
            }
            .padding(.top, 4)
        }
    }

    private var miniDivider: some View {
        Rectangle().fill(DrflowTheme.separator).frame(width: 1, height: 36)
    }

    private func commissionMetric(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actividad

    private var activityRow: some View {
        HStack(spacing: 10) {
            activityPill(icon: "clock.fill", title: "Horas live", value: String(format: "%.0f h", profile.liveHoursThisMonth))
            activityPill(icon: "shippingbox.fill", title: "Envíos/mes", value: "\(profile.shipmentsThisMonth)")
            activityPill(icon: "cart.fill", title: "Pedidos", value: "\(profile.totalOrders)")
        }
    }

    private func activityPill(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PremiumAccent.tabActive)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background { DashboardChromeCardBackground(cornerRadius: 16) }
    }

    // MARK: - Enlaces privados

    private var privateLinksCard: some View {
        sectionCard(title: "Enlaces privados", icon: "link.circle.fill") {
            VStack(spacing: 10) {
                ForEach(profile.privateLinks) { link in
                    privateLinkRow(link)
                }
            }
        }
    }

    private func privateLinkRow(_ link: DrflowAffiliatePrivateLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let platform = DrflowSocialPlatformIcon.from(channel: link.channel) {
                    DrflowSocialIcon(platform: platform, size: 18)
                } else {
                    Image(systemName: link.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PremiumAccent.tabActive)
                }

                Text(link.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)

                Spacer()

                Button {
                    UIPasteboard.general.string = link.url
                    copiedLinkId = link.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedLinkId == link.id { copiedLinkId = nil }
                    }
                } label: {
                    Text(copiedLinkId == link.id ? "Copiado" : "Copiar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(copiedLinkId == link.id ? DrflowTheme.positive : PremiumAccent.tabActive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(PremiumAccent.tabActive.opacity(0.1))
                        }
                }
                .buttonStyle(.plain)
            }

            Text(link.url)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DrflowTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
        }
    }

    // MARK: - Productos

    private var productsCard: some View {
        sectionCard(title: "Catálogo autorizado", icon: "bag.fill") {
            if !profile.allowedProducts.isEmpty {
                Text("Puede vender")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DrflowTheme.positive)
                productList(profile.allowedProducts, allowed: true)
            }

            if !profile.blockedProducts.isEmpty {
                Text("No autorizado")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .padding(.top, profile.allowedProducts.isEmpty ? 0 : 8)
                productList(profile.blockedProducts, allowed: false)
            }
        }
    }

    private func productList(_ items: [DrflowAffiliateProductAccess], allowed: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    DrflowProductImage(assetName: item.imageAssetName, height: 44, cornerRadius: 10, padding: 4)
                        .frame(width: 44)
                        .opacity(allowed ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.productName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(allowed ? DrflowTheme.textPrimary : DrflowTheme.textTertiary)
                            .lineLimit(2)
                        if let reason = item.reason {
                            Text(reason)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(allowed ? DrflowTheme.positive : Color.orange.opacity(0.8))
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(allowed ? DrflowTheme.positive.opacity(0.06) : Color.orange.opacity(0.06))
                }
            }
        }
    }

    // MARK: - Certificados

    private var certificatesCard: some View {
        sectionCard(title: "Certificados de venta", icon: "rosette") {
            if profile.certificates.isEmpty {
                Text("Sin certificados todavía.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(profile.certificates) { cert in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PremiumAccent.tabActive.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: cert.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(PremiumAccent.tabActive)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(cert.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(DrflowTheme.textPrimary)
                                Text(cert.subtitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DrflowTheme.textSecondary)
                            }

                            Spacer(minLength: 0)

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(cert.tier)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(PremiumAccent.tabActive)
                                Text(cert.earnedDate)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DrflowTheme.textMuted)
                            }
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(DrflowTheme.cardBorder, lineWidth: 0.8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - CTA estadísticas

    private var statisticsCTA: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PremiumAccent.tabActive.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PremiumAccent.tabActive)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Ver estadísticas completas")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text("Ventas, envíos, horas live y canales")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DrflowTheme.textMuted)
        }
        .padding(16)
        .background { DashboardChromeCardBackground(cornerRadius: 20) }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PremiumAccent.tabActive)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
            content()
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: 20) }
    }

    private func infoRow(label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
            .padding(.vertical, 10)
            if !isLast { Divider().overlay(DrflowTheme.separator) }
        }
    }
}

struct AffiliateStatsRoute: Hashable {
    let profile: DrflowAffiliateProfile
}

#Preview {
    NavigationStack {
        AffiliateDetailView(
            profile: DrflowAffiliateProfile(
                userId: UUID(),
                displayName: "Sofía Mendez",
                handle: "@sofiamendez",
                rank: 1,
                tier: "Elite",
                commissionRate: 0.25,
                monthlySales: 12_400,
                monthlyCommission: 3_100,
                projectedPayout: 3_658,
                pendingCommission: 558,
                nextPayoutDate: "15 Jul 2026",
                liveHoursThisMonth: 34,
                shipmentsThisMonth: 67,
                totalOrders: 89,
                conversionRate: 6.4,
                privateLinks: [],
                productAccess: [],
                certificates: [],
                monthlyHistory: [],
                channelBreakdown: []
            ),
            directoryRow: nil,
            accessToken: nil,
            isSelf: false,
            localAvatarImage: nil
        )
    }
}
