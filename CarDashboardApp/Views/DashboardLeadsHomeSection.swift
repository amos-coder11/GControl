import SwiftUI

/// Bloque principal de leads en Inicio (sustituye «Información financiera»).
struct DashboardLeadsHomeSection: View {
    @ObservedObject var stats: DealershipStatsViewModel
    var onWorkdayTap: () -> Void = {}
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var workdayStore: WorkdayStore

    @StateObject private var leadsVM = LeadsViewModel()

    private let corner: CGFloat = 24
    /// Altura compartida para que ambas tarjetas de gráficos queden iguales.
    private let chartRowHeight: CGFloat = 176
    private let chartPlotHeight: CGFloat = 96

    private var leadThreads: [ChatThread] {
        chatInbox.liveThreads.filter { $0.kind == .lead }
    }

    private var recentThreads: [ChatThread] {
        Array(leadThreads.prefix(3))
    }

    private var newLeadsCount: Int {
        leadThreads.reduce(0) { $0 + ($1.unread ?? 0) }
    }

    private var whatsAppCount: Int {
        leadThreads.filter { $0.socialSource == .whatsApp }.count
    }

    private var instagramCount: Int {
        leadThreads.filter { $0.socialSource == .instagram }.count
    }

    private var callsCount: Int {
        max(stats.appointmentsCount, leadsVM.leads.filter {
            ($0.source ?? "").lowercased().contains("llamada")
                || ($0.source ?? "").lowercased().contains("call")
        }.count)
    }

    private var totalOriginCount: Int {
        max(1, whatsAppCount + instagramCount + callsCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                workdayHistoryCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                leadsOriginCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: chartRowHeight)

            recentLeadsCard
        }
        .task(id: auth.session?.accessToken) {
            if let token = auth.session?.accessToken {
                await chatInbox.refreshCrmConversations(accessToken: token)
            }
            if leadsVM.leads.isEmpty, !leadsVM.isLoading {
                await leadsVM.load()
            }
        }
    }

    // MARK: - Gráficos

    private var workdayHistoryCard: some View {
        Button(action: onWorkdayTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Jornada laboral")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Text("7 días")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }

                Spacer(minLength: 8)

                DashboardLeadsCapsuleBars(
                    values: workdayBarValues,
                    labels: workdayBarLabels,
                    barColor: Color(red: 0.22, green: 0.78, blue: 0.45)
                )
                .frame(height: chartPlotHeight)

                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    legendDot(
                        color: Color(red: 0.22, green: 0.78, blue: 0.45),
                        label: WorkdayStore.formatHoursShort(seconds: workdayStore.weekTotalWorkedSeconds)
                    )
                    Spacer(minLength: 0)
                    legendDot(
                        color: Color(red: 0.35, green: 0.85, blue: 0.45),
                        label: "\(workdayStore.weekTotalMessages) msgs"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background { DashboardChromeCardBackground(cornerRadius: corner) }
        }
        .buttonStyle(.plain)
    }

    private var workdayBarLabels: [String] {
        workdayStore.last7Days.map(\.shortLabel)
    }

    private var workdayBarValues: [CGFloat] {
        let hours = workdayStore.last7Days.map { CGFloat($0.workedHours) }
        if hours.allSatisfy({ $0 == 0 }) {
            return Array(repeating: 0.08, count: 7)
        }
        return hours.map { max(0.08, $0) }
    }

    private var leadsOriginCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Origen de leads")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 10) {
                DashboardLeadsDonut(
                    segments: [
                        (.cyan, Double(callsCount) / Double(totalOriginCount)),
                        (Color(red: 0.22, green: 0.78, blue: 0.42), Double(whatsAppCount) / Double(totalOriginCount)),
                        (Color(red: 0.62, green: 0.45, blue: 0.98), Double(instagramCount) / Double(totalOriginCount)),
                    ],
                    centerTitle: "\(stats.leadsTotal > 0 ? stats.leadsTotal : leadThreads.count)",
                    centerSubtitle: "Total"
                )
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 9) {
                    originLegendRow(color: .cyan, label: "Llamadas", pct: callsCount)
                    originLegendRow(color: Color(red: 0.22, green: 0.78, blue: 0.42), label: "WhatsApp", pct: whatsAppCount)
                    originLegendRow(color: Color(red: 0.62, green: 0.45, blue: 0.98), label: "Instagram", pct: instagramCount)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: chartPlotHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
    }

    private var recentLeadsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Leads recientes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if newLeadsCount > 0 {
                    Text("\(newLeadsCount) nuevos")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                }
                Spacer()
                Button {
                    tabRouter.selected = .chat
                } label: {
                    HStack(spacing: 4) {
                        Text("Ver todos")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            if recentThreads.isEmpty {
                Text("Sin conversaciones recientes en Chat → Generales.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentThreads.enumerated()), id: \.element.id) { index, thread in
                        recentLeadRow(thread)
                        if index < recentThreads.count - 1 {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
            }

            Button {
                tabRouter.selected = .chat
            } label: {
                HStack(spacing: 6) {
                    Text("Ver todos los leads")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
    }

    private func recentLeadRow(_ thread: ChatThread) -> some View {
        let status = leadStatus(for: thread)

        return HStack(alignment: .center, spacing: 12) {
            leadAvatar(thread)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(thread.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(status.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.85), in: Capsule())
                }
                Text(thread.preview.isEmpty ? "Nueva consulta" : thread.preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text(thread.time.isEmpty ? "Reciente" : thread.time)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                leadActionCircle(
                    icon: "message.fill",
                    tint: Color(red: 0.12, green: 0.72, blue: 0.38)
                ) {
                    openThread(thread)
                }
                leadActionCircle(icon: "chevron.right", tint: Color.white.opacity(0.18)) {
                    openThread(thread)
                }
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func leadAvatar(_ thread: ChatThread) -> some View {
        ChatThreadAvatarView(
            thread: thread,
            accessToken: auth.session?.accessToken,
            diameter: 44
        )
    }

    private func leadActionCircle(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func openThread(_ thread: ChatThread) {
        tabRouter.selected = .chat
    }

    private func leadStatus(for thread: ChatThread) -> (label: String, color: Color) {
        if let match = leadsVM.leads.first(where: { $0.title.lowercased() == thread.title.lowercased() }),
           let status = match.status?.uppercased(), !status.isEmpty {
            return (status, statusColor(status))
        }
        if (thread.unread ?? 0) > 0 {
            return ("NUEVO", .purple)
        }
        return ("SEGUIMIENTO", .blue)
    }

    private func statusColor(_ status: String) -> Color {
        let s = status.lowercased()
        if s.contains("ganado") || s.contains("won") { return .green }
        if s.contains("oportun") { return .orange }
        if s.contains("nuevo") || s.contains("new") { return .purple }
        return .blue
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func originLegendRow(color: Color, label: String, pct: Int) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            Text("\(Int((Double(pct) / Double(totalOriginCount) * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
    }
}

// MARK: - Mini gráficos

/// Barras verticales con cápsulas (fondo gris + relleno), estilo referencia.
private struct DashboardLeadsCapsuleBars: View {
    let values: [CGFloat]
    let labels: [String]
    var barColor: Color = Color(red: 0.38, green: 0.62, blue: 1.0)

    private let trackOpacity: Double = 0.10

    var body: some View {
        GeometryReader { geo in
            let plotHeight = geo.size.height - 18
            let maxV = max(values.max() ?? 1, 0.01)
            let count = max(values.count, labels.count)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<count, id: \.self) { idx in
                    let value = idx < values.count ? values[idx] : 0
                    let label = idx < labels.count ? labels[idx] : ""
                    let fillH = max(6, (value / maxV) * plotHeight)

                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(trackOpacity))
                                .frame(height: plotHeight)
                            Capsule(style: .continuous)
                                .fill(barColor)
                                .frame(height: fillH)
                        }
                        .frame(maxWidth: .infinity)

                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

private struct DashboardLeadsDonut: View {
    let segments: [(Color, Double)]
    let centerTitle: String
    let centerSubtitle: String

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(9, geo.size.width * 0.13)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                ForEach(Array(normalizedSegments.enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(
                            segment.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(centerTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(centerSubtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
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
