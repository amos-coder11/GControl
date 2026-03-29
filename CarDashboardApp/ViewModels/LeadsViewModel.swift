import Combine
import Foundation

@MainActor
final class LeadsViewModel: ObservableObject {
    @Published private(set) var leads: [LeadCrm] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await LeadsCrmService.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
