import SwiftUI

/// Formulario para denunciar contenido objetable.
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
        case harassment = "Acoso o amenazas"
        case hate = "Incitación al odio"
        case sexual = "Contenido sexual explícito"
        case violence = "Violencia o contenido gráfico"
        case spam = "Spam o estafa"
        case other = "Otro motivo"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Denunciar a \(reportedUserName)")
                        .font(.headline)
                    if let preview = contentPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }

                Section("Motivo") {
                    Picker("Motivo", selection: $selectedReason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.rawValue).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Notas (opcional)") {
                    TextField("Detalles adicionales", text: $extraNotes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section {
                    Text("Revisaremos tu denuncia en un plazo máximo de 24 horas. Podemos eliminar el contenido y expulsar al usuario infractor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Denunciar contenido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enviar") {
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
        var reason = selectedReason.rawValue
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
