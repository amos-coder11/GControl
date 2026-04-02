import Foundation

/// Centralized user-visible and internal string constants (no scattered literals).
enum VoiceStrings {
    enum Error {
        static let microphonePermissionDenied =
            "Microphone access is required. Please enable it in Settings."
        static let sessionTokenFetchFailed =
            "Could not start a session. Check your connection and try again."
        static let webRTCConnectionFailedFormat = "Connection failed: %@"
        static let iceConnectionFailed =
            "Network connection to the AI failed. Try again."
        static let audioSessionSetupFailed =
            "Audio setup failed. Restart the app."
        static let backendUnreachable =
            "Cannot reach the server. Check your network."
        static let tokenExpired =
            "Session expired before connecting. Please try again."
        static let unknownFormat = "Unexpected error: %@"
    }

    enum UI {
        static let conversationTitle = "Voice"
        static let statusIdle = "Idle"
        static let statusRequestingPermission = "Microphone…"
        static let statusFetchingToken = "Starting session…"
        static let statusConnecting = "Connecting…"
        static let statusConnected = "Connected — tap to stop"
        static let statusDisconnecting = "Stopping…"
        static let transcriptPlaceholder = "Transcript will appear here."
        static let transcriptSectionTitle = "Transcript"
        static let settingsTitle = "Settings"
        static let settingsBackendURL = "Backend base URL"
        static let settingsEnvironment = "Environment"
        static let settingsSave = "Save"
        static let settingsDismiss = "Done"
        static let backendURLPlaceholder = "http://127.0.0.1:3000"
        static let errorBannerDismiss = "Dismiss"
    }

    enum Accessibility {
        static let micButton = "Microphone"
        static let micHintStart = "Starts a voice session"
        static let micHintStop = "Stops the voice session"
        static let settingsButton = "Open settings"
    }

    enum InfoPlist {
        static let microphoneUsage =
            "This app uses your microphone to have a voice conversation with AI."
    }
}
