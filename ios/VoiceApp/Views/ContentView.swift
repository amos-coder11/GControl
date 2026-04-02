import SwiftUI

/// Root view: picks environment from `AppStorage` and rebuilds the session stack when it changes.
struct ContentView: View {
    @AppStorage("VoiceApp.selectedEnvironment") private var environmentRawValue: String = AppEnvironment.dev.rawValue

    private var environment: AppEnvironment {
        AppEnvironment(rawValue: environmentRawValue) ?? .dev
    }

    var body: some View {
        ConversationView(environment: environment)
            .id(environmentRawValue)
    }
}
