import SwiftUI

enum DashboardHomeDestination: Hashable {
    case orders
    case affiliates
}

/// Panel principal de Inicio (e-commerce / afiliados) con tarjetas blancas.
struct DashboardCommerceHomeSection: View {
    @ObservedObject var stats: DealershipStatsViewModel
    @EnvironmentObject private var ordersStore: OrdersStore
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var tabRouter: MainTabRouter

    private let corner: CGFloat = 24
    private let topRowHeight: CGFloat = 176

    private var leadTotal: Int {
        let crm = stats.leadsTotal
        return crm > 0 ? crm : max(chatInbox.liveThreads.filter { $0.kind == .lead }.count, 1000)
    }

    private var ordersCount: Int {
        ordersStore.isUsingLiveData ? ordersStore.totalOrders : max(stats.carsSold, ordersStore.totalOrders)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: DashboardHomeDestination.affiliates) {
                    leadOriginCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                NavigationLink(value: DashboardHomeDestination.orders) {
                    metricCard(
                        title: "Pedidos",
                        value: "\(ordersCount)",
                        growth: "+17%",
                        sparkline: [0.35, 0.42, 0.38, 0.55, 0.62, 0.58, 0.72],
                        hint: "Ver pedidos"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
            .frame(height: topRowHeight)

            topProductsCard
        }
    }

    // MARK: - Origen de leads

    private var leadOriginCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Origen de leads")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary.opacity(0.92))

            Spacer(minLength: 10)

            HStack(alignment: .center, spacing: 10) {
                DashboardCommerceDonut(
                    segments: [
                        (Color(red: 0.32, green: 0.38, blue: 0.95), 0.50),
                        (Color(red: 0.55, green: 0.42, blue: 0.98), 0.30),
                        (Color(red: 0.22, green: 0.78, blue: 0.42), 0.15),
                        (DrflowTheme.textMuted, 0.05),
                    ],
                    centerTitle: "\(leadTotal)",
                    centerSubtitle: "Total"
                )
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 8) {
                    originLegendRow(color: Color(red: 0.32, green: 0.38, blue: 0.95), label: "TikTok Shop", pct: 50)
                    originLegendRow(color: Color(red: 0.55, green: 0.42, blue: 0.98), label: "Instagram", pct: 30)
                    originLegendRow(color: Color(red: 0.09, green: 0.47, blue: 0.95), label: "Facebook", pct: 15)
                    originLegendRow(color: DrflowTheme.textMuted, label: "En vivo", pct: 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 2) {
                Text("Ver red")
                    .font(.system(size: 9, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(PremiumAccent.tabActive)
            .padding(10)
        }
    }

    private func originLegendRow(color: Color, label: String, pct: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(pct)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary.opacity(0.92))
        }
    }

    // MARK: - Métricas

    private func metricCard(title: String, value: String, growth: String, sparkline: [CGFloat], hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)
                Spacer(minLength: 0)
                if let hint {
                    HStack(spacing: 2) {
                        Text(hint)
                            .font(.system(size: 9, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(PremiumAccent.tabActive)
                }
            }

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text(growth)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.35, green: 0.88, blue: 0.55))

            DashboardCommerceSparkline(values: sparkline)
                .frame(height: 28)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background { DashboardChromeCardBackground(cornerRadius: 18) }
    }

    // MARK: - Productos más vendidos

    private var topProductsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Productos más vendidos") {
                tabRouter.selected = .chat
            }

            VStack(spacing: 0) {
                ForEach(Array(DashboardCommerceMock.topProducts.enumerated()), id: \.element.id) { index, product in
                    topProductRow(product)
                    if index < DashboardCommerceMock.topProducts.count - 1 {
                        Divider().overlay(DrflowTheme.separator)
                    }
                }
            }
        }
        .padding(16)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
    }

    private func topProductRow(_ product: DashboardCommerceProduct) -> some View {
        Group {
            if let catalogProduct = DrflowProductCatalog.product(id: product.productId) {
                NavigationLink(value: catalogProduct) {
                    topProductRowContent(product)
                }
                .buttonStyle(.plain)
            } else {
                topProductRowContent(product)
            }
        }
    }

    private func topProductRowContent(_ product: DashboardCommerceProduct) -> some View {
        HStack(spacing: 12) {
            DrflowProductImage(assetName: product.imageAssetName, height: 48, cornerRadius: 12, padding: 4)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .lineLimit(1)
                Text("\(product.unitsSold) unidades vendidas")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(product.revenueFormatted)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(product.growthFormatted)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.88, blue: 0.55))
            }

            DashboardCommerceSparkline(values: product.sparkline, color: Color(red: 0.45, green: 0.55, blue: 1.0))
                .frame(width: 44, height: 28)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DrflowTheme.textMuted)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)
            Spacer()
            Button(action: action) {
                HStack(spacing: 3) {
                    Text("Ver todos")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Datos demo

private enum DashboardCommerceMock {
    static let topProducts: [DashboardCommerceProduct] = [
        .init(productId: "nad-plus", name: "NAD +", imageAssetName: "ProductDrgsmileNADPlus", modelResourceName: "NAD +", unitsSold: 120, revenue: 5880, growth: 32, sparkline: [0.3, 0.45, 0.42, 0.55, 0.7, 0.68, 0.82]),
        .init(productId: "energy-focus", name: "Traders Market Energy Focus", imageAssetName: "ProductDrgsmileEnergyFocus", modelResourceName: "Traders Market Energy Focus", unitsSold: 98, revenue: 6566, growth: 21, sparkline: [0.25, 0.3, 0.35, 0.4, 0.48, 0.52, 0.58]),
        .init(productId: "recovery-sleep", name: "Traders Recovery Sleep & Wellness", imageAssetName: "ProductDrgsmileRecoverySleep", modelResourceName: "Traders Recovery Sleep & Wellness", unitsSold: 76, revenue: 5092, growth: 18, sparkline: [0.2, 0.28, 0.32, 0.38, 0.42, 0.5, 0.55]),
    ]
}

private struct DashboardCommerceProduct: Identifiable {
    let id = UUID()
    let productId: String
    let name: String
    let imageAssetName: String
    let modelResourceName: String
    let unitsSold: Int
    let revenue: Double
    let growth: Int
    let sparkline: [CGFloat]

    var revenueFormatted: String {
        DealershipStatsViewModel.formatUSD(revenue)
    }

    var growthFormatted: String { "+\(growth)%" }
}


// MARK: - Gráficos

private struct DashboardCommerceDonut: View {
    let segments: [(Color, Double)]
    let centerTitle: String
    let centerSubtitle: String

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(9, geo.size.width * 0.13)
            ZStack {
                Circle()
                    .stroke(DrflowTheme.separator, lineWidth: lineWidth)
                ForEach(Array(normalizedSegments.enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(centerTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(centerSubtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }
        }
    }

    private var normalizedSegments: [(color: Color, start: CGFloat, end: CGFloat)] {
        var start: CGFloat = 0
        return segments.map { color, fraction in
            let end = start + CGFloat(max(0, min(fraction, 1)))
            defer { start = end }
            return (color, start, end)
        }
    }
}

private struct DashboardCommerceSparkline: View {
    let values: [CGFloat]
    var color: Color = Color(red: 0.45, green: 0.55, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 0.01)
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * (1 - (value - minV) / range)
            return CGPoint(x: x, y: y)
        }
    }
}
