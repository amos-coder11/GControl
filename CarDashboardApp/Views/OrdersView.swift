import SwiftUI

/// Pestaña Pedidos: listado de pedidos (no chat).
struct OrdersView: View {
    @EnvironmentObject private var ordersStore: OrdersStore
    @State private var selectedStatus: DrflowOrderStatus?
    @State private var searchText = ""

    private var allOrders: [DrflowOrder] {
        ordersStore.orders
    }

    private var filteredOrders: [DrflowOrder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allOrders.filter { order in
            let matchesStatus = selectedStatus == nil || order.status == selectedStatus
            let matchesSearch = query.isEmpty
                || order.customerName.lowercased().contains(query)
                || order.productTitle.lowercased().contains(query)
                || order.productsLabel.lowercased().contains(query)
                || order.channel.lowercased().contains(query)
            return matchesStatus && matchesSearch
        }
    }

    private var pendingCount: Int {
        allOrders.filter { $0.status == .pending }.count
    }

    var body: some View {
        RevolutChromeContainer {
            NavigationStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pedidos")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .padding(.top, 20)

                        if ordersStore.isLoading {
                            ProgressView("Cargando pedidos Shopify…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let err = ordersStore.lastError, !ordersStore.isUsingLiveData {
                            Text("Mostrando datos de ejemplo · \(err)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                        } else if ordersStore.isUsingLiveData, let label = ordersStore.dataSourceLabel {
                            Text(label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DrflowTheme.positive)
                        }

                        summaryRow

                        searchField

                        statusFilters

                        if filteredOrders.isEmpty {
                            ContentUnavailableView {
                                Label("Sin pedidos", systemImage: "tray")
                            } description: {
                                Text("No hay pedidos que coincidan con tu búsqueda.")
                            }
                            .foregroundStyle(DrflowTheme.textSecondary)
                            .padding(.top, 24)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(filteredOrders) { order in
                                    NavigationLink(value: order) {
                                        OrderListCard(order: order)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
                .navigationDestination(for: DrflowOrder.self) { order in
                    OrderDetailSimulationView(
                        simulation: DrflowOrderCatalog.simulation(for: order)
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await ordersStore.refresh()
        }
        .task {
            await ordersStore.refresh()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryPill(title: "Total", value: "\(allOrders.count)")
            summaryPill(title: "Pendientes", value: "\(pendingCount)")
            summaryPill(title: "Completados", value: "\(allOrders.filter { $0.status == .completed }.count)")
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            DashboardChromeCardBackground(cornerRadius: 16)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DrflowTheme.textTertiary)
            TextField("Buscar pedido o cliente", text: $searchText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            DashboardChromeSearchCapsuleBackground()
        }
    }

    private var statusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "Todos", isSelected: selectedStatus == nil) {
                    selectedStatus = nil
                }
                ForEach(DrflowOrderStatus.allCases) { status in
                    filterChip(title: status.rawValue, isSelected: selectedStatus == status) {
                        selectedStatus = status
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : DrflowTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? PremiumAccent.tabActive : DrflowTheme.surfaceMuted)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct OrderListCard: View {
    let order: DrflowOrder

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            productThumbnail

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(order.productTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Text(order.amountFormatted)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DrflowTheme.textPrimary)
                }

                if showsProductDetail {
                    Text(order.productsLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    channelChip
                    Text("@\(order.customerName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(order.timeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DrflowTheme.textMuted)
                }

                statusBadge

                HStack(spacing: 4) {
                    Text("Ver simulación")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(PremiumAccent.tabActive)
            }
        }
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: 20)
        }
    }

    private var showsProductDetail: Bool {
        order.productTitle.lowercased().contains("bundle")
            || order.productsLabel.contains("·")
    }

    @ViewBuilder
    private var productThumbnail: some View {
        if let asset = order.imageAssetName {
            DrflowProductImage(
                assetName: asset,
                height: 64,
                cornerRadius: 14,
                padding: 6
            )
            .frame(width: 64)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(DrflowTheme.textMuted)
                }
        }
    }

    private var channelChip: some View {
        HStack(spacing: 4) {
            if let platform = DrflowSocialPlatformIcon.from(channel: order.channel) {
                DrflowSocialIcon(platform: platform, size: 12)
            }
            Text(order.channel)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(channelColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(channelColor.opacity(0.1))
        }
    }

    private var statusBadge: some View {
        Text(order.status.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(statusColor.opacity(0.12))
            }
    }

    private var channelColor: Color {
        DrflowSocialPlatformIcon.from(channel: order.channel)?.labelColor ?? DrflowTheme.textSecondary
    }

    private var statusColor: Color {
        switch order.status {
        case .pending: return .orange
        case .processing: return PremiumAccent.tabActive
        case .completed: return DrflowTheme.positive
        }
    }
}

#Preview {
    OrdersView()
}
