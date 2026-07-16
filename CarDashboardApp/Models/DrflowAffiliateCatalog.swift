import Foundation

// MARK: - Perfil simulado de afiliado

struct DrflowAffiliatePrivateLink: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let icon: String
    let channel: String
}

struct DrflowAffiliateProductAccess: Identifiable, Hashable {
    let id: String
    let productName: String
    let imageAssetName: String
    let isAllowed: Bool
    let reason: String?
}

struct DrflowAffiliateCertificate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let earnedDate: String
    let icon: String
    let tier: String
}

struct DrflowAffiliateMonthlyStat: Identifiable, Hashable {
    let id: String
    let monthLabel: String
    let sales: Double
    let commission: Double
    let liveHours: Double
    let shipments: Int
}

struct DrflowAffiliateChannelStat: Identifiable, Hashable {
    let id: String
    let channel: String
    let sales: Double
    let orders: Int
    let sharePct: Int
}

struct DrflowAffiliateProfile: Hashable {
    let userId: UUID
    let displayName: String
    let handle: String
    let rank: Int
    let tier: String
    let commissionRate: Double
    let monthlySales: Double
    let monthlyCommission: Double
    let projectedPayout: Double
    let pendingCommission: Double
    let nextPayoutDate: String
    let liveHoursThisMonth: Double
    let shipmentsThisMonth: Int
    let totalOrders: Int
    let conversionRate: Double
    let privateLinks: [DrflowAffiliatePrivateLink]
    let productAccess: [DrflowAffiliateProductAccess]
    let certificates: [DrflowAffiliateCertificate]
    let monthlyHistory: [DrflowAffiliateMonthlyStat]
    let channelBreakdown: [DrflowAffiliateChannelStat]

    var commissionRatePercent: Int { Int((commissionRate * 100).rounded()) }

    var allowedProducts: [DrflowAffiliateProductAccess] {
        productAccess.filter(\.isAllowed)
    }

    var blockedProducts: [DrflowAffiliateProductAccess] {
        productAccess.filter { !$0.isAllowed }
    }

    static func formatUSD(_ value: Double) -> String {
        DealershipStatsViewModel.formatUSD(value)
    }
}

enum DrflowAffiliateCatalog {
    static func profile(for row: CommunityProfilesService.DirectoryRow, rank: Int) -> DrflowAffiliateProfile {
        let seed = abs(row.userId.hashValue)
        let tier = tier(for: rank, seed: seed)
        let rate = commissionRate(for: tier)
        let sales = mockSales(seed: seed)
        let commission = (sales * rate).rounded(toPlaces: 2)
        let pending = (commission * 0.18).rounded(toPlaces: 2)
        let projected = commission + pending

        return DrflowAffiliateProfile(
            userId: row.userId,
            displayName: row.resolvedDisplayName,
            handle: handle(for: row),
            rank: rank,
            tier: tier,
            commissionRate: rate,
            monthlySales: sales,
            monthlyCommission: commission,
            projectedPayout: projected,
            pendingCommission: pending,
            nextPayoutDate: "15 Jul 2026",
            liveHoursThisMonth: liveHours(seed: seed, tier: tier),
            shipmentsThisMonth: shipments(seed: seed),
            totalOrders: orders(seed: seed),
            conversionRate: conversion(seed: seed),
            privateLinks: privateLinks(for: row, handle: handle(for: row)),
            productAccess: productAccess(tier: tier, seed: seed),
            certificates: certificates(tier: tier, rank: rank, sales: sales),
            monthlyHistory: monthlyHistory(seed: seed, rate: rate),
            channelBreakdown: channelBreakdown(seed: seed)
        )
    }

    // MARK: - Generadores

    private static func handle(for row: CommunityProfilesService.DirectoryRow) -> String {
        let base = row.resolvedDisplayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return "@\(base.isEmpty ? "afiliado" : base)"
    }

    private static func tier(for rank: Int, seed: Int) -> String {
        if rank == 1 { return "Elite" }
        if rank <= 3 { return "Pro" }
        if seed % 5 == 0 { return "Live" }
        return "Base"
    }

    private static func commissionRate(for tier: String) -> Double {
        switch tier {
        case "Elite": return 0.25
        case "Pro": return 0.20
        case "Live": return 0.22
        default: return 0.15
        }
    }

    private static func mockSales(seed: Int) -> Double {
        Double(1_800 + (seed % 26_200)).rounded(toPlaces: 2)
    }

    private static func liveHours(seed: Int, tier: String) -> Double {
        let base = Double(8 + seed % 40)
        return tier == "Live" || tier == "Elite" ? base + 12 : base
    }

    private static func shipments(seed: Int) -> Int {
        12 + seed % 88
    }

    private static func orders(seed: Int) -> Int {
        18 + seed % 120
    }

    private static func conversion(seed: Int) -> Double {
        Double(3 + seed % 9) + Double(seed % 10) / 10
    }

    private static func privateLinks(for row: CommunityProfilesService.DirectoryRow, handle: String) -> [DrflowAffiliatePrivateLink] {
        let slug = handle.replacingOccurrences(of: "@", with: "")
        return [
            DrflowAffiliatePrivateLink(
                id: "main",
                title: "Enlace principal",
                url: "https://drgsmileusa.com/ref/\(slug)",
                icon: "link",
                channel: "Web"
            ),
            DrflowAffiliatePrivateLink(
                id: "tiktok",
                title: "TikTok Shop",
                url: "https://shop.tiktok.com/\(slug)",
                icon: "bag",
                channel: "TikTok Shop"
            ),
            DrflowAffiliatePrivateLink(
                id: "instagram",
                title: "Bio Instagram",
                url: "https://drgsmileusa.com/ig/\(slug)",
                icon: "camera",
                channel: "Instagram"
            ),
            DrflowAffiliatePrivateLink(
                id: "live",
                title: "Sala en vivo",
                url: "https://drgsmileusa.com/live/\(slug)",
                icon: "dot.radiowaves.left.and.right",
                channel: "En vivo"
            ),
        ]
    }

    private static func productAccess(tier: String, seed: Int) -> [DrflowAffiliateProductAccess] {
        let products: [(id: String, name: String, asset: String)] = [
            ("energy-focus", "Traders Market Energy Focus", DrflowProductCatalog.energyFocus.imageAssetName),
            ("nad-plus", "NAD +", DrflowProductCatalog.nadPlus.imageAssetName),
            ("recovery-sleep", "Traders Recovery Sleep & Wellness", DrflowProductCatalog.recoverySleep.imageAssetName),
            ("bundle", "Bundle 3 productos", DrflowProductCatalog.energyFocus.imageAssetName),
        ]

        return products.map { product in
            let allowed: Bool
            let reason: String?

            switch tier {
            case "Elite", "Pro":
                allowed = true
                reason = nil
            case "Live":
                allowed = product.id != "bundle"
                reason = allowed ? nil : "Requiere tier Pro para bundles"
            default:
                allowed = product.id == "nad-plus" || (product.id == "energy-focus" && seed % 2 == 0)
                reason = allowed ? nil : "Producto restringido en tier Base"
            }

            return DrflowAffiliateProductAccess(
                id: product.id,
                productName: product.name,
                imageAssetName: product.asset,
                isAllowed: allowed,
                reason: reason
            )
        }
    }

    private static func certificates(tier: String, rank: Int, sales: Double) -> [DrflowAffiliateCertificate] {
        var items: [DrflowAffiliateCertificate] = [
            DrflowAffiliateCertificate(
                id: "cert-onboard",
                title: "Afiliado verificado",
                subtitle: "Onboarding completado",
                earnedDate: "Mar 2026",
                icon: "checkmark.seal.fill",
                tier: "Base"
            ),
        ]

        if sales >= 3_000 {
            items.append(DrflowAffiliateCertificate(
                id: "cert-3k",
                title: "Vendedor activo",
                subtitle: "Más de $3,000 en ventas",
                earnedDate: "Jun 2026",
                icon: "star.fill",
                tier: "Pro"
            ))
        }
        if rank <= 3 {
            items.append(DrflowAffiliateCertificate(
                id: "cert-top",
                title: "Top \(rank) de la red",
                subtitle: "Ranking mensual drgsmileusa",
                earnedDate: "Jul 2026",
                icon: "trophy.fill",
                tier: tier
            ))
        }
        if tier == "Live" || tier == "Elite" {
            items.append(DrflowAffiliateCertificate(
                id: "cert-live",
                title: "Certificado Live Sales",
                subtitle: "50+ horas en vivo este trimestre",
                earnedDate: "Q2 2026",
                icon: "video.fill",
                tier: "Live"
            ))
        }
        if sales >= 8_000 {
            items.append(DrflowAffiliateCertificate(
                id: "cert-elite",
                title: "Elite Smile Partner",
                subtitle: "Certificación de venta avanzada",
                earnedDate: "Jul 2026",
                icon: "rosette",
                tier: "Elite"
            ))
        }

        return items
    }

    private static func monthlyHistory(seed: Int, rate: Double) -> [DrflowAffiliateMonthlyStat] {
        let months = ["Feb", "Mar", "Abr", "May", "Jun", "Jul"]
        return months.enumerated().map { index, label in
            let base = 1_400 + (seed % 900) + index * (180 + seed % 120)
            let sales = Double(base).rounded(toPlaces: 2)
            return DrflowAffiliateMonthlyStat(
                id: "m-\(index)",
                monthLabel: label,
                sales: sales,
                commission: (sales * rate).rounded(toPlaces: 2),
                liveHours: Double(6 + (seed + index * 3) % 28),
                shipments: 10 + (seed + index * 7) % 45
            )
        }
    }

    private static func channelBreakdown(seed: Int) -> [DrflowAffiliateChannelStat] {
        let tiktok = 35 + seed % 25
        let instagram = 20 + seed % 20
        let facebook = 10 + seed % 15
        let live = max(5, 100 - tiktok - instagram - facebook)
        let totalSales = Double(8_000 + seed % 12_000)

        return [
            DrflowAffiliateChannelStat(id: "ch-tt", channel: "TikTok Shop", sales: totalSales * Double(tiktok) / 100, orders: 20 + seed % 40, sharePct: tiktok),
            DrflowAffiliateChannelStat(id: "ch-ig", channel: "Instagram", sales: totalSales * Double(instagram) / 100, orders: 10 + seed % 25, sharePct: instagram),
            DrflowAffiliateChannelStat(id: "ch-fb", channel: "Facebook", sales: totalSales * Double(facebook) / 100, orders: 6 + seed % 18, sharePct: facebook),
            DrflowAffiliateChannelStat(id: "ch-live", channel: "En vivo", sales: totalSales * Double(live) / 100, orders: 8 + seed % 20, sharePct: live),
        ]
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

/// Ruta de navegación al detalle de afiliado.
struct AffiliateDetailRoute: Hashable {
    let userId: UUID
    let rank: Int
}
