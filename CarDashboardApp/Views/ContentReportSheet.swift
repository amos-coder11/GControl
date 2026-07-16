import SwiftUI

/// Form to report objectionable content.
struct ContentReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var moderation: UserModerationStore

    let reportedUserName: String
    let reportedUserId: UUID
    let contentType: UserModerationService.ContentType
    let contentId: UUID?
    let contentPreview: String?

    @State private var selectedReason: ReportReason = .harassment
    @State private var extraNotes = ""
    @State private var isSubmitting = false

    enum ReportReason: String, CaseIterable, Identifiable {
        case harassment
        case hate
        case sexual
        case violence
        case spam
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .harassment: return "Harassment or threats"
            case .hate: return "Hate speech"
            case .sexual: return "Explicit sexual content"
            case .violence: return "Violence or graphic content"
            case .spam: return "Spam or scam"
            case .other: return "Other reason"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Report \(reportedUserName)")
                        .font(.headline)
                    if let preview = contentPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }

                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.label).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Notes (optional)") {
                    TextField("Additional details", text: $extraNotes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section {
                    Text("We'll review your report within 24 hours. We may remove content and ban the offending user.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        var reason = selectedReason.label
        let notes = extraNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            reason += " — \(notes)"
        }
        let ok = await moderation.reportContent(
            reportedUserId: reportedUserId,
            contentType: contentType,
            contentId: contentId,
            contentPreview: contentPreview,
            reason: reason
        )
        if ok { dismiss() }
    }
}
