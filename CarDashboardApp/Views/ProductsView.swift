import SwiftUI

/// Catálogo de productos Dr G Smile USA.
struct ProductsView: View {
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var navigationPath = NavigationPath()

    var body: some View {
        RevolutChromeContainer {
            NavigationStack(path: $navigationPath) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Productos")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)

                        VStack(spacing: 12) {
                            ForEach(DrflowProductCatalog.products) { product in
                                NavigationLink(value: product) {
                                    ProductCatalogRow(product: product)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
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
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: tabRouter.productToOpen?.id) { _, _ in
            guard let product = tabRouter.productToOpen else { return }
            navigationPath.append(product)
            tabRouter.productToOpen = nil
        }
    }
}

private struct ProductCatalogRow: View {
    let product: DrflowProduct

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DrflowProductImage(
                assetName: product.imageAssetName,
                height: 72,
                cornerRadius: 14,
                padding: 6
            )
            .frame(width: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(product.brand)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(product.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Text(product.priceFormatted)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumAccent.tabActive)
                }

                HStack(spacing: 4) {
                    Text("Ver métricas")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(PremiumAccent.tabActive)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            DashboardChromeCardBackground(cornerRadius: 20)
        }
    }
}

struct ProductDetailView: View {
    let product: DrflowProduct

    private var metrics: DrflowProductMetrics {
        DrflowProductMetricsCatalog.metrics(for: product)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                DrflowProductImage(assetName: product.imageAssetName, height: 300, cornerRadius: 20, padding: 16)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(product.brand)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textTertiary)

                    Text(product.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DrflowTheme.textPrimary)

                    Text(product.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)

                    Text(product.priceFormatted)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PremiumAccent.tabActive)
                        .padding(.top, 4)

                    Text("Precio de referencia · PVP en tienda")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }

                metricsSummaryCard

                NavigationLink(value: ProductMetricsRoute(product: product)) {
                    metricsCTA
                }
                .buttonStyle(.plain)

                ForEach(Array(product.descriptionParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(DrflowTheme.textPrimary)
                        .lineSpacing(4)
                }

                if !product.benefits.isEmpty {
                    detailSection(title: "Beneficios") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(product.benefits, id: \.self) { benefit in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(PremiumAccent.tabActive)
                                    Text(benefit)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DrflowTheme.textPrimary)
                                }
                            }
                        }
                    }
                }

                if let supplementFacts = product.supplementFacts {
                    detailSection(title: "Información del suplemento") {
                        Text(supplementFacts)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .lineSpacing(3)
                    }
                }

                if let directions = product.directions {
                    detailSection(title: "Modo de uso") {
                        Text(directions)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DrflowTheme.textPrimary)
                    }
                }

                if !product.importantInfo.isEmpty {
                    detailSection(title: "Información importante") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(product.importantInfo, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                    Text(item)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                }
                            }
                        }
                    }
                }

                detailSection(title: "Aviso legal") {
                    Text(product.disclaimer)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .background(DrflowTheme.background.ignoresSafeArea())
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var metricsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PremiumAccent.tabActive)
                Text("Métricas del mes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }

            HStack(spacing: 0) {
                metricPill(title: "Ingresos", value: DrflowProductMetrics.formatUSD(metrics.monthlyRevenue))
                Rectangle().fill(DrflowTheme.separator).frame(width: 1, height: 32)
                metricPill(title: "Pedidos", value: "\(metrics.monthlyOrders)")
                Rectangle().fill(DrflowTheme.separator).frame(width: 1, height: 32)
                metricPill(title: "Comisiones", value: DrflowProductMetrics.formatUSD(metrics.affiliateCommissionsPaid))
            }

            HStack(spacing: 10) {
                miniMetric(icon: "shippingbox.fill", label: "Envíos", value: "\(metrics.shipmentsThisMonth)")
                miniMetric(icon: "percent", label: "Conversión", value: String(format: "%.1f%%", metrics.conversionRate))
                miniMetric(icon: "arrow.uturn.backward", label: "Devoluciones", value: String(format: "%.1f%%", metrics.returnRate))
            }
        }
        .padding(16)
        .background { DashboardChromeCardBackground(cornerRadius: 18) }
    }

    private var metricsCTA: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PremiumAccent.tabActive.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PremiumAccent.tabActive)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Ver métricas completas")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text("Canales, afiliados, embudo y ventas semanales")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DrflowTheme.textMuted)
        }
        .padding(16)
        .background { DashboardChromeCardBackground(cornerRadius: 18) }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniMetric(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PremiumAccent.tabActive)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            DashboardChromeCardBackground(cornerRadius: 18)
        }
    }
}

#Preview {
    ProductsView()
}
