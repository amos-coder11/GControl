import PhotosUI
import SwiftUI

// MARK: - Home

/// Home dashboard — contenedores separados con scroll.
struct GrooHomeView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel
    @State private var appeared = false
    @State private var showAccount = false
    @State private var showAddSale = false
    @State private var showActionHistory = false
    @State private var showEmployeeManual = false
    @State private var showSmileStudio = false
    @State private var scrollY: CGFloat = 0

    private var showsScrollHeader: Bool { scrollY > 28 }

    private var firstName: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return "there"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DrflowTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        topHeader
                        aiSmileHeroCard
                        ourServicesSection
                        ourDoctorsSection
                        clinicPulseStrip
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .opacity(appeared ? 1 : 0)
                    .grooScrollYReporter()
                }
                .grooTrackScrollY($scrollY)

                GrooActiveScrollHeader(isVisible: showsScrollHeader, backgroundColor: DrflowTheme.background) {
                    activeScrollHeaderContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
            .sheet(isPresented: $showAccount) {
                GrooAccountView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showAddSale) {
                GrooAddSaleSheet()
                    .environmentObject(groo)
            }
            .sheet(isPresented: $showActionHistory) {
                GrooActionHistoryView()
                    .environmentObject(groo)
            }
            .sheet(isPresented: $showEmployeeManual) {
                GControlEmployeeManualView()
            }
            .sheet(isPresented: $showSmileStudio) {
                GrooSmileStudioView()
                    .environmentObject(groo)
                    .environmentObject(tabRouter)
            }
        }
    }

    // MARK: - AI Smile hero

    private var aiSmileHeroCard: some View {
        Button {
            showSmileStudio = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 54, height: 54)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Smile Studio")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Photo → perfect smile preview · 3D model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                GrooBrand.primary,
                                Color(red: 0.28, green: 0.48, blue: 0.98),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: GrooBrand.primary.opacity(0.35), radius: 14, y: 6)
            }
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    // MARK: - Services

    private var ourServicesSection: some View {
        VStack(spacing: 14) {
            dentalSectionHeader(title: "Our Services") {
                tabRouter.openCalendar()
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(homeServices.enumerated()), id: \.element.id) { index, service in
                    dentalServiceCard(service, highlighted: index == 0)
                }
            }
        }
    }

    private struct HomeService: Identifiable {
        let id: String
        let title: String
        let available: Int
        let icon: String
        let action: HomeServiceAction
    }

    private enum HomeServiceAction {
        case orthodontics
        case retainers
        case cleanings
        case oralHygiene
    }

    private var homeServices: [HomeService] {
        [
            .init(id: "ortho", title: "Orthodontics", available: 7, icon: "mouth.fill", action: .orthodontics),
            .init(id: "retainers", title: "Retainers", available: 4, icon: "circle.dashed", action: .retainers),
            .init(id: "cleanings", title: "Cleanings", available: 3, icon: "sparkles", action: .cleanings),
            .init(id: "hygiene", title: "Oral Hygiene", available: 4, icon: "leaf.fill", action: .oralHygiene),
        ]
    }

    private func dentalServiceCard(_ service: HomeService, highlighted: Bool) -> some View {
        Button {
            handleService(service.action)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: service.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(highlighted ? .white : GrooBrand.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(highlighted ? Color.white.opacity(0.22) : GrooBrand.primarySoft)
                        )
                    Spacer(minLength: 0)
                    Text("This week")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(highlighted ? .white.opacity(0.95) : Color.black.opacity(0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(highlighted ? Color.white.opacity(0.2) : Color.black.opacity(0.05))
                        )
                }

                Text("Available \(service.available)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(highlighted ? .white.opacity(0.9) : Color.black.opacity(0.45))

                Text(service.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(highlighted ? .white : Color.black.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(highlighted ? GrooBrand.primary : Color.white)
                    Image(systemName: "tooth")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(highlighted ? Color.white.opacity(0.14) : Color.black.opacity(0.04))
                        .offset(x: 8, y: 10)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(highlighted ? 0.12 : 0.05), radius: highlighted ? 14 : 10, y: 5)
            }
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    private func handleService(_ action: HomeServiceAction) {
        switch action {
        case .orthodontics, .retainers:
            tabRouter.openCalendar()
        case .cleanings:
            tabRouter.openCalendar()
        case .oralHygiene:
            showSmileStudio = true
        }
    }

    // MARK: - Doctors

    private var ourDoctorsSection: some View {
        VStack(spacing: 14) {
            dentalSectionHeader(title: "Our Doctors") {
                tabRouter.openPatients()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(GrooClinicDefaults.doctors.enumerated()), id: \.offset) { index, name in
                        doctorMiniCard(name: name, specialty: doctorSpecialty(at: index))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func doctorSpecialty(at index: Int) -> String {
        let specialties = [
            "Surgery",
            "General Dentistry",
            "Orthodontics",
            "Emergency Care",
        ]
        return specialties[index % specialties.count]
    }

    private func doctorMiniCard(name: String, specialty: String) -> some View {
        Button {
            tabRouter.openCalendar()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(GrooBrand.primarySoft)
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.7))
                }

                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)

                Text(specialty)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                    Text("5.0")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .padding(14)
            .frame(width: 158, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            }
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    // MARK: - Clinic pulse (compact ops)

    private var clinicPulseStrip: some View {
        HStack(spacing: 0) {
            pulseItem(title: "Patients", value: "\(groo.patients.count)", icon: "person.2.fill") {
                tabRouter.openPatients()
            }
            pulseDivider
            pulseItem(title: "Today", value: "\(groo.todayPendingAppointmentsCount)", icon: "calendar") {
                tabRouter.openCalendar()
            }
            pulseDivider
            pulseItem(title: "Revenue", value: groo.formattedMonthlyRevenue, icon: "dollarsign") {
                showAddSale = true
            }
            pulseDivider
            pulseItem(title: "Manual", value: "ES/EN", icon: "book.pages.fill") {
                showEmployeeManual = true
            }
        }
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }

    private var pulseDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(width: 1, height: 36)
    }

    private func pulseItem(title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GrooBrand.primary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func dentalSectionHeader(title: String, seeAll: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.9))
            Spacer()
            Button(action: seeAll) {
                HStack(spacing: 4) {
                    Text("See All")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color.black.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    /// Barra compacta activa al hacer scroll (logo + acciones).
    private var activeScrollHeaderContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image("GrooLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text(GrooBrand.appName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
            }

            Spacer(minLength: 8)

            earningsHeaderPill

            Button { showAccount = true } label: {
                compactProfileAvatar(size: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private func compactProfileAvatar(size: CGFloat) -> some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(String(firstName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        .shadow(color: GrooBrand.purple.opacity(0.25), radius: 6, y: 2)
    }

    private var topHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hello, \(firstName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                HStack(spacing: 8) {
                    Image("GrooLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                    Text(GrooBrand.appName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.92))
                }
            }

            Spacer(minLength: 8)

            earningsHeaderPill

            profileAvatar
        }
    }

    private var earningsHeaderPill: some View {
        Button { showAddSale = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.58, blue: 0.28))
                Text(groo.formattedMonthlyRevenue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 6, y: 2))
        }
        .buttonStyle(.plain)
    }

    private var profileAvatar: some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(String(firstName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        .shadow(color: GrooBrand.purple.opacity(0.4), radius: 8, y: 0)
        .onTapGesture { showAccount = true }
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

