import Foundation

struct CarLeadStats: Equatable {
    let appointments: Int
    let leads: Int
    let won: Int

    static let zero = CarLeadStats(appointments: 0, leads: 0, won: 0)
}

@MainActor
final class CarInventoryLeadIndex: ObservableObject {
    @Published private(set) var allLeads: [LeadCrm] = []
    @Published private(set) var isLoading = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        allLeads = (try? await LeadsCrmService.fetchAll()) ?? []
    }

    func stats(for car: Car) -> CarLeadStats {
        let matched = allLeads.filter { $0.matches(car: car) }
        guard !matched.isEmpty else { return .zero }
        return CarLeadStats(
            appointments: matched.filter(\.isAppointmentLead).count,
            leads: matched.count,
            won: matched.filter(\.isWonLead).count
        )
    }

    func leads(for car: Car, limit: Int = 20) -> [LeadCrm] {
        Array(allLeads.filter { $0.matches(car: car) }.prefix(limit))
    }
}
