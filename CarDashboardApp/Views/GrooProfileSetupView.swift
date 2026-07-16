import SwiftUI
import UniformTypeIdentifiers

struct GrooProfileSetupView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @State private var step = 0
    @State private var showImporter = false

    private let totalSteps = 7
    private let ageRanges = ["18–24", "25–34", "35–44", "45–54", "55+", "Prefer not to say"]
    private let genders = ["Woman", "Man", "Non-binary", "Other", "Prefer not to say"]

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your profile")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                    Text("Step \(step + 1) of \(totalSteps)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DrflowTheme.controlFill)
                            Capsule()
                                .fill(GrooBrand.purple)
                                .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepBody
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }

                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textSecondary)
                    }
                    Spacer()
                    Button(step == totalSteps - 1 ? "Go to diagnostic" : "Next") {
                        if step < totalSteps - 1 {
                            step += 1
                            groo.save()
                        } else {
                            groo.completeProfile()
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(canAdvance ? GrooBrand.purple : DrflowTheme.textMuted))
                    .disabled(!canAdvance)
                }
                .padding(20)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .commaSeparatedText, UTType(filenameExtension: "doc") ?? .data, UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                groo.profile.cvFileName = url.lastPathComponent
                groo.save()
            }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return !groo.profile.firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !groo.profile.lastName.trimmingCharacters(in: .whitespaces).isEmpty
        case 3: return !groo.profile.ageRange.isEmpty
        case 4: return !groo.profile.gender.isEmpty
        default: return true
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case 0:
            titled("First and last name") {
                field("First name", text: $groo.profile.firstName)
                field("Last name", text: $groo.profile.lastName)
            }
        case 1:
            titled("Phone (optional)", subtitle: "For SMS/WhatsApp reminders.") {
                field("Phone", text: $groo.profile.phone, keyboard: .phonePad)
            }
        case 2:
            titled("Country / location") {
                field("Country (code)", text: $groo.profile.country)
            }
        case 3:
            titled("Age range") {
                chipList(ageRanges, selected: $groo.profile.ageRange)
            }
        case 4:
            titled("Gender") {
                chipList(genders, selected: $groo.profile.gender)
            }
        case 5:
            titled("LinkedIn (optional)") {
                field("URL or username", text: $groo.profile.linkedIn)
            }
        default:
            titled("Resume (optional)", subtitle: "PDF/DOC/DOCX, max 10 MB.") {
                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text(groo.profile.cvFileName.isEmpty ? "Upload resume" : groo.profile.cvFileName)
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GrooBrand.purple)
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(GrooBrand.purpleSoft)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func titled(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
            content()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .URL ? .never : .words)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DrflowTheme.surfaceMuted)
            }
            .onChange(of: text.wrappedValue) { _, _ in groo.save() }
    }

    private func chipList(_ options: [String], selected: Binding<String>) -> some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                let on = selected.wrappedValue == option
                Button {
                    selected.wrappedValue = option
                    groo.save()
                } label: {
                    HStack {
                        Text(option)
                            .foregroundStyle(DrflowTheme.textPrimary)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? GrooBrand.purple : DrflowTheme.textMuted)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(on ? GrooBrand.purpleSoft : DrflowTheme.surfaceMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
