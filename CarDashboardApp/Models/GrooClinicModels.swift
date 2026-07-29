import Foundation
import SwiftUI

// MARK: - Alias de marca
//
// Las vistas de clínica nombran el violeta Groo como `primary`; `purple` es el
// mismo color con el nombre que usa el resto del diseño.

extension GrooBrand {
    static let appName = "Groo"
    static var primary: Color { purple }
    static var primarySoft: Color { purpleSoft }
}

// MARK: - Formato de moneda

enum GrooCurrencyFormat {
    static func format(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}

// MARK: - Tipos de consulta

enum GrooConsultationType: String, CaseIterable, Identifiable, Codable, Hashable {
    case firstVisit
    case followUp
    case cleaning
    case whitening
    case orthodontics
    case implant
    case emergency
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .firstVisit: return "Primera visita"
        case .followUp: return "Control"
        case .cleaning: return "Limpieza"
        case .whitening: return "Blanqueamiento"
        case .orthodontics: return "Ortodoncia"
        case .implant: return "Implante"
        case .emergency: return "Urgencia"
        case .other: return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .firstVisit: return "person.crop.circle.badge.plus"
        case .followUp: return "arrow.triangle.2.circlepath"
        case .cleaning: return "sparkles"
        case .whitening: return "sun.max.fill"
        case .orthodontics: return "square.grid.3x3.fill"
        case .implant: return "wrench.and.screwdriver.fill"
        case .emergency: return "cross.case.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var defaultPrice: Double {
        switch self {
        case .firstVisit: return 60
        case .followUp: return 45
        case .cleaning: return 90
        case .whitening: return 250
        case .orthodontics: return 400
        case .implant: return 1200
        case .emergency: return 120
        case .other: return 0
        }
    }
}

// MARK: - Filtro de la lista de pacientes

enum GrooPatientListFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case returning
    case pending
    case upcoming

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todos"
        case .returning: return "Recurrentes"
        case .pending: return "Con saldo"
        case .upcoming: return "Con cita"
        }
    }
}

// MARK: - Paciente

struct GrooPatient: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var fullName: String
    var phone: String = ""
    var treatment: String = ""
    /// Opcionales: la ficha solo muestra la fila cuando hay dato.
    var email: String?
    var allergies: String?
    var notes: String?
    var dateOfBirth: Date?
    var nextAppointment: Date?
    var createdAt: Date = Date()
}

// MARK: - Historia clínica

struct GrooClinicalRecord: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var patientId: UUID
    var title: String
    var treatment: String = ""
    var notes: String = ""
    var date: Date = Date()
    var consultationType: GrooConsultationType? = .followUp
    /// Lo que el paciente ha abonado por esta visita.
    var amountPaid: Double = 0
    /// Lo que costaba el servicio, que puede ser mayor que lo abonado.
    var servicePrice: Double = 0
    var durationMinutes: Int = 30
    var doctorName: String = ""
    var roomName: String = ""

    var pendingAmount: Double { max(0, servicePrice - amountPaid) }
    var isFullyPaid: Bool { pendingAmount <= 0.01 }

    var doctorDisplay: String {
        doctorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Sin asignar"
            : doctorName
    }

    var roomDisplay: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Sin asignar"
            : roomName
    }

    var formattedDuration: String {
        guard durationMinutes >= 60 else { return "\(durationMinutes) min" }
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}

// MARK: - Presupuesto

struct GrooBudgetLineItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var detail: String = ""
    var quantity: Int = 1
    var unitPrice: Double = 0

    var total: Double { Double(quantity) * unitPrice }
    /// Alias usado en las tarjetas de resumen.
    var revenue: Double { total }
}

struct GrooPatientBudgetDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var patient: GrooPatient
    var clinicName: String
    var professionalName: String
    var issueDate: Date
    var validUntil: Date
    var lineItems: [GrooBudgetLineItem]
    var notes: String
    /// Ya abonado por el paciente en visitas anteriores.
    var alreadyPaid: Double
    /// Saldo pendiente arrastrado del historial.
    var historicalPending: Double

    var patientId: UUID { patient.id }
    var fullName: String { patient.fullName }
    var phone: String { patient.phone }

    var subtotal: Double { lineItems.reduce(0) { $0 + $1.total } }
    var totalBudget: Double { max(0, subtotal + historicalPending - alreadyPaid) }
}

// MARK: - Cita

struct GrooAppointmentDraft: Identifiable, Equatable {
    var id: UUID = UUID()
    var patientId: UUID
    var fullName: String
    var phone: String
    var consultationType: GrooConsultationType
    var dueAt: Date
    var estimatedRevenue: Double
    var note: String

    /// Las vistas usan indistintamente `note` y `notes`.
    var notes: String {
        get { note }
        set { note = newValue }
    }

    var title: String { "\(consultationType.label) · \(fullName)" }
}

// MARK: - Valores por defecto de la clínica

enum GrooClinicDefaults {
    static let doctors = [
        "Dra. García",
        "Dr. Martínez",
        "Dra. López",
        "Dr. Rodríguez",
    ]

    static let rooms = [
        "Consultorio 1",
        "Consultorio 2",
        "Sala de cirugía",
    ]

    static func typicalDuration(for type: GrooConsultationType) -> Int {
        switch type {
        case .firstVisit: return 45
        case .followUp: return 20
        case .cleaning: return 45
        case .whitening: return 60
        case .orthodontics: return 30
        case .implant: return 90
        case .emergency: return 30
        case .other: return 30
        }
    }

    static func typicalDoctor(for type: GrooConsultationType) -> String {
        switch type {
        case .implant, .emergency: return doctors[1]
        case .orthodontics: return doctors[2]
        default: return doctors[0]
        }
    }

    static func typicalRoom(for type: GrooConsultationType) -> String {
        switch type {
        case .implant: return rooms[2]
        case .orthodontics, .whitening: return rooms[1]
        default: return rooms[0]
        }
    }
}
