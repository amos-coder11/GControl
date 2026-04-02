import SwiftUI

/// Dismissible inline error banner (no tokens or secrets).
struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color("VoiceWarning", bundle: .main))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button(VoiceStrings.UI.errorBannerDismiss) {
                onDismiss()
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("VoiceBannerFill", bundle: .main))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("VoiceBannerStroke", bundle: .main), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
