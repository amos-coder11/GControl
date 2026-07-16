import SwiftUI

/// Estadísticas detalladas de un afiliado: histórico mensual, canales, envíos y horas live.
struct AffiliateStatisticsView: View {
    let profile: DrflowAffiliateProfile

    private var maxSales: Double {
        profile.monthlyHistory.map(\.sales).max() ?? 1
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                summaryHero
                monthlySalesChart
                monthlyMetricsGrid
                channelBreakdownCard
                performanceCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Resumen

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profile.displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary)

            Text("\(profile.tier) · \(profile.commissionRatePercent)% comisión · \(String(format: "%.1f", profile.conversionRate))% conversión")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DrflowTheme.textSecondary)

            HStack(spacing: 0) {
                statBlock(title: "Ventas 6M", value: DrflowAffiliateProfile.formatUSD(sixMonthSales))
                divider
                statBlock(title: "Comisión 6M", value: DrflowAffiliateProfile.formatUSD(sixMonthCommission))
                divider
                statBlock(title: "Envíos 6M", value: "\(sixMonthShipments)")
            }
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: 22) }
    }

    private var sixMonthSales: Double {
        profile.monthlyHistory.reduce(0) { $0 + $1.sales }
    }

    private var sixMonthCommission: Double {
        profile.monthlyHistory.reduce(0) { $0 + $1.commission }
    }

    private var sixMonthShipments: Int {
        profile.monthlyHistory.reduce(0) { $0 + $1.shipments }
    }

    private var divider: some View {
        Rectangle().fill(DrflowTheme.separator).frame(width: 1, height: 40)
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Gráfico ventas

    private var monthlySalesChart: some View {
        sectionCard(title: "Ventas por mes", icon: "chart.bar.fill") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(profile.monthlyHistory) { month in
                    VStack(spacing: 6) {
                        Text(shortAmount(month.sales))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DrflowTheme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [PremiumAccent.tabActive, PremiumAccent.tabActive.opacity(0.45)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(12, CGFloat(month.sales / maxSales) * 100))

                        Text(month.monthLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140, alignment: .bottom)
        }
    }

    // MARK: - Grid mensual

    private var monthlyMetricsGrid: some View {
        sectionCard(title: "Horas live y envíos / mes", icon: "calendar") {
            VStack(spacing: 0) {
                HStack {
                    Text("Mes")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Live")
                        .frame(width: 52, alignment: .trailing)
                    Text("Envíos")
                        .frame(width: 52, alignment: .trailing)
                    Text("Comisión")
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)
                .padding(.bottom, 8)

                ForEach(Array(profile.monthlyHistory.enumerated()), id: \.element.id) { index, month in
                    HStack {
                        Text(month.monthLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.0fh", month.liveHours))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(PremiumAccent.tabActive)
                            .frame(width: 52, alignment: .trailing)

                        Text("\(month.shipments)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .frame(width: 52, alignment: .trailing)

                        Text(DrflowAffiliateProfile.formatUSD(month.commission))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.positive)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 10)

                    if index < profile.monthlyHistory.count - 1 {
                        Divider().overlay(DrflowTheme.separator)
                    }
                }
            }
        }
    }

    // MARK: - Canales

    private var channelBreakdownCard: some View {
        sectionCard(title: "Ventas por canal", icon: "square.grid.2x2.fill") {
            VStack(spacing: 12) {
                ForEach(profile.channelBreakdown) { channel in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let platform = DrflowSocialPlatformIcon.from(channel: channel.channel) {
                                DrflowSocialIcon(platform: platform, size: 20)
                            }
                            Text(channel.channel)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                            Spacer()
                            Text("\(channel.sharePct)%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(PremiumAccent.tabActive)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DrflowTheme.surfaceMuted)
                                Capsule()
                                    .fill(PremiumAccent.tabActive.opacity(0.75))
                                    .frame(width: geo.size.width * CGFloat(channel.sharePct) / 100)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text(DrflowAffiliateProfile.formatUSD(channel.sales))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(DrflowTheme.textPrimary)
                            Spacer()
                            Text("\(channel.orders) pedidos")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DrflowTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rendimiento

    private var performanceCard: some View {
        sectionCard(title: "Rendimiento actual", icon: "gauge.with.needle.fill") {
            VStack(spacing: 0) {
                perfRow(label: "Conversión media", value: String(format: "%.1f%%", profile.conversionRate))
                perfRow(label: "Horas live este mes", value: String(format: "%.0f h", profile.liveHoursThisMonth))
                perfRow(label: "Envíos este mes", value: "\(profile.shipmentsThisMonth)")
                perfRow(label: "Pedidos totales", value: "\(profile.totalOrders)")
                perfRow(label: "Ranking en red", value: "#\(profile.rank)", isLast: true)
            }
        }
    }

    private func perfRow(label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
            .padding(.vertical, 10)
            if !isLast { Divider().overlay(DrflowTheme.separator) }
        }
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

    private func shortAmount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fK", value / 1000)
        }
        return DrflowAffiliateProfile.formatUSD(value)
    }
}

#Preview {
    NavigationStack {
        AffiliateStatisticsView(
            profile: DrflowAffiliateCatalog.profile(
                for: CommunityProfilesService.DirectoryRow(
                    id: UUID(),
                    userId: UUID(),
                    fullName: "Sofía Mendez",
                    avatarUrl: nil,
                    latitude: nil,
                    longitude: nil,
                    organizationId: nil,
                    locationUpdatedAt: nil
                ),
                rank: 1
            )
        )
    }
}
