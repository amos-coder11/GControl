import Combine
import Foundation
import SwiftUI

enum GrooAppPhase: String, Codable {
    case onboarding
    case profileSetup
    case careIntro
    case careQuiz
    case careResults
    case main
}

struct GrooOnboardingAnswers: Codable, Equatable {
    var reasons: [String] = []
    var careerStage: String = ""
    var workSituation: String = ""
    var goals: [String] = []
    var priorMentor: String = ""
    var workStyle: String = ""
    var managesPeople: String = ""
}

struct GrooUserProfile: Codable, Equatable {
    var firstName: String = ""
    var lastName: String = ""
    var phone: String = ""
    var country: String = {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier ?? "US"
        }
        return Locale.current.regionCode ?? "US"
    }()
    var ageRange: String = ""
    var gender: String = ""
    var linkedIn: String = ""
    var cvFileName: String = ""
}

struct GrooChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var isUser: Bool
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), isUser: Bool, text: String, createdAt: Date = Date()) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.createdAt = createdAt
    }
}

struct GrooChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [GrooChatMessage]

    var preview: String {
        messages.last(where: { !$0.isUser })?.text
            ?? messages.last?.text
            ?? "New session"
    }
}

struct GrooReminder: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var note: String
    var dueAt: Date
    var createdAt: Date
    var isDone: Bool
}

enum GrooSubscriptionTier: String, Codable {
    case trial
    case monthly
    case annual
    case pro
}

/// Estado persistente de la experiencia GROO (mentoría CARE + chat).
@MainActor
final class GrooAppStore: ObservableObject {
    @Published var phase: GrooAppPhase = .onboarding
    @Published var onboarding = GrooOnboardingAnswers()
    @Published var profile = GrooUserProfile()
    @Published var careAnswers: [Int: Int] = [:]
    @Published var diagnostic: GrooDiagnosticResult?
    @Published var sessions: [GrooChatSession] = []
    @Published var activeSessionId: UUID?
    @Published var reminders: [GrooReminder] = []
    @Published var subscription: GrooSubscriptionTier = .trial
    @Published var trialMessagesRemaining: Int = 12
    @Published var showPaywall = false
    @Published var hasDismissedPaywallOnce = false
    /// Navega al chat al entrar en la pestaña principal (no persistido).
    @Published var shouldOpenChatOnMain = false

    private let storageKey = "Groo.appStore.v1"

    init() {
        load()
        if activeSessionId == nil, let first = sessions.first {
            activeSessionId = first.id
        }
        Task {
            await GrooReminderNotificationService.rescheduleAll(
                reminders: reminders.filter { !$0.isDone && $0.dueAt > Date() }
            )
        }
    }

    var activeSession: GrooChatSession? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    var displayName: String {
        let n = "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "professional" : n
    }

    /// Recordatorios pendientes (no completados) para el badge de la pestaña.
    var activeRemindersCount: Int {
        reminders.filter { !$0.isDone }.count
    }

    // MARK: - Navigation helpers

    func completeOnboarding() {
        phase = .profileSetup
        save()
    }

    func completeProfile() {
        phase = diagnostic == nil ? .careIntro : .main
        save()
    }

    func startCareQuiz() {
        careAnswers = [:]
        phase = .careQuiz
        save()
    }

    func answerCare(questionId: Int, value: Int) {
        careAnswers[questionId] = value
        objectWillChange.send()
        if careAnswers.count >= GrooCareCatalog.questions.count {
            finishCareQuiz()
        } else {
            save()
        }
    }

    func finishCareQuiz() {
        diagnostic = GrooCareScoring.result(from: careAnswers)
        phase = .careResults
        save()
    }

    func enterMainFromResults(startChat: Bool) {
        phase = .main
        if startChat {
            ensureWelcomeSession()
            shouldOpenChatOnMain = true
        }
        if subscription == .trial && !hasDismissedPaywallOnce {
            showPaywall = true
        }
        save()
    }

    func dismissPaywallContinueTrial() {
        showPaywall = false
        hasDismissedPaywallOnce = true
        save()
    }

    func selectPlan(_ tier: GrooSubscriptionTier) {
        subscription = tier
        showPaywall = false
        hasDismissedPaywallOnce = true
        if tier != .trial {
            trialMessagesRemaining = 999
        }
        save()
    }

    // MARK: - Sessions / chat

    @discardableResult
    func startNewSession() -> UUID {
        let welcome = welcomeMessage()
        let session = GrooChatSession(
            id: UUID(),
            title: "Session \(sessions.count + 1)",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [welcome]
        )
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        save()
        return session.id
    }

    func ensureWelcomeSession() {
        if sessions.isEmpty {
            startNewSession()
        } else if activeSessionId == nil {
            activeSessionId = sessions.first?.id
        }
    }

    func selectSession(_ id: UUID) {
        activeSessionId = id
        save()
    }

    func appendUserMessage(_ text: String, countsAgainstTrial: Bool = true) -> Bool {
        ensureWelcomeSession()
        guard let id = activeSessionId,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return false }

        if countsAgainstTrial, subscription == .trial, trialMessagesRemaining <= 0 {
            showPaywall = true
            return false
        }

        sessions[idx].messages.append(GrooChatMessage(isUser: true, text: text))
        sessions[idx].updatedAt = Date()
        if sessions[idx].title.hasPrefix("Session") {
            sessions[idx].title = String(text.prefix(42))
        }
        if countsAgainstTrial, subscription == .trial {
            trialMessagesRemaining = max(0, trialMessagesRemaining - 1)
        }
        save()
        return true
    }

    /// Creates a reminder from chat when the message includes a reminder intent + deadline (no AI).
    func handleChatReminderIfNeeded(text: String) -> String? {
        guard GrooReminderTimeParser.isReminderRequest(text),
              let dueAt = GrooReminderTimeParser.parseDueDate(from: text),
              dueAt > Date()
        else { return nil }

        let title = GrooReminderTimeParser.suggestedTitle(from: text)
        let span = GrooReminderTimeParser.relativeSpanDescription(from: text)
        addReminder(
            title: title,
            note: String(text.prefix(160)),
            dueAt: dueAt
        )
        return GrooReminderTimeParser.cannedAssistantReply(title: title, span: span, dueAt: dueAt)
    }

    func appendAssistantMessage(_ text: String) {
        guard let id = activeSessionId,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(GrooChatMessage(isUser: false, text: text))
        sessions[idx].updatedAt = Date()
        save()
    }

    func filteredSessions(query: String) -> [GrooChatSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.lowercased().contains(q)
                || $0.preview.lowercased().contains(q)
                || $0.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    // MARK: - Reminders

    func addReminder(title: String, note: String, dueAt: Date) {
        let reminder = GrooReminder(
            id: UUID(),
            title: title,
            note: note,
            dueAt: dueAt,
            createdAt: Date(),
            isDone: false
        )
        reminders.insert(reminder, at: 0)
        save()
        Task {
            await GrooReminderNotificationService.schedule(reminder: reminder)
        }
    }

    func toggleReminder(_ id: UUID) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].isDone.toggle()
        if reminders[i].isDone {
            GrooReminderNotificationService.cancel(reminderId: id)
        } else if reminders[i].dueAt > Date() {
            Task {
                await GrooReminderNotificationService.schedule(reminder: reminders[i])
            }
        }
        save()
    }

    func deleteReminder(_ id: UUID) {
        GrooReminderNotificationService.cancel(reminderId: id)
        reminders.removeAll { $0.id == id }
        save()
    }

    private func welcomeMessage() -> GrooChatMessage {
        if let d = diagnostic {
            let text = """
            Hi \(displayName.split(separator: " ").first.map(String.init) ?? displayName). I'm GROO, your career companion.

            Your CARE diagnostic: \(String(format: "%.1f", d.overall))/5 — «\(d.nickname)».
            \(d.summary)

            Where would you like to start today?
            """
            return GrooChatMessage(isUser: false, text: text)
        }
        return GrooChatMessage(
            isUser: false,
            text: "Hi. I'm GROO, the career companion you never had. Tell me what brings you here today — clarity, a difficult conversation, or your next step."
        )
    }

    func careContextForMentor() -> String {
        guard let d = diagnostic else {
            return "The user does not yet have a complete CARE diagnostic."
        }
        var lines = [
            "USER CARE DIAGNOSTIC:",
            "Overall: \(String(format: "%.1f", d.overall))/5 — \(d.nickname)",
            d.summary,
            "Dimensions:"
        ]
        for p in d.pillars {
            lines.append("- \(p.pillar.title): \(String(format: "%.1f", p.average))/5 (area: \(p.lowestTrait))")
        }
        lines.append("Methodology: C.A.R.E+U. Connect each response to Communication, Attitude, Relationships, Execution, or YOU.")
        lines.append("Do not offer therapy or medical advice.")
        if !onboarding.goals.isEmpty {
            lines.append("Stated goals: \(onboarding.goals.joined(separator: ", "))")
        }
        if !onboarding.careerStage.isEmpty {
            lines.append("Career stage: \(onboarding.careerStage)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var phase: GrooAppPhase
        var onboarding: GrooOnboardingAnswers
        var profile: GrooUserProfile
        var careAnswers: [String: Int]
        var diagnostic: GrooDiagnosticResult?
        var sessions: [GrooChatSession]
        var activeSessionId: UUID?
        var reminders: [GrooReminder]
        var subscription: GrooSubscriptionTier
        var trialMessagesRemaining: Int
        var hasDismissedPaywallOnce: Bool
    }

    func save() {
        let snap = Snapshot(
            phase: phase,
            onboarding: onboarding,
            profile: profile,
            careAnswers: Dictionary(uniqueKeysWithValues: careAnswers.map { (String($0.key), $0.value) }),
            diagnostic: diagnostic,
            sessions: sessions,
            activeSessionId: activeSessionId,
            reminders: reminders,
            subscription: subscription,
            trialMessagesRemaining: trialMessagesRemaining,
            hasDismissedPaywallOnce: hasDismissedPaywallOnce
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        phase = snap.phase
        onboarding = snap.onboarding
        profile = snap.profile
        careAnswers = Dictionary(uniqueKeysWithValues: snap.careAnswers.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        diagnostic = snap.diagnostic
        sessions = snap.sessions
        activeSessionId = snap.activeSessionId
        reminders = snap.reminders
        subscription = snap.subscription
        trialMessagesRemaining = snap.trialMessagesRemaining
        hasDismissedPaywallOnce = snap.hasDismissedPaywallOnce
    }

    func resetProgressForTesting() {
        phase = .onboarding
        onboarding = GrooOnboardingAnswers()
        profile = GrooUserProfile()
        careAnswers = [:]
        diagnostic = nil
        sessions = []
        activeSessionId = nil
        reminders = []
        subscription = .trial
        trialMessagesRemaining = 12
        hasDismissedPaywallOnce = false
        showPaywall = false
        save()
    }
}
