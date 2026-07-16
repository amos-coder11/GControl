import SwiftUI

/// Flujo post-login: onboarding → perfil → CARE → resultados → tabs.
struct GrooRootFlow: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        Group {
            switch groo.phase {
            case .onboarding:
                GrooOnboardingFlowView()
            case .profileSetup:
                GrooProfileSetupView()
            case .careIntro:
                GrooCareIntroView()
            case .careQuiz:
                GrooCareDiagnosticView()
            case .careResults:
                GrooDiagnosticResultsView()
            case .main:
                MainTabView()
            }
        }
        .environmentObject(groo)
        .animation(.easeInOut(duration: 0.25), value: groo.phase)
    }
}

// MARK: - Onboarding (pre-registro / post-login)

struct GrooOnboardingFlowView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @State private var step = 0

    private let totalSteps = 7

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                progressHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepContent
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }
                bottomBar
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("GROO")
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
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            multiSelect(
                title: "What brought you to GROO today?",
                options: [
                    "Clarity on my next step",
                    "Prepare for a difficult conversation",
                    "Grow as a leader",
                    "Regain momentum",
                    "Negotiate or ask for what I need",
                    "Just exploring"
                ],
                selected: $groo.onboarding.reasons
            )
        case 1:
            singleSelect(
                title: "What stage of your career are you in?",
                options: [
                    "Early career / first years",
                    "Growing professional (3–8 years)",
                    "Senior / specialist",
                    "Leadership / manager",
                    "Executive (15+ years)",
                    "Transition / between jobs"
                ],
                selected: $groo.onboarding.careerStage
            )
        case 2:
            singleSelect(
                title: "What is your current work situation?",
                options: [
                    "Full-time employee",
                    "Part-time employee",
                    "Freelance / self-employed",
                    "Student",
                    "Between jobs",
                    "Other"
                ],
                selected: $groo.onboarding.workSituation
            )
        case 3:
            multiSelect(
                title: "What is your main goal?",
                options: [
                    "Promotion or new role",
                    "Better communication",
                    "More confidence",
                    "Stronger professional network",
                    "Execute with more focus",
                    "Balance and energy"
                ],
                selected: $groo.onboarding.goals
            )
        case 4:
            singleSelect(
                title: "Have you worked with a mentor or coach before?",
                options: ["Yes", "No", "Only informally"],
                selected: $groo.onboarding.priorMentor
            )
        case 5:
            singleSelect(
                title: "How do you prefer to work on your goals?",
                options: [
                    "Guided conversation (chat)",
                    "Plans and reminders",
                    "Mix of both",
                    "I don't know yet"
                ],
                selected: $groo.onboarding.workStyle
            )
        default:
            singleSelect(
                title: "Do you manage people? (optional)",
                options: ["Yes", "No", "Prefer not to say"],
                selected: $groo.onboarding.managesPeople
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
            Spacer()
            Button(step == totalSteps - 1 ? "Continue" : "Next") {
                if step < totalSteps - 1 {
                    step += 1
                } else {
                    groo.completeOnboarding()
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
        .background(Color.white.opacity(0.96))
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return !groo.onboarding.reasons.isEmpty
        case 1: return !groo.onboarding.careerStage.isEmpty
        case 2: return !groo.onboarding.workSituation.isEmpty
        case 3: return !groo.onboarding.goals.isEmpty
        case 4: return !groo.onboarding.priorMentor.isEmpty
        case 5: return !groo.onboarding.workStyle.isEmpty
        default: return true
        }
    }

    private func multiSelect(title: String, options: [String], selected: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
            Text("You can choose more than one option.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
            ForEach(options, id: \.self) { option in
                let on = selected.wrappedValue.contains(option)
                Button {
                    if on {
                        selected.wrappedValue.removeAll { $0 == option }
                    } else {
                        selected.wrappedValue.append(option)
                    }
                    groo.save()
                } label: {
                    HStack {
                        Text(option)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? GrooBrand.purple : DrflowTheme.textMuted)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? GrooBrand.purpleSoft : DrflowTheme.surfaceMuted)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(on ? GrooBrand.purple.opacity(0.45) : DrflowTheme.cardBorder, lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func singleSelect(title: String, options: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
            ForEach(options, id: \.self) { option in
                let on = selected.wrappedValue == option
                Button {
                    selected.wrappedValue = option
                    groo.save()
                } label: {
                    HStack {
                        Text(option)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? GrooBrand.purple : DrflowTheme.textMuted)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? GrooBrand.purpleSoft : DrflowTheme.surfaceMuted)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(on ? GrooBrand.purple.opacity(0.45) : DrflowTheme.cardBorder, lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
