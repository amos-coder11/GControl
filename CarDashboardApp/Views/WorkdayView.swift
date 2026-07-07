import SwiftUI

struct WorkdayView: View {
    @EnvironmentObject private var workday: WorkdayStore
    @EnvironmentObject private var auth: AuthViewModel

    @State private var showHistory = false

    private let corner: CGFloat = 22

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .navigationTitle("Mi jornada")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
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
        }
        .onChange(of: auth.session?.user.id) { _, uid in
            workday.attach(userId: uid)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Control de tu tiempo laboral")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
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
                        .foregroundStyle(PremiumAccent.ice)
                        .frame(width: 40, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(PremiumAccent.ice.opacity(0.16))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Horario del concesionario")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                        Text(DealershipOpeningHours.locationTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hoy")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(DealershipOpeningHours.todayLabel(for: context.date))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    scheduleStatusPill(
                        text: DealershipOpeningHours.statusLabel(at: context.date),
                        color: isClosedToday ? .white.opacity(0.45) : (isOpen ? Color(red: 0.22, green: 0.78, blue: 0.45) : .orange)
                    )
                }

                VStack(spacing: 8) {
                    ForEach(DealershipOpeningHours.weeklySummary, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                            Spacer()
                            Text(row.hours)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                }
            }
            .padding(18)
            .background { DashboardChromeCardBackground(cornerRadius: corner) }
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
            Text(todayDayLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Text("Estado actual")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer()
                if workday.isDayFinished {
                    statusPill(text: "Jornada finalizada", color: .orange)
                } else if let kind = workday.currentKind, workday.isActive {
                    statusPill(text: kind.title, color: kind.accent)
                } else {
                    statusPill(text: "Sin iniciar", color: .white.opacity(0.45))
                }
            }

            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(workday.elapsedFormatted)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.45))
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
                                    .fill(Color(red: 0.18, green: 0.72, blue: 0.42))
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: workday.finishJornada) {
                        Label("Finalizar jornada", systemImage: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.92, green: 0.28, blue: 0.32))
                            }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.orange)
                        Text("Has finalizado la jornada de hoy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }

                    Button(action: workday.reactivateJornada) {
                        Label("Reactivar jornada", systemImage: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.18, green: 0.72, blue: 0.42))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
    }

    private var activityGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registrar estado")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

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
                icon: "phone.fill",
                tint: .cyan,
                title: "Llamadas hechas",
                value: "\(workday.callsMadeToday)"
            )
            statMiniCard(
                icon: "bubble.left.and.bubble.right.fill",
                tint: PremiumAccent.mint,
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
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button("Ver historial") { showHistory = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if workday.todaySegments.isEmpty {
                Text("Aún no hay actividad registrada hoy.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background { DashboardChromeCardBackground(cornerRadius: corner) }
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
                .background { DashboardChromeCardBackground(cornerRadius: corner) }
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
            .foregroundStyle(.white.opacity(0.38))
    }

    private func statMiniCard(icon: String, tint: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background { DashboardChromeCardBackground(cornerRadius: corner) }
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
                    .foregroundStyle(.white)
                Text(kind.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected ? kind.accent.opacity(0.65) : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 1.2 : 0.6
                            )
                    }
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
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.kind.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if isCurrent {
                        Text("Actualmente")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(segment.kind.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(segment.kind.accent.opacity(0.18))
                            }
                    }
                    Spacer()
                    Text(WorkdayStore.formatDuration(segment.duration))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit()
                }
                Text(WorkdayStore.formatRange(start: segment.start, end: segment.end))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
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
                            Text("Llamadas: \(day.callsMade) · Mensajes: \(day.messagesResponded)")
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

// MARK: - Tarjeta Inicio

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
        .preferredColorScheme(.dark)
    }
}
