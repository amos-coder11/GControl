import SwiftUI

private enum WorkdayTheme {
    static let green = Color(red: 0.18, green: 0.72, blue: 0.42)
    static let greenSoft = Color(red: 0.18, green: 0.72, blue: 0.42).opacity(0.14)
    static let greenTintHex = "#2EB86B"
}

struct WorkdayView: View {
    @EnvironmentObject private var workday: WorkdayStore
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showHistory = false
    @State private var headerIconReplayToken = UUID()

    private let corner: CGFloat = 22

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                timerCard
                activityGrid
                todayStatsRow
                timelineSection
                scheduleCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(GrooClinicDesign.ScreenBackground())
        .navigationTitle("Mi jornada")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                }
                .accessibilityLabel("Historial de jornadas")
            }
        }
        .sheet(isPresented: $showHistory) {
            WorkdayHistorySheet()
                .environmentObject(workday)
        }
        .onAppear {
            workday.attach(userId: auth.session?.user.id)
            headerIconReplayToken = UUID()
        }
        .onChange(of: auth.session?.user.id) { _, uid in
            workday.attach(userId: uid)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HomeWorkdayAnimatedIcon(
                size: 22,
                replayToken: headerIconReplayToken,
                isPlaying: true,
                tintHex: WorkdayTheme.greenTintHex
            )
            .frame(width: 32, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WorkdayTheme.greenSoft)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Control de tu tiempo laboral")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(todayDayLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayDayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: Date()).capitalized
    }

    private var scheduleCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isOpen = DealershipOpeningHours.isOpenNow(at: context.date)
            let isClosedToday = DealershipOpeningHours.isClosed(on: context.date)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(GrooBrand.primarySoft)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Horario de la clínica")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DrflowTheme.textSecondary)
                        Text(DealershipOpeningHours.locationTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hoy")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DrflowTheme.textTertiary)
                        Text(DealershipOpeningHours.todayLabel(for: context.date))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                    Spacer()
                    scheduleStatusPill(
                        text: DealershipOpeningHours.statusLabel(at: context.date),
                        color: isClosedToday ? DrflowTheme.textMuted : (isOpen ? GrooBrand.primary : .orange)
                    )
                }

                VStack(spacing: 8) {
                    ForEach(DealershipOpeningHours.weeklySummary, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DrflowTheme.textSecondary)
                            Spacer()
                            Text(row.hours)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                        }
                    }
                }
            }
            .padding(18)
            .background { WorkdayLightCardBackground(cornerRadius: corner) }
        }
    }

    private func scheduleStatusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            }
    }

    private var timerCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Estado actual")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
                Spacer()
                if workday.isDayFinished {
                    statusPill(text: "Jornada finalizada", color: .orange)
                } else if let kind = workday.currentKind, workday.isActive {
                    statusPill(text: kind.title, color: kind.accent)
                } else {
                    statusPill(text: "Sin iniciar", color: DrflowTheme.textMuted)
                }
            }

            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(workday.elapsedFormatted)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(WorkdayTheme.green)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                HStack(spacing: 28) {
                    timerUnitLabel("Horas")
                    timerUnitLabel("Minutos")
                    timerUnitLabel("Segundos")
                }
            }
            .frame(maxWidth: .infinity)

            if let start = workday.jornadaStartLabel {
                Text("Inicio de jornada: \(start)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }

            if !workday.isDayFinished {
                if !workday.isActive {
                    Button(action: workday.startJornada) {
                        Label("Iniciar jornada", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(WorkdayTheme.green)
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: workday.finishJornada) {
                        Label("Finalizar jornada", systemImage: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(GrooBrand.primarySoft)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(GrooBrand.primary.opacity(0.35), lineWidth: 1)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(GrooBrand.primary)
                        Text("Has finalizado la jornada de hoy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(GrooBrand.primarySoft)
                    }

                    Button(action: workday.reactivateJornada) {
                        Label("Reactivar jornada", systemImage: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(WorkdayTheme.green)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background { WorkdayLightCardBackground(cornerRadius: corner) }
    }

    private var activityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registrar estado")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(WorkdayActivityKind.allCases) { kind in
                    WorkdayActivityCard(
                        kind: kind,
                        isSelected: workday.currentKind == kind && workday.isActive,
                        isDisabled: workday.isDayFinished
                    ) {
                        workday.switchActivity(kind)
                    }
                }
            }
        }
    }

    private var todayStatsRow: some View {
        HStack(spacing: 12) {
            statMiniCard(
                icon: "bubble.left.and.bubble.right.fill",
                tint: GrooBrand.primary,
                title: "Mensajes respondidos",
                value: "\(workday.messagesRespondedToday)"
            )
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hoy")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Spacer()
                Button("Ver historial") { showHistory = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrooBrand.primary)
            }

            if workday.todaySegments.isEmpty {
                Text("Aún no hay actividad registrada hoy.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background { WorkdayLightCardBackground(cornerRadius: corner) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workday.todaySegments.enumerated()), id: \.element.id) { index, segment in
                        WorkdayTimelineRow(
                            segment: segment,
                            isCurrent: index == workday.todaySegments.count - 1
                                && segment.end == nil
                                && workday.isActive
                        )
                    }
                }
                .padding(16)
                .background { WorkdayLightCardBackground(cornerRadius: corner) }
            }
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(color.opacity(0.14))
        }
    }

    private func timerUnitLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DrflowTheme.textTertiary)
    }

    private func statMiniCard(icon: String, tint: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background { WorkdayLightCardBackground(cornerRadius: corner) }
    }
}

// MARK: - Tarjeta de actividad

private struct WorkdayActivityCard: View {
    let kind: WorkdayActivityKind
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: kind.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(kind.accent)
                        .frame(width: 36, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(kind.accent.opacity(0.16))
                        }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(kind.accent)
                    }
                }
                Text(kind.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(kind.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? kind.accent.opacity(0.08) : Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected ? kind.accent.opacity(0.55) : DrflowTheme.cardBorder,
                                lineWidth: isSelected ? 1.2 : 1
                            )
                    }
                    .shadow(color: DrflowTheme.cardShadow.opacity(isSelected ? 0.5 : 1), radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Timeline

private struct WorkdayTimelineRow: View {
    let segment: WorkdaySegment
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(segment.kind.accent)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(DrflowTheme.separator)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.kind.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    if isCurrent {
                        Text("Actualmente")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(segment.kind.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(segment.kind.accent.opacity(0.14))
                            }
                    }
                    Spacer()
                    Text(WorkdayStore.formatDuration(segment.duration))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .monospacedDigit()
                }
                Text(WorkdayStore.formatRange(start: segment.start, end: segment.end))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Historial

struct WorkdayHistorySheet: View {
    @EnvironmentObject private var workday: WorkdayStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if workday.history.isEmpty {
                    Text("Todavía no hay jornadas finalizadas.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workday.history) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(day.displayDate)
                                .font(.headline)
                            Text("Tiempo trabajado: \(WorkdayStore.formatDuration(seconds: day.workedSeconds))")
                                .font(.subheadline)
                            Text("Mensajes: \(day.messagesResponded)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Tarjeta Inicio (tema claro · Groo Home)

struct GrooWorkdayHomeCard: View {
    @ObservedObject var workday: WorkdayStore
    var onOpenDetail: () -> Void

    @State private var iconReplayToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HomeWorkdayAnimatedIcon(
                    size: 22,
                    replayToken: iconReplayToken,
                    isPlaying: true,
                    tintHex: WorkdayTheme.greenTintHex
                )
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(WorkdayTheme.greenSoft)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mi jornada laboral")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WorkdayTheme.green)
                    Text(statusSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if workday.isActive, !workday.isDayFinished {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(workday.elapsedFormatted)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(WorkdayTheme.green)
                            .monospacedDigit()
                    }
                }
            }

            HStack(spacing: 10) {
                primaryActionButton
                if workday.isActive || workday.isDayFinished {
                    secondaryButton(title: "Ver detalle", action: onOpenDetail)
                }
            }

            HStack(spacing: 16) {
                statPill(
                    icon: "calendar",
                    label: "Semana",
                    value: WorkdayStore.formatHoursShort(seconds: workday.weekTotalWorkedSeconds)
                )
                statPill(
                    icon: "message.fill",
                    label: "Mensajes",
                    value: "\(workday.weekTotalMessages)"
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WorkdayLightCardBackground(cornerRadius: 22) }
        .onAppear { iconReplayToken = UUID() }
        .onChange(of: workday.isActive) { _, _ in iconReplayToken = UUID() }
        .onChange(of: workday.isDayFinished) { _, _ in iconReplayToken = UUID() }
    }

    private var statusSubtitle: String {
        if workday.isDayFinished {
            return "Jornada finalizada · \(WorkdayStore.formatHoursShort(seconds: workday.elapsedSeconds)) hoy"
        }
        if workday.isActive, let kind = workday.currentKind {
            if let start = workday.jornadaStartLabel {
                return "\(kind.title) · desde \(start)"
            }
            return kind.title
        }
        if DealershipOpeningHours.isClosed() {
            return "Hoy la clínica está cerrada"
        }
        return "Horario hoy: \(DealershipOpeningHours.todayLabel())"
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if workday.isDayFinished {
            actionButton(title: "Reactivar jornada", filled: true) {
                workday.reactivateJornada()
            }
        } else if workday.isActive {
            actionButton(title: "Finalizar jornada", filled: false) {
                workday.finishJornada()
            }
        } else {
            actionButton(title: "Iniciar jornada", filled: true) {
                workday.startJornada()
            }
        }
    }

    private func actionButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Color.white : WorkdayTheme.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    Capsule(style: .continuous)
                        .fill(filled ? WorkdayTheme.green : WorkdayTheme.greenSoft)
                        .overlay {
                            if !filled {
                                Capsule(style: .continuous)
                                    .strokeBorder(WorkdayTheme.green.opacity(0.35), lineWidth: 1)
                            }
                        }
                }
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DrflowTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    Capsule(style: .continuous)
                        .fill(DrflowTheme.controlFill)
                }
        }
        .buttonStyle(.plain)
    }

    private func statPill(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Fondo tarjeta clara (jornada)

private struct WorkdayLightCardBackground: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DrflowTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: DrflowTheme.cardShadow, radius: 10, y: 4)
    }
}

// MARK: - Tarjeta Inicio (tema oscuro · legacy dashboard)

struct DashboardWorkdayHomeCard: View {
    @ObservedObject var workday: WorkdayStore
    var onTap: () -> Void

    private let corner: CGFloat = 16

    var body: some View {
        Button(action: handleTap) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PremiumAccent.mint)
                            .frame(width: 32, height: 32)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(PremiumAccent.mint.opacity(0.16))
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mi jornada laboral")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.48))
                            Text(primaryTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 4)

                        if workday.isActive, !workday.isDayFinished {
                            Text(workday.elapsedFormatted)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { DashboardChromeCardBackground(cornerRadius: corner) }
            }
        }
        .buttonStyle(.plain)
    }

    private var primaryTitle: String {
        if workday.isDayFinished {
            return "Jornada finalizada hoy"
        }
        if workday.isActive, let kind = workday.currentKind {
            return kind.title
        }
        return "Inicia tu jornada laboral"
    }

    private func handleTap() {
        if !workday.isActive, !workday.isDayFinished {
            workday.startJornada()
        }
        onTap()
    }
}

// MARK: - Hoja Jornada (al tocar desde Inicio)

struct WorkdayJornadaSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WorkdayView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { dismiss() }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
