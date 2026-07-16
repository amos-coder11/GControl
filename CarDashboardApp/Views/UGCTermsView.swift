import SwiftUI

/// EULA / zero-tolerance terms for user-generated content.
enum UGCTermsText {
    static let title = "Terms of Use and Community"

    static let body = """
    Welcome to Groo. By using the career mentor chat and other user-generated content features, you agree to the following:

    1. Zero tolerance
    Objectionable content and abusive behavior are not allowed. This includes, but is not limited to: harassment, threats, hate speech, explicit sexual content, graphic violence, spam, and impersonation.

    2. Your responsibility
    You are responsible for the content you post or send. Groo may remove content and suspend or ban accounts that violate these rules.

    3. Reports
    You can report messages or users from any conversation. Our team reviews each report and acts within 24 hours, removing content and banning offending users when appropriate.

    4. Blocking
    You can block any abusive user. When you block someone, you will stop seeing their content immediately and the Groo team will be notified automatically for review.

    5. Filtering
    The app automatically filters objectionable language in messages sent and displayed.

    6. Scope of service
    Groo is a mentorship platform for human and professional skills development. It does not offer therapy, psychological diagnosis, or medical advice. For mental health concerns, seek support from a qualified professional.

    7. Contact
    For moderation inquiries: soporte@groo.co

    Terms version: \(ContentModerationFilter.currentTermsVersion)
    """
}

/// Full terms screen (from settings or registration link).
struct UGCTermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(UGCTermsText.body)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(UGCTermsText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// Mandatory acceptance sheet before signing up or signing in.
struct UGCTermsAcceptanceSheet: View {
    @Binding var isPresented: Bool
    var onAccepted: () -> Void

    @State private var didReadTerms = false
    @State private var showFullTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(UGCTermsText.title)
                        .font(.system(size: 22, weight: .bold))

                    Text(UGCTermsText.body)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Button("Read full terms") {
                        showFullTerms = true
                    }
                    .font(.system(size: 14, weight: .semibold))

                    Toggle(isOn: $didReadTerms) {
                        Text("I have read and accept the Terms of Use. I understand there is zero tolerance for objectionable content or abusive users.")
                            .font(.system(size: 14))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.35, green: 0.55, blue: 1.0)))

                    Button {
                        onAccepted()
                        isPresented = false
                    } label: {
                        Text("Accept and continue")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(didReadTerms ? Color.accentColor : Color.gray.opacity(0.35))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(!didReadTerms)
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .sheet(isPresented: $showFullTerms) {
                UGCTermsView()
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    UGCTermsAcceptanceSheet(isPresented: .constant(true)) {}
}
