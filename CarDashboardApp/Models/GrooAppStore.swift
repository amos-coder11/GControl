import Combine
import Foundation
import SwiftUI

enum GrooConsultationType: String, Codable, CaseIterable, Identifiable {
    case checkup
    case cleaning
    case endodontics
    case orthodontics
    case whitening
    case surgery
    case emergency
    case followUp
    case implant
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .checkup: return "Revisión general"
        case .cleaning: return "Limpieza"
        case .endodontics: return "Endodoncia"
        case .orthodontics: return "Ortodoncia"
        case .whitening: return "Blanqueamiento"
        case .surgery: return "Cirugía"
        case .emergency: return "Urgencia"
        case .followUp: return "Control / seguimiento"
        case .implant: return "Implante"
        case .other: return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .checkup: return "heart.text.square"
        case .cleaning: return "sparkles"
        case .endodontics: return "cross.case"
        case .orthodontics: return "mouth"
        case .whitening: return "sun.max"
        case .surgery: return "scissors"
        case .emergency: return "bolt.heart"
        case .followUp: return "arrow.triangle.2.circlepath"
        case .implant: return "circle.grid.cross"
        case .other: return "doc.text"
        }
    }

    var defaultPrice: Double {
        switch self {
        case .checkup: return 85
        case .cleaning: return 120
        case .endodontics: return 450
        case .orthodontics: return 95
        case .whitening: return 280
        case .surgery: return 650
        case .emergency: return 150
        case .followUp: return 65
        case .implant: return 1_200
        case .other: return 100
        }
    }

    static func parse(from text: String) -> GrooConsultationType? {
        let lower = text.lowercased()
        if lower.contains("endodon") { return .endodontics }
        if lower.contains("limpieza") || lower.contains("profilaxis") { return .cleaning }
        if lower.contains("ortodon") || lower.contains("bracket") { return .orthodontics }
        if lower.contains("blanque") { return .whitening }
        if lower.contains("urgenc") || lower.contains("emerg") { return .emergency }
        if lower.contains("implant") { return .implant }
        if lower.contains("cirug") { return .surgery }
        if lower.contains("control") || lower.contains("seguim") { return .followUp }
        if lower.contains("revis") || lower.contains("consulta") { return .checkup }
        return allCases.first { lower.contains($0.rawValue) || lower.contains($0.label.lowercased()) }
    }
}

enum GrooPatientListFilter: String, CaseIterable, Identifiable {
    case all
    case returning
    case newPatients

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todos"
        case .returning: return "Recurrentes"
        case .newPatients: return "Nuevos"
        }
    }
}

struct GrooAppointmentDraft: Equatable {
    var patientId: UUID
    var fullName: String
    var phone: String
    var consultationType: GrooConsultationType
    var dueAt: Date
    var estimatedRevenue: Double
    var note: String
}

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
    /// JPEG en base64 para adjuntos (p. ej. sonrisa IA). Opcional para compatibilidad.
    var imageJPEGBase64: String?

    init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        createdAt: Date = Date(),
        imageJPEGBase64: String? = nil
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.createdAt = createdAt
        self.imageJPEGBase64 = imageJPEGBase64
    }

    var uiImage: UIImage? {
        guard let imageJPEGBase64,
              let data = Data(base64Encoded: imageJPEGBase64),
              let image = UIImage(data: data) else { return nil }
        return image
    }
}

struct GrooChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [GrooChatMessage]
    /// Paciente vinculado cuando el chat se abre desde su ficha.
    var patientId: UUID?

    var preview: String {
        guard let last = messages.last else { return "New session" }
        if last.imageJPEGBase64 != nil {
            let t = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "📷 Sonrisa mejorada" : "📷 \(t)"
        }
        return messages.last(where: { !$0.isUser })?.text ?? last.text
    }
}

struct GrooReminder: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var note: String
    var dueAt: Date
    var createdAt: Date
    var isDone: Bool
    /// Ingreso de la cita cuando está completada (opcional).
    var revenue: Double?
    /// Paciente vinculado (autocompletado desde ficha).
    var patientId: UUID?
    /// Tipo de consulta agendada.
    var consultationType: GrooConsultationType?
}

struct GrooSaleEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var amount: Double
    var date: Date
}

struct GrooPatient: Identifiable, Codable, Equatable {
    let id: UUID
    var fullName: String
    var phone: String
    var email: String?
    var dateOfBirth: Date?
    var treatment: String
    var allergies: String?
    var notes: String?
    var nextAppointment: Date?
}

struct GrooClinicalRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var patientId: UUID
    var date: Date
    var title: String
    var treatment: String
    var notes: String
    var createdAt: Date
    var consultationType: GrooConsultationType?
    /// Precio del servicio / tratamiento acordado.
    var quotedPrice: Double?
    /// Importe que pagó el paciente en esta visita.
    var amountSpent: Double?
    var reminderId: UUID?
    /// Duración de la consulta en minutos.
    var durationMinutes: Int?
    /// Profesional que atendió la visita.
    var doctorName: String?
    /// Sala o box clínico.
    var roomName: String?

    var formattedDuration: String {
        guard let minutes = durationMinutes, minutes > 0 else { return "Sin registrar" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) h" }
        return "\(hours) h \(remainder) min"
    }

    var doctorDisplay: String {
        let name = doctorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Sin asignar" : name
    }

    var roomDisplay: String {
        let room = roomName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return room.isEmpty ? "Sin registrar" : room
    }

    /// Precio del tratamiento en esta visita.
    var servicePrice: Double {
        quotedPrice ?? consultationType?.defaultPrice ?? amountSpent ?? 0
    }

    /// Lo que el paciente pagó en esta visita.
    var amountPaid: Double { amountSpent ?? 0 }

    /// Saldo pendiente de esta visita.
    var pendingAmount: Double { max(0, servicePrice - amountPaid) }

    var isFullyPaid: Bool { pendingAmount <= 0.01 }
}

enum GrooClinicDefaults {
    static let doctors = [
        "Dra. Elena Ruiz",
        "Dra. Carmen Vega",
        "Dra. Sofía Méndez",
        "Dr. Javier Ortega",
    ]
    static let rooms = [
        "Sala 1 — General",
        "Sala 2 — Endodoncia",
        "Sala 3 — Cirugía",
        "Sala Ortodoncia",
        "Sala Urgencias",
    ]

    static func typicalDuration(for type: GrooConsultationType) -> Int {
        switch type {
        case .checkup: return 30
        case .cleaning: return 45
        case .endodontics: return 60
        case .orthodontics: return 30
        case .whitening: return 50
        case .surgery: return 90
        case .emergency: return 25
        case .followUp: return 20
        case .implant: return 75
        case .other: return 30
        }
    }

    static func typicalRoom(for type: GrooConsultationType) -> String {
        switch type {
        case .endodontics: return "Sala 2 — Endodoncia"
        case .orthodontics: return "Sala Ortodoncia"
        case .surgery, .implant: return "Sala 3 — Cirugía"
        case .emergency: return "Sala Urgencias"
        case .whitening: return "Sala 1 — General"
        default: return "Sala 1 — General"
        }
    }

    static func typicalDoctor(for type: GrooConsultationType) -> String {
        switch type {
        case .endodontics, .surgery, .implant: return "Dra. Elena Ruiz"
        case .orthodontics: return "Dra. Sofía Méndez"
        case .emergency: return "Dr. Javier Ortega"
        default: return "Dra. Carmen Vega"
        }
    }
}

enum GrooClinicActionKind: String, Codable {
    case sale
    case appointment
}

struct GrooClinicAction: Identifiable, Equatable {
    let id: UUID
    let kind: GrooClinicActionKind
    let title: String
    let amount: Double
    let date: Date

    var kindLabel: String {
        switch kind {
        case .sale: return "Venta"
        case .appointment: return "Cita"
        }
    }

    var icon: String {
        switch kind {
        case .sale: return "cart.fill"
        case .appointment: return "calendar.badge.checkmark"
        }
    }
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
    @Published var sales: [GrooSaleEntry] = []
    @Published var patients: [GrooPatient] = []
    @Published var clinicalRecords: [GrooClinicalRecord] = []
    @Published var subscription: GrooSubscriptionTier = .trial
    @Published var trialMessagesRemaining: Int = 12
    @Published var showPaywall = false
    @Published var hasDismissedPaywallOnce = false
    /// Navega al chat al entrar en la pestaña principal (no persistido).
    @Published var shouldOpenChatOnMain = false
    /// Abre un hilo concreto en la bandeja de chat (no persistido).
    @Published var pendingChatNavigation: UUID?
    /// Abre la ficha de un paciente en la pestaña Pacientes (no persistido).
    @Published var pendingPatientNavigation: UUID?
    /// Borrador de cita con datos del paciente (no persistido).
    @Published var pendingAppointmentDraft: GrooAppointmentDraft?
    @Published var shouldOpenCalendarWithDraft = false

    private let storageKey = "Groo.appStore.v1"
    private static let clinicalDemoVersionKey = "Groo.clinicalDemo.v4"
    private static let patientPhotoKeyPrefix = "Groo.patientPhoto."

    init() {
        load()
        var didSeed = false
        if patients.isEmpty {
            patients = Self.defaultPatients
            didSeed = true
        }
        if clinicalRecords.isEmpty {
            clinicalRecords = Self.defaultClinicalRecords(for: patients)
            didSeed = true
        }
        if UserDefaults.standard.integer(forKey: Self.clinicalDemoVersionKey) < 4, !patients.isEmpty {
            clinicalRecords = Self.defaultClinicalRecords(for: patients)
            UserDefaults.standard.set(4, forKey: Self.clinicalDemoVersionKey)
            didSeed = true
        }
        if didSeed { save() }
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

    /// Mensajes no leídos del asistente en todas las conversaciones.
    var unreadChatCount: Int {
        sessions.reduce(0) { partial, session in
            partial + Self.unreadCount(in: session)
        }
    }

    static func unreadCount(in session: GrooChatSession) -> Int {
        guard let lastUser = session.messages.lastIndex(where: \.isUser) else {
            return session.messages.filter { !$0.isUser }.count
        }
        return session.messages.suffix(from: session.messages.index(after: lastUser)).filter { !$0.isUser }.count
    }

    /// Importe estimado por cita completada sin monto explícito.
    static let defaultAppointmentRevenue: Double = 185

    /// Ingresos del mes por citas completadas.
    var currentMonthAppointmentsRevenue: Double {
        reminders
            .filter { $0.isDone && Self.isInCurrentMonth($0.dueAt) }
            .reduce(0) { $0 + ($1.revenue ?? Self.defaultAppointmentRevenue) }
    }

    /// Ingresos del mes por ventas registradas.
    var currentMonthSalesRevenue: Double {
        sales
            .filter { Self.isInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total generado este mes (ventas + citas).
    var currentMonthTotalRevenue: Double {
        currentMonthSalesRevenue + currentMonthAppointmentsRevenue
    }

    var formattedMonthlyRevenue: String {
        DealershipStatsViewModel.formatUSD(currentMonthTotalRevenue)
    }

    var formattedMonthlySales: String {
        DealershipStatsViewModel.formatUSD(currentMonthSalesRevenue)
    }

    var formattedMonthlyAppointments: String {
        DealershipStatsViewModel.formatUSD(currentMonthAppointmentsRevenue)
    }

    static let defaultPatients: [GrooPatient] = [
        GrooPatient(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!,
            fullName: "María López",
            phone: "+1 305 555 0142",
            email: "maria.lopez@email.com",
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 1988, month: 4, day: 12)),
            treatment: "Endodoncia",
            allergies: "Penicilina",
            notes: "Paciente ansiosa; preferir anestesia local reforzada.",
            nextAppointment: Calendar.current.date(byAdding: .hour, value: 2, to: Date())
        ),
        GrooPatient(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000002")!,
            fullName: "Carlos Méndez",
            phone: "+1 305 555 0198",
            email: "carlos.mendez@email.com",
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 1975, month: 9, day: 3)),
            treatment: "Limpieza dental",
            allergies: nil,
            notes: "Control periodontal cada 6 meses.",
            nextAppointment: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        ),
        GrooPatient(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000003")!,
            fullName: "Ana Ruiz",
            phone: "+1 786 555 0133",
            email: "ana.ruiz@email.com",
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 1992, month: 11, day: 21)),
            treatment: "Control postoperatorio",
            allergies: "Látex",
            notes: nil,
            nextAppointment: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        ),
        GrooPatient(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000004")!,
            fullName: "Laura Vega",
            phone: "+1 305 555 0177",
            email: "laura.vega@email.com",
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 1985, month: 2, day: 8)),
            treatment: "Blanqueamiento",
            allergies: nil,
            notes: "Sensibilidad dental leve.",
            nextAppointment: nil
        ),
        GrooPatient(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000005")!,
            fullName: "Miguel Torres",
            phone: "+1 786 555 0165",
            email: nil,
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 2001, month: 7, day: 15)),
            treatment: "Ortodoncia — revisión",
            allergies: nil,
            notes: "Brackets activos — revisión mensual.",
            nextAppointment: Calendar.current.date(byAdding: .day, value: 5, to: Date())
        ),
    ]

    static func defaultClinicalRecords(for patients: [GrooPatient]) -> [GrooClinicalRecord] {
        let cal = Calendar.current
        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        }
        func record(
            _ uuid: String,
            patient: GrooPatient,
            offset: Int,
            title: String,
            type: GrooConsultationType,
            treatment: String,
            notes: String,
            amount: Double,
            duration: Int? = nil,
            doctor: String? = nil,
            room: String? = nil,
            paid: Double? = nil,
            quoted: Double? = nil
        ) -> GrooClinicalRecord {
            let price = quoted ?? amount
            let paidAmount = paid ?? amount
            return GrooClinicalRecord(
                id: UUID(uuidString: uuid)!,
                patientId: patient.id,
                date: day(offset),
                title: title,
                treatment: treatment,
                notes: notes,
                createdAt: day(offset),
                consultationType: type,
                quotedPrice: price,
                amountSpent: paidAmount,
                reminderId: nil,
                durationMinutes: duration ?? GrooClinicDefaults.typicalDuration(for: type),
                doctorName: doctor ?? GrooClinicDefaults.typicalDoctor(for: type),
                roomName: room ?? GrooClinicDefaults.typicalRoom(for: type)
            )
        }

        guard
            let maria = patients.first(where: { $0.fullName.contains("María") }),
            let carlos = patients.first(where: { $0.fullName.contains("Carlos") }),
            let ana = patients.first(where: { $0.fullName.contains("Ana") }),
            let laura = patients.first(where: { $0.fullName.contains("Laura") }),
            let miguel = patients.first(where: { $0.fullName.contains("Miguel") })
        else { return [] }

        return [
            record("B2000001-0000-4000-8000-000000000001", patient: maria, offset: -90, title: "Primera visita", type: .checkup, treatment: "Evaluación integral", notes: "Paciente nueva en clínica. Rx panorámica.", amount: 85),
            record("B2000001-0000-4000-8000-000000000002", patient: maria, offset: -60, title: "Urgencia por dolor", type: .emergency, treatment: "Alivio del dolor molar 36", notes: "Inflamación apical. Analgésico y plan endodóntico.", amount: 150),
            record("B2000001-0000-4000-8000-000000000003", patient: maria, offset: -45, title: "Consulta endodóntica", type: .endodontics, treatment: "Evaluación endodóntica", notes: "Rx periapical: lesión apical confirmada.", amount: 120),
            record("B2000001-0000-4000-8000-000000000004", patient: maria, offset: -14, title: "Inicio endodoncia", type: .endodontics, treatment: "Apertura cameral", notes: "Toleró bien. Obturación en próxima cita.", amount: 450, paid: 200, quoted: 450),
            record("B2000001-0000-4000-8000-000000000005", patient: maria, offset: -7, title: "Control postoperatorio", type: .followUp, treatment: "Revisión endodoncia", notes: "Sin dolor. Continuar tratamiento.", amount: 65),
            record("B2000001-0000-4000-8000-000000000006", patient: carlos, offset: -180, title: "Primera visita", type: .checkup, treatment: "Revisión + plan periodontal", notes: "Paciente recurrente de otra clínica.", amount: 85),
            record("B2000001-0000-4000-8000-000000000007", patient: carlos, offset: -30, title: "Limpieza profunda", type: .cleaning, treatment: "Profilaxis + curetaje", notes: "Sangrado leve QI. Control en 6 meses.", amount: 120),
            record("B2000001-0000-4000-8000-000000000008", patient: ana, offset: -21, title: "Control postoperatorio", type: .followUp, treatment: "Revisión extracción", notes: "Herida cicatrizando bien.", amount: 65),
            record("B2000001-0000-4000-8000-000000000009", patient: laura, offset: -45, title: "Evaluación estética", type: .whitening, treatment: "Estudio blanqueamiento", notes: "Sensibilidad leve. Kit en casa indicado.", amount: 95),
            record("B2000001-0000-4000-8000-000000000010", patient: laura, offset: -10, title: "Blanqueamiento en clínica", type: .whitening, treatment: "Sesión 1 de 2", notes: "Buena respuesta. Segunda sesión programada.", amount: 280),
            record("B2000001-0000-4000-8000-000000000011", patient: miguel, offset: -120, title: "Primera visita ortodoncia", type: .orthodontics, treatment: "Estudio + fotos", notes: "Maloclase clase II. Plan brackets.", amount: 95),
            record("B2000001-0000-4000-8000-000000000012", patient: miguel, offset: -90, title: "Colocación brackets", type: .orthodontics, treatment: "Bracket superior e inferior", notes: "Instrucciones de higiene entregadas.", amount: 850, paid: 500, quoted: 850),
            record("B2000001-0000-4000-8000-000000000013", patient: miguel, offset: -30, title: "Revisión mensual", type: .orthodontics, treatment: "Cambio arco + ligaduras", notes: "Evolución favorable.", amount: 95),
            record("B2000001-0000-4000-8000-000000000014", patient: miguel, offset: -7, title: "Control brackets", type: .followUp, treatment: "Ajuste ligaduras", notes: "Sin urgencias.", amount: 65),
        ]
    }

    func filteredPatients(query: String, filter: GrooPatientListFilter = .all) -> [GrooPatient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [GrooPatient]
        if q.isEmpty {
            base = patients
        } else {
            base = patients.filter {
                $0.fullName.lowercased().contains(q)
                    || $0.phone.lowercased().contains(q)
                    || $0.treatment.lowercased().contains(q)
                    || ($0.email?.lowercased().contains(q) ?? false)
                    || ($0.allergies?.lowercased().contains(q) ?? false)
                    || ($0.notes?.lowercased().contains(q) ?? false)
            }
        }
        let filtered: [GrooPatient]
        switch filter {
        case .all:
            filtered = base
        case .returning:
            filtered = base.filter { isReturningPatient($0.id) }
        case .newPatients:
            filtered = base.filter { !hasVisitedBefore($0.id) }
        }
        return filtered.sorted { lhs, rhs in
            let left = lastVisitDate(for: lhs.id) ?? .distantPast
            let right = lastVisitDate(for: rhs.id) ?? .distantPast
            if left != right { return left > right }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    var todayPendingAppointmentsCount: Int {
        reminders.filter { !$0.isDone && Calendar.current.isDateInToday($0.dueAt) }.count
    }

    func patient(withId id: UUID) -> GrooPatient? {
        patients.first { $0.id == id }
    }

    func consultationCount(for patientId: UUID) -> Int {
        clinicalRecords.filter { $0.patientId == patientId }.count
    }

    func clinicalHistory(for patientId: UUID) -> [GrooClinicalRecord] {
        clinicalRecords
            .filter { $0.patientId == patientId }
            .sorted { $0.date > $1.date }
    }

    func totalSpent(for patientId: UUID) -> Double {
        clinicalHistory(for: patientId)
            .reduce(0) { $0 + $1.amountPaid }
    }

    func formattedTotalSpent(for patientId: UUID) -> String {
        GrooCurrencyFormat.format(totalSpent(for: patientId))
    }

    func totalQuoted(for patientId: UUID) -> Double {
        clinicalHistory(for: patientId).reduce(0) { $0 + $1.servicePrice }
    }

    func formattedTotalQuoted(for patientId: UUID) -> String {
        GrooCurrencyFormat.format(totalQuoted(for: patientId))
    }

    /// Total cobrado a la clínica por este paciente (visitas completadas).
    func totalEarnedFromPatient(_ patientId: UUID) -> Double {
        totalSpent(for: patientId)
    }

    func formattedTotalEarnedFromPatient(_ patientId: UUID) -> String {
        formattedTotalSpent(for: patientId)
    }

    /// Saldo pendiente: visitas con pago parcial + citas futuras no cobradas.
    func pendingBalance(for patientId: UUID) -> Double {
        let visitPending = clinicalHistory(for: patientId).reduce(0) { $0 + $1.pendingAmount }
        let upcoming = reminders
            .filter { !$0.isDone && $0.patientId == patientId && $0.dueAt >= Date() }
            .reduce(0.0) {
                $0 + ($1.revenue ?? $1.consultationType?.defaultPrice ?? GrooAppStore.defaultAppointmentRevenue)
            }
        return visitPending + upcoming
    }

    func formattedPendingBalance(for patientId: UUID) -> String {
        GrooCurrencyFormat.format(pendingBalance(for: patientId))
    }

    func formattedClinicalUSD(_ value: Double) -> String {
        GrooCurrencyFormat.format(value)
    }

    func makeBudgetDraft(for patient: GrooPatient) -> GrooPatientBudgetDraft {
        var items: [GrooBudgetLineItem] = []

        for record in clinicalHistory(for: patient.id).reversed() where record.pendingAmount > 0.01 {
            items.append(
                GrooBudgetLineItem(
                    id: UUID(),
                    title: record.title,
                    detail: record.consultationType?.label ?? record.treatment,
                    quantity: 1,
                    unitPrice: record.pendingAmount
                )
            )
        }

        for reminder in reminders where !reminder.isDone && reminder.patientId == patient.id && reminder.dueAt >= Date() {
            let price = reminder.revenue ?? reminder.consultationType?.defaultPrice ?? Self.defaultAppointmentRevenue
            items.append(
                GrooBudgetLineItem(
                    id: UUID(),
                    title: reminder.title,
                    detail: "Cita · \(formattedClinicalDateShort(reminder.dueAt))",
                    quantity: 1,
                    unitPrice: price
                )
            )
        }

        if items.isEmpty {
            let type = GrooConsultationType.parse(from: patient.treatment) ?? .followUp
            items.append(
                GrooBudgetLineItem(
                    id: UUID(),
                    title: patient.treatment.isEmpty ? "Plan de tratamiento" : patient.treatment,
                    detail: "Presupuesto estimado",
                    quantity: 1,
                    unitPrice: type.defaultPrice
                )
            )
        }

        let cal = Calendar.current
        return GrooPatientBudgetDraft(
            patient: patient,
            clinicName: GrooBrand.appName,
            professionalName: displayName,
            issueDate: Date(),
            validUntil: cal.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
            lineItems: items,
            notes: patient.notes ?? "Presupuesto sujeto a evaluación clínica final.",
            alreadyPaid: totalSpent(for: patient.id),
            historicalPending: 0
        )
    }

    func lastVisitDate(for patientId: UUID) -> Date? {
        clinicalHistory(for: patientId).first?.date
    }

    func firstVisitDate(for patientId: UUID) -> Date? {
        clinicalHistory(for: patientId).last?.date
    }

    func formattedClinicalDate(_ date: Date) -> String {
        Self.clinicalDateFormatter.string(from: date)
    }

    func formattedClinicalDateShort(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .locale(Locale(identifier: "es_ES"))
        )
    }

    func formattedClinicalTime(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour()
                .minute()
                .locale(Locale(identifier: "es_ES"))
        )
    }

    func lastVisitLabel(for patientId: UUID) -> String {
        guard let last = lastVisitDate(for: patientId) else { return "Sin visitas" }
        if Calendar.current.isDateInToday(last) {
            return "Hoy · \(formattedClinicalTime(last))"
        }
        if Calendar.current.isDateInYesterday(last) {
            return "Ayer · \(formattedClinicalTime(last))"
        }
        return formattedClinicalDateShort(last)
    }

    func firstVisitLabel(for patientId: UUID) -> String {
        guard let first = firstVisitDate(for: patientId) else { return "—" }
        return formattedClinicalDateShort(first)
    }

    private static let clinicalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    func isReturningPatient(_ patientId: UUID) -> Bool {
        consultationCount(for: patientId) > 1
    }

    func hasVisitedBefore(_ patientId: UUID) -> Bool {
        !clinicalHistory(for: patientId).isEmpty
    }

    var clinicTotalVisits: Int { clinicalRecords.count }

    var clinicReturningPatientsCount: Int {
        patients.filter { isReturningPatient($0.id) }.count
    }

    var clinicPatientsWithHistoryCount: Int {
        Set(clinicalRecords.map(\.patientId)).count
    }

    // MARK: - Fotos de paciente

    func patientPhotoData(for patientId: UUID) -> Data? {
        UserDefaults.standard.data(forKey: Self.patientPhotoKeyPrefix + patientId.uuidString)
    }

    func setPatientPhotoData(_ data: Data?, for patientId: UUID) {
        let key = Self.patientPhotoKeyPrefix + patientId.uuidString
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        objectWillChange.send()
    }

    func makeAppointmentDraft(for patient: GrooPatient, type: GrooConsultationType = .followUp) -> GrooAppointmentDraft {
        var parts: [String] = ["Tel: \(patient.phone)"]
        if let email = patient.email, !email.isEmpty { parts.append("Email: \(email)") }
        if let allergies = patient.allergies, !allergies.isEmpty { parts.append("Alergias: \(allergies)") }
        if let notes = patient.notes, !notes.isEmpty { parts.append(notes) }
        let defaultDate = patient.nextAppointment
            ?? Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date().addingTimeInterval(86_400))
            ?? Date().addingTimeInterval(86_400)
        return GrooAppointmentDraft(
            patientId: patient.id,
            fullName: patient.fullName,
            phone: patient.phone,
            consultationType: type,
            dueAt: defaultDate,
            estimatedRevenue: type.defaultPrice,
            note: parts.joined(separator: " · ")
        )
    }

    func scheduleAppointment(from draft: GrooAppointmentDraft) {
        let title = "\(draft.consultationType.label) — \(draft.fullName)"
        addReminder(
            title: title,
            note: draft.note,
            dueAt: draft.dueAt,
            revenue: draft.estimatedRevenue,
            patientId: draft.patientId,
            consultationType: draft.consultationType
        )
        if var patient = patient(withId: draft.patientId) {
            patient.nextAppointment = draft.dueAt
            patient.treatment = draft.consultationType.label
            updatePatient(patient)
        }
        pendingAppointmentDraft = nil
        shouldOpenCalendarWithDraft = false
    }

    func openScheduleAppointment(for patient: GrooPatient, type: GrooConsultationType = .followUp) {
        pendingAppointmentDraft = makeAppointmentDraft(for: patient, type: type)
        shouldOpenCalendarWithDraft = true
    }

    func addPatient(
        fullName: String,
        phone: String,
        email: String = "",
        treatment: String = "",
        allergies: String = "",
        notes: String = "",
        dateOfBirth: Date? = nil
    ) {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let patient = GrooPatient(
            id: UUID(),
            fullName: name,
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.isEmpty ? nil : email,
            dateOfBirth: dateOfBirth,
            treatment: treatment.isEmpty ? "Sin tratamiento activo" : treatment,
            allergies: allergies.isEmpty ? nil : allergies,
            notes: notes.isEmpty ? nil : notes,
            nextAppointment: nil
        )
        patients.append(patient)
        patients.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        save()
    }

    func updatePatient(_ patient: GrooPatient) {
        guard let idx = patients.firstIndex(where: { $0.id == patient.id }) else { return }
        patients[idx] = patient
        save()
    }

    func addClinicalRecord(
        patientId: UUID,
        title: String,
        treatment: String,
        notes: String,
        date: Date = Date(),
        consultationType: GrooConsultationType? = nil,
        amountSpent: Double? = nil,
        quotedPrice: Double? = nil,
        reminderId: UUID? = nil,
        durationMinutes: Int? = nil,
        doctorName: String? = nil,
        roomName: String? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        if let reminderId,
           clinicalRecords.contains(where: { $0.reminderId == reminderId }) {
            return
        }
        let type = consultationType ?? GrooConsultationType.parse(from: trimmedTitle) ?? .other
        let price = quotedPrice ?? type.defaultPrice
        let paid = amountSpent ?? price
        let trimmedDoctor = doctorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRoom = roomName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = GrooClinicalRecord(
            id: UUID(),
            patientId: patientId,
            date: date,
            title: trimmedTitle,
            treatment: treatment.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            consultationType: type,
            quotedPrice: price,
            amountSpent: paid,
            reminderId: reminderId,
            durationMinutes: durationMinutes ?? GrooClinicDefaults.typicalDuration(for: type),
            doctorName: (trimmedDoctor?.isEmpty == false ? trimmedDoctor : nil)
                ?? GrooClinicDefaults.typicalDoctor(for: type),
            roomName: (trimmedRoom?.isEmpty == false ? trimmedRoom : nil)
                ?? GrooClinicDefaults.typicalRoom(for: type)
        )
        clinicalRecords.insert(record, at: 0)
        save()
    }

    func openPatientProfile(_ patientId: UUID) {
        pendingPatientNavigation = patientId
    }

    func startChat(for patient: GrooPatient) {
        if let existing = sessions.first(where: { $0.patientId == patient.id }) {
            activeSessionId = existing.id
            prepareChatNavigation(to: existing.id)
            shouldOpenChatOnMain = true
            return
        }

        if let legacyIndex = sessions.firstIndex(where: {
            $0.patientId == nil && $0.title.caseInsensitiveCompare(patient.fullName) == .orderedSame
        }) {
            sessions[legacyIndex].patientId = patient.id
            activeSessionId = sessions[legacyIndex].id
            save()
            prepareChatNavigation(to: sessions[legacyIndex].id)
            shouldOpenChatOnMain = true
            return
        }

        let id = startNewSession()
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = patient.fullName
            sessions[idx].patientId = patient.id
            sessions[idx].messages = [patientChatWelcomeMessage(for: patient)]
            save()
        }
        prepareChatNavigation(to: id)
        shouldOpenChatOnMain = true
    }

    func upcomingReminder(for patientId: UUID) -> GrooReminder? {
        reminders
            .filter { !$0.isDone && $0.patientId == patientId && $0.dueAt >= Date() }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    func lastClinicalRecord(for patientId: UUID) -> GrooClinicalRecord? {
        clinicalHistory(for: patientId).first
    }

    func patientChatWelcomeMessage(for patient: GrooPatient) -> GrooChatMessage {
        let last = clinicalHistory(for: patient.id).first
        let next = upcomingReminder(for: patient.id)
        var lines = ["Chat con \(patient.fullName) · \(patient.treatment)"]
        if let last {
            lines.append("Última: \(formattedClinicalDateShort(last.date)) — \(last.title)")
        }
        if let next {
            lines.append("Próxima cita: \(formattedClinicalDateShort(next.dueAt))")
        } else {
            lines.append("Sin cita · escribe «agendar mañana a las 10»")
        }
        lines.append("Cobrado: \(formattedTotalEarnedFromPatient(patient.id)) · Debe: \(formattedPendingBalance(for: patient.id))")
        return GrooChatMessage(isUser: false, text: lines.joined(separator: "\n"))
    }

    func patientContextForMentor(patientId: UUID) -> String? {
        guard let patient = patient(withId: patientId) else { return nil }
        let history = clinicalHistory(for: patientId)
        var lines = [
            "CHAT ACTIVO CON PACIENTE:",
            "Nombre: \(patient.fullName)",
            "Teléfono: \(patient.phone)",
            "Tratamiento activo: \(patient.treatment)",
        ]
        if let email = patient.email, !email.isEmpty { lines.append("Email: \(email)") }
        if let allergies = patient.allergies, !allergies.isEmpty { lines.append("Alergias: \(allergies)") }
        if let notes = patient.notes, !notes.isEmpty { lines.append("Notas: \(notes)") }
        if let last = history.first {
            lines.append("Última visita: \(formattedClinicalDate(last.date)) — \(last.title)")
            lines.append("  Tipo: \(last.consultationType?.label ?? "—"), Doctor: \(last.doctorDisplay), Sala: \(last.roomDisplay), Duración: \(last.formattedDuration)")
            if !last.treatment.isEmpty { lines.append("  Tratamiento: \(last.treatment)") }
        }
        if let next = upcomingReminder(for: patientId) {
            lines.append("Próxima cita agendada: \(formattedClinicalDate(next.dueAt)) — \(next.title)")
        } else if let nextAppt = patient.nextAppointment {
            lines.append("Próxima cita (ficha): \(formattedClinicalDate(nextAppt))")
        } else {
            lines.append("Sin cita programada.")
        }
        lines.append("Visitas totales: \(history.count). Total cobrado: \(formattedTotalEarnedFromPatient(patientId)). Pendiente: \(formattedPendingBalance(for: patientId)).")
        if history.count > 1 {
            lines.append("Historial reciente:")
            for record in history.prefix(5) {
                let pay = "Precio \(formattedClinicalUSD(record.servicePrice)), pagó \(formattedClinicalUSD(record.amountPaid))"
                let pending = record.pendingAmount > 0.01 ? ", debe \(formattedClinicalUSD(record.pendingAmount))" : ""
                lines.append("- \(formattedClinicalDateShort(record.date)): \(record.title) — \(pay)\(pending)")
            }
        }
        lines.append("Si el usuario pide agendar o programar una cita, usa los datos de este paciente automáticamente.")
        lines.append("Responde en español cuando el usuario escriba en español.")
        return lines.joined(separator: "\n")
    }

    func mentorContextSupplement(for session: GrooChatSession?) -> String {
        var parts = [careContextForMentor()]
        if let patientId = session?.patientId,
           let patientCtx = patientContextForMentor(patientId: patientId) {
            parts.append(patientCtx)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Agenda cita vinculada al paciente del chat cuando detecta intención + fecha.
    func handleChatPatientAppointmentIfNeeded(text: String, patientId: UUID) -> String? {
        let lower = text.lowercased()
        let schedulingIntent = lower.contains("agendar")
            || lower.contains("programar")
            || lower.contains("reservar")
            || (lower.contains("cita") && (lower.contains("para") || lower.contains("el ") || lower.contains("mañana") || lower.contains("hoy")))
        guard schedulingIntent else { return nil }
        guard let dueAt = GrooReminderTimeParser.parseDueDate(from: text), dueAt > Date() else { return nil }
        guard let patient = patient(withId: patientId) else { return nil }

        let type = GrooConsultationType.parse(from: text) ?? .followUp
        var draft = makeAppointmentDraft(for: patient, type: type)
        draft.dueAt = dueAt
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.note = (draft.note.isEmpty ? "" : draft.note + " · ") + String(text.prefix(120))
        }
        scheduleAppointment(from: draft)

        let when = formattedClinicalDate(dueAt)
        return "✅ Cita agendada: \(when) · \(type.label). Ver en Agenda."
    }

    /// Historial unificado de ventas y citas completadas, más reciente primero.
    var actionHistory: [GrooClinicAction] {
        var items: [GrooClinicAction] = []
        items.reserveCapacity(sales.count + reminders.filter(\.isDone).count)

        for sale in sales {
            items.append(
                GrooClinicAction(
                    id: sale.id,
                    kind: .sale,
                    title: sale.title,
                    amount: sale.amount,
                    date: sale.date
                )
            )
        }

        for reminder in reminders where reminder.isDone {
            items.append(
                GrooClinicAction(
                    id: reminder.id,
                    kind: .appointment,
                    title: reminder.title,
                    amount: reminder.revenue ?? Self.defaultAppointmentRevenue,
                    date: reminder.dueAt
                )
            )
        }

        return items.sorted { $0.date > $1.date }
    }

    func filteredActionHistory(kind: GrooClinicActionKind?) -> [GrooClinicAction] {
        guard let kind else { return actionHistory }
        return actionHistory.filter { $0.kind == kind }
    }

    private static func isInCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
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
            prepareChatNavigation()
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

    @discardableResult
    func startSession(titled title: String) -> UUID {
        let id = startNewSession()
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            save()
        }
        return id
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

    func prepareChatNavigation(to sessionId: UUID? = nil) {
        ensureWelcomeSession()
        let target = sessionId ?? activeSessionId
        guard let target else { return }
        selectSession(target)
        pendingChatNavigation = target
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
        if sessions[idx].patientId == nil, sessions[idx].title.hasPrefix("Session") {
            sessions[idx].title = String(text.prefix(42))
        }
        bumpSessionToTop(at: idx)
        if countsAgainstTrial, subscription == .trial {
            trialMessagesRemaining = max(0, trialMessagesRemaining - 1)
        }
        save()
        return true
    }

    /// Envía la vista previa de sonrisa IA a una conversación y abre el chat.
    @discardableResult
    func sendSmilePreviewToChat(
        sessionId: UUID,
        image: UIImage,
        caption: String = "Esta sería tu sonrisa mejorada."
    ) -> Bool {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        let prepared = GrooImageProcessing.resize(image, maxSide: 1280)
        guard let jpeg = GrooImageProcessing.jpegData(prepared, quality: 0.82) else { return false }

        let message = GrooChatMessage(
            isUser: true,
            text: caption,
            imageJPEGBase64: jpeg.base64EncodedString()
        )
        sessions[idx].messages.append(message)
        if sessions[idx].patientId == nil, sessions[idx].title.hasPrefix("Session") {
            sessions[idx].title = "Sonrisa mejorada"
        }
        bumpSessionToTop(at: idx)
        activeSessionId = sessionId
        save()
        prepareChatNavigation(to: sessionId)
        shouldOpenChatOnMain = true
        return true
    }

    /// Creates a reminder from chat when the message includes a reminder intent + deadline (no AI).
    func handleChatReminderIfNeeded(text: String, patientId: UUID? = nil) -> String? {
        guard GrooReminderTimeParser.isReminderRequest(text),
              let dueAt = GrooReminderTimeParser.parseDueDate(from: text),
              dueAt > Date()
        else { return nil }

        let title = GrooReminderTimeParser.suggestedTitle(from: text)
        let span = GrooReminderTimeParser.relativeSpanDescription(from: text)
        let type = GrooConsultationType.parse(from: text)
        addReminder(
            title: title,
            note: String(text.prefix(160)),
            dueAt: dueAt,
            revenue: type?.defaultPrice,
            patientId: patientId,
            consultationType: type
        )
        if let patientId, var patient = patient(withId: patientId) {
            patient.nextAppointment = dueAt
            if let type { patient.treatment = type.label }
            updatePatient(patient)
        }
        return GrooReminderTimeParser.cannedAssistantReply(title: title, span: span, dueAt: dueAt)
    }

    func appendAssistantMessage(_ text: String) {
        guard let id = activeSessionId,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(GrooChatMessage(isUser: false, text: text))
        bumpSessionToTop(at: idx)
        save()
    }

    func filteredSessions(query: String) -> [GrooChatSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [GrooChatSession]
        if q.isEmpty {
            base = sessions
        } else {
            base = sessions.filter {
                $0.title.lowercased().contains(q)
                    || $0.preview.lowercased().contains(q)
                    || $0.messages.contains { $0.text.lowercased().contains(q) }
            }
        }
        return base.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Mueve la conversación al tope de la lista (estilo WhatsApp).
    private func bumpSessionToTop(at idx: Int) {
        guard sessions.indices.contains(idx) else { return }
        sessions[idx].updatedAt = Date()
        let session = sessions.remove(at: idx)
        sessions.insert(session, at: 0)
    }

    // MARK: - Reminders

    func addReminder(
        title: String,
        note: String,
        dueAt: Date,
        revenue: Double? = nil,
        patientId: UUID? = nil,
        consultationType: GrooConsultationType? = nil
    ) {
        let reminder = GrooReminder(
            id: UUID(),
            title: title,
            note: note,
            dueAt: dueAt,
            createdAt: Date(),
            isDone: false,
            revenue: revenue,
            patientId: patientId,
            consultationType: consultationType
        )
        reminders.insert(reminder, at: 0)
        save()
        Task {
            await GrooReminderNotificationService.schedule(reminder: reminder)
        }
    }

    func toggleReminder(_ id: UUID) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        let wasDone = reminders[i].isDone
        reminders[i].isDone.toggle()
        if reminders[i].isDone {
            GrooReminderNotificationService.cancel(reminderId: id)
            if !wasDone {
                registerClinicalVisitFromReminder(reminders[i])
            }
        } else if reminders[i].dueAt > Date() {
            Task {
                await GrooReminderNotificationService.schedule(reminder: reminders[i])
            }
        }
        save()
    }

    private func registerClinicalVisitFromReminder(_ reminder: GrooReminder) {
        guard let patientId = reminder.patientId else { return }
        let type = reminder.consultationType
            ?? GrooConsultationType.parse(from: reminder.title)
            ?? .followUp
        addClinicalRecord(
            patientId: patientId,
            title: reminder.title,
            treatment: type.label,
            notes: reminder.note,
            date: reminder.dueAt,
            consultationType: type,
            amountSpent: reminder.revenue ?? type.defaultPrice,
            quotedPrice: reminder.revenue ?? type.defaultPrice,
            reminderId: reminder.id,
            durationMinutes: GrooClinicDefaults.typicalDuration(for: type),
            doctorName: GrooClinicDefaults.typicalDoctor(for: type),
            roomName: GrooClinicDefaults.typicalRoom(for: type)
        )
    }

    func deleteReminder(_ id: UUID) {
        GrooReminderNotificationService.cancel(reminderId: id)
        reminders.removeAll { $0.id == id }
        save()
    }

    func addSale(title: String, amount: Double, date: Date = Date()) {
        guard amount > 0 else { return }
        let entry = GrooSaleEntry(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Venta clínica" : title,
            amount: amount,
            date: date
        )
        sales.insert(entry, at: 0)
        save()
    }

    private func welcomeMessage() -> GrooChatMessage {
        if let d = diagnostic {
            let text = """
            Hi \(displayName.split(separator: " ").first.map(String.init) ?? displayName). I'm \(GrooBrand.appName), your dental clinic assistant.

            Your clinic assessment: \(String(format: "%.1f", d.overall))/5 — «\(d.nickname)».
            \(d.summary)

            What should we handle first in the clinic today?
            """
            return GrooChatMessage(isUser: false, text: text)
        }
        return GrooChatMessage(
            isUser: false,
            text: "Hi. I'm \(GrooBrand.appName), your assistant for running a dental clinic. Tell me what you need — appointments, follow-ups, billing, or team coordination."
        )
    }

    func careContextForMentor() -> String {
        guard let d = diagnostic else {
            return "The user does not yet have a complete clinic readiness assessment."
        }
        var lines = [
            "USER CLINIC ASSESSMENT:",
            "Overall: \(String(format: "%.1f", d.overall))/5 — \(d.nickname)",
            d.summary,
            "Dimensions:"
        ]
        for p in d.pillars {
            lines.append("- \(p.pillar.title): \(String(format: "%.1f", p.average))/5 (area: \(p.lowestTrait))")
        }
        lines.append("Methodology: Patients, Operations, Team, Billing, and Practice. Connect each response to clinic management.")
        lines.append("Do not provide clinical diagnoses or treatment plans.")
        if !onboarding.goals.isEmpty {
            lines.append("Stated goals: \(onboarding.goals.joined(separator: ", "))")
        }
        if !onboarding.careerStage.isEmpty {
            lines.append("Practice type: \(onboarding.careerStage)")
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
        var sales: [GrooSaleEntry]?
        var patients: [GrooPatient]?
        var clinicalRecords: [GrooClinicalRecord]?
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
            sales: sales,
            patients: patients,
            clinicalRecords: clinicalRecords,
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
        sales = snap.sales ?? []
        patients = snap.patients ?? []
        clinicalRecords = snap.clinicalRecords ?? []
        if clinicalRecords.isEmpty, !patients.isEmpty {
            clinicalRecords = Self.defaultClinicalRecords(for: patients)
        }
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
        sales = []
        patients = []
        clinicalRecords = []
        subscription = .trial
        trialMessagesRemaining = 12
        hasDismissedPaywallOnce = false
        showPaywall = false
        save()
    }
}
