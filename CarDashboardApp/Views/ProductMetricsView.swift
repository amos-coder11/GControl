import SwiftUI

/// Métricas completas de un producto: ventas, canales, afiliados y embudo.
struct ProductMetricsView: View {
    let product: DrflowProduct
    let metrics: DrflowProductMetrics

    private var maxWeeklyRevenue: Double {
        metrics.weeklySales.map(\.revenue).max() ?? 1
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                summaryHero
                weeklyChart
                channelCard
                topAffiliatesCard
                funnelCard
                operationsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle("Métricas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(product.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(2)

            HStack(spacing: 0) {
                statBlock(title: "Ingresos/mes", value: DrflowProductMetrics.formatUSD(metrics.monthlyRevenue), accent: PremiumAccent.tabActive)
                divider
                statBlock(title: "Pedidos", value: "\(metrics.monthlyOrders)", accent: DrflowTheme.textPrimary)
                divider
                statBlock(title: "Comisiones", value: DrflowProductMetrics.formatUSD(metrics.affiliateCommissionsPaid), accent: DrflowTheme.positive)
            }
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: 22) }
    }

    private var divider: some View {
        Rectangle().fill(DrflowTheme.separator).frame(width: 1, height: 40)
    }

    private func statBlock(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyChart: some View {
        sectionCard(title: "Ventas por semana", icon: "chart.bar.fill") {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(metrics.weeklySales) { week in
                    VStack(spacing: 6) {
                        Text(shortAmount(week.revenue))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DrflowTheme.textMuted)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [PremiumAccent.tabActive, PremiumAccent.tabActive.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(14, CGFloat(week.revenue / maxWeeklyRevenue) * 90))

                        Text(week.weekLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textSecondary)

                        Text("\(week.orders) ped.")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(DrflowTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    private var channelCard: some View {
        sectionCard(title: "Ingresos por canal", icon: "square.grid.2x2.fill") {
            VStack(spacing: 12) {
                ForEach(metrics.channelBreakdown) { channel in
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
                            Text(DrflowProductMetrics.formatUSD(channel.revenue))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
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

    private var topAffiliatesCard: some View {
        sectionCard(title: "Top afiliados", icon: "person.3.fill") {
            VStack(spacing: 10) {
                ForEach(Array(metrics.topAffiliates.enumerated()), id: \.element.id) { index, affiliate in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(index == 0 ? PremiumAccent.tabActive : DrflowTheme.textMuted)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(affiliate.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                            Text(affiliate.handle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DrflowTheme.textTertiary)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(DrflowProductMetrics.formatUSD(affiliate.sales))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("\(affiliate.orders) ped. · \(DrflowProductMetrics.formatUSD(affiliate.commission)) com.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DrflowTheme.textMuted)
                        }
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(index == 0 ? PremiumAccent.tabActive.opacity(0.06) : DrflowTheme.surfaceMuted)
                    }
                }
            }
        }
    }

    private var funnelCard: some View {
        sectionCard(title: "Embudo de conversión", icon: "arrow.down.right.circle.fill") {
            VStack(spacing: 10) {
                ForEach(Array(metrics.funnel.enumerated()), id: \.element.id) { index, step in
                    let maxCount = metrics.funnel.first?.count ?? 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(step.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DrflowTheme.textSecondary)
                            Spacer()
                            Text("\(step.count.formatted())")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            if let pct = step.conversionPct, index > 0 {
                                Text("(\(String(format: "%.1f", pct))%)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.positive)
                            }
                        }

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PremiumAccent.tabActive.opacity(0.7))
                                .frame(width: max(24, geo.size.width * CGFloat(step.count) / CGFloat(maxCount)))
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }

    private var operationsCard: some View {
        sectionCard(title: "Operaciones", icon: "shippingbox.fill") {
            VStack(spacing: 0) {
                opsRow(label: "Unidades vendidas", value: "\(metrics.unitsSold)")
                opsRow(label: "Envíos este mes", value: "\(metrics.shipmentsThisMonth)")
                opsRow(label: "Tasa de conversión", value: String(format: "%.1f%%", metrics.conversionRate))
                opsRow(label: "Comisión media afiliado", value: "\(metrics.avgCommissionRatePercent)%")
                opsRow(label: "Tasa de devolución", value: String(format: "%.1f%%", metrics.returnRate), isLast: true)
            }
        }
    }

    private func opsRow(label: String, value: String, isLast: Bool = false) -> some View {
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
        if value >= 1000 { return String(format: "$%.1fK", value / 1000) }
        return DrflowProductMetrics.formatUSD(value)
    }
}

#Preview {
    NavigationStack {
        ProductMetricsView(
            product: DrflowProductCatalog.energyFocus,
            metrics: DrflowProductMetricsCatalog.metrics(for: DrflowProductCatalog.energyFocus)
        )
    }
}
