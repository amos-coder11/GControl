import PhotosUI
import SwiftUI
import UIKit

// MARK: - Chat root (bandeja → conversación)

private enum GrooChatDestination: Hashable, Identifiable {
    case mentor(UUID)
    case instagram(ChatThread)

    var id: String {
        switch self {
        case .mentor(let id): return "mentor-\(id.uuidString)"
        case .instagram(let thread): return "ig-\(thread.id.uuidString)"
        }
    }
}

struct GrooChatRootView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @EnvironmentObject private var auth: AuthViewModel
    @State private var destination: GrooChatDestination?
    @State private var query = ""

    var body: some View {
        NavigationStack {
            GrooChatInboxView(
                query: $query,
                onOpenSession: { id in
                    groo.selectSession(id)
                    destination = .mentor(id)
                },
                onOpenInstagram: { thread in
                    chatInbox.activeLeadThreadId = thread.id
                    destination = .instagram(thread)
                },
                onNewChat: {
                    let id = groo.startNewSession()
                    destination = .mentor(id)
                }
            )
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .mentor(let id):
                    GrooMentorChatView()
                        .onAppear { groo.selectSession(id) }
                case .instagram(let thread):
                    ChatConversationView(thread: thread)
                        .onDisappear { chatInbox.activeLeadThreadId = nil }
                }
            }
        }
        .onAppear {
            groo.ensureWelcomeSession()
            Task { await refreshInstagramInbox() }
        }
        .task(id: auth.session?.accessToken) {
            await refreshInstagramInbox()
        }
        .onChange(of: groo.pendingChatNavigation) { _, sessionId in
            guard let sessionId else { return }
            groo.pendingChatNavigation = nil
            groo.selectSession(sessionId)
            destination = .mentor(sessionId)
        }
    }

    private func refreshInstagramInbox() async {
        guard let token = auth.session?.accessToken, !token.isEmpty else { return }
        await chatInbox.refreshCrmConversations(accessToken: token)
    }
}

// MARK: - Bandeja de conversaciones (moderna · azul Groo)

enum GrooInboxFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case instagram = "Instagram"
    case assistant = "Assistant"

    var id: String { rawValue }
}

struct GrooChatInboxView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var chatInbox: ChatInboxStore
    @Binding var query: String
    var onOpenSession: (UUID) -> Void
    var onOpenInstagram: (ChatThread) -> Void
    var onNewChat: () -> Void

    @State private var filter: GrooInboxFilter = .all

    private var q: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var sessions: [GrooChatSession] {
        guard filter != .instagram else { return [] }
        let base = groo.filteredSessions(query: query)
        switch filter {
        case .all, .assistant:
            return base
        case .unread:
            return base.filter { unreadCount(for: $0) > 0 }
        case .instagram:
            return []
        }
    }

    private var instagramThreads: [ChatThread] {
        let base = chatInbox.liveThreads.filter { thread in
            thread.socialSource == .instagram
                || (chatInbox.crmConversationIdByThread[thread.id] ?? "").hasPrefix("ig:")
        }
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) || $0.preview.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                stickyInboxHeader
                ScrollView {
                    if filter == .assistant && query.isEmpty {
                        pinnedContacts
                    }
                    if filter == .all || filter == .instagram {
                        if !instagramThreads.isEmpty {
                            instagramListContent
                        } else if filter == .instagram {
                            emptyInstagramContent
                        }
                    }
                    if filter != .instagram {
                        if sessions.isEmpty && (filter != .all || instagramThreads.isEmpty) {
                            emptyInboxContent
                        } else if !sessions.isEmpty {
                            conversationListContent
                        }
                    }
                }
            }

            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background {
                        Circle()
                            .fill(GrooBrand.primary)
                            .shadow(color: GrooBrand.primary.opacity(0.35), radius: 12, y: 6)
                    }
            }
            .buttonStyle(GrooChatPressStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .background(GrooChatTheme.listBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var stickyInboxHeader: some View {
        VStack(spacing: 0) {
            inboxHeader
            filterRow
        }
        .background {
            GrooChatTheme.softHeaderGradient
                .ignoresSafeArea(edges: .top)
        }
    }

    private var inboxHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Messages")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text("Clinic conversations")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
                Spacer()
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.85)))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GrooBrand.primary.opacity(0.75))
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search chats")
                        .foregroundStyle(Color.black.opacity(0.35))
                )
                    .font(.system(size: 16))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .tint(GrooBrand.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.black.opacity(0.28))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GrooInboxFilter.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            filter = item
                        }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(filter == item ? GrooBrand.primary : Color.black.opacity(0.45))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(filter == item ? Color.white : Color.white.opacity(0.45))
                                    .shadow(color: .black.opacity(filter == item ? 0.06 : 0), radius: 6, y: 2)
                            }
                    }
                    .buttonStyle(GrooChatPressStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .padding(.bottom, 4)
    }

    private var pinnedContacts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(GrooClinicContacts.pinned) { contact in
                    Button {
                        let id = groo.startSession(titled: contact.name)
                        onOpenSession(id)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(contact.tint.opacity(0.14))
                                    .frame(width: 58, height: 58)
                                Image(systemName: contact.symbol)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(contact.tint)
                            }
                            Text(contact.name.split(separator: " ").first.map(String.init) ?? contact.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .lineLimit(1)
                            Text(contact.role)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(GrooChatTheme.metaText)
                                .lineLimit(1)
                        }
                        .frame(width: 78)
                    }
                    .buttonStyle(GrooChatPressStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var conversationListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                Button {
                    onOpenSession(session.id)
                } label: {
                    GrooInboxConversationRow(
                        title: displayTitle(session),
                        preview: session.preview,
                        date: session.updatedAt,
                        unreadCount: unreadCount(for: session),
                        isPinned: index == 0 && filter == .all
                    )
                }
                .buttonStyle(GrooChatPressStyle())

                if index < sessions.count - 1 {
                    Divider().padding(.leading, 82)
                }
            }
        }
        .padding(.bottom, 88)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var instagramListContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filter == .all {
                Text("Instagram")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .padding(.horizontal, 8)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(instagramThreads.enumerated()), id: \.element.id) { index, thread in
                    Button {
                        onOpenInstagram(thread)
                    } label: {
                        GrooInboxConversationRow(
                            title: thread.title,
                            preview: thread.preview.isEmpty ? "Instagram message" : thread.preview,
                            date: Date(),
                            unreadCount: thread.unread ?? 0,
                            isPinned: false
                        )
                    }
                    .buttonStyle(GrooChatPressStyle())

                    if index < instagramThreads.count - 1 {
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, filter == .instagram ? 88 : 4)
    }

    private var emptyInstagramContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(GrooBrand.primary)
                .padding(.top, 36)
            Text("No Instagram chats yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("When someone DMs your Instagram business account, the message appears here.")
                .font(.system(size: 14))
                .foregroundStyle(GrooChatTheme.metaText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 80)
    }

    private var emptyInboxContent: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(GrooBrand.primarySoft)
                    .frame(width: 110, height: 110)
                Image("GrooCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
            }
            .padding(.top, 40)

            Text(query.isEmpty ? "No conversations yet" : "No results")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(
                query.isEmpty
                    ? "Start messaging your clinic team or ask \(GrooBrand.appName) about appointments and patients."
                    : "Try another name or keyword."
            )
            .font(.system(size: 15))
            .foregroundStyle(GrooChatTheme.metaText)
            .multilineTextAlignment(.center)
            if query.isEmpty {
                Button(action: onNewChat) {
                    Text("Start conversation")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(GrooBrand.primary))
                }
                .buttonStyle(GrooChatPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.bottom, 120)
    }

    private func displayTitle(_ session: GrooChatSession) -> String {
        if session.title.hasPrefix("Session") { return "\(GrooBrand.appName) Clinic" }
        return session.title
    }

    private func unreadCount(for session: GrooChatSession) -> Int {
        GrooAppStore.unreadCount(in: session)
    }
}

// MARK: - Calendar

struct GrooCalendarView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @State private var selectedDate = Date()
    @State private var showAdd = false
    @State private var title = ""
    @State private var note = ""
    @State private var dueAt = Date()
    @State private var revenueText = ""
    @State private var linkedPatientId: UUID?
    @State private var consultationType: GrooConsultationType = .followUp

    private var itemsForSelectedDay: [GrooReminder] {
        groo.reminders.filter { Calendar.current.isDate($0.dueAt, inSameDayAs: selectedDate) }
            .sorted { $0.dueAt < $1.dueAt }
    }

    private var upcomingCount: Int {
        groo.reminders.filter { !$0.isDone && $0.dueAt >= Calendar.current.startOfDay(for: Date()) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GrooClinicDesign.ScreenBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        calendarSummaryStrip

                        DatePicker(
                            "Agenda clínica",
                            selection: $selectedDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .tint(GrooBrand.primary)
                        .padding(14)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
                        }

                        dayAgendaSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetAppointmentForm()
                        dueAt = Calendar.current.date(
                            bySettingHour: 10, minute: 0, second: 0, of: selectedDate
                        ) ?? selectedDate
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(GrooBrand.primary)
                    }
                }
            }
            .onAppear { applyPendingAppointmentDraftIfNeeded() }
            .onChange(of: groo.shouldOpenCalendarWithDraft) { _, _ in
                applyPendingAppointmentDraftIfNeeded()
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        if linkedPatientId != nil {
                            Section {
                                Label("Datos del paciente autocompletados", systemImage: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GrooBrand.primary)
                            }
                        }
                        Picker("Tipo de consulta", selection: $consultationType) {
                            ForEach(GrooConsultationType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        TextField("Título de la cita", text: $title)
                        TextField("Nota clínica", text: $note, axis: .vertical)
                        TextField("Importe cita (opcional)", text: $revenueText)
                            .keyboardType(.decimalPad)
                        DatePicker("Fecha y hora", selection: $dueAt)
                    }
                    .navigationTitle("Nueva cita")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") {
                                showAdd = false
                                resetAppointmentForm()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Guardar") {
                                let revenue = revenueText
                                    .replacingOccurrences(of: "$", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                let amount = revenue.isEmpty ? consultationType.defaultPrice : Double(revenue)
                                groo.addReminder(
                                    title: title.isEmpty ? "\(consultationType.label)" : title,
                                    note: note,
                                    dueAt: dueAt,
                                    revenue: amount,
                                    patientId: linkedPatientId,
                                    consultationType: consultationType
                                )
                                resetAppointmentForm()
                                showAdd = false
                                selectedDate = dueAt
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func resetAppointmentForm() {
        title = ""
        note = ""
        revenueText = ""
        linkedPatientId = nil
        consultationType = .followUp
    }

    private func applyPendingAppointmentDraftIfNeeded() {
        guard groo.shouldOpenCalendarWithDraft, let draft = groo.pendingAppointmentDraft else { return }
        title = "\(draft.consultationType.label) — \(draft.fullName)"
        note = draft.note
        dueAt = draft.dueAt
        revenueText = String(format: "%.0f", draft.estimatedRevenue)
        linkedPatientId = draft.patientId
        consultationType = draft.consultationType
        selectedDate = draft.dueAt
        showAdd = true
        groo.shouldOpenCalendarWithDraft = false
    }

    private var calendarSummaryStrip: some View {
        GrooClinicDesign.KPIStrip(items: [
            (label: "Hoy", value: "\(itemsForSelectedDay.count)", icon: "calendar"),
            (label: "Pendientes", value: "\(upcomingCount)", icon: "clock.badge.exclamationmark"),
            (label: "Completadas", value: "\(groo.reminders.filter(\.isDone).count)", icon: "checkmark.circle"),
        ])
    }

    private var dayAgendaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                Spacer()
                if upcomingCount > 0 {
                    Text("\(upcomingCount) pendientes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrooBrand.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(GrooBrand.primarySoft))
                }
            }

            if itemsForSelectedDay.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28))
                        .foregroundStyle(GrooBrand.primary.opacity(0.7))
                    Text("Sin citas este día")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textPrimary)
                    Text("Añade una visita, control o tarea clínica.")
                        .font(.system(size: 13))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(itemsForSelectedDay.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 2) {
                                Text(item.dueAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrooBrand.primary)
                                Circle()
                                    .fill(item.isDone ? DrflowTheme.positive : GrooBrand.primary)
                                    .frame(width: 8, height: 8)
                            }
                            .frame(width: 64)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.textPrimary)
                                    .strikethrough(item.isDone)
                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.system(size: 13))
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                }
                                if item.isDone {
                                    Text(
                                        DealershipStatsViewModel.formatUSD(
                                            item.revenue ?? GrooAppStore.defaultAppointmentRevenue
                                        )
                                    )
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.positive)
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                groo.toggleReminder(item.id)
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? DrflowTheme.positive : GrooBrand.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < itemsForSelectedDay.count - 1 {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                }
            }
        }
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
                            description: Text("Empty by default. \(GrooBrand.appName) can suggest reminders when you mention appointments, follow-ups, or sterilization tasks in chat.")
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
                            groo.prepareChatNavigation()
                            tabRouter.openChat()
                        } label: {
                            Text("Chat with \(GrooBrand.appName) and come up with a plan")
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
                            description: Text("Complete the clinic assessment to see your radar and action plan.")
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
            .navigationTitle("Clinic assessment")
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
                Text("Welcome to \(GrooBrand.appName) Premium")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Picker("", selection: $tab) {
                    Text("Monthly").tag(0)
                    Text("Annual").tag(1)
                    Text("\(GrooBrand.appName) PRO").tag(2)
                }
                .pickerStyle(.segmented)

                Group {
                    switch tab {
                    case 0:
                        planCard(
                            title: "\(GrooBrand.appName) Monthly",
                            price: "$12.99 / month",
                            detail: "Unlimited clinic assistant chat and operational reminders.",
                            tier: .monthly
                        )
                    case 2:
                        planCard(
                            title: "\(GrooBrand.appName) PRO",
                            price: "Early Access",
                            detail: "For founders: you'll never pay more than your founder rate.",
                            tier: .pro
                        )
                    default:
                        planCard(
                            title: "\(GrooBrand.appName) 365",
                            price: "$79 / year · $6.58/month",
                            detail: "34% off. Unlimited assistant, team workflows, and clinic insights. Early Access.",
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

                Text("You can cancel anytime from account settings. \(GrooBrand.appName) provides clinic operations guidance, not clinical treatment advice.")
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

// MARK: - Pacientes

struct GrooPatientAvatarView: View {
    let patient: GrooPatient
    var size: CGFloat = 48
    @EnvironmentObject private var groo: GrooAppStore

    var body: some View {
        Group {
            if let data = groo.patientPhotoData(for: patient.id),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(
                        LinearGradient(
                            colors: [GrooBrand.primarySoft, Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    Text(String(patient.fullName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(GrooBrand.primary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
        .shadow(color: GrooBrand.primary.opacity(0.12), radius: 4, y: 2)
    }
}

/// Fecha destacada para timeline clínica.
private struct GrooClinicalDateBadge: View {
    let date: Date

    private var day: String {
        date.formatted(.dateTime.day().locale(Locale(identifier: "es_ES")))
    }

    private var month: String {
        date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "es_ES"))).uppercased()
    }

    private var year: String {
        date.formatted(.dateTime.year().locale(Locale(identifier: "es_ES")))
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(day)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(GrooBrand.primary)
            Text(month)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DrflowTheme.textSecondary)
            Text(year)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DrflowTheme.textTertiary)
        }
        .frame(width: 52)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GrooBrand.primarySoft)
        }
    }
}

private struct GrooPatientCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct GrooPatientsView: View {
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var query = ""
    @State private var filter: GrooPatientListFilter = .all
    @State private var showAddPatient = false
    @State private var selectedPatientId: GrooPatientRoute?

    private var patients: [GrooPatient] {
        groo.filteredPatients(query: query, filter: filter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GrooClinicDesign.ScreenBackground()

                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        patientsSearchBar
                        patientsKPIStrip
                        patientsFilterRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(Color.white)

                    if patients.isEmpty {
                        patientsEmptyState
                    } else {
                        List {
                            Section {
                                ForEach(patients) { patient in
                                    Button {
                                        selectedPatientId = GrooPatientRoute(id: patient.id)
                                    } label: {
                                        patientListRow(patient)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                }
                            } header: {
                                GrooClinicDesign.SectionHeader(
                                    title: "Directorio clínico",
                                    subtitle: "\(patients.count) pacientes · última visita reciente primero"
                                )
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Pacientes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddPatient = true } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(GrooBrand.primary)
                    }
                }
            }
            .navigationDestination(item: $selectedPatientId) { route in
                if let patient = groo.patient(withId: route.id) {
                    GrooPatientProfileView(patient: patient)
                }
            }
            .sheet(isPresented: $showAddPatient) {
                GrooAddPatientSheet()
                    .environmentObject(groo)
            }
            .onAppear { openPendingPatientIfNeeded() }
            .onChange(of: groo.pendingPatientNavigation) { _, _ in
                openPendingPatientIfNeeded()
            }
        }
    }

    private var patientsKPIStrip: some View {
        GrooClinicDesign.KPIStrip(items: [
            (label: "Registrados", value: "\(groo.patients.count)", icon: "person.2.fill"),
            (label: "Recurrentes", value: "\(groo.clinicReturningPatientsCount)", icon: "arrow.triangle.2.circlepath"),
            (label: "Visitas", value: "\(groo.clinicTotalVisits)", icon: "stethoscope"),
        ])
    }

    private var patientsFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GrooPatientListFilter.allCases) { option in
                    GrooClinicDesign.FilterChip(
                        title: option.label,
                        isSelected: filter == option
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = option }
                    }
                }
            }
        }
    }

    private var patientsSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GrooBrand.primary.opacity(0.75))
            TextField(
                "",
                text: $query,
                prompt: Text("Buscar por nombre, teléfono o tratamiento…")
                    .foregroundStyle(Color.black.opacity(0.35))
            )
            .font(.system(size: 16))
            .foregroundStyle(Color.black.opacity(0.85))
            .tint(GrooBrand.primary)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.black.opacity(0.28))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(GrooBrand.primary.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private func patientListRow(_ patient: GrooPatient) -> some View {
        let count = groo.consultationCount(for: patient.id)
        let returning = groo.isReturningPatient(patient.id)
        let hasVisits = groo.hasVisitedBefore(patient.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                GrooPatientAvatarView(patient: patient, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(patient.fullName)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(DrflowTheme.textPrimary)
                        if returning {
                            Text("Recurrente")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(GrooBrand.primary))
                        }
                    }
                    Text(patient.treatment)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DrflowTheme.textSecondary)
                        .lineLimit(1)
                    Label(patient.phone, systemImage: "phone.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.15))
            }

            Divider().opacity(0.5)

            HStack(spacing: 0) {
                visitMiniStat(
                    title: "Última visita",
                    value: hasVisits ? groo.lastVisitLabel(for: patient.id) : "Sin registro",
                    icon: "clock.arrow.circlepath"
                )
                Divider().frame(height: 36)
                visitMiniStat(
                    title: count == 1 ? "Consulta" : "Consultas",
                    value: "\(count)",
                    icon: "stethoscope"
                )
                Divider().frame(height: 36)
                visitMiniStat(
                    title: "Cobrado",
                    value: count > 0 ? groo.formattedTotalEarnedFromPatient(patient.id) : "—",
                    icon: "dollarsign.circle",
                    accent: DrflowTheme.positive
                )
                if groo.pendingBalance(for: patient.id) > 0 {
                    Divider().frame(height: 36)
                    visitMiniStat(
                        title: "Debe",
                        value: groo.formattedPendingBalance(for: patient.id),
                        icon: "exclamationmark.circle",
                        accent: Color.orange
                    )
                }
            }
        }
        .padding(14)
        .background(GrooPatientCardBackground())
    }

    private func visitMiniStat(title: String, value: String, icon: String, accent: Color = GrooBrand.primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent == DrflowTheme.positive ? accent : DrflowTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var patientsEmptyState: some View {
        ContentUnavailableView {
            Label("Sin pacientes", systemImage: "person.2.slash")
        } description: {
            Text(
                query.isEmpty
                    ? "Añade pacientes para gestionar su historial clínico."
                    : "No hay resultados para «\(query)»."
            )
        } actions: {
            if query.isEmpty {
                Button("Añadir paciente") { showAddPatient = true }
                    .buttonStyle(.borderedProminent)
                    .tint(GrooBrand.primary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func openPendingPatientIfNeeded() {
        guard let id = groo.pendingPatientNavigation else { return }
        groo.pendingPatientNavigation = nil
        selectedPatientId = GrooPatientRoute(id: id)
    }
}

private struct GrooPatientRoute: Identifiable, Hashable {
    let id: UUID
}

struct GrooPatientProfileView: View {
    let patient: GrooPatient
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @State private var showAddRecord = false
    @State private var showSchedule = false
    @State private var showBudget = false
    @State private var selectedRecord: GrooClinicalRecord?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var livePatient: GrooPatient

    init(patient: GrooPatient) {
        self.patient = patient
        _livePatient = State(initialValue: patient)
    }

    private var history: [GrooClinicalRecord] {
        groo.clinicalHistory(for: livePatient.id)
    }

    private var consultationCount: Int {
        groo.consultationCount(for: livePatient.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GrooClinicDesign.sectionSpacing) {
                profileHeader
                profileQuickActions
                clinicalOverviewCard
                clinicalHistorySection
                personalDataCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(GrooClinicDesign.ScreenBackground())
        .navigationTitle(livePatient.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddRecord) {
            GrooAddClinicalRecordSheet(patientId: livePatient.id, patient: livePatient)
                .environmentObject(groo)
        }
        .sheet(isPresented: $showSchedule) {
            GrooScheduleAppointmentSheet(patient: livePatient)
                .environmentObject(groo)
                .environmentObject(tabRouter)
        }
        .sheet(isPresented: $showBudget) {
            GrooPatientBudgetSheet(patient: livePatient)
                .environmentObject(groo)
        }
        .sheet(item: $selectedRecord) { record in
            GrooClinicalRecordDetailSheet(record: record, patientName: livePatient.fullName)
                .environmentObject(groo)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.82) {
                    groo.setPatientPhotoData(jpeg, for: livePatient.id)
                }
                selectedPhoto = nil
            }
        }
        .onChange(of: groo.patients) { _, _ in
            if let updated = groo.patient(withId: livePatient.id) {
                livePatient = updated
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    GrooPatientAvatarView(patient: livePatient, size: 88)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(GrooBrand.primary))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(livePatient.fullName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(livePatient.treatment)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GrooBrand.primary)
                if groo.isReturningPatient(livePatient.id) {
                    Label("Paciente recurrente", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)
                } else if groo.hasVisitedBefore(livePatient.id) {
                    Label("Historial clínico activo", systemImage: "doc.text.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DrflowTheme.textSecondary)
                } else {
                    Text("Nuevo en clínica")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DrflowTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }

    private var profileQuickActions: some View {
        HStack(spacing: 0) {
            GrooClinicDesign.QuickAction(title: "Agendar cita", icon: "calendar.badge.plus") {
                showSchedule = true
            }
            GrooClinicDesign.QuickAction(title: "Presupuesto", icon: "doc.richtext") {
                showBudget = true
            }
            GrooClinicDesign.QuickAction(title: "Consulta", icon: "doc.badge.plus") {
                showAddRecord = true
            }
            GrooClinicDesign.QuickAction(title: "Chat", icon: "message.fill") {
                groo.startChat(for: livePatient)
                tabRouter.openChat()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: GrooClinicDesign.cardRadius, style: .continuous)
                .fill(GrooClinicDesign.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private var clinicalOverviewCard: some View {
        GrooClinicDesign.ProCard {
            VStack(alignment: .leading, spacing: 16) {
                GrooClinicDesign.SectionHeader(
                    title: "Resumen clínico",
                    subtitle: groo.isReturningPatient(livePatient.id)
                        ? "Paciente recurrente"
                        : (groo.hasVisitedBefore(livePatient.id) ? "Historial activo" : "Sin visitas registradas")
                )

                HStack(spacing: 10) {
                    visitDateTile(
                        title: "Primera visita",
                        value: groo.firstVisitLabel(for: livePatient.id),
                        icon: "figure.walk.arrival",
                        tint: Color(red: 0.45, green: 0.55, blue: 0.72)
                    )
                    visitDateTile(
                        title: "Última visita",
                        value: groo.hasVisitedBefore(livePatient.id)
                            ? groo.lastVisitLabel(for: livePatient.id)
                            : "Sin registro",
                        icon: "clock.arrow.circlepath",
                        tint: GrooBrand.primary
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    overviewMetric(
                        value: groo.formattedTotalEarnedFromPatient(livePatient.id),
                        label: "Total cobrado",
                        icon: "dollarsign.circle.fill",
                        accent: DrflowTheme.positive
                    )
                    overviewMetric(
                        value: groo.formattedPendingBalance(for: livePatient.id),
                        label: "Pendiente de pago",
                        icon: "exclamationmark.circle.fill",
                        accent: Color.orange
                    )
                    overviewMetric(
                        value: groo.formattedTotalQuoted(for: livePatient.id),
                        label: "Precio tratamientos",
                        icon: "tag.fill",
                        accent: GrooBrand.primary
                    )
                    overviewMetric(
                        value: "\(consultationCount)",
                        label: consultationCount == 1 ? "Consulta" : "Consultas",
                        icon: "stethoscope"
                    )
                }

                if let next = livePatient.nextAppointment {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color(red: 0.12, green: 0.58, blue: 0.28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Próxima cita")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DrflowTheme.textTertiary)
                            Text(groo.formattedClinicalDate(next))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.94, green: 0.98, blue: 0.95))
                    }
                }
            }
        }
    }

    private func overviewMetric(value: String, label: String, icon: String, accent: Color = GrooBrand.primary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DrflowTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.07))
        }
    }

    private func visitDateTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DrflowTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        }
    }

    private var personalDataCard: some View {
        GrooClinicDesign.ProCard {
            VStack(alignment: .leading, spacing: 12) {
                GrooClinicDesign.SectionHeader(
                    title: "Datos administrativos",
                    subtitle: "Contacto y antecedentes"
                )

                dataRow(icon: "phone.fill", label: "Teléfono", value: livePatient.phone)
                if let email = livePatient.email, !email.isEmpty {
                    dataRow(icon: "envelope.fill", label: "Email", value: email)
                }
                if let dob = livePatient.dateOfBirth {
                    dataRow(
                        icon: "birthday.cake.fill",
                        label: "Nacimiento",
                        value: dob.formatted(date: .long, time: .omitted)
                    )
                }
                if let allergies = livePatient.allergies, !allergies.isEmpty {
                    dataRow(icon: "exclamationmark.triangle.fill", label: "Alergias", value: allergies, warn: true)
                }
                if let notes = livePatient.notes, !notes.isEmpty {
                    dataRow(icon: "note.text", label: "Notas", value: notes)
                }
            }
        }
    }

    private func dataRow(icon: String, label: String, value: String, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(warn ? .orange : GrooBrand.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DrflowTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var clinicalHistorySection: some View {
        GrooClinicDesign.ProCard {
            VStack(alignment: .leading, spacing: 14) {
                GrooClinicDesign.SectionHeader(
                    title: "Historial clínico",
                    subtitle: history.isEmpty ? nil : "\(history.count) visitas registradas",
                    actionTitle: "Añadir",
                    action: { showAddRecord = true }
                )

                if history.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32))
                            .foregroundStyle(GrooBrand.primary.opacity(0.5))
                        Text("Aún no hay visitas registradas")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Cada consulta quedará con fecha, tipo e importe.")
                            .font(.system(size: 13))
                            .foregroundStyle(DrflowTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Registrar primera visita") { showAddRecord = true }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GrooBrand.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    patientPaymentSummaryBar

                    VStack(spacing: 0) {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, record in
                            clinicalTimelineRow(record, isLast: index == history.count - 1)
                        }
                    }
                }
            }
        }
    }

    private var patientPaymentSummaryBar: some View {
        HStack(spacing: 0) {
            paymentSummaryCell(
                title: "Cobrado",
                value: groo.formattedTotalEarnedFromPatient(livePatient.id),
                tint: DrflowTheme.positive
            )
            Divider().frame(height: 36)
            paymentSummaryCell(
                title: "Pendiente",
                value: groo.formattedPendingBalance(for: livePatient.id),
                tint: groo.pendingBalance(for: livePatient.id) > 0 ? Color.orange : DrflowTheme.textSecondary
            )
            Divider().frame(height: 36)
            paymentSummaryCell(
                title: "Precio total",
                value: groo.formattedTotalQuoted(for: livePatient.id),
                tint: GrooBrand.primary
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
        }
    }

    private func paymentSummaryCell(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func clinicalTimelineRow(_ record: GrooClinicalRecord, isLast: Bool) -> some View {
        let type = record.consultationType ?? .other
        return Button {
            selectedRecord = record
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    GrooClinicalDateBadge(date: record.date)
                    if !isLast {
                        Rectangle()
                            .fill(GrooBrand.primary.opacity(0.15))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(DrflowTheme.textPrimary)
                            Text(groo.formattedClinicalDate(record.date))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DrflowTheme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(groo.formattedClinicalUSD(record.amountPaid))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(DrflowTheme.positive)
                            if record.pendingAmount > 0.01 {
                                Text("Debe \(groo.formattedClinicalUSD(record.pendingAmount))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.orange)
                            }
                        }
                    }

                    visitPaymentRow(record)

                    HStack(spacing: 6) {
                        Image(systemName: type.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(type.label)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(GrooBrand.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(GrooBrand.primarySoft))

                    VStack(alignment: .leading, spacing: 6) {
                        clinicalMetaRow(icon: "clock.fill", label: "Duración", text: record.formattedDuration)
                        clinicalMetaRow(icon: "stethoscope", label: "Doctora", text: record.doctorDisplay)
                        clinicalMetaRow(icon: "door.left.hand.closed", label: "Sala", text: record.roomDisplay)
                    }

                    if !record.treatment.isEmpty {
                        Text(record.treatment)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DrflowTheme.textPrimary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 4) {
                        Text("Ver detalle de la visita")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(GrooBrand.primary.opacity(0.85))
                }
                .padding(.bottom, isLast ? 0 : 20)
            }
        }
        .buttonStyle(.plain)
    }

    private func visitPaymentRow(_ record: GrooClinicalRecord) -> some View {
        HStack(spacing: 8) {
            paymentMiniChip(
                label: "Precio",
                value: groo.formattedClinicalUSD(record.servicePrice),
                tint: GrooBrand.primary
            )
            paymentMiniChip(
                label: "Pagó",
                value: groo.formattedClinicalUSD(record.amountPaid),
                tint: DrflowTheme.positive
            )
            if record.pendingAmount > 0.01 {
                paymentMiniChip(
                    label: "Debe",
                    value: groo.formattedClinicalUSD(record.pendingAmount),
                    tint: Color.orange
                )
            } else {
                paymentMiniChip(label: "Estado", value: "Pagado", tint: DrflowTheme.positive)
            }
        }
    }

    private func paymentMiniChip(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DrflowTheme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        }
    }

    private func clinicalMetaRow(icon: String, label: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GrooBrand.primary.opacity(0.85))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DrflowTheme.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DrflowTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var patientWhiteCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct GrooAddPatientSheet: View {
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var treatment = ""
    @State private var allergies = ""
    @State private var notes = ""
    @State private var hasBirthDate = false
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificación") {
                    TextField("Nombre completo *", text: $fullName)
                    TextField("Teléfono", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Clínica") {
                    TextField("Tratamiento activo", text: $treatment)
                    TextField("Alergias", text: $allergies)
                    TextField("Notas", text: $notes, axis: .vertical)
                }
                Section("Nacimiento") {
                    Toggle("Registrar fecha", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Fecha", selection: $dateOfBirth, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Nuevo paciente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        groo.addPatient(
                            fullName: fullName,
                            phone: phone,
                            email: email,
                            treatment: treatment,
                            allergies: allergies,
                            notes: notes,
                            dateOfBirth: hasBirthDate ? dateOfBirth : nil
                        )
                        dismiss()
                    }
                    .disabled(fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GrooScheduleAppointmentSheet: View {
    let patient: GrooPatient
    var compact: Bool = false
    @EnvironmentObject private var groo: GrooAppStore
    @EnvironmentObject private var tabRouter: MainTabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GrooAppointmentDraft

    init(patient: GrooPatient, compact: Bool = false) {
        self.patient = patient
        self.compact = compact
        let type = GrooConsultationType.followUp
        _draft = State(
            initialValue: GrooAppointmentDraft(
                patientId: patient.id,
                fullName: patient.fullName,
                phone: patient.phone,
                consultationType: type,
                dueAt: Date().addingTimeInterval(86_400),
                estimatedRevenue: type.defaultPrice,
                note: ""
            )
        )
    }

    var body: some View {
        if compact {
            compactScheduleBody
        } else {
            fullScheduleBody
        }
    }

    private var compactScheduleBody: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    GrooPatientAvatarView(patient: patient, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(patient.fullName)
                            .font(.system(size: 16, weight: .bold))
                        Text(patient.treatment)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GrooBrand.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Picker("Tipo", selection: $draft.consultationType) {
                    ForEach(GrooConsultationType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: draft.consultationType) { _, type in
                    draft.estimatedRevenue = type.defaultPrice
                }

                DatePicker("Fecha y hora", selection: $draft.dueAt)
                    .datePickerStyle(.compact)

                Button {
                    groo.scheduleAppointment(from: draft)
                    dismiss()
                } label: {
                    Text("Guardar cita")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(GrooBrand.primary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Nueva cita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .onAppear {
            draft = groo.makeAppointmentDraft(for: patient, type: draft.consultationType)
        }
    }

    private var fullScheduleBody: some View {
        NavigationStack {
            Form {
                Section("Paciente") {
                    LabeledContent("Nombre", value: draft.fullName)
                    LabeledContent("Teléfono", value: draft.phone)
                }
                Section {
                    Picker("Tipo de consulta", selection: $draft.consultationType) {
                        ForEach(GrooConsultationType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .onChange(of: draft.consultationType) { _, type in
                        draft.estimatedRevenue = type.defaultPrice
                    }
                    DatePicker("Fecha y hora", selection: $draft.dueAt)
                    TextField("Importe estimado", value: $draft.estimatedRevenue, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Notas (autocompletadas)", text: $draft.note, axis: .vertical)
                } header: {
                    Text("Cita")
                } footer: {
                    Text("Al marcar la cita como completada en el calendario, se añadirá automáticamente al historial clínico.")
                }
            }
            .navigationTitle("Agendar cita")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        groo.scheduleAppointment(from: draft)
                        dismiss()
                        tabRouter.selected = .calendar
                    }
                }
            }
        }
        .onAppear {
            draft = groo.makeAppointmentDraft(for: patient, type: draft.consultationType)
        }
    }
}

struct GrooClinicalRecordDetailSheet: View {
    let record: GrooClinicalRecord
    let patientName: String
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss

    private var type: GrooConsultationType { record.consultationType ?? .other }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GrooClinicDesign.ProCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.title)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                    Text(patientName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(GrooBrand.primary)
                                    Text(groo.formattedClinicalDate(record.date))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DrflowTheme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                Text(groo.formattedClinicalUSD(record.amountPaid))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(DrflowTheme.positive)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: type.icon)
                                Text(type.label)
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GrooBrand.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(GrooBrand.primarySoft))
                        }
                    }

                    GrooClinicDesign.ProCard {
                        VStack(spacing: 0) {
                            detailRow(
                                icon: "tag.fill",
                                title: "Precio del servicio",
                                value: groo.formattedClinicalUSD(record.servicePrice),
                                tint: GrooBrand.primary
                            )
                            Divider().padding(.leading, 44)
                            detailRow(
                                icon: "dollarsign.circle.fill",
                                title: "Pagó el paciente",
                                value: groo.formattedClinicalUSD(record.amountPaid),
                                tint: DrflowTheme.positive
                            )
                            Divider().padding(.leading, 44)
                            detailRow(
                                icon: record.isFullyPaid ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                title: record.isFullyPaid ? "Estado" : "Pendiente de pago",
                                value: record.isFullyPaid
                                    ? "Pagado completo"
                                    : groo.formattedClinicalUSD(record.pendingAmount),
                                tint: record.isFullyPaid ? DrflowTheme.positive : Color.orange
                            )
                        }
                    }

                    GrooClinicDesign.ProCard {
                        VStack(spacing: 0) {
                            detailRow(
                                icon: "clock.fill",
                                title: "Duración",
                                value: record.formattedDuration,
                                tint: GrooBrand.primary
                            )
                            Divider().padding(.leading, 44)
                            detailRow(
                                icon: "stethoscope",
                                title: "Doctora / Doctor",
                                value: record.doctorDisplay,
                                tint: Color(red: 0.45, green: 0.55, blue: 0.72)
                            )
                            Divider().padding(.leading, 44)
                            detailRow(
                                icon: "door.left.hand.closed",
                                title: "Sala",
                                value: record.roomDisplay,
                                tint: Color(red: 0.12, green: 0.58, blue: 0.28)
                            )
                        }
                    }

                    if !record.treatment.isEmpty {
                        GrooClinicDesign.ProCard {
                            VStack(alignment: .leading, spacing: 8) {
                                GrooClinicDesign.SectionHeader(title: "Tratamiento realizado")
                                Text(record.treatment)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DrflowTheme.textPrimary)
                            }
                        }
                    }

                    if !record.notes.isEmpty {
                        GrooClinicDesign.ProCard {
                            VStack(alignment: .leading, spacing: 8) {
                                GrooClinicDesign.SectionHeader(title: "Notas clínicas")
                                Text(record.notes)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DrflowTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(GrooClinicDesign.ScreenBackground())
            .navigationTitle("Detalle de visita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func detailRow(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DrflowTheme.textTertiary)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DrflowTheme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

struct GrooAddClinicalRecordSheet: View {
    let patientId: UUID
    var patient: GrooPatient?
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var treatment = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var consultationType: GrooConsultationType = .followUp
    @State private var quotedPriceText = ""
    @State private var amountText = ""
    @State private var durationMinutes = 30
    @State private var doctorName = GrooClinicDefaults.doctors[0]
    @State private var roomName = GrooClinicDefaults.rooms[0]
    @State private var useCustomDoctor = false
    @State private var useCustomRoom = false
    @State private var customDoctor = ""
    @State private var customRoom = ""

    private let durationOptions = [15, 20, 25, 30, 45, 50, 60, 75, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Consulta") {
                    Picker("Tipo", selection: $consultationType) {
                        ForEach(GrooConsultationType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .onChange(of: consultationType) { _, type in
                        quotedPriceText = String(format: "%.0f", type.defaultPrice)
                        if amountText.isEmpty {
                            amountText = quotedPriceText
                        }
                        if treatment.isEmpty { treatment = type.label }
                        durationMinutes = GrooClinicDefaults.typicalDuration(for: type)
                        doctorName = GrooClinicDefaults.typicalDoctor(for: type)
                        roomName = GrooClinicDefaults.typicalRoom(for: type)
                    }
                    TextField("Motivo / título *", text: $title)
                    TextField("Tratamiento realizado", text: $treatment)
                    TextField("Precio del servicio ($)", text: $quotedPriceText)
                        .keyboardType(.decimalPad)
                    TextField("Importe pagado ($)", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Atención clínica") {
                    Picker("Duración", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Toggle("Doctora personalizada", isOn: $useCustomDoctor)
                    if useCustomDoctor {
                        TextField("Nombre del profesional", text: $customDoctor)
                    } else {
                        Picker("Doctora / Doctor", selection: $doctorName) {
                            ForEach(GrooClinicDefaults.doctors, id: \.self) { doctor in
                                Text(doctor).tag(doctor)
                            }
                        }
                    }
                    Toggle("Sala personalizada", isOn: $useCustomRoom)
                    if useCustomRoom {
                        TextField("Nombre de la sala", text: $customRoom)
                    } else {
                        Picker("Sala", selection: $roomName) {
                            ForEach(GrooClinicDefaults.rooms, id: \.self) { room in
                                Text(room).tag(room)
                            }
                        }
                    }
                }
                Section("Notas clínicas") {
                    TextField("Observaciones, diagnóstico, plan…", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Historial clínico")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let quoted = Double(quotedPriceText.replacingOccurrences(of: ",", with: "."))
                        let paid = Double(amountText.replacingOccurrences(of: ",", with: "."))
                        groo.addClinicalRecord(
                            patientId: patientId,
                            title: title.isEmpty ? consultationType.label : title,
                            treatment: treatment,
                            notes: notes,
                            date: date,
                            consultationType: consultationType,
                            amountSpent: paid ?? quoted ?? consultationType.defaultPrice,
                            quotedPrice: quoted ?? consultationType.defaultPrice,
                            durationMinutes: durationMinutes,
                            doctorName: useCustomDoctor ? customDoctor : doctorName,
                            roomName: useCustomRoom ? customRoom : roomName
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && treatment.isEmpty)
                }
            }
            .onAppear {
                if let patient {
                    if notes.isEmpty, let n = patient.notes { notes = "Contexto: \(n)" }
                    if let allergies = patient.allergies {
                        notes = (notes.isEmpty ? "" : notes + "\n") + "Alergias: \(allergies)"
                    }
                }
                quotedPriceText = String(format: "%.0f", consultationType.defaultPrice)
                amountText = quotedPriceText
                durationMinutes = GrooClinicDefaults.typicalDuration(for: consultationType)
                doctorName = GrooClinicDefaults.typicalDoctor(for: consultationType)
                roomName = GrooClinicDefaults.typicalRoom(for: consultationType)
            }
        }
    }
}

private struct GrooPatientPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Presupuesto PDF

struct GrooPatientBudgetSheet: View {
    let patient: GrooPatient
    @EnvironmentObject private var groo: GrooAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GrooPatientBudgetDraft
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    init(patient: GrooPatient) {
        self.patient = patient
        _draft = State(initialValue: GrooPatientBudgetDraft(
            patient: patient,
            clinicName: GrooBrand.appName,
            professionalName: "",
            issueDate: Date(),
            validUntil: Date(),
            lineItems: [],
            notes: "",
            alreadyPaid: 0,
            historicalPending: 0
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paciente") {
                    LabeledContent("Nombre", value: draft.patient.fullName)
                    LabeledContent("Teléfono", value: draft.patient.phone)
                    LabeledContent("Ya abonado", value: GrooCurrencyFormat.format(draft.alreadyPaid))
                }

                Section("Conceptos") {
                    ForEach($draft.lineItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Tratamiento", text: $item.title)
                            TextField("Detalle", text: $item.detail)
                            HStack {
                                Stepper("Cant: \(item.quantity)", value: $item.quantity, in: 1...99)
                                Spacer()
                                TextField("Precio", value: $item.unitPrice, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                            }
                            Text("Total línea: \(GrooCurrencyFormat.format(item.total))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DrflowTheme.positive)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { draft.lineItems.remove(atOffsets: $0) }

                    Button {
                        draft.lineItems.append(
                            GrooBudgetLineItem(
                                id: UUID(),
                                title: "Nuevo concepto",
                                detail: "",
                                quantity: 1,
                                unitPrice: 0
                            )
                        )
                    } label: {
                        Label("Añadir concepto", systemImage: "plus.circle.fill")
                    }
                }

                Section("Resumen") {
                    LabeledContent("Subtotal", value: GrooCurrencyFormat.format(draft.subtotal))
                    LabeledContent("Ya abonado", value: GrooCurrencyFormat.format(draft.alreadyPaid))
                    LabeledContent("Total a pagar", value: GrooCurrencyFormat.format(draft.totalBudget))
                        .font(.headline)
                }

                Section("Notas") {
                    TextField("Observaciones para el paciente", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        Label("Generar PDF y enviar", systemImage: "square.and.arrow.up.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .disabled(draft.lineItems.isEmpty)
                } footer: {
                    Text("Se abrirá el menú para enviar por WhatsApp, email o guardar el PDF.")
                }
            }
            .navigationTitle("Presupuesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                draft = groo.makeBudgetDraft(for: patient)
            }
            .sheet(isPresented: $showShare) {
                if let pdfURL {
                    GrooSharePDFSheet(url: pdfURL)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func generateAndShare() {
        guard let url = GrooClinicBudgetPDFGenerator.generatePDF(from: draft) else {
            errorMessage = "No se pudo generar el PDF."
            return
        }
        pdfURL = url
        showShare = true
    }
}
