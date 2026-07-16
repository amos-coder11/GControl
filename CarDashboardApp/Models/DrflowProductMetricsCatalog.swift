import Foundation

struct DrflowProductChannelMetric: Identifiable, Hashable {
    let id: String
    let channel: String
    let revenue: Double
    let orders: Int
    let sharePct: Int
}

struct DrflowProductAffiliateMetric: Identifiable, Hashable {
    let id: String
    let name: String
    let handle: String
    let sales: Double
    let orders: Int
    let commission: Double
}

struct DrflowProductWeeklyPoint: Identifiable, Hashable {
    let id: String
    let weekLabel: String
    let revenue: Double
    let orders: Int
}

struct DrflowProductFunnelStep: Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
    let conversionPct: Double?
}

struct DrflowProductMetrics: Hashable {
    let productId: String
    let monthlyRevenue: Double
    let monthlyOrders: Int
    let unitsSold: Int
    let affiliateCommissionsPaid: Double
    let avgCommissionRate: Double
    let conversionRate: Double
    let shipmentsThisMonth: Int
    let returnRate: Double
    let channelBreakdown: [DrflowProductChannelMetric]
    let topAffiliates: [DrflowProductAffiliateMetric]
    let weeklySales: [DrflowProductWeeklyPoint]
    let funnel: [DrflowProductFunnelStep]

    var avgCommissionRatePercent: Int { Int((avgCommissionRate * 100).rounded()) }

    static func formatUSD(_ value: Double) -> String {
        DealershipStatsViewModel.formatUSD(value)
    }
}

enum DrflowProductMetricsCatalog {
    static func metrics(for product: DrflowProduct) -> DrflowProductMetrics {
        catalog[product.id] ?? buildDefault(for: product)
    }

    private static let catalog: [String: DrflowProductMetrics] = {
        Dictionary(uniqueKeysWithValues: DrflowProductCatalog.products.map { ($0.id, buildDefault(for: $0)) })
    }()

    private static func buildDefault(for product: DrflowProduct) -> DrflowProductMetrics {
        switch product.id {
        case "energy-focus":
            return DrflowProductMetrics(
                productId: product.id,
                monthlyRevenue: 18_420,
                monthlyOrders: 274,
                unitsSold: 312,
                affiliateCommissionsPaid: 3_684,
                avgCommissionRate: 0.20,
                conversionRate: 5.8,
                shipmentsThisMonth: 298,
                returnRate: 1.2,
                channelBreakdown: [
                    DrflowProductChannelMetric(id: "c1", channel: "TikTok Shop", revenue: 9_210, orders: 142, sharePct: 50),
                    DrflowProductChannelMetric(id: "c2", channel: "Instagram", revenue: 5_526, orders: 78, sharePct: 30),
                    DrflowProductChannelMetric(id: "c3", channel: "En vivo", revenue: 2_763, orders: 34, sharePct: 15),
                    DrflowProductChannelMetric(id: "c4", channel: "Facebook", revenue: 921, orders: 20, sharePct: 5),
                ],
                topAffiliates: [
                    DrflowProductAffiliateMetric(id: "a1", name: "Sofía Mendez", handle: "@sofiadrg", sales: 4_820, orders: 72, commission: 1_204),
                    DrflowProductAffiliateMetric(id: "a2", name: "Carlos Ruiz", handle: "@carlosfit23", sales: 2_680, orders: 40, commission: 536),
                    DrflowProductAffiliateMetric(id: "a3", name: "Ana Ruiz", handle: "@anaruiz_live", sales: 2_140, orders: 32, commission: 535),
                ],
                weeklySales: weekly(base: 3_800, growth: 420),
                funnel: funnel(views: 24_000, clicks: 1_640, carts: 310, purchases: 274)
            )
        case "nad-plus":
            return DrflowProductMetrics(
                productId: product.id,
                monthlyRevenue: 14_210,
                monthlyOrders: 290,
                unitsSold: 318,
                affiliateCommissionsPaid: 2_842,
                avgCommissionRate: 0.20,
                conversionRate: 6.4,
                shipmentsThisMonth: 305,
                returnRate: 0.9,
                channelBreakdown: [
                    DrflowProductChannelMetric(id: "c1", channel: "TikTok Shop", revenue: 5_684, orders: 116, sharePct: 40),
                    DrflowProductChannelMetric(id: "c2", channel: "Instagram", revenue: 4_263, orders: 87, sharePct: 30),
                    DrflowProductChannelMetric(id: "c3", channel: "Facebook", revenue: 2_842, orders: 52, sharePct: 20),
                    DrflowProductChannelMetric(id: "c4", channel: "En vivo", revenue: 1_421, orders: 35, sharePct: 10),
                ],
                topAffiliates: [
                    DrflowProductAffiliateMetric(id: "a1", name: "Laura Vega", handle: "@lauravega_fit", sales: 3_430, orders: 70, commission: 686),
                    DrflowProductAffiliateMetric(id: "a2", name: "Miguel Torres", handle: "@migueltorres", sales: 2_940, orders: 60, commission: 529),
                    DrflowProductAffiliateMetric(id: "a3", name: "María Gómez", handle: "@mariagomez", sales: 1_960, orders: 40, commission: 490),
                ],
                weeklySales: weekly(base: 2_900, growth: 310),
                funnel: funnel(views: 18_500, clicks: 1_420, carts: 340, purchases: 290)
            )
        case "recovery-sleep":
            return DrflowProductMetrics(
                productId: product.id,
                monthlyRevenue: 12_060,
                monthlyOrders: 180,
                unitsSold: 195,
                affiliateCommissionsPaid: 2_412,
                avgCommissionRate: 0.20,
                conversionRate: 4.9,
                shipmentsThisMonth: 188,
                returnRate: 1.5,
                channelBreakdown: [
                    DrflowProductChannelMetric(id: "c1", channel: "Instagram", revenue: 4_824, orders: 72, sharePct: 40),
                    DrflowProductChannelMetric(id: "c2", channel: "TikTok Shop", revenue: 3_618, orders: 54, sharePct: 30),
                    DrflowProductChannelMetric(id: "c3", channel: "Facebook", revenue: 2_412, orders: 36, sharePct: 20),
                    DrflowProductChannelMetric(id: "c4", channel: "En vivo", revenue: 1_206, orders: 18, sharePct: 10),
                ],
                topAffiliates: [
                    DrflowProductAffiliateMetric(id: "a1", name: "Laura Vega", handle: "@lauravega_fit", sales: 3_350, orders: 50, commission: 670),
                    DrflowProductAffiliateMetric(id: "a2", name: "Sofía Mendez", handle: "@sofiadrg", sales: 2_010, orders: 30, commission: 502),
                    DrflowProductAffiliateMetric(id: "a3", name: "Jorge Delgado", handle: "@jorgedelgado_9", sales: 1_340, orders: 20, commission: 268),
                ],
                weeklySales: weekly(base: 2_400, growth: 280),
                funnel: funnel(views: 16_200, clicks: 980, carts: 210, purchases: 180)
            )
        default:
            return DrflowProductMetrics(
                productId: product.id,
                monthlyRevenue: product.price * 100,
                monthlyOrders: 100,
                unitsSold: 110,
                affiliateCommissionsPaid: product.price * 20,
                avgCommissionRate: 0.20,
                conversionRate: 5.0,
                shipmentsThisMonth: 105,
                returnRate: 1.0,
                channelBreakdown: [],
                topAffiliates: [],
                weeklySales: weekly(base: 2_000, growth: 200),
                funnel: funnel(views: 10_000, clicks: 600, carts: 120, purchases: 100)
            )
        }
    }

    private static func weekly(base: Double, growth: Double) -> [DrflowProductWeeklyPoint] {
        (1...4).map { week in
            DrflowProductWeeklyPoint(
                id: "w\(week)",
                weekLabel: "S\(week)",
                revenue: base + growth * Double(week - 1),
                orders: Int(40 + week * 12)
            )
        }
    }

    private static func funnel(views: Int, clicks: Int, carts: Int, purchases: Int) -> [DrflowProductFunnelStep] {
        [
            DrflowProductFunnelStep(id: "f1", label: "Vistas producto", count: views, conversionPct: nil),
            DrflowProductFunnelStep(id: "f2", label: "Clics en ficha", count: clicks, conversionPct: Double(clicks) / Double(views) * 100),
            DrflowProductFunnelStep(id: "f3", label: "Añadido al carrito", count: carts, conversionPct: Double(carts) / Double(clicks) * 100),
            DrflowProductFunnelStep(id: "f4", label: "Compras", count: purchases, conversionPct: Double(purchases) / Double(carts) * 100),
        ]
    }
}

struct ProductMetricsRoute: Hashable {
    let product: DrflowProduct
}
