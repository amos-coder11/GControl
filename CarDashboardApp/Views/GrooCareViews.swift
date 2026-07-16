import SwiftUI

// MARK: - Iconos CARE (libro · copa · verde · physics)

struct GrooPillarIconsRow: View {
    var activeIndex: Int? = nil
    /// Índices de pilares ya completados (0…3).
    var completedIndices: Set<Int> = []
    var height: CGFloat = 64
    var showTitles: Bool = false

    private let items: [(asset: String, title: String)] = [
        ("LibroIcon", "Communication"),
        ("CopaIcon", "Attitude"),
        ("VerdeIcon", "Relationships"),
        ("PhysicsIcon", "Execution"),
    ]

    /// Pilares completados antes del paso actual (p. ej. paso 3 → {0, 1, 2}).
    static func completedIndices(beforeStep step: Int) -> Set<Int> {
        guard step > 0 else { return [] }
        return Set((0..<step).map { $0 % 4 })
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let isActive = activeIndex == index
                let isCompleted = completedIndices.contains(index)

                VStack(spacing: 5) {
                    Image(item.asset)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            if isActive {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(GrooBrand.purple.opacity(0.55), lineWidth: 2)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if isCompleted {
                                pillarCompletedBadge
                                    .padding(6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)

                    if showTitles {
                        Text(item.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .scaleEffect(isActive ? 1.03 : 1)
                .opacity(activeIndex == nil || isActive || isCompleted ? 1 : 0.55)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeIndex)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: completedIndices)
            }
        }
    }

    private var pillarCompletedBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Circle()
                .fill(GrooBrand.purple)
                .frame(width: 18, height: 18)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct GrooCareIntroView: View {
    @EnvironmentObject private var groo: GrooAppStore

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    Text("CARE Diagnostic")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Text("25 questions · about 5 minutes · free · no card required · confidential")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Measures Communication, Attitude, Relationships, Execution, and YOU")
                        bullet("1–5 scale; advance when you answer")
                        bullet("This is not therapy or a clinical diagnosis")
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                Spacer()
                Button {
                    groo.startCareQuiz()
                } label: {
                    Text("Take the free diagnostic")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(GrooBrand.purple))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(24)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GrooBrand.purple)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DrflowTheme.textPrimary)
        }
    }
}

struct GrooCareDiagnosticView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @State private var pendingValue: Int?
    @State private var isAdvancing = false

    private let totalQuestions = GrooCareCatalog.questions.count

    private var answeredCount: Int { groo.careAnswers.count }
    private var currentIndex: Int { min(answeredCount, totalQuestions - 1) }
    private var current: GrooCareQuestion { GrooCareCatalog.questions[currentIndex] }
    private var progress: Double { Double(answeredCount) / Double(totalQuestions) }

    private var pillarQuestionProgress: (current: Int, total: Int) {
        let inPillar = GrooCareCatalog.questions(for: current.pillar)
        let index = inPillar.firstIndex(where: { $0.id == current.id }) ?? 0
        return (index + 1, inPillar.count)
    }

    var body: some View {
        RevolutChromeContainer {
            VStack(spacing: 0) {
                diagnosticHeader

                Spacer(minLength: 16)

                questionCard
                    .padding(.horizontal, 20)
                    .id(current.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                Spacer(minLength: 28)

                answerScale
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: current.id)
    }

    private var diagnosticHeader: some View {
        VStack(spacing: 12) {
            if current.pillar == .foundation {
                HStack(spacing: 8) {
                    Image("GraduationCap")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("YOU · Personal foundations")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GrooBrand.purple)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(GrooBrand.purpleSoft)
                        .overlay {
                            Capsule().strokeBorder(GrooBrand.purple.opacity(0.25), lineWidth: 1)
                        }
                }
            }

            HStack(alignment: .center) {
                pillarChip
                Spacer()
                Text("Question \(currentIndex + 1) of \(totalQuestions)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DrflowTheme.controlFill))
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DrflowTheme.controlFill)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [GrooBrand.purple, GrooBrand.purple.opacity(0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 6)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: progress)

                Text("\(pillarQuestionProgress.current) of \(pillarQuestionProgress.total) in \(current.pillar.title)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var pillarChip: some View {
        Text(current.pillar.title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(GrooBrand.purple)
    }

    private var questionCard: some View {
        VStack(spacing: 18) {
            Text(current.trait)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(GrooBrand.purpleSoft)
                        .overlay {
                            Capsule().strokeBorder(GrooBrand.purple.opacity(0.2), lineWidth: 1)
                        }
                }

            Text(current.text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [GrooBrand.purple.opacity(0.22), DrflowTheme.cardBorder],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: GrooBrand.purple.opacity(0.08), radius: 20, y: 10)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        }
    }

    private var answerScale: some View {
        VStack(spacing: 14) {
            Text("How much do you identify with this?")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)

            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    scaleButton(value: value)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsdown")
                    Text("Disagree")
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Agree")
                    Image(systemName: "hand.thumbsup")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DrflowTheme.textTertiary)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(DrflowTheme.cardBorder, lineWidth: 1)
                }
        }
    }

    private func scaleButton(value: Int) -> some View {
        let isSelected = pendingValue == value

        return Button {
            guard !isAdvancing else { return }
            isAdvancing = true
            pendingValue = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                groo.answerCare(questionId: current.id, value: value)
                pendingValue = nil
                isAdvancing = false
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? GrooBrand.purple : Color.white)
                    .frame(width: isSelected ? 54 : 48, height: isSelected ? 54 : 48)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.clear : GrooBrand.purple.opacity(0.28),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(
                        color: isSelected ? GrooBrand.purple.opacity(0.35) : .black.opacity(0.04),
                        radius: isSelected ? 10 : 4,
                        y: isSelected ? 4 : 2
                    )

                Text("\(value)")
                    .font(.system(size: isSelected ? 20 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : GrooBrand.purple)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isAdvancing)
    }
}

struct GrooDiagnosticResultsView: View {
    @EnvironmentObject private var groo: GrooAppStore

    var body: some View {
        RevolutChromeContainer {
            if let result = groo.diagnostic {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Your CARE diagnostic")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(DrflowTheme.textPrimary)

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(format: "%.1f", result.overall))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrooBrand.purple)
                                Text("/ 5")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.textTertiary)
                                Spacer()
                                Text(result.nickname)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(GrooBrand.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(GrooBrand.purpleSoft))
                            }

                            Text(result.summary)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DrflowTheme.textSecondary)

                            GrooRadarChart(scores: result.pillars)
                                .frame(height: 260)
                                .padding(.vertical, 8)

                            ForEach(result.pillars) { pillar in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(pillar.pillar.title)
                                            .font(.system(size: 17, weight: .semibold))
                                        Spacer()
                                        Text(String(format: "%.1f", pillar.average))
                                            .font(.system(size: 17, weight: .bold, design: .rounded))
                                            .foregroundStyle(GrooBrand.purple)
                                    }
                                    Text("Growth area: \(pillar.lowestTrait)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                    Text(pillar.pillar.growthHint)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(DrflowTheme.textTertiary)
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(DrflowTheme.surfaceMuted)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                    }

                    diagnosticBottomBar
                }
            }
        }
    }

    private var diagnosticBottomBar: some View {
        VStack(spacing: 10) {
            Button {
                groo.enterMainFromResults(startChat: true)
            } label: {
                Text("Let's Chat with GROO")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(GrooBrand.purple))
                    .foregroundStyle(.white)
                    .shadow(color: GrooBrand.purple.opacity(0.28), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            Button("Go to dashboard") {
                groo.enterMainFromResults(startChat: false)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(GrooBrand.purple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct GrooRadarChart: View {
    let scores: [GrooPillarScore]
    var compact: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * (compact ? 0.34 : 0.38)
            let count = max(scores.count, 1)
            let labelOffset: CGFloat = compact ? 18 : 28
            let labelFont: CGFloat = compact ? 8 : 12

            ZStack {
                ForEach(1...5, id: \.self) { ring in
                    radarPolygon(center: center, radius: radius * CGFloat(ring) / 5, count: count)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                }
                radarValues(center: center, radius: radius, count: count)
                    .fill(GrooBrand.purple.opacity(0.22))
                radarValues(center: center, radius: radius, count: count)
                    .stroke(GrooBrand.purple, lineWidth: 2)

                ForEach(Array(scores.enumerated()), id: \.element.id) { index, item in
                    let angle = angle(for: index, count: count)
                    let labelPoint = point(center: center, radius: radius + labelOffset, angle: angle)
                    Text(String(format: "%.1f", item.average))
                        .font(.system(size: labelFont, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .position(labelPoint)
                }
            }
        }
    }

    private func angle(for index: Int, count: Int) -> Double {
        (-.pi / 2) + (Double(index) / Double(count)) * 2 * .pi
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }

    private func radarPolygon(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { path in
            for i in 0..<count {
                let p = point(center: center, radius: radius, angle: angle(for: i, count: count))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }

    private func radarValues(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { path in
            for i in 0..<count {
                let score = scores[i].average
                let r = radius * CGFloat(min(max(score, 0), 5) / 5)
                let p = point(center: center, radius: r, angle: angle(for: i, count: count))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}
