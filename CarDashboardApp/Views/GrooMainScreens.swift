import SwiftUI

import SwiftUI

struct GrooSessionsView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var query = ""

    private var sessions: [GrooChatSession] {
        groo.filteredSessions(query: query)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerBlock
                        searchField

                        if sessions.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(sessions) { session in
                                    sessionCard(session)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        groo.startNewSession()
                        tabRouter.openChat()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(GrooBrand.purple))
                    }
                }
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your conversations")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)
            Text("Pick up where you left off with GROO")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DrflowTheme.textMuted)
            TextField("Search sessions", text: $query)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DrflowTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(GrooBrand.purpleSoft)
                    .frame(width: 88, height: 88)
                Image("GrooCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
            }

            Text(query.isEmpty ? "No sessions yet" : "No results")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(DrflowTheme.textPrimary)

            Text(
                query.isEmpty
                    ? "Start a chat with GROO and your sessions will appear here."
                    : "Try another search term."
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(DrflowTheme.textSecondary)
            .multilineTextAlignment(.center)

            if query.isEmpty {
                Button {
                    groo.startNewSession()
                    tabRouter.openChat()
                } label: {
                    Text("New chat with GROO")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GrooBrand.purple))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        }
    }

    private func sessionCard(_ session: GrooChatSession) -> some View {
        Button {
            groo.selectSession(session.id)
            tabRouter.openChat()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Image("GrooCharacter")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("\(session.messages.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(GrooBrand.purple))
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(relativeDate(session.updatedAt))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textTertiary)
                    }

                    Text(session.preview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DrflowTheme.textMuted)
                    .padding(.top, 4)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            }
        }
        .buttonStyle(GrooSoftPressStyle())
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct GrooSoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct GrooRemindersView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @State private var showAdd = false
    @State private var title = ""
    @State private var note = ""
    @State private var dueAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()
                Group {
                    if groo.reminders.isEmpty {
                        ContentUnavailableView(
                            "Reminders",
                            systemImage: "bell",
                            description: Text("Empty by default. GROO can suggest reminders when you mention interviews, reviews, or meetings in chat.")
                        )
                    } else {
                        List {
                            ForEach(groo.reminders) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        groo.toggleReminder(item.id)
                                    } label: {
                                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isDone ? DrflowTheme.positive : GrooBrand.purple)
                                    }
                                    .buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .strikethrough(item.isDone)
                                        if !item.note.isEmpty {
                                            Text(item.note)
                                                .font(.system(size: 13))
                                                .foregroundStyle(DrflowTheme.textSecondary)
                                        }
                                        Text(item.dueAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(DrflowTheme.textTertiary)
                                    }
                                }
                                .listRowBackground(Color.white.opacity(0.85))
                            }
                            .onDelete { indexSet in
                                for i in indexSet {
                                    groo.deleteReminder(groo.reminders[i].id)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(GrooBrand.purple)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $title)
                        TextField("Note", text: $note, axis: .vertical)
                        DatePicker("When", selection: $dueAt)
                    }
                    .navigationTitle("New reminder")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                groo.addReminder(title: title.isEmpty ? "Reminder" : title, note: note, dueAt: dueAt)
                                title = ""
                                note = ""
                                showAdd = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}

struct GrooDiagnosticDashboardView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                RevolutBackgroundView()
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result = groo.diagnostic {
                        Text("My Diagnostic")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f / 5", result.overall))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrooBrand.purple)
                                Text(result.nickname)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.textSecondary)
                            }
                            Spacer()
                        }

                        GrooRadarChart(scores: result.pillars)
                            .frame(height: 240)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommended action")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(GrooBrand.purple)
                            Text(result.recommendedAction)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DrflowTheme.textPrimary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(GrooBrand.purpleSoft)
                        }

                        Button {
                            groo.ensureWelcomeSession()
                            tabRouter.openChat()
                        } label: {
                            Text("Chat with GROO and come up with a plan")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(GrooBrand.purple))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button("View full results") {
                            groo.phase = .careResults
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GrooBrand.purple)
                        .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView(
                            "My Diagnostic",
                            systemImage: "chart.radar",
                            description: Text("Complete the CARE diagnostic to see your radar and plan.")
                        )
                        Button("Take the free diagnostic") {
                            groo.phase = .careIntro
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GrooBrand.purple))
                    }

                    Divider().padding(.vertical, 8)

                    Button("Sign out") {
                        Task { await auth.signOut() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            }
            .navigationTitle("My diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        groo.showPaywall = true
                    } label: {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(GrooBrand.purple)
                    }
                }
            }
            .sheet(isPresented: $groo.showPaywall) {
                GrooPremiumPaywallView()
                    .environmentObject(groo)
                    .environmentObject(auth)
            }
        }
    }
}

struct GrooPremiumPaywallView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 1
    @State private var promo = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Groo Premium")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Picker("", selection: $tab) {
                    Text("Monthly").tag(0)
                    Text("Annual").tag(1)
                    Text("Groo PRO").tag(2)
                }
                .pickerStyle(.segmented)

                Group {
                    switch tab {
                    case 0:
                        planCard(
                            title: "Groo Monthly",
                            price: "$12.99 / month",
                            detail: "Unlimited 1-on-1 mentorship and goal tracking.",
                            tier: .monthly
                        )
                    case 2:
                        planCard(
                            title: "Groo PRO",
                            price: "Early Access",
                            detail: "For founders: you'll never pay more than your founder rate.",
                            tier: .pro
                        )
                    default:
                        planCard(
                            title: "Groo 365",
                            price: "$79 / year · $6.58/month",
                            detail: "34% off. Unlimited mentorship, achievements, and goals. Early Access.",
                            tier: .annual
                        )
                    }
                }

                TextField("Promo code", text: $promo)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DrflowTheme.surfaceMuted))

                Button("Continue on Trial") {
                    groo.dismissPaywallContinueTrial()
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GrooBrand.purple)
                .frame(maxWidth: .infinity)

                Button("Sign out") {
                    Task {
                        await auth.signOut()
                        dismiss()
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textTertiary)
                .frame(maxWidth: .infinity)

                Text("You can cancel anytime from account settings. GROO is not therapy or medical advice.")
                    .font(.system(size: 11))
                    .foregroundStyle(DrflowTheme.textTertiary)

                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        groo.dismissPaywallContinueTrial()
                        dismiss()
                    }
                }
            }
        }
    }

    private func planCard(title: String, price: String, detail: String, tier: GrooSubscriptionTier) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(price)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(GrooBrand.purple)
            Text(detail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DrflowTheme.textSecondary)
            Button("Choose plan") {
                groo.selectPlan(tier)
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(GrooBrand.purple))
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DrflowTheme.surfaceMuted)
        }
    }
}
