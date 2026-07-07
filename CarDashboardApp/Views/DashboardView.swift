import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var notificationsStore: DashboardNotificationsStore

    @StateObject private var vm = DealershipStatsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var workdayStore: WorkdayStore
    @State private var homeSearchText = ""
    @State private var showFinancialStatsSheet = false
    @State private var showNotificationsSheet = false
    @State private var showAddCarSheet = false
    @State private var showRankingSheet = false
    @State private var showBlitzSheet = false
    @State private var showContractsSheet = false
    @State private var showWorkdaySheet = false

    var body: some View {
        ZStack {
            DashboardHomeBackdropImage()
            VStack(spacing: 0) {
                    // Cabecera fija (no se desplaza con el contenido), como en la referencia.
                    DashboardHomeTopBar(
                        initials: auth.userInitials,
                        profileImage: auth.profileAvatarImage,
                        searchText: $homeSearchText,
                        onStats: { showFinancialStatsSheet = true },
                        onNotifications: { showNotificationsSheet = true }
                    )
                    .appChromeHeaderOuterPadding()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            DashboardKPICarousel(vm: vm, workday: workdayStore)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)

                            DashboardQuickActionsRow(
                                onAddCar: { showAddCarSheet = true },
                                onRanking: { showRankingSheet = true },
                                onBudgets: { showContractsSheet = true },
                                onMore: { showBlitzSheet = true }
                            )

                            DashboardLeadsHomeSection(
                                stats: vm,
                                onWorkdayTap: { showWorkdaySheet = true }
                            )

                            if let err = communityVM.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFinancialStatsSheet) {
            DashboardFinancialDetailSheet(stats: vm)
        }
        .sheet(isPresented: $showNotificationsSheet) {
            DashboardNotificationsSheet(store: notificationsStore)
        }
        .sheet(isPresented: $showAddCarSheet) {
            AddVehicleSheet()
                .environmentObject(tabRouter)
                .environmentObject(auth)
                .environmentObject(carsVM)
        }
        .sheet(isPresented: $showRankingSheet) {
            CommercialRankingSheet(profiles: communityVM.directory)
        }
        .sheet(isPresented: $showBlitzSheet) {
            BlitzHubSheet()
                .environmentObject(tabRouter)
        }
        .sheet(isPresented: $showContractsSheet) {
            InvoiceAndContractsHubSheet()
        }
        .sheet(isPresented: $showWorkdaySheet) {
            WorkdayJornadaSheet()
                .environmentObject(workdayStore)
                .environmentObject(auth)
        }
        // Recalcula el resumen de inventario cuando termina la carga o cambian los coches.
        .onChange(of: carsVM.isLoadingVehicles) { _, loading in
            if loading, carsVM.cars.isEmpty {
                vm.beginStockValueLoad()
            } else if !loading {
                withAnimation(.easeOut(duration: 1.15)) {
                    vm.finishStockValueLoad(from: carsVM.cars)
                }
            }
        }
        .onChange(of: carsVM.cars) { _, newCars in
            guard !carsVM.isLoadingVehicles || !newCars.isEmpty else { return }
            withAnimation(.easeOut(duration: 1.15)) {
                vm.finishStockValueLoad(from: newCars)
            }
        }
        .onAppear {
            if carsVM.cars.isEmpty, carsVM.isLoadingVehicles {
                vm.beginStockValueLoad()
            } else {
                withAnimation(.easeOut(duration: 1.15)) {
                    vm.finishStockValueLoad(from: carsVM.cars)
                }
            }
        }
        // Métricas REALES del CRM (leads, ventas, importe del equipo). Se recargan
        // al entrar y al cambiar de usuario.
        .task(id: auth.session?.accessToken) {
            if let token = auth.session?.accessToken {
                await vm.refreshFromBackend(token: token, userId: auth.session?.user.id)
            }
        }
        .onAppear {
            workdayStore.attach(userId: auth.session?.user.id)
            Task { await WorkdayNotificationService.rescheduleAll() }
        }
        .onChange(of: auth.session?.user.id) { _, uid in
            workdayStore.attach(userId: uid)
        }
    }
}

// MARK: - Carrusel KPI (tipo Revolut)

private struct DashboardKPISlide: Identifiable {
    let id: String
    let eyebrow: String
    let value: String
    let pill: String?
}

private struct DashboardKPICarousel: View {
    @ObservedObject var vm: DealershipStatsViewModel
    @ObservedObject var workday: WorkdayStore
    @State private var selection: String = "monthly_commission"

    private var slides: [DashboardKPISlide] {
        [
            DashboardKPISlide(
                id: "monthly_commission",
                eyebrow: "Comisiones mensuales",
                value: vm.monthlyCommissionFormatted,
                pill: vm.periodDisplayLabel
            ),
            DashboardKPISlide(
                id: "calls",
                eyebrow: "Llamadas hechas",
                value: "\(workday.callsMadeToday)",
                pill: "Hoy"
            ),
            DashboardKPISlide(
                id: "messages",
                eyebrow: "Mensajes respondidos",
                value: "\(workday.messagesRespondedToday)",
                pill: "Hoy"
            ),
            DashboardKPISlide(
                id: "captured_mine",
                eyebrow: "Coches captados",
                value: "\(vm.myCapturedCars > 0 ? vm.myCapturedCars : vm.capturedCars)",
                pill: "Mis captaciones"
            ),
            DashboardKPISlide(
                id: "sold",
                eyebrow: "Coches vendidos",
                value: "\(vm.carsSold)",
                pill: vm.periodDisplayLabel
            ),
        ]
    }

    private var selectionIndex: Int {
        slides.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $selection) {
                ForEach(slides) { slide in
                    VStack(spacing: 12) {
                        Spacer(minLength: 20)

                        Text(slide.eyebrow)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)

                        if slide.id == "monthly_commission" {
                            AnimatedEURAmountText(amount: vm.monthlyCommissionAmount)
                                .animation(.easeOut(duration: 1.15), value: vm.monthlyCommissionAmount)
                        } else {
                            Text(slide.value)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.55)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }

                        if let pill = slide.pill, !pill.isEmpty {
                            Text(pill)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .environment(\.colorScheme, .dark)
                                }
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                                }
                        }

                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 268)

            HStack(spacing: 6) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, _ in
                    Capsule(style: .continuous)
                        .fill(index == selectionIndex ? Color.white : Color.white.opacity(0.28))
                        .frame(width: index == selectionIndex ? 9 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: selectionIndex)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Acciones rápidas (cristal oscuro)

private struct DashboardQuickActionsRow: View {
    var onAddCar: () -> Void
    var onRanking: () -> Void
    var onBudgets: () -> Void
    var onMore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            quickItem(icon: "plus.circle.fill", title: "Añadir un coche", action: onAddCar)
            quickItem(icon: "chart.bar.xaxis", title: "Ranking", action: onRanking)
            quickItem(icon: "doc.text.fill", title: "Contratos", action: onBudgets)
            quickItem(icon: "ellipsis.circle.fill", title: "Más", action: onMore)
        }
    }

    private func quickItem(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.35),
                                            Color.white.opacity(0.08),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(MainTabRouter())
        .environmentObject(ChatNavigationCoordinator())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(InvoiceHistoryStore())
        .environmentObject(DashboardNotificationsStore())
        .environmentObject(WorkdayStore())
        .environmentObject(ChatInboxStore())
}
