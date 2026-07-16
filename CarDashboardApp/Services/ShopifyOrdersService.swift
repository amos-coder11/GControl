import Foundation

/// URL del backend que expone `/api/shopify/*` (credenciales solo en servidor).
enum ShopifyBackendConfig {
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SHOPIFY_BACKEND_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), !trimmed.isEmpty {
                return url
            }
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:3000")!
        #else
        return URL(string: "https://drflowbackend.onrender.com")!
        #endif
    }
}

struct ShopifyOrderDTO: Decodable {
    let id: String
    let shopifyId: Int?
    let orderNumber: String?
    let customerName: String
    let productTitle: String
    let productsLabel: String
    let imageURL: String?
    let amount: Double
    let amountFormatted: String?
    let currency: String?
    let timeLabel: String
    let status: String
    let channel: String
    let createdAt: String?
}

struct ShopifyOrdersPayload: Decodable {
    let orders: [ShopifyOrderDTO]
    let source: String?
}

struct ShopifySummaryPayload: Decodable {
    let totalOrders: Int
    let pendingOrders: Int
    let completedOrders: Int
    let monthOrderCount: Int
    let monthRevenue: Double
    let monthRevenueFormatted: String?
    let source: String?
}

struct ShopifyOrdersFetchResult {
    let orders: [DrflowOrder]
    let source: String?
}

enum ShopifyOrdersService {
    enum ServiceError: LocalizedError {
        case badResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Respuesta inválida del servidor Shopify."
            case .server(let message): return message
            }
        }
    }

    static func fetchOrders(limit: Int = 50) async throws -> ShopifyOrdersFetchResult {
        var components = URLComponents(
            url: ShopifyBackendConfig.baseURL.appendingPathComponent("api/shopify/orders"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components?.url else { throw ServiceError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }

        if http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(ShopifyErrorPayload.self, from: data) {
                throw ServiceError.server(err.message ?? err.error ?? "Error Shopify (\(http.statusCode))")
            }
            throw ServiceError.server("Error Shopify (\(http.statusCode))")
        }

        let payload = try JSONDecoder().decode(ShopifyOrdersPayload.self, from: data)
        return ShopifyOrdersFetchResult(
            orders: payload.orders.map(DrflowOrderCatalog.order(fromShopify:)),
            source: payload.source
        )
    }

    static func fetchSummary() async throws -> ShopifySummaryPayload {
        let url = ShopifyBackendConfig.baseURL.appendingPathComponent("api/shopify/summary")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }

        if http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(ShopifyErrorPayload.self, from: data) {
                throw ServiceError.server(err.message ?? err.error ?? "Error Shopify (\(http.statusCode))")
            }
            throw ServiceError.server("Error Shopify (\(http.statusCode))")
        }

        return try JSONDecoder().decode(ShopifySummaryPayload.self, from: data)
    }
}

private struct ShopifyErrorPayload: Decodable {
    let error: String?
    let message: String?
}

@MainActor
final class OrdersStore: ObservableObject {
    @Published private(set) var orders: [DrflowOrder] = DrflowOrderCatalog.demoOrders
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var isUsingLiveData = false
    @Published private(set) var dataSourceLabel: String?

    @Published private(set) var monthRevenue: Double = 0
    @Published private(set) var monthOrderCount: Int = 0
    @Published private(set) var totalOrders: Int = 0
    @Published private(set) var pendingOrders: Int = 0
    @Published private(set) var completedOrders: Int = 0

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let ordersTask = ShopifyOrdersService.fetchOrders(limit: 50)
            async let summaryTask = ShopifyOrdersService.fetchSummary()

            let ordersResult = try await ordersTask
            let summary = try await summaryTask

            guard !ordersResult.orders.isEmpty else {
                applyDemoFallback(message: "Shopify no devolvió pedidos.")
                return
            }

            orders = ordersResult.orders
            monthRevenue = summary.monthRevenue
            monthOrderCount = summary.monthOrderCount
            totalOrders = summary.totalOrders
            pendingOrders = summary.pendingOrders
            completedOrders = summary.completedOrders
            isUsingLiveData = true
            dataSourceLabel = Self.label(for: summary.source ?? ordersResult.source)
            lastError = nil
        } catch {
            applyDemoFallback(message: error.localizedDescription)
        }
    }

    private func applyDemoFallback(message: String) {
        orders = DrflowOrderCatalog.demoOrders
        isUsingLiveData = false
        dataSourceLabel = nil
        lastError = message
        totalOrders = orders.count
        pendingOrders = orders.filter { $0.status == .pending }.count
        completedOrders = orders.filter { $0.status == .completed }.count
        monthOrderCount = totalOrders
        monthRevenue = orders.reduce(0) { $0 + $1.amount }
    }

    private static func label(for source: String?) -> String {
        switch source {
        case "shopify", "shopify_admin_token":
            return "Datos en vivo · Shopify"
        case "shopify_fixture":
            return "Prueba local · backend fixture"
        default:
            return "Datos del backend"
        }
    }
}
