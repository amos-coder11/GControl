import Foundation

/// Application-level errors surfaced to the user.
enum AppError: LocalizedError {
    case microphonePermissionDenied
    case sessionTokenFetchFailed(underlying: Error)
    case webRTCConnectionFailed(reason: String)
    case iceConnectionFailed
    case audioSessionSetupFailed(underlying: Error)
    case backendUnreachable
    case tokenExpired
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return VoiceStrings.Error.microphonePermissionDenied
        case .sessionTokenFetchFailed:
            return VoiceStrings.Error.sessionTokenFetchFailed
        case .webRTCConnectionFailed(let reason):
            return String(format: VoiceStrings.Error.webRTCConnectionFailedFormat, reason)
        case .iceConnectionFailed:
            return VoiceStrings.Error.iceConnectionFailed
        case .audioSessionSetupFailed:
            return VoiceStrings.Error.audioSessionSetupFailed
        case .backendUnreachable:
            return VoiceStrings.Error.backendUnreachable
        case .tokenExpired:
            return VoiceStrings.Error.tokenExpired
        case .unknown(let error):
            return String(format: VoiceStrings.Error.unknownFormat, error.localizedDescription)
        }
    }
}
