import PhotosUI
import SwiftUI

/// Home dashboard — contenedores separados con scroll.
struct GrooHomeView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel
    @State private var appeared = false
    @State private var showAccount = false

    private var firstName: String {
        let n = groo.profile.firstName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return "there"
    }

    private var result: GrooDiagnosticResult? { groo.diagnostic }

    private struct PillarCard: Identifiable {
        let pillar: GrooCarePillar
        let title: String
        let assetName: String
        var id: String { pillar.rawValue }
    }

    private var pillarCards: [PillarCard] {
        [
            .init(pillar: .communication, title: "Communication", assetName: "LibroIcon"),
            .init(pillar: .attitude, title: "Attitude", assetName: "CopaIcon"),
            .init(pillar: .relationships, title: "Relationships", assetName: "VerdeIcon"),
            .init(pillar: .execution, title: "Execution", assetName: "PhysicsIcon"),
        ]
    }

    private var upcomingReminders: [(icon: String, title: String, when: String, tint: Color)] {
        let live = groo.reminders.filter { !$0.isDone }.prefix(2)
        if !live.isEmpty {
            return live.map { item in
                (
                    icon: "bell.fill",
                    title: item.title,
                    when: item.dueAt.formatted(date: .abbreviated, time: .shortened),
                    tint: Color(red: 0.35, green: 0.55, blue: 0.98)
                )
            }
        }
        return [
            ("calendar", "Interview with Acme Co.", "May 2, 10:00 AM", Color(red: 0.35, green: 0.55, blue: 0.98)),
            ("bell.fill", "Performance review", "May 15, 2:00 PM", Color(red: 0.45, green: 0.72, blue: 0.98)),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        topHeader

                        heroRow(characterSize: 190)
                            .frame(height: 170)

                        pillarsRow
                            .frame(height: 118)

                        careRow
                            .frame(height: 176)

                        progressCTA
                            .frame(minHeight: 72)

                        focusAndReminders
                            .frame(height: 188)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .opacity(appeared ? 1 : 0)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
            .sheet(isPresented: $showAccount) {
                GrooAccountView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
        }
    }

    // MARK: - Header

    private var topHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image("GrooLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .shadow(color: GrooBrand.purple.opacity(0.3), radius: 6, y: 2)

                Text("GROO")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.9))
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrooBrand.purple)
                Text("0")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 6, y: 2))

            profileAvatar
        }
    }

    private var profileAvatar: some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(String(firstName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        .shadow(color: GrooBrand.purple.opacity(0.4), radius: 8, y: 0)
        .onTapGesture { showAccount = true }
    }

    // MARK: - Hero (burbuja izquierda · personaje derecha, sin solape)

    private func heroRow(characterSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 8) {
            speechBubble
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image("GrooCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: characterSize, height: characterSize)
                .shadow(color: GrooBrand.purple.opacity(0.28), radius: 18, y: 6)
        }
    }

    private var speechBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hey \(firstName), I'm GROO 👋")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("What would you like to focus on today?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.5))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
        }
    }

    // MARK: - Pillars

    private var pillarsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(pillarCards) { card in
                Button {
                    groo.ensureWelcomeSession()
                    tabRouter.openChat()
                } label: {
                    VStack(spacing: 6) {
                        Image(card.assetName)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(card.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                    }
                }
                .buttonStyle(GrooSoftPressStyle())
            }
        }
    }

    // MARK: - CARE (dos columnas iguales)

    private var careRow: some View {
        Group {
            if let result {
                HStack(alignment: .top, spacing: 12) {
                    careScorePanel(result)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    careDimensionsPanel(result)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Button {
                    groo.phase = .careIntro
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(GrooBrand.purpleSoft).frame(width: 44, height: 44)
                            Image(systemName: "chart.radar")
                                .foregroundStyle(GrooBrand.purple)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Take your free CARE diagnostic")
                                .font(.system(size: 14, weight: .bold))
                            Text("5 minutes · 25 questions · no card needed")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.45))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(GrooBrand.purple)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(softCard)
                }
                .buttonStyle(GrooSoftPressStyle())
            }
        }
    }

    private func careScorePanel(_ result: GrooDiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your CARE Score")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))

            HStack(alignment: .center, spacing: 12) {
                GrooRingScore(score: result.overall, lineWidth: 10, fontSize: 22)
                    .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayNickname(result.nickname))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GrooBrand.purple)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            GrooBrand.purpleSoft,
                                            Color(red: 0.94, green: 0.90, blue: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                    Text("You have a strong foundation and clear direction.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 2)

            Button {
                groo.phase = .careResults
            } label: {
                HStack(spacing: 4) {
                    Text("View full diagnostic")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(GrooBrand.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(softCard)
    }

    private func careDimensionsPanel(_ result: GrooDiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CARE Dimensions")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
            GrooRadarChart(scores: result.pillars, compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .padding(12)
        .background(softCard)
    }

    // MARK: - CTA

    private var progressCTA: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [GrooBrand.purple, GrooBrand.purple.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Let's make progress, together.")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("Chat with GROO and create a plan to overcome professional friction.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                groo.ensureWelcomeSession()
                tabRouter.openChat()
            } label: {
                Text("Chat with GROO →")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(GrooBrand.purple))
            }
            .buttonStyle(GrooSoftPressStyle())
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.90, blue: 1.0),
                            Color(red: 0.90, green: 0.93, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: GrooBrand.purple.opacity(0.08), radius: 8, y: 3)
        }
    }

    // MARK: - Focus + Reminders (dos columnas, misma altura)

    private var focusAndReminders: some View {
        HStack(alignment: .top, spacing: 12) {
            todaysFocusCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            upcomingRemindersCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var todaysFocusCard: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.90, blue: 1.0),
                                Color(red: 0.90, green: 0.95, blue: 1.0),
                                Color.white
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 72)

                Image("GraduationCap")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 78)
                    .shadow(color: Color(red: 0.2, green: 0.45, blue: 0.9).opacity(0.25), radius: 10, y: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Create a consistent\nlearning routine")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Button {
                groo.ensureWelcomeSession()
                tabRouter.openChat()
            } label: {
                Text("Register Now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
            }
            .buttonStyle(GrooSoftPressStyle())
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.96, blue: 1.0),
                            Color(red: 0.96, green: 0.97, blue: 1.0),
                            Color.white
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }

    private var upcomingRemindersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Upcoming reminders")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button {
                    tabRouter.selected = .reminders
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(red: 0.35, green: 0.55, blue: 0.98)))
                }
                .buttonStyle(GrooSoftPressStyle())
            }

            VStack(spacing: 6) {
                ForEach(Array(upcomingReminders.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(item.tint.opacity(0.14)))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(item.when)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.95, blue: 1.0),
                            Color(red: 0.90, green: 0.94, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    // MARK: - Helpers

    private var softCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func displayNickname(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("steady") { return "Steady Builder" }
        if raw.localizedCaseInsensitiveContains("quiet") || raw.localizedCaseInsensitiveContains("comunic") {
            return "Quiet Communicator"
        }
        return raw
    }
}

private struct GrooSoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GrooRingScore: View {
    let score: Double
    var lineWidth: CGFloat = 11
    var fontSize: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .stroke(GrooBrand.purpleSoft, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score / 5, 0), 1)))
                .stroke(
                    AngularGradient(
                        colors: [GrooBrand.purple.opacity(0.7), GrooBrand.purple],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.9))
                Text("out of 5")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
        }
    }
}

struct GrooAccountView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var auth: AuthViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSavingPhoto = false

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        profileCard
                        subscriptionCard
                        careerCard
                        signOutButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Account")
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    isSavingPhoto = true
                    defer { isSavingPhoto = false }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await auth.updateProfileAvatar(with: image)
                    }
                    selectedPhoto = nil
                }
            }
            .sheet(isPresented: $groo.showPaywall) {
                GrooPremiumPaywallView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    profileAvatarView(size: 88)

                    ZStack {
                        Circle().fill(GrooBrand.purple)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSavingPhoto)

            VStack(spacing: 4) {
                Text(groo.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Text(auth.session?.user.email ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }

            if isSavingPhoto {
                ProgressView()
                    .tint(GrooBrand.purple)
            } else {
                Text("Tap the photo to change it")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DrflowTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(accountCardBackground)
    }

    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        Group {
            if let img = auth.profileAvatarImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(GrooBrand.purpleSoft)
                    Text(String(groo.displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.purple)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
        .shadow(color: GrooBrand.purple.opacity(0.18), radius: 12, y: 4)
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GrooBrand.purple)

            HStack {
                Text("Plan")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Text(groo.subscription == .trial ? "Trial" : groo.subscription.rawValue.capitalized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GrooBrand.purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GrooBrand.purpleSoft))
            }

            Button("Manage Premium") { groo.showPaywall = true }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(accountCardBackground)
    }

    private var careerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Career")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GrooBrand.purple)

            accountRowButton(title: "View full diagnostic", icon: "chart.radar") {
                if groo.diagnostic != nil {
                    groo.phase = .careResults
                } else {
                    groo.phase = .careIntro
                }
            }

            Divider().opacity(0.5)

            accountRowButton(title: "Retake CARE diagnostic", icon: "arrow.clockwise") {
                groo.phase = .careIntro
            }
        }
        .padding(18)
        .background(accountCardBackground)
    }

    private func accountRowButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GrooBrand.purple)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DrflowTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    private var signOutButton: some View {
        Button("Sign out", role: .destructive) {
            Task { await auth.signOut() }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(accountCardBackground)
    }

    private var accountCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}
