import SwiftUI

/// Tarjeta hero de comisiones mensuales (estilo referencia, paleta clara de la app).
struct DashboardMonthlyCommissionsCard: View {
    @ObservedObject var stats: DealershipStatsViewModel
    @EnvironmentObject private var ordersStore: OrdersStore

    private let corner: CGFloat = 24

    private var totalAmount: Double {
        if ordersStore.isUsingLiveData, ordersStore.monthRevenue > 0 {
            return ordersStore.monthRevenue
        }
        return stats.monthlyCommissionAmount > 0 ? stats.monthlyCommissionAmount : 10_450
    }

    private var periodLabel: String {
        let label = stats.periodDisplayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? Self.defaultPeriodLabel() : label
    }

    private let chartValues: [CGFloat] = [2.5, 3.0, 3.8, 4.6, 5.4, 6.2, 7.0, 8.1, 9.2, 10.45]
    private let yAxisLabels = ["12K", "10K", "8K", "6K", "4K", "2K", "0"]
    private let xAxisLabels = ["01", "08", "15", "22", "29"]

    private let platformRows: [(platform: DrflowSocialPlatformIcon, title: String, amount: Double, growth: Int)] = [
        (.tiktok, "TikTok Shop", 6_250, 34),
        (.instagram, "Instagram", 3_100, 21),
        (.facebook, "Facebook", 1_000, 18),
        (.live, "En vivo", 1_100, 15),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerRow

            HStack(alignment: .top, spacing: 8) {
                yAxisLabelsColumn
                chartArea
            }
            .frame(height: 148)

            xAxisRow

            Divider().overlay(DrflowTheme.separator)

            platformBreakdownRow
        }
        .padding(18)
        .background {
            DashboardChromeCardBackground(cornerRadius: corner)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comisiones mensuales")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)

                Text(DealershipStatsViewModel.formatUSD(totalAmount))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("28% vs. mes anterior")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(DrflowTheme.positive)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                dateSelectorChip

                Text(GrooBrand.appName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(GrooBrand.purple)
                    .frame(height: 112, alignment: .bottom)
            }
        }
    }

    private var dateSelectorChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
            Text(periodLabel)
                .font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(DrflowTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(DrflowTheme.searchFill)
                .overlay {
                    Capsule()
                        .strokeBorder(DrflowTheme.cardBorder, lineWidth: 0.6)
                }
        }
    }

    private var yAxisLabelsColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(yAxisLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DrflowTheme.textMuted)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(width: 28)
    }

    private var chartArea: some View {
        GeometryReader { geo in
            let points = normalizedChartPoints(in: geo.size, maxValue: 12)
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    let y = geo.size.height * CGFloat(index) / 5
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(DrflowTheme.surfaceMuted, lineWidth: 0.5)
                }

                if points.count > 1 {
                    let areaPath = chartPath(points: points, size: geo.size, closeToBottom: true)
                    areaPath
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.52, blue: 1.0).opacity(0.35),
                                    Color(red: 0.35, green: 0.52, blue: 1.0).opacity(0.02),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    chartPath(points: points, size: geo.size, closeToBottom: false)
                        .stroke(
                            Color(red: 0.42, green: 0.58, blue: 1.0),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(Color(red: 0.42, green: 0.58, blue: 1.0))
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.5)
                            }
                            .position(point)
                    }
                }
            }
        }
    }

    private var xAxisRow: some View {
        HStack {
            Spacer().frame(width: 28)
            HStack {
                ForEach(xAxisLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DrflowTheme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var platformBreakdownRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(platformRows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        DrflowSocialIcon(platform: row.platform, size: 22)
                        Text(row.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text(DealershipStatsViewModel.formatUSD(row.amount))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(row.growth)%")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(DrflowTheme.positive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func normalizedChartPoints(in size: CGSize, maxValue: CGFloat) -> [CGPoint] {
        guard chartValues.count > 1 else { return [] }
        return chartValues.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(chartValues.count - 1)
            let y = size.height * (1 - value / maxValue)
            return CGPoint(x: x, y: y)
        }
    }

    private func chartPath(points: [CGPoint], size: CGSize, closeToBottom: Bool) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            if closeToBottom, let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: size.height))
                path.addLine(to: CGPoint(x: first.x, y: size.height))
                path.closeSubpath()
            }
        }
    }

    private static func defaultPeriodLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        let raw = f.string(from: Date())
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
