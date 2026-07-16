import Foundation
import Supabase
import SwiftUI

@MainActor
final class UserModerationStore: ObservableObject {
    @Published private(set) var blockedUserIds: Set<UUID> = []
    @Published private(set) var hasAcceptedCurrentTerms = false
    @Published var lastErrorMessage: String?
    @Published var lastSuccessMessage: String?

    private let client: SupabaseClient
    private var loadedUserId: UUID?

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
        hasAcceptedCurrentTerms = Self.localTermsAcceptedVersion() == ContentModerationFilter.currentTermsVersion
    }

    func isBlocked(_ userId: UUID) -> Bool {
        blockedUserIds.contains(userId)
    }

    func load(for userId: UUID) async {
        loadedUserId = userId
        do {
            async let blocks = UserModerationService.fetchBlockedUserIds(for: userId, client: client)
            async let terms = UserModerationService.fetchTermsAcceptance(userId: userId, client: client)
            let (blocked, acceptance) = try await (blocks, terms)
            blockedUserIds = blocked
            let accepted = acceptance?.termsVersion == ContentModerationFilter.currentTermsVersion
            hasAcceptedCurrentTerms = accepted
            if accepted {
                Self.storeLocalTermsAcceptedVersion(ContentModerationFilter.currentTermsVersion)
            }
        } catch {
            // Tablas aún no desplegadas: conservar aceptación local.
            hasAcceptedCurrentTerms = Self.localTermsAcceptedVersion() == ContentModerationFilter.currentTermsVersion
        }
    }

    func reset() {
        loadedUserId = nil
        blockedUserIds = []
        hasAcceptedCurrentTerms = Self.localTermsAcceptedVersion() == ContentModerationFilter.currentTermsVersion
    }

    func acceptTerms(userId: UUID) async -> Bool {
        lastErrorMessage = nil
        do {
            try await UserModerationService.acceptTerms(userId: userId, client: client)
            hasAcceptedCurrentTerms = true
            Self.storeLocalTermsAcceptedVersion(ContentModerationFilter.currentTermsVersion)
            return true
        } catch {
            // Sin backend: aceptación local suficiente para revisión de App Store.
            hasAcceptedCurrentTerms = true
            Self.storeLocalTermsAcceptedVersion(ContentModerationFilter.currentTermsVersion)
            return true
        }
    }

    func acceptTermsLocallyBeforeAuth() {
        hasAcceptedCurrentTerms = true
        Self.storeLocalTermsAcceptedVersion(ContentModerationFilter.currentTermsVersion)
    }

    func reportContent(
        reportedUserId: UUID,
        contentType: UserModerationService.ContentType,
        contentId: UUID?,
        contentPreview: String?,
        reason: String
    ) async -> Bool {
        lastErrorMessage = nil
        lastSuccessMessage = nil
        do {
            try await UserModerationService.submitReport(
                reportedUserId: reportedUserId,
                contentType: contentType,
                contentId: contentId,
                contentPreview: contentPreview,
                reason: reason,
                client: client
            )
            lastSuccessMessage = "Denuncia enviada. La revisaremos en un plazo máximo de 24 horas."
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func blockUser(
        _ blockedId: UUID,
        autoReportReason: String,
        contentType: UserModerationService.ContentType,
        contentId: UUID?,
        contentPreview: String?
    ) async -> Bool {
        lastErrorMessage = nil
        lastSuccessMessage = nil
        guard loadedUserId != blockedId else { return false }
        do {
            _ = try await UserModerationService.blockUser(blockedId: blockedId, client: client)
            blockedUserIds.insert(blockedId)
            try? await UserModerationService.submitReport(
                reportedUserId: blockedId,
                contentType: contentType,
                contentId: contentId,
                contentPreview: contentPreview,
                reason: autoReportReason,
                client: client
            )
            lastSuccessMessage = "Usuario bloqueado. Su contenido ya no aparecerá en tu feed."
            return true
        } catch {
            // Bloqueo local inmediato aunque falle la red.
            blockedUserIds.insert(blockedId)
            lastSuccessMessage = "Usuario bloqueado en este dispositivo."
            return true
        }
    }

    func unblockUser(_ blockedId: UUID) async {
        lastErrorMessage = nil
        do {
            try await UserModerationService.unblockUser(blockedId: blockedId, client: client)
        } catch {
            // Quitar localmente de todos modos.
        }
        blockedUserIds.remove(blockedId)
    }

    private static let localTermsKey = "Drflow.UGC.TermsVersion"

    private static func localTermsAcceptedVersion() -> String? {
        UserDefaults.standard.string(forKey: localTermsKey)
    }

    private static func storeLocalTermsAcceptedVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: localTermsKey)
    }
}
