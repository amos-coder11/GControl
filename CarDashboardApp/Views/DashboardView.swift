import SwiftUI

private enum DashboardScrollID {
    static let kpiCarousel = "dashboard_kpi_carousel"
}

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var carsVM: CarsViewModel
    @StateObject private var vm = DealershipStatsViewModel()
    @State private var homeSearchText = ""

    var body: some View {
        RevolutChromeContainer {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Cabecera fija (no se desplaza con el contenido), como en la referencia.
                    DashboardHomeTopBar(
                        initials: auth.userInitials,
                        profileImage: auth.profileAvatarImage,
                        searchText: $homeSearchText,
                        onStats: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(DashboardScrollID.kpiCarousel, anchor: .top)
                            }
                        },
                        onNotifications: {}
                    )
                    .appChromeHeaderOuterPadding()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            DashboardKPICarousel(vm: vm)
                                .id(DashboardScrollID.kpiCarousel)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)

                            DashboardQuickActionsRow(
                                onAddCar: {},
                                onRanking: {},
                                onBudgets: {},
                                onMore: {}
                            )

                            DashboardHomeNotificationsSection(cars: carsVM.cars)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .toolbar(.hidden, for: .navigationBar)
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

#Preview {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(CarsViewModel())
}
