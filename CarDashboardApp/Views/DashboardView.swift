import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var invoiceHistory: InvoiceHistoryStore
    @EnvironmentObject private var notificationsStore: DashboardNotificationsStore

    @StateObject private var vm = DealershipStatsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @StateObject private var locationHub = DashboardLocationHub()
    @State private var homeSearchText = ""
    @State private var showFinancialDetail = false
    @State private var showFinancialStatsSheet = false
    @State private var showNotificationsSheet = false
    @State private var showAddCarSheet = false
    @State private var showRankingSheet = false
    @State private var showInvoiceHub = false
    @State private var showBlitzSheet = false

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
                            DashboardKPICarousel(vm: vm)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)

                            DashboardQuickActionsRow(
                                onAddCar: { showAddCarSheet = true },
                                onRanking: { showRankingSheet = true },
                                onBudgets: { showInvoiceHub = true },
                                onMore: { showBlitzSheet = true }
                            )

                            DashboardPendingCoordinatorTasksSection(
                                myUserId: auth.session?.user.id,
                                directory: communityVM.directory
                            )

                            DashboardFinancialSummaryCard(stats: vm, showDetail: $showFinancialDetail)

                            DashboardTeamMapCard(
                                community: communityVM,
                                locationHub: locationHub,
                                currentUserId: auth.session?.user.id,
                                accessToken: auth.session?.accessToken,
                                currentUserProfileImage: auth.profileAvatarImage,
                                currentUserInitials: auth.userInitials
                            )

                            DashboardConnectedUsersStrip(
                                members: communityVM.directory,
                                currentUserId: auth.session?.user.id,
                                accessToken: auth.session?.accessToken,
                                currentUserProfileImage: auth.profileAvatarImage,
                                currentUserInitials: auth.userInitials
                            )

                            if let err = communityVM.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            DashboardHomeNotificationsSection(cars: carsVM.cars)
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
        .sheet(isPresented: $showFinancialDetail) {
            DashboardFinancialDetailSheet(stats: vm)
        }
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
        .sheet(isPresented: $showInvoiceHub) {
            InvoiceAndContractsHubSheet()
                .environmentObject(invoiceHistory)
        }
        .sheet(isPresented: $showBlitzSheet) {
            BlitzHubSheet()
                .environmentObject(tabRouter)
        }
        .task(id: auth.session?.user.id) {
            if let uid = auth.session?.user.id {
                await chatInbox.refreshCoordinatorTasksFromServer(currentUserId: uid)
            }
        }
        .onAppear {
            locationHub.onLocationForUpload = { coord in
                Task { await communityVM.uploadMyCoordinate(coord) }
            }
            locationHub.requestWhenInUseAndStart()
        }
        .onDisappear {
            locationHub.stopUpdates()
        }
        .task(id: carsVM.cars.count) {
            vm.refreshFromInventory(cars: carsVM.cars)
        }
        .onChange(of: carsVM.cars) { _, newCars in
            vm.refreshFromInventory(cars: newCars)
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
    @State private var selection: String = "stock_value"

    private var slides: [DashboardKPISlide] {
        [
            DashboardKPISlide(
                id: "stock_value",
                eyebrow: "Valor total del stock",
                value: vm.totalStockValue,
                pill: vm.periodDisplayLabel
            ),
            DashboardKPISlide(
                id: "captured",
                eyebrow: "Coches captados",
                value: "\(vm.capturedCars)",
                pill: "+\(vm.capturedChangePercent)%"
            ),
            DashboardKPISlide(
                id: "dealership",
                eyebrow: "Total ganado por el concesionario",
                value: vm.totalDealershipEarnings,
                pill: vm.totalEarningsSubtitle
            ),
            DashboardKPISlide(
                id: "commissions",
                eyebrow: "Total ganado por comisiones",
                value: vm.commercialCommissions,
                pill: vm.commissionsSubtitle
            ),
            DashboardKPISlide(
                id: "vehicles_stock",
                eyebrow: "Vehículos en stock",
                value: "\(vm.vehiclesInStock)",
                pill: vm.vehiclesStockBadge.trimmingCharacters(in: .whitespaces)
            ),
            DashboardKPISlide(
                id: "sold",
                eyebrow: "Coches vendidos",
                value: "\(vm.carsSold)",
                pill: vm.periodDisplayLabel
            ),
            DashboardKPISlide(
                id: "profit",
                eyebrow: "Beneficio ventas",
                value: vm.salesProfit,
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

                        Text(slide.value)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.55)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

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
            quickItem(icon: "doc.text.fill", title: "Facturas", action: onBudgets)
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

// MARK: - Tareas coordinador asignadas a ti

private struct DashboardPendingCoordinatorTasksSection: View {
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var chatNav: ChatNavigationCoordinator
    @EnvironmentObject private var tabRouter: MainTabRouter
    let myUserId: UUID?
    let directory: [CommunityProfilesService.DirectoryRow]

    private var tasks: [CoordinatorOutboundTask] {
        guard let myUserId else { return [] }
        return chatInbox.myPendingAssignedCoordinatorTasks(myUserId: myUserId)
    }

    private static let deadlineFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func senderName(for task: CoordinatorOutboundTask) -> String {
        directory.first { $0.userId == task.senderUserId }?.resolvedDisplayName ?? "Compañero"
    }

    var body: some View {
        if tasks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tareas por hacer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                VStack(spacing: 10) {
                    ForEach(tasks.prefix(12)) { task in
                        Button {
                            openThread(for: task.senderUserId)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.cyan.opacity(0.9))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.95))
                                        .multilineTextAlignment(.leading)
                                    Text("De: \(senderName(for: task))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Text("Límite: \(Self.deadlineFmt.string(from: task.deadline))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(
                                            task.deadline < Date() && !task.isComplete
                                                ? Color.orange.opacity(0.95)
                                                : Color.white.opacity(0.45)
                                        )
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func openThread(for senderId: UUID) {
        if let thread = chatInbox.teamDirectChatThreads.first(where: { $0.peerUserId == senderId }) {
            chatNav.threadToOpen = thread
        } else if let row = directory.first(where: { $0.userId == senderId }) {
            chatNav.threadToOpen = ChatThread.makeTeamDirect(from: row)
        }
        tabRouter.selected = .chat
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
        .environmentObject(MainTabRouter())
        .environmentObject(ChatNavigationCoordinator())
        .environmentObject(ChatInboxStore())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(InvoiceHistoryStore())
        .environmentObject(DashboardNotificationsStore())
}
