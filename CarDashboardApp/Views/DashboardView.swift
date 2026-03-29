import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DealershipStatsViewModel()

    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                headerBlock
                statsGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dashboard de Estadísticas")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PremiumAccent.ink)

            Text("Resumen operativo del concesionario, en tiempo casi real.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                DealershipStatCard(
                    icon: "car.fill",
                    iconBackground: PremiumAccent.coral,
                    title: "Vehículos en stock",
                    value: "\(vm.vehiclesInStock)",
                    badge: vm.vehiclesStockBadge
                )

                DealershipStatCard(
                    icon: "euro.circle.fill",
                    iconBackground: PremiumAccent.ice,
                    title: "Valor total del stock",
                    value: vm.totalStockValue,
                    badge: vm.totalStockBadge
                )

                DealershipImageStatCard(
                    title: "Coches captados",
                    value: "\(vm.capturedCars)",
                    changePercent: vm.capturedChangePercent,
                    imageURL: RemoteAssets.carShowroomImageURL
                )

                DealershipStatCard(
                    icon: "eurosign.circle.fill",
                    iconBackground: PremiumAccent.amber,
                    title: "Comisiones comerciales",
                    value: vm.commercialCommissions,
                    titleUppercase: false,
                    subtitle: vm.commissionsSubtitle
                )

                DealershipStatCard(
                    icon: "checkmark.seal.fill",
                    iconBackground: PremiumAccent.mint,
                    title: "Coches vendidos",
                    value: "\(vm.carsSold)",
                    titleUppercase: false
                )

                DealershipStatCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconBackground: PremiumAccent.ice,
                    title: "Beneficio ventas",
                    value: vm.salesProfit,
                    titleUppercase: false
                )
            }

            DealershipWideStatCard(
                icon: "sparkles",
                iconBackground: PremiumAccent.mint,
                title: "Total ganado por el concesionario",
                value: vm.totalDealershipEarnings,
                subtitle: vm.totalEarningsSubtitle
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        Color.white.ignoresSafeArea()
        DashboardView()
    }
}
