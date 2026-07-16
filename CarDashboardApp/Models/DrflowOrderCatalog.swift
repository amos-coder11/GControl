import Foundation

enum DrflowOrderStatus: String, CaseIterable, Identifiable {
    case pending = "Pendiente"
    case processing = "En proceso"
    case completed = "Completado"

    var id: String { rawValue }
}

struct DrflowOrder: Identifiable, Hashable {
    let id: String
    let customerName: String
    /// Nombre principal del producto (o resumen del pedido).
    let productTitle: String
    let productsLabel: String
    let imageAssetName: String?
    let amount: Double
    let timeLabel: String
    let status: DrflowOrderStatus
    let channel: String

    var shortId: String {
        id.replacingOccurrences(of: "ord-", with: "")
    }

    var amountFormatted: String {
        DrflowOrderSimulation.formatUSD(amount)
    }
}

// MARK: - Simulación de pedido

struct DrflowOrderLineItem: Identifiable, Hashable {
    let id: String
    let name: String
    let quantity: Int
    let unitPrice: Double
    let imageAssetName: String?

    var lineTotal: Double { Double(quantity) * unitPrice }

    var unitPriceFormatted: String { DrflowOrderSimulation.formatUSD(unitPrice) }
    var lineTotalFormatted: String { DrflowOrderSimulation.formatUSD(lineTotal) }
}

struct DrflowOrderAffiliate: Hashable {
    let name: String
    let handle: String
    let tier: String
    let commissionRate: Double
    let monthlySales: Double

    var commissionRatePercent: Int { Int((commissionRate * 100).rounded()) }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    var monthlySalesFormatted: String { DrflowOrderSimulation.formatUSD(monthlySales) }
}

struct DrflowOrderAttribution: Hashable {
    let sourceDetail: String
    let channelLabel: String
    let campaign: String?
    let referralCode: String?
    let clickTimestamp: String?
    let conversionWindow: String
}

struct DrflowOrderFinancials: Hashable {
    let subtotal: Double
    let shipping: Double
    let discount: Double
    let tax: Double
    let totalCharged: Double
    let platformFee: Double
    let platformFeePercent: Int
    let paymentProcessing: Double
    let affiliateCommission: Double
    let networkOverride: Double
    let networkOverridePercent: Int
    let brandMargin: Double

    var netRevenue: Double {
        totalCharged - platformFee - paymentProcessing
    }

    var totalChargedFormatted: String { DrflowOrderSimulation.formatUSD(totalCharged) }
    var affiliateCommissionFormatted: String { DrflowOrderSimulation.formatUSD(affiliateCommission) }
    var brandMarginFormatted: String { DrflowOrderSimulation.formatUSD(brandMargin) }
}

struct DrflowOrderFunnelStep: Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
    let conversionPct: Double?
}

struct DrflowOrderTimelineEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let timeLabel: String
    let icon: String
    let isCompleted: Bool
}

struct DrflowOrderSimulation: Hashable {
    let order: DrflowOrder
    let lineItems: [DrflowOrderLineItem]
    let affiliate: DrflowOrderAffiliate
    let attribution: DrflowOrderAttribution
    let financials: DrflowOrderFinancials
    let funnel: [DrflowOrderFunnelStep]
    let timeline: [DrflowOrderTimelineEvent]
    let paymentMethod: String
    let shippingCity: String

    static func formatUSD(_ value: Double) -> String {
        DealershipStatsViewModel.formatUSD(value)
    }
}

enum DrflowOrderCatalog {
    static let demoOrders: [DrflowOrder] = [
        DrflowOrder(
            id: "ord-1001",
            customerName: "jorgedelgado_9",
            productTitle: "NAD + · Traders Market Energy Focus",
            productsLabel: "2 productos · drgsmileusa",
            imageAssetName: DrflowProductCatalog.nadPlus.imageAssetName,
            amount: 116,
            timeLabel: "Hoy, 12:30",
            status: .processing,
            channel: "TikTok Shop"
        ),
        DrflowOrder(
            id: "ord-1002",
            customerName: "camivillalba",
            productTitle: "Traders Recovery Sleep & Wellness",
            productsLabel: "1 producto · drgsmileusa",
            imageAssetName: DrflowProductCatalog.recoverySleep.imageAssetName,
            amount: 67,
            timeLabel: "Ayer",
            status: .completed,
            channel: "Instagram"
        ),
        DrflowOrder(
            id: "ord-1003",
            customerName: "raquelonodri",
            productTitle: "Bundle 3 productos",
            productsLabel: "NAD + · Energy Focus · Recovery Sleep",
            imageAssetName: DrflowProductCatalog.energyFocus.imageAssetName,
            amount: 132.40,
            timeLabel: "Hoy, 10:15",
            status: .pending,
            channel: "Facebook"
        ),
        DrflowOrder(
            id: "ord-1004",
            customerName: "mariagomez",
            productTitle: "NAD +",
            productsLabel: "1 producto · drgsmileusa",
            imageAssetName: DrflowProductCatalog.nadPlus.imageAssetName,
            amount: 49,
            timeLabel: "Hoy, 09:02",
            status: .completed,
            channel: "En vivo"
        ),
        DrflowOrder(
            id: "ord-1005",
            customerName: "carlosfit23",
            productTitle: "Traders Market Energy Focus",
            productsLabel: "1 producto · drgsmileusa",
            imageAssetName: DrflowProductCatalog.energyFocus.imageAssetName,
            amount: 67,
            timeLabel: "Ayer, 18:40",
            status: .processing,
            channel: "TikTok Shop"
        ),
    ]

    static func mergedOrders(liveThreads: [ChatThread]) -> [DrflowOrder] {
        demoOrders
    }

    static func order(fromShopify dto: ShopifyOrderDTO) -> DrflowOrder {
        DrflowOrder(
            id: dto.id,
            customerName: dto.customerName,
            productTitle: dto.productTitle,
            productsLabel: dto.productsLabel,
            imageAssetName: imageAssetName(forProductTitle: dto.productTitle),
            amount: dto.amount,
            timeLabel: dto.timeLabel,
            status: status(fromShopify: dto.status),
            channel: dto.channel
        )
    }

    private static func status(fromShopify raw: String) -> DrflowOrderStatus {
        switch raw.lowercased() {
        case "completed", "completado":
            return .completed
        case "processing", "en proceso":
            return .processing
        default:
            return .pending
        }
    }

    private static func imageAssetName(forProductTitle title: String) -> String? {
        let lower = title.lowercased()
        if lower.contains("nad") {
            return DrflowProductCatalog.nadPlus.imageAssetName
        }
        if lower.contains("recovery") || lower.contains("sleep") {
            return DrflowProductCatalog.recoverySleep.imageAssetName
        }
        if lower.contains("energy") || lower.contains("focus") {
            return DrflowProductCatalog.energyFocus.imageAssetName
        }
        return DrflowProductCatalog.products.first?.imageAssetName
    }

    static func simulation(for order: DrflowOrder) -> DrflowOrderSimulation {
        simulations[order.id] ?? buildDefaultSimulation(for: order)
    }

    private static let simulations: [String: DrflowOrderSimulation] = {
        Dictionary(uniqueKeysWithValues: demoOrders.map { ($0.id, buildDefaultSimulation(for: $0)) })
    }()

    private static func buildDefaultSimulation(for order: DrflowOrder) -> DrflowOrderSimulation {
        let lineItems = lineItems(for: order)
        let subtotal = lineItems.reduce(0) { $0 + $1.lineTotal }
        let shipping = shippingFee(for: order)
        let discount = discount(for: order, subtotal: subtotal)
        let tax = taxedAmount(subtotal: subtotal - discount, shipping: shipping)
        let totalCharged = order.amount
        let platformFeePercent = platformFeePercent(for: order.channel)
        let platformFee = (subtotal * Double(platformFeePercent) / 100).rounded(toPlaces: 2)
        let paymentProcessing = (totalCharged * 0.029 + 0.30).rounded(toPlaces: 2)
        let affiliate = affiliate(for: order)
        let affiliateCommission = (subtotal * affiliate.commissionRate).rounded(toPlaces: 2)
        let networkOverridePercent = 3
        let networkOverride = (subtotal * Double(networkOverridePercent) / 100).rounded(toPlaces: 2)
        let brandMargin = (totalCharged - platformFee - paymentProcessing - affiliateCommission - networkOverride).rounded(toPlaces: 2)

        return DrflowOrderSimulation(
            order: order,
            lineItems: lineItems,
            affiliate: affiliate,
            attribution: attribution(for: order),
            financials: DrflowOrderFinancials(
                subtotal: subtotal,
                shipping: shipping,
                discount: discount,
                tax: tax,
                totalCharged: totalCharged,
                platformFee: platformFee,
                platformFeePercent: platformFeePercent,
                paymentProcessing: paymentProcessing,
                affiliateCommission: affiliateCommission,
                networkOverride: networkOverride,
                networkOverridePercent: networkOverridePercent,
                brandMargin: brandMargin
            ),
            funnel: funnel(for: order),
            timeline: timeline(for: order),
            paymentMethod: paymentMethod(for: order),
            shippingCity: shippingCity(for: order)
        )
    }

    private static func lineItems(for order: DrflowOrder) -> [DrflowOrderLineItem] {
        switch order.id {
        case "ord-1001":
            return [
                DrflowOrderLineItem(id: "li-1", name: "NAD +", quantity: 1, unitPrice: 49, imageAssetName: DrflowProductCatalog.nadPlus.imageAssetName),
                DrflowOrderLineItem(id: "li-2", name: "Traders Market Energy Focus", quantity: 1, unitPrice: 67, imageAssetName: DrflowProductCatalog.energyFocus.imageAssetName),
            ]
        case "ord-1003":
            return [
                DrflowOrderLineItem(id: "li-3", name: "NAD +", quantity: 1, unitPrice: 49, imageAssetName: DrflowProductCatalog.nadPlus.imageAssetName),
                DrflowOrderLineItem(id: "li-4", name: "Traders Market Energy Focus", quantity: 1, unitPrice: 67, imageAssetName: DrflowProductCatalog.energyFocus.imageAssetName),
                DrflowOrderLineItem(id: "li-5", name: "Traders Recovery Sleep & Wellness", quantity: 1, unitPrice: 67, imageAssetName: DrflowProductCatalog.recoverySleep.imageAssetName),
            ]
        default:
            return [
                DrflowOrderLineItem(
                    id: "li-\(order.id)",
                    name: order.productTitle,
                    quantity: 1,
                    unitPrice: order.amount,
                    imageAssetName: order.imageAssetName
                ),
            ]
        }
    }

    private static func affiliate(for order: DrflowOrder) -> DrflowOrderAffiliate {
        switch order.channel {
        case "TikTok Shop":
            return DrflowOrderAffiliate(name: "Sofía Mendez", handle: "@sofiadrg", tier: "Elite", commissionRate: 0.22, monthlySales: 4_820)
        case "Instagram":
            return DrflowOrderAffiliate(name: "Laura Vega", handle: "@lauravega_fit", tier: "Pro", commissionRate: 0.20, monthlySales: 2_940)
        case "Facebook":
            return DrflowOrderAffiliate(name: "Miguel Torres", handle: "@migueltorres", tier: "Pro", commissionRate: 0.18, monthlySales: 1_760)
        case "En vivo":
            return DrflowOrderAffiliate(name: "Ana Ruiz", handle: "@anaruiz_live", tier: "Elite Live", commissionRate: 0.25, monthlySales: 6_100)
        default:
            return DrflowOrderAffiliate(name: "Red DrG", handle: "@drgsmileusa", tier: "Base", commissionRate: 0.15, monthlySales: 980)
        }
    }

    private static func attribution(for order: DrflowOrder) -> DrflowOrderAttribution {
        switch order.channel {
        case "TikTok Shop":
            return DrflowOrderAttribution(
                sourceDetail: "TikTok Shop · Vídeo orgánico #847",
                channelLabel: "TikTok Shop",
                campaign: "Energy Focus Q3",
                referralCode: "SOFIA-TT-22",
                clickTimestamp: "Hoy, 11:58",
                conversionWindow: "32 min"
            )
        case "Instagram":
            return DrflowOrderAttribution(
                sourceDetail: "Instagram · Story con enlace swipe-up",
                channelLabel: "Instagram",
                campaign: "Recovery Sleep Launch",
                referralCode: "LAURA-IG-09",
                clickTimestamp: "Ayer, 20:14",
                conversionWindow: "2 h 10 min"
            )
        case "Facebook":
            return DrflowOrderAttribution(
                sourceDetail: "Facebook · Grupo Wellness USA",
                channelLabel: "Facebook",
                campaign: "Bundle Verano",
                referralCode: "MIGUEL-FB-03",
                clickTimestamp: "Hoy, 09:47",
                conversionWindow: "28 min"
            )
        case "En vivo":
            return DrflowOrderAttribution(
                sourceDetail: "En vivo · Live TikTok #52",
                channelLabel: "En vivo",
                campaign: "Live NAD+ Flash Sale",
                referralCode: "ANA-LIVE-52",
                clickTimestamp: "Hoy, 08:55",
                conversionWindow: "7 min"
            )
        default:
            return DrflowOrderAttribution(
                sourceDetail: order.channel,
                channelLabel: order.channel,
                campaign: nil,
                referralCode: nil,
                clickTimestamp: nil,
                conversionWindow: "—"
            )
        }
    }

    private static func funnel(for order: DrflowOrder) -> [DrflowOrderFunnelStep] {
        switch order.channel {
        case "TikTok Shop":
            return [
                DrflowOrderFunnelStep(id: "f1", label: "Impresiones", count: 18_400, conversionPct: nil),
                DrflowOrderFunnelStep(id: "f2", label: "Clics en producto", count: 1_260, conversionPct: 6.8),
                DrflowOrderFunnelStep(id: "f3", label: "Añadido al carrito", count: 214, conversionPct: 17.0),
                DrflowOrderFunnelStep(id: "f4", label: "Compra completada", count: 38, conversionPct: 17.8),
            ]
        case "Instagram":
            return [
                DrflowOrderFunnelStep(id: "f1", label: "Alcance story", count: 4_200, conversionPct: nil),
                DrflowOrderFunnelStep(id: "f2", label: "Clics enlace", count: 380, conversionPct: 9.0),
                DrflowOrderFunnelStep(id: "f3", label: "Checkout iniciado", count: 74, conversionPct: 19.5),
                DrflowOrderFunnelStep(id: "f4", label: "Compra completada", count: 21, conversionPct: 28.4),
            ]
        case "Facebook":
            return [
                DrflowOrderFunnelStep(id: "f1", label: "Miembros grupo", count: 12_800, conversionPct: nil),
                DrflowOrderFunnelStep(id: "f2", label: "Clics publicación", count: 520, conversionPct: 4.1),
                DrflowOrderFunnelStep(id: "f3", label: "Interés en bundle", count: 96, conversionPct: 18.5),
                DrflowOrderFunnelStep(id: "f4", label: "Compra completada", count: 14, conversionPct: 14.6),
            ]
        case "En vivo":
            return [
                DrflowOrderFunnelStep(id: "f1", label: "Espectadores live", count: 2_850, conversionPct: nil),
                DrflowOrderFunnelStep(id: "f2", label: "Clics pin producto", count: 640, conversionPct: 22.5),
                DrflowOrderFunnelStep(id: "f3", label: "Checkout rápido", count: 118, conversionPct: 18.4),
                DrflowOrderFunnelStep(id: "f4", label: "Compra completada", count: 47, conversionPct: 39.8),
            ]
        default:
            return [
                DrflowOrderFunnelStep(id: "f1", label: "Visitas", count: 1_000, conversionPct: nil),
                DrflowOrderFunnelStep(id: "f2", label: "Clics", count: 120, conversionPct: 12),
                DrflowOrderFunnelStep(id: "f3", label: "Carrito", count: 24, conversionPct: 20),
                DrflowOrderFunnelStep(id: "f4", label: "Compra", count: 5, conversionPct: 20.8),
            ]
        }
    }

    private static func timeline(for order: DrflowOrder) -> [DrflowOrderTimelineEvent] {
        let completed = order.status == .completed
        let processing = order.status == .processing || completed

        return [
            DrflowOrderTimelineEvent(
                id: "t1",
                title: "Pedido recibido",
                subtitle: "Cliente \(order.customerName) completó el checkout.",
                timeLabel: order.timeLabel,
                icon: "cart.fill",
                isCompleted: true
            ),
            DrflowOrderTimelineEvent(
                id: "t2",
                title: "Pago confirmado",
                subtitle: "Stripe autorizó \(order.amountFormatted).",
                timeLabel: processing ? "—" : "Pendiente",
                icon: "checkmark.seal.fill",
                isCompleted: processing
            ),
            DrflowOrderTimelineEvent(
                id: "t3",
                title: "Comisión calculada",
                subtitle: "Comisión afiliado reservada según tier \(affiliate(for: order).tier).",
                timeLabel: processing ? "—" : "Pendiente",
                icon: "percent",
                isCompleted: processing
            ),
            DrflowOrderTimelineEvent(
                id: "t4",
                title: "Comisión acreditada",
                subtitle: "Disponible en panel de afiliados.",
                timeLabel: completed ? "Hoy" : "Pendiente",
                icon: "dollarsign.circle.fill",
                isCompleted: completed
            ),
        ]
    }

    private static func platformFeePercent(for channel: String) -> Int {
        switch channel {
        case "TikTok Shop": return 8
        case "Instagram": return 5
        case "Facebook": return 6
        case "En vivo": return 4
        default: return 5
        }
    }

    private static func shippingFee(for order: DrflowOrder) -> Double {
        order.id == "ord-1003" ? 0 : 0
    }

    private static func discount(for order: DrflowOrder, subtotal: Double) -> Double {
        if order.id == "ord-1003" {
            return max(0, (subtotal - order.amount)).rounded(toPlaces: 2)
        }
        return 0
    }

    private static func taxedAmount(subtotal: Double, shipping: Double) -> Double {
        ((subtotal + shipping) * 0.07).rounded(toPlaces: 2)
    }

    private static func paymentMethod(for order: DrflowOrder) -> String {
        switch order.id {
        case "ord-1001", "ord-1005": return "Apple Pay"
        case "ord-1002": return "Visa ···· 4242"
        case "ord-1003": return "PayPal"
        default: return "Tarjeta"
        }
    }

    private static func shippingCity(for order: DrflowOrder) -> String {
        switch order.id {
        case "ord-1001": return "Miami, FL"
        case "ord-1002": return "Austin, TX"
        case "ord-1003": return "Orlando, FL"
        case "ord-1004": return "Los Angeles, CA"
        default: return "Houston, TX"
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
