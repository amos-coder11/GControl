import Foundation
import Supabase
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    let appVersion = "1.0.0"
    let buildNumber = "2025.03"

    @Published var notifyTeamPushEnabled: Bool = true

    func loadNotifyTeamPush(client: SupabaseClient, userId: UUID) async {
        let v = await UserProfileService.fetchNotifyTeamPush(userId: userId, client: client)
        notifyTeamPushEnabled = v
    }

    func persistNotifyTeamPush(_ value: Bool, client: SupabaseClient, userId: UUID) async {
        do {
            try await UserProfileService.setNotifyTeamPush(value, userId: userId, client: client)
        } catch {
            await loadNotifyTeamPush(client: client, userId: userId)
        }
    }
}
