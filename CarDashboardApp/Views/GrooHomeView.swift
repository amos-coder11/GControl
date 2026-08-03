import PhotosUI
import SwiftUI

// MARK: - Home

/// Home dashboard — contenedores separados con scroll.
struct GrooHomeView: View {
    private enum HomeMetricKind {
        case citas
        case pacientes
    }

    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var workdayStore: WorkdayStore
    @State private var appeared = false
    @State private var selectedWeekDay = Calendar.current.startOfDay(for: Date())
    @State private var weekDayAnimationToken = UUID()
    @State private var weekDayIconAnimate = false
    @State private var citasIconReplayToken = UUID()
    @State private var pacientesIconReplayToken = UUID()
    @State private var selectedMetric: HomeMetricKind?
    @State private var showSmileStudio3D = false
    @State private var showEmployeeManual = false
    @State private var showWorkdaySheet = false

    private var firstName: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return "there"
    }

    private static let homeBrandName = "SmileStudio"

    private var homeRoleLabel: String {
        switch groo.onboarding.workSituation {
        case "Dentist / owner":
            return "Dentista"
        case "Associate dentist":
            return "Dentista asociado"
        case "Office manager":
            return "Gerente"
        case "Front desk / reception":
            return "Recepción"
        case "Hygienist or assistant":
            return "Asistente"
        case "Other":
            return "Equipo"
        default:
            return "Asistente"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DrflowTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        Color.clear
                            .frame(height: homeHeaderSpacerHeight)

                        homeSmileStudioBanner
                        homeMetricsRow
                        homeWorkdayCard
                        homeWeekStrip
                        homeHeroCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .opacity(appeared ? 1 : 0)
                }

                homeStickyHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
                citasIconReplayToken = UUID()
                pacientesIconReplayToken = UUID()
            }
            .sheet(isPresented: $showSmileStudio3D) {
                GrooSmileStudioView(opensIn3D: true)
                    .environmentObject(groo)
                    .environmentObject(tabRouter)
            }
            .sheet(isPresented: $showEmployeeManual) {
                GControlEmployeeManualView()
            }
            .sheet(isPresented: $showWorkdaySheet) {
                WorkdayJornadaSheet()
                    .environmentObject(workdayStore)
            }
            .onReceive(NotificationCenter.default.publisher(for: .grooOpenWorkday)) { _ in
                showWorkdaySheet = true
            }
        }
    }

    // MARK: - Jornada laboral

    private var homeWorkdayCard: some View {
        GrooWorkdayHomeCard(workday: workdayStore) {
            showWorkdaySheet = true
        }
    }

    // MARK: - AI Smile Studio (banner → 3D)

    private var homeSmileStudioBanner: some View {
        Button {
            showSmileStudio3D = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.34, blue: 0.92),
                                Color(red: 0.18, green: 0.52, blue: 0.98),
                                Color(red: 0.38, green: 0.72, blue: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Self.homeBlue.opacity(0.28), radius: 16, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NUEVO")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.82, green: 0.96, blue: 0.94))
                        }

                    Text("AI Smile Studio")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("Foto → preview de sonrisa perfecta con modelo 3D")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("Probar ahora")
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Self.homeBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.trailing, 150)
                .padding(.top, 16)
                .padding(.bottom, 16)

                Image("SmileStudioDoctor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .offset(x: 10, y: 10)

                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .offset(x: -118, y: -52)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    // MARK: - Métricas (dos tarjetas)

    private static let homeBlue = Color(red: 0 / 255, green: 122 / 255, blue: 236 / 255)
    private static let homeIndigo = Color(red: 9 / 255, green: 0 / 255, blue: 255 / 255)

    private var homeMetricsRow: some View {
        HStack(spacing: 12) {
            homeMetricCard(
                kind: .citas,
                label: "Citas",
                value: "\(groo.todayPendingAppointmentsCount) hoy",
                progress: min(1, Double(groo.todayPendingAppointmentsCount) / 8),
                progressColor: Color(red: 0.18, green: 0.78, blue: 0.42)
            )

            homeMetricCard(
                kind: .pacientes,
                label: "Pacientes",
                value: "\(groo.patients.count) activos",
                progress: min(1, Double(groo.patients.count) / 20),
                progressColor: Self.homeBlue
            )
        }
    }

    @ViewBuilder
    private func homeMetricIcon(kind: HomeMetricKind) -> some View {
        switch kind {
        case .citas:
            HomeAppointmentsAnimatedIcon(
                size: 26,
                replayToken: citasIconReplayToken,
                isPlaying: true
            )
        case .pacientes:
            HomePatientsAnimatedIcon(
                size: 26,
                replayToken: pacientesIconReplayToken,
                isPlaying: true
            )
        }
    }

    private func selectMetric(_ kind: HomeMetricKind) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedMetric = kind
        }
        switch kind {
        case .citas:
            citasIconReplayToken = UUID()
        case .pacientes:
            pacientesIconReplayToken = UUID()
        }
    }

    private func homeMetricCard(
        kind: HomeMetricKind,
        label: String,
        value: String,
        progress: Double,
        progressColor: Color
    ) -> some View {
        let isSelected = selectedMetric == kind

        return Button {
            selectMetric(kind)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        homeMetricIcon(kind: kind)
                            .frame(width: 32, height: 32)

                        Text(label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(isSelected ? 0.62 : 0.42))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Text(value)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                homeProgressRing(progress: progress, color: progressColor)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                isSelected ? progressColor.opacity(0.35) : Color.black.opacity(0.06),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                    .shadow(color: .black.opacity(isSelected ? 0.06 : 0.04), radius: 10, y: 4)
            }
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    private func homeProgressRing(progress: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.06, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
    }

    // MARK: - Semana horizontal

    private var homeWeekStrip: some View {
        HStack(spacing: 6) {
            ForEach(homeWeekDays, id: \.self) { day in
                homeWeekDayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private var homeWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return [today]
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func homeWeekDayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: selectedWeekDay)
        let weekday = day.formatted(.dateTime.weekday(.abbreviated))
        let dayNum = cal.component(.day, from: day)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedWeekDay = day
                weekDayAnimationToken = UUID()
                weekDayIconAnimate = true
            }
        } label: {
            VStack(spacing: 6) {
                Text(weekday)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.88) : Color.black.opacity(0.38))

                HomeWeekDayDocumentIcon(
                    isSelected: isSelected,
                    replayToken: weekDayAnimationToken,
                    isPlaying: isSelected && weekDayIconAnimate
                )

                Text("\(dayNum)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.92) : Color.black.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero (capa-inicio)

    private var homeHeroCard: some View {
        ZStack(alignment: .bottom) {
            Image("CapaInicio")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .clipped()

            homeHeroContentCap
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }

    /// Capa inferior: difuminado + vidrio, no bloque blanco plano.
    private var homeHeroContentCap: some View {
        VStack(spacing: 0) {
            Button {
                showEmployeeManual = true
            } label: {
                Text("Empezar ahora")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.92)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                            }
                            .shadow(color: Self.homeBlue.opacity(0.12), radius: 14, y: 6)
                    }
            }
            .buttonStyle(GrooSoftPressStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.94),
                        Color.white.opacity(0.98),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.35),
                        Color.black,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - Header (blur flotante, estilo Chat)

    private var homeHeaderSpacerHeight: CGFloat { 82 }

    private var homeStickyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            topHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GrooChatTheme.floatingBlurChrome()
                .ignoresSafeArea(edges: .top)
                .padding(.bottom, -22)
        }
        .zIndex(10)
    }

    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hello, \(firstName)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.45))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Self.homeBrandName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                Spacer(minLength: 0)
                Text(homeRoleLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GrooActionHistoryView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: GrooClinicActionKind?

    private var items: [GrooClinicAction] {
        groo.filteredActionHistory(kind: filter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.97, green: 0.98, blue: 1.0))

                if items.isEmpty {
                    ContentUnavailableView(
                        "Sin acciones",
                        systemImage: "tray",
                        description: Text("Aquí verás ventas registradas y citas marcadas como completadas.")
                    )
                } else {
                    List(items) { action in
                        actionRow(action)
                            .listRowSeparator(.visible)
                    }
                    .listStyle(.plain)
                }
            }
            .background(GrooChatTheme.listBackground.ignoresSafeArea())
            .navigationTitle("Historial de acciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            filterChip(title: "Todas", kind: nil)
            filterChip(title: "Ventas", kind: .sale)
            filterChip(title: "Citas", kind: .appointment)
        }
    }

    private func filterChip(title: String, kind: GrooClinicActionKind?) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { filter = kind }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filter == kind ? .white : GrooBrand.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(filter == kind ? GrooBrand.primary : GrooBrand.primarySoft)
                }
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ action: GrooClinicAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(action.kind == .sale ? Color(red: 0.12, green: 0.58, blue: 0.28) : GrooBrand.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(
                        (action.kind == .sale ? Color(red: 0.12, green: 0.58, blue: 0.28) : GrooBrand.primary)
                            .opacity(0.12)
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(action.kindLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GrooBrand.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(GrooBrand.primarySoft))
                    Text(action.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Text(DealershipStatsViewModel.formatUSD(action.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.positive)
        }
        .padding(.vertical, 4)
    }
}

struct GrooAddSaleSheet: View {
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""

    private var parsedAmount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Concepto (ej. Blanqueamiento)", text: $title)
                    TextField("Importe", text: $amountText)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Las citas completadas en el calendario también suman en «Citas».")
                }
            }
            .navigationTitle("Registrar venta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let amount = parsedAmount {
                            groo.addSale(title: title, amount: amount)
                            dismiss()
                        }
                    }
                    .disabled(parsedAmount == nil || (parsedAmount ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GrooSoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GrooAccountView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var auth: AuthViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var showEmployeeManual = false

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        profileCard
                        subscriptionCard
                        careerCard
                        signOutButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Account")
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    isSavingPhoto = true
                    defer { isSavingPhoto = false }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await auth.updateProfileAvatar(with: image)
                    }
                    selectedPhoto = nil
                }
            }
            .sheet(isPresented: $groo.showPaywall) {
                GrooPremiumPaywallView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showEmployeeManual) {
                GControlEmployeeManualView()
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    profileAvatarView(size: 88)

                    ZStack {
                        Circle().fill(GrooBrand.purple)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSavingPhoto)

            VStack(spacing: 4) {
                Text(groo.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(auth.session?.user.email ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }

            if isSavingPhoto {
                ProgressView()
                    .tint(GrooBrand.purple)
            } else {
                Text("Tap the photo to change it")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(accountCardBackground)
    }

    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(String(groo.displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
        .shadow(color: GrooBrand.purple.opacity(0.18), radius: 12, y: 4)
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GrooBrand.purple)

            HStack {
                Text("Plan")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Text(groo.subscription == .trial ? "Trial" : groo.subscription.rawValue.capitalized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GrooBrand.purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GrooBrand.purpleSoft))
            }

            Button("Manage Premium") { groo.showPaywall = true }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(accountCardBackground)
    }

    private var careerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clinic")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GrooBrand.primary)

            accountRowButton(title: "Manual de empleado", icon: "book.pages.fill") {
                showEmployeeManual = true
            }

            Divider().opacity(0.5)

            accountRowButton(title: "View clinic assessment", icon: "chart.radar") {
                if groo.diagnostic != nil {
                    groo.phase = .careResults
                } else {
                    groo.phase = .careIntro
                }
            }

            Divider().opacity(0.5)

            accountRowButton(title: "Retake clinic assessment", icon: "arrow.clockwise") {
                groo.phase = .careIntro
            }
        }
        .padding(18)
        .background(accountCardBackground)
    }

    private func accountRowButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GrooBrand.purple)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DrflowTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    private var signOutButton: some View {
        Button("Sign out", role: .destructive) {
            Task { await auth.signOut() }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(accountCardBackground)
    }

    private var accountCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

