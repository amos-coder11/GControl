import Foundation

/// Maps `ConversationViewModel.SessionState` to user-visible status copy (testable without UI).
enum SessionStateFormatter {
    static func statusLine(for state: ConversationViewModel.SessionState) -> String {
        switch state {
        case .idle:
            return VoiceStrings.UI.statusIdle
        case .requestingPermission:
            return VoiceStrings.UI.statusRequestingPermission
        case .fetchingToken:
            return VoiceStrings.UI.statusFetchingToken
        case .connecting:
            return VoiceStrings.UI.statusConnecting
        case .connected:
            return VoiceStrings.UI.statusConnected
        case .disconnecting:
            return VoiceStrings.UI.statusDisconnecting
        case .error(let appError):
            return appError.localizedDescription ?? "Error"
        }
    }
}
