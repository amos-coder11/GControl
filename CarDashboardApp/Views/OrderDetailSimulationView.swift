import SwiftUI

/// Detalle simulado de un pedido: origen, cobro, comisiones y embudo de conversión.
struct OrderDetailSimulationView: View {
    let simulation: DrflowOrderSimulation

    private var order: DrflowOrder { simulation.order }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                attributionCard
                affiliateCard
                financialBreakdownCard
                lineItemsCard
                funnelCard
                timelineCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle("Pedido #\(order.shortId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order.productTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("@\(order.customerName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)
                }

                Spacer(minLength: 8)

                statusPill
            }

            HStack(spacing: 0) {
                heroMetric(title: "Cobrado", value: simulation.financials.totalChargedFormatted, accent: DrflowTheme.textPrimary)
                divider
                heroMetric(title: "Comisión afiliado", value: simulation.financials.affiliateCommissionFormatted, accent: DrflowTheme.positive)
                divider
                heroMetric(title: "Margen marca", value: simulation.financials.brandMarginFormatted, accent: PremiumAccent.tabActive)
            }
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: 22) }
    }

    private var statusPill: some View {
        Text(order.status.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(statusColor.opacity(0.12))
            }
    }

    private var statusColor: Color {
        switch order.status {
        case .pending: return .orange
        case .processing: return PremiumAccent.tabActive
        case .completed: return DrflowTheme.positive
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DrflowTheme.separator)
            .frame(width: 1, height: 36)
    }

    private func heroMetric(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Origen

    private var attributionCard: some View {
        sectionCard(title: "Origen del pedido", icon: "location.fill") {
            HStack(spacing: 12) {
                if let platform = DrflowSocialPlatformIcon.from(channel: order.channel) {
                    DrflowSocialIcon(platform: platform, size: 36)
                        .frame(width: 52, height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DrflowTheme.surfaceMuted)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(simulation.attribution.sourceDetail)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)

                    Text(simulation.attribution.channelLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DrflowSocialPlatformIcon.from(channel: order.channel)?.labelColor ?? DrflowTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                attributionRow(label: "Campaña", value: simulation.attribution.campaign ?? "—")
                attributionRow(label: "Código ref.", value: simulation.attribution.referralCode ?? "—")
                attributionRow(label: "Primer clic", value: simulation.attribution.clickTimestamp ?? "—")
                attributionRow(label: "Ventana conversión", value: simulation.attribution.conversionWindow, isLast: true)
            }
            .padding(.top, 4)
        }
    }

    private func attributionRow(label: String, value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)

            if !isLast {
                Divider().overlay(DrflowTheme.separator)
            }
        }
    }

    // MARK: - Afiliado

    private var affiliateCard: some View {
        sectionCard(title: "Afiliado que generó la venta", icon: "person.crop.circle.badge.checkmark") {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PremiumAccent.tabActive.opacity(0.25), Color(red: 0.62, green: 0.45, blue: 0.98).opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(simulation.affiliate.initials)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumAccent.tabActive)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(simulation.affiliate.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Text(simulation.affiliate.handle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(simulation.affiliate.tier)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(PremiumAccent.tabActive)
                        }
                    Text("\(simulation.affiliate.commissionRatePercent)% comisión")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }

            HStack(spacing: 10) {
                miniStat(title: "Ventas del mes", value: simulation.affiliate.monthlySalesFormatted)
                miniStat(title: "Comisión pedido", value: simulation.financials.affiliateCommissionFormatted, highlight: true)
            }
        }
    }

    private func miniStat(title: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? DrflowTheme.positive : DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight ? DrflowTheme.positive.opacity(0.08) : DrflowTheme.surfaceMuted)
        }
    }

    // MARK: - Finanzas

    private var financialBreakdownCard: some View {
        sectionCard(title: "Desglose económico", icon: "dollarsign.circle.fill") {
            VStack(spacing: 0) {
                moneyRow(label: "Subtotal productos", value: simulation.financials.subtotal, style: .neutral)
                moneyRow(label: "Envío", value: simulation.financials.shipping, style: .neutral)
                if simulation.financials.discount > 0 {
                    moneyRow(label: "Descuento", value: -simulation.financials.discount, style: .positive)
                }
                moneyRow(label: "Impuestos", value: simulation.financials.tax, style: .neutral)
                moneyRow(label: "Total cobrado al cliente", value: simulation.financials.totalCharged, style: .emphasis, showDividerAfter: true)

                moneyRow(label: "Comisión plataforma (\(simulation.financials.platformFeePercent)%)", value: -simulation.financials.platformFee, style: .deduction)
                moneyRow(label: "Procesamiento pago", value: -simulation.financials.paymentProcessing, style: .deduction)
                moneyRow(label: "Comisión afiliado (\(simulation.affiliate.commissionRatePercent)%)", value: -simulation.financials.affiliateCommission, style: .deduction)
                if simulation.financials.networkOverride > 0 {
                    moneyRow(label: "Override red (\(simulation.financials.networkOverridePercent)%)", value: -simulation.financials.networkOverride, style: .deduction)
                }
                moneyRow(label: "Margen neto marca", value: simulation.financials.brandMargin, style: .highlight, isLast: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Text("Pago con \(simulation.paymentMethod) · \(simulation.shippingCity)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
            .padding(.top, 8)
        }
    }

    private enum MoneyRowStyle {
        case neutral, positive, deduction, emphasis, highlight
    }

    private func moneyRow(
        label: String,
        value: Double,
        style: MoneyRowStyle,
        showDividerAfter: Bool = false,
        isLast: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: style == .emphasis || style == .highlight ? 13 : 12, weight: style == .emphasis || style == .highlight ? .bold : .medium))
                    .foregroundStyle(style == .highlight ? DrflowTheme.textPrimary : DrflowTheme.textSecondary)
                Spacer()
                Text(DrflowOrderSimulation.formatUSD(value))
                    .font(.system(size: style == .emphasis || style == .highlight ? 15 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(moneyColor(for: style, value: value))
            }
            .padding(.vertical, style == .emphasis || style == .highlight ? 12 : 9)

            if showDividerAfter || (!isLast && style != .emphasis) {
                Divider().overlay(DrflowTheme.separator)
            }
        }
    }

    private func moneyColor(for style: MoneyRowStyle, value: Double) -> Color {
        switch style {
        case .neutral: return DrflowTheme.textPrimary
        case .positive: return DrflowTheme.positive
        case .deduction: return Color.orange.opacity(0.9)
        case .emphasis: return DrflowTheme.textPrimary
        case .highlight: return PremiumAccent.tabActive
        }
    }

    // MARK: - Productos

    private var lineItemsCard: some View {
        sectionCard(title: "Productos del pedido", icon: "bag.fill") {
            VStack(spacing: 10) {
                ForEach(simulation.lineItems) { item in
                    HStack(spacing: 12) {
                        if let asset = item.imageAssetName {
                            DrflowProductImage(assetName: asset, height: 52, cornerRadius: 12, padding: 5)
                                .frame(width: 52)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DrflowTheme.surfaceMuted)
                                .frame(width: 52, height: 52)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                                .lineLimit(2)
                            Text("\(item.quantity)× · \(item.unitPriceFormatted) c/u")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DrflowTheme.textTertiary)
                        }

                        Spacer(minLength: 0)

                        Text(item.lineTotalFormatted)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Embudo

    private var funnelCard: some View {
        sectionCard(title: "Simulación de embudo", icon: "chart.bar.fill") {
            VStack(spacing: 10) {
                ForEach(Array(simulation.funnel.enumerated()), id: \.element.id) { index, step in
                    funnelStepRow(step: step, maxCount: simulation.funnel.first?.count ?? 1, isFirst: index == 0)
                }
            }

            Text("Datos simulados según el canal \(order.channel) y el comportamiento histórico de drgsmileusa.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DrflowTheme.textMuted)
                .padding(.top, 4)
        }
    }

    private func funnelStepRow(step: DrflowOrderFunnelStep, maxCount: Int, isFirst: Bool) -> some View {
        let widthRatio = maxCount > 0 ? CGFloat(step.count) / CGFloat(maxCount) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(step.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)
                Spacer()
                Text("\(step.count.formatted())")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                if let pct = step.conversionPct, !isFirst {
                    Text("(\(Int(pct))%)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DrflowTheme.positive)
                }
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PremiumAccent.tabActive.opacity(0.85), PremiumAccent.tabActive.opacity(0.45)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * widthRatio, 28))
            }
            .frame(height: 8)
        }
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        sectionCard(title: "Línea de tiempo", icon: "clock.fill") {
            VStack(spacing: 0) {
                ForEach(Array(simulation.timeline.enumerated()), id: \.element.id) { index, event in
                    timelineRow(event: event, isLast: index == simulation.timeline.count - 1)
                }
            }
        }
    }

    private func timelineRow(event: DrflowOrderTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(event.isCompleted ? DrflowTheme.positive : DrflowTheme.surfaceMuted)
                        .frame(width: 28, height: 28)
                    Image(systemName: event.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(event.isCompleted ? .white : DrflowTheme.textMuted)
                }

                if !isLast {
                    Rectangle()
                        .fill(event.isCompleted ? DrflowTheme.positive.opacity(0.35) : DrflowTheme.separator)
                        .frame(width: 2, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Spacer()
                    Text(event.timeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textMuted)
                }
                Text(event.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    // MARK: - Layout helpers

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
}

#Preview {
    NavigationStack {
        OrderDetailSimulationView(
            simulation: DrflowOrderCatalog.simulation(for: DrflowOrderCatalog.demoOrders[0])
        )
    }
}
