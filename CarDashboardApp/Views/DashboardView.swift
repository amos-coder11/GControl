import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var notificationsStore: DashboardNotificationsStore
    @EnvironmentObject private var ordersStore: OrdersStore

    @StateObject private var vm = DealershipStatsViewModel()
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var workdayStore: WorkdayStore
    @State private var homeSearchText = ""
    @State private var showFinancialStatsSheet = false
    @State private var showNotificationsSheet = false

    var body: some View {
        ZStack {
            DrflowTheme.background.ignoresSafeArea()
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
                            DashboardMonthlyCommissionsCard(stats: vm)
                                .padding(.top, 16)

                            DashboardCommerceHomeSection(stats: vm)

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
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFinancialStatsSheet) {
            DashboardFinancialDetailSheet(stats: vm)
        }
        .sheet(isPresented: $showNotificationsSheet) {
            DashboardNotificationsSheet(store: notificationsStore)
        }
        // Métricas REALES del CRM
        // al entrar y al cambiar de usuario.
        .task(id: auth.session?.accessToken) {
            if let token = auth.session?.accessToken {
                await vm.refreshFromBackend(token: token, userId: auth.session?.user.id)
                await chatInbox.refreshCrmConversations(accessToken: token)
            }
            await ordersStore.refresh()
        }
        .onAppear {
            workdayStore.attach(userId: auth.session?.user.id)
            Task { await WorkdayNotificationService.rescheduleAll() }
        }
        .onChange(of: auth.session?.user.id) { _, uid in
            workdayStore.attach(userId: uid)
        }
        .navigationDestination(for: DashboardHomeDestination.self) { destination in
            switch destination {
            case .orders:
                HomeOrdersDestinationView()
            case .affiliates:
                HomeAffiliatesDestinationView()
            }
        }
        .navigationDestination(for: DrflowProduct.self) { product in
            ProductDetailView(product: product)
        }
        .navigationDestination(for: ProductMetricsRoute.self) { route in
            ProductMetricsView(
                product: route.product,
                metrics: DrflowProductMetricsCatalog.metrics(for: route.product)
            )
        }
        .navigationDestination(for: DrflowOrder.self) { order in
            OrderDetailSimulationView(simulation: DrflowOrderCatalog.simulation(for: order))
        }
        .navigationDestination(for: AffiliateDetailRoute.self) { route in
            homeAffiliateDetail(for: route)
        }
        .navigationDestination(for: AffiliateStatsRoute.self) { route in
            AffiliateStatisticsView(profile: route.profile)
        }
    }

    @ViewBuilder
    private func homeAffiliateDetail(for route: AffiliateDetailRoute) -> some View {
        if let row = communityVM.directory.first(where: { $0.userId == route.userId }) {
            let profile = DrflowAffiliateCatalog.profile(for: row, rank: route.rank)
            AffiliateDetailView(
                profile: profile,
                directoryRow: row,
                accessToken: auth.session?.accessToken,
                isSelf: row.userId == auth.session?.user.id,
                localAvatarImage: row.userId == auth.session?.user.id ? auth.profileAvatarImage : nil
            )
        } else {
            ContentUnavailableView("Afiliado no encontrado", systemImage: "person.crop.circle.badge.xmark")
        }
    }
}

// MARK: - Destinos desde Inicio

struct HomeOrdersDestinationView: View {
    @EnvironmentObject private var ordersStore: OrdersStore

    private var orders: [DrflowOrder] { ordersStore.orders }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pedidos de la red")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)

                VStack(spacing: 12) {
                    ForEach(orders) { order in
                        NavigationLink(value: order) {
                            HomeOrderPreviewRow(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle("Pedidos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct HomeOrderPreviewRow: View {
    let order: DrflowOrder

    var body: some View {
        HStack(spacing: 12) {
            if let asset = order.imageAssetName {
                DrflowProductImage(assetName: asset, height: 52, cornerRadius: 12, padding: 4)
                    .frame(width: 52)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(order.productTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .lineLimit(2)
                Text(order.channel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(order.amountFormatted)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 3) {
                    Text("Simulación")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(PremiumAccent.tabActive)
            }
        }
        .padding(14)
        .background { DashboardChromeCardBackground(cornerRadius: 18) }
    }
}

struct HomeAffiliatesDestinationView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var communityVM: DashboardCommunityViewModel

    private var team: [(row: CommunityProfilesService.DirectoryRow, rank: Int)] {
        let sorted = communityVM.directory.sorted {
            mockSales(for: $0.userId) > mockSales(for: $1.userId)
        }
        return sorted.enumerated().map { ($0.element, $0.offset + 1) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Toca un afiliado para ver su perfil completo.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)

                if team.isEmpty {
                    ContentUnavailableView {
                        Label("Sin afiliados", systemImage: "person.2")
                    } description: {
                        Text("Aún no hay perfiles en el directorio.")
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(team, id: \.row.id) { item in
                            NavigationLink(value: AffiliateDetailRoute(userId: item.row.userId, rank: item.rank)) {
                                HomeAffiliatePreviewRow(
                                    row: item.row,
                                    rank: item.rank,
                                    accessToken: auth.session?.accessToken,
                                    isSelf: item.row.userId == auth.session?.user.id,
                                    localAvatarImage: item.row.userId == auth.session?.user.id ? auth.profileAvatarImage : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle("Afiliados")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func mockSales(for userId: UUID) -> Double {
        Double(1_200 + abs(userId.hashValue) % 28_800)
    }
}

private struct HomeAffiliatePreviewRow: View {
    let row: CommunityProfilesService.DirectoryRow
    let rank: Int
    let accessToken: String?
    let isSelf: Bool
    let localAvatarImage: UIImage?

    private var mockSales: Double {
        Double(1_200 + abs(row.userId.hashValue) % 28_800)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? PremiumAccent.tabActive : DrflowTheme.textMuted)
                .frame(width: 20)

            DashboardConnectedMemberCell(
                row: row,
                size: 48,
                accessToken: accessToken,
                isSelf: isSelf,
                localAvatarImage: localAvatarImage,
                showsNameBelowAvatar: false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(row.resolvedDisplayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text("Comisión \(DealershipStatsViewModel.formatUSD(mockSales * 0.20))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PremiumAccent.tabActive)
        }
        .padding(14)
        .background { DashboardChromeCardBackground(cornerRadius: 18) }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(MainTabRouter())
        .environmentObject(ChatNavigationCoordinator())
        .environmentObject(DashboardCommunityViewModel())
        .environmentObject(InvoiceHistoryStore())
        .environmentObject(DashboardNotificationsStore())
        .environmentObject(WorkdayStore())
        .environmentObject(ChatInboxStore())
}
