import Combine
import CoreLocation
import Foundation
import Supabase

@MainActor
final class DashboardCommunityViewModel: ObservableObject {
    @Published private(set) var directory: [CommunityProfilesService.DirectoryRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var refreshTimer: AnyCancellable?
    private var auth: AuthViewModel?

    func attach(auth: AuthViewModel) {
        self.auth = auth
    }

    func startPeriodicRefresh() {
        refreshTimer?.cancel()
        refreshTimer = Timer.publish(every: 15, tolerance: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    func stopPeriodicRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    func refresh() async {
        guard let auth, auth.session != nil else {
            directory = []
            return
        }
        isLoading = directory.isEmpty
        lastError = nil
        defer { isLoading = false }
        do {
            let orgId = await VehiclesService.fetchMyOrganizationId()
            guard let orgId else {
                lastError = "Tu cuenta no tiene empresa/organización asignada. Un administrador debe asignarte `user_profiles.organization_id`."
                directory = []
                return
            }
            directory = try await CommunityProfilesService.fetchDirectory(
                client: SupabaseClientProvider.shared,
                organizationId: orgId
            )
        } catch {
            lastError = error.localizedDescription
            directory = []
        }
    }

    func uploadMyCoordinate(_ coordinate: CLLocationCoordinate2D) async {
        guard let auth, let session = auth.session else { return }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        await CommunityProfilesService.pushMyLocation(
            userId: session.user.id,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            client: SupabaseClientProvider.shared
        )
        await refresh()
    }
}
