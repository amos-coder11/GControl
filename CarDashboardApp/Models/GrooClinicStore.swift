import Foundation

/// API de clínica que consumen las vistas de pacientes, historia clínica,
/// citas y presupuestos. El estado vive en `GrooAppStore` para que SwiftUI
/// observe los cambios; aquí va la lógica.
@MainActor
extension GrooAppStore {

    // MARK: - Pacientes

    func patient(withId id: UUID) -> GrooPatient? {
        patients.first { $0.id == id }
    }

    func filteredPatients(query: String, filter: GrooPatientListFilter) -> [GrooPatient] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return patients
            .filter { patient in
                guard !needle.isEmpty else { return true }
                return patient.fullName.lowercased().contains(needle)
                    || patient.phone.lowercased().contains(needle)
                    || patient.treatment.lowercased().contains(needle)
            }
            .filter { patient in
                switch filter {
                case .all:
                    return true
                case .returning:
                    return isReturningPatient(patient.id)
                case .pending:
                    return pendingBalance(for: patient.id) > 0.01
                case .upcoming:
                    guard let next = patient.nextAppointment else { return false }
                    return next >= Date()
                }
            }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    @discardableResult
    func addPatient(
        fullName: String,
        phone: String,
        email: String,
        treatment: String,
        allergies: String,
        notes: String,
        dateOfBirth: Date?
    ) -> GrooPatient {
        func optional(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let patient = GrooPatient(
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone,
            treatment: treatment,
            email: optional(email),
            allergies: optional(allergies),
            notes: optional(notes),
            dateOfBirth: dateOfBirth
        )
        patients.append(patient)
        save()
        return patient
    }

    func patientPhotoData(for id: UUID) -> Data? {
        patientPhotos[id]
    }

    func setPatientPhotoData(_ data: Data, for id: UUID) {
        patientPhotos[id] = data
        save()
    }

    // MARK: - Historia clínica

    /// Visitas del paciente, de la más reciente a la más antigua.
    func clinicalHistory(for patientId: UUID) -> [GrooClinicalRecord] {
        clinicalRecords
            .filter { $0.patientId == patientId }
            .sorted { $0.date > $1.date }
    }

    func consultationCount(for patientId: UUID) -> Int {
        clinicalRecords.count { $0.patientId == patientId }
    }

    func hasVisitedBefore(_ patientId: UUID) -> Bool {
        consultationCount(for: patientId) > 0
    }

    func isReturningPatient(_ patientId: UUID) -> Bool {
        consultationCount(for: patientId) > 1
    }

    @discardableResult
    func addClinicalRecord(
        patientId: UUID,
        title: String,
        treatment: String,
        notes: String,
        date: Date,
        consultationType: GrooConsultationType,
        amountSpent: Double,
        quotedPrice: Double,
        durationMinutes: Int,
        doctorName: String,
        roomName: String
    ) -> GrooClinicalRecord {
        let record = GrooClinicalRecord(
            patientId: patientId,
            title: title,
            treatment: treatment,
            notes: notes,
            date: date,
            consultationType: consultationType,
            amountPaid: amountSpent,
            servicePrice: max(quotedPrice, amountSpent),
            durationMinutes: durationMinutes,
            doctorName: doctorName,
            roomName: roomName
        )
        clinicalRecords.append(record)

        // El tratamiento de la ficha refleja la última visita.
        if let idx = patients.firstIndex(where: { $0.id == patientId }),
           !treatment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patients[idx].treatment = treatment
        }

        save()
        return record
    }

    // MARK: - Métricas

    var clinicTotalVisits: Int { clinicalRecords.count }

    var clinicReturningPatientsCount: Int {
        patients.count { isReturningPatient($0.id) }
    }

    func totalEarned(from patientId: UUID) -> Double {
        clinicalHistory(for: patientId).reduce(0) { $0 + $1.amountPaid }
    }

    func totalQuoted(for patientId: UUID) -> Double {
        clinicalHistory(for: patientId).reduce(0) { $0 + $1.servicePrice }
    }

    func pendingBalance(for patientId: UUID) -> Double {
        max(0, totalQuoted(for: patientId) - totalEarned(from: patientId))
    }

    // MARK: - Formato

    func formattedClinicalUSD(_ amount: Double) -> String {
        GrooCurrencyFormat.format(amount)
    }

    func formattedClinicalDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM yyyy · HH:mm"
        return formatter.string(from: date)
    }

    func formattedTotalEarnedFromPatient(_ patientId: UUID) -> String {
        formattedClinicalUSD(totalEarned(from: patientId))
    }

    func formattedTotalQuoted(for patientId: UUID) -> String {
        formattedClinicalUSD(totalQuoted(for: patientId))
    }

    func formattedPendingBalance(for patientId: UUID) -> String {
        formattedClinicalUSD(pendingBalance(for: patientId))
    }

    func firstVisitLabel(for patientId: UUID) -> String {
        guard let first = clinicalHistory(for: patientId).last else { return "—" }
        return formattedClinicalDate(first.date)
    }

    func lastVisitLabel(for patientId: UUID) -> String {
        guard let last = clinicalHistory(for: patientId).first else { return "—" }
        return formattedClinicalDate(last.date)
    }

    /// Fecha compacta para las tarjetas del chat, sin hora.
    func formattedClinicalDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    func lastClinicalRecord(for patientId: UUID) -> GrooClinicalRecord? {
        clinicalHistory(for: patientId).first
    }

    /// Próxima cita del paciente. Los recordatorios no guardan el paciente, así
    /// que se localizan por el nombre con el que `scheduleAppointment` los crea.
    func upcomingReminder(for patientId: UUID) -> GrooReminder? {
        guard let patient = patient(withId: patientId) else { return nil }
        let now = Date()
        return reminders
            .filter { !$0.isDone && $0.dueAt >= now && $0.title.contains(patient.fullName) }
            .min { $0.dueAt < $1.dueAt }
    }

    // MARK: - Citas

    func makeAppointmentDraft(
        for patient: GrooPatient,
        type: GrooConsultationType
    ) -> GrooAppointmentDraft {
        GrooAppointmentDraft(
            patientId: patient.id,
            fullName: patient.fullName,
            phone: patient.phone,
            consultationType: type,
            dueAt: patient.nextAppointment ?? Date().addingTimeInterval(86_400),
            estimatedRevenue: type.defaultPrice,
            note: ""
        )
    }

    /// Guarda la cita como recordatorio y la deja lista para el calendario.
    func scheduleAppointment(from draft: GrooAppointmentDraft) {
        addReminder(
            title: draft.title,
            note: draft.note,
            dueAt: draft.dueAt,
            revenue: draft.estimatedRevenue,
            patientId: draft.patientId,
            consultationType: draft.consultationType
        )

        if let idx = patients.firstIndex(where: { $0.id == draft.patientId }) {
            patients[idx].nextAppointment = draft.dueAt
        }

        pendingAppointmentDraft = draft
        shouldOpenCalendarWithDraft = true
        save()
    }

    // MARK: - Presupuestos

    func makeBudgetDraft(for patient: GrooPatient) -> GrooPatientBudgetDraft {
        GrooPatientBudgetDraft(
            patient: patient,
            clinicName: GrooBrand.appName,
            professionalName: [profile.firstName, profile.lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            issueDate: Date(),
            validUntil: Date().addingTimeInterval(30 * 86_400),
            lineItems: [],
            notes: "",
            alreadyPaid: totalEarned(from: patient.id),
            historicalPending: pendingBalance(for: patient.id)
        )
    }

    // MARK: - Citas como recordatorio

    /// Importe que se asume cuando una cita no trae precio propio.
    static let defaultAppointmentRevenue: Double = 45

    /// Variante clínica de `addReminder`: además de la alerta guarda el importe,
    /// el paciente y el tipo de consulta para las métricas de la agenda.
    func addReminder(
        title: String,
        note: String,
        dueAt: Date,
        revenue: Double?,
        patientId: UUID?,
        consultationType: GrooConsultationType?
    ) {
        addReminder(title: title, note: note, dueAt: dueAt)
        guard let idx = reminders.lastIndex(where: { $0.title == title && $0.dueAt == dueAt })
        else { return }
        reminders[idx].revenue = revenue
        reminders[idx].patientId = patientId
        reminders[idx].consultationType = consultationType
        save()
    }

    // MARK: - Sesiones

    /// Respuestas del asistente posteriores al último mensaje del usuario.
    /// El modelo no guarda estado de lectura, así que esto es lo más cercano
    /// a "sin leer" sin inventar un campo nuevo.
    static func unreadCount(in session: GrooChatSession) -> Int {
        guard let lastUserIndex = session.messages.lastIndex(where: { $0.isUser }) else {
            return session.messages.count { !$0.isUser }
        }
        return session.messages
            .suffix(from: session.messages.index(after: lastUserIndex))
            .count { !$0.isUser }
    }

    // MARK: - Navegación

    func prepareChatNavigation() {
        pendingChatNavigation = activeSessionId ?? sessions.first?.id
    }

    /// Abre (o crea) la conversación del paciente y navega a ella.
    func startChat(for patient: GrooPatient) {
        let id = startSession(titled: patient.fullName)
        pendingChatNavigation = id
    }

    @discardableResult
    func startSession(titled title: String) -> UUID {
        if let existing = sessions.first(where: { $0.title == title }) {
            activeSessionId = existing.id
            return existing.id
        }
        let id = startNewSession()
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            save()
        }
        return id
    }
}
