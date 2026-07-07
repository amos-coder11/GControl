import Combine
import Foundation
import SwiftUI

// MARK: - Actividad de jornada

enum WorkdayActivityKind: String, Codable, CaseIterable, Identifiable {
    case enJornada
    case descanso
    case reunion
    case horasExtras
    case ausencia
    case otro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enJornada: "En jornada"
        case .descanso: "Descanso"
        case .reunion: "Reunión"
        case .horasExtras: "Horas extras"
        case .ausencia: "Ausencia"
        case .otro: "Otro"
        }
    }

    var subtitle: String {
        switch self {
        case .enJornada: "Tiempo activo de trabajo"
        case .descanso: "Pausa para comer o descansar"
        case .reunion: "Reuniones o capacitaciones"
        case .horasExtras: "Tiempo adicional trabajado"
        case .ausencia: "Ausencia del puesto"
        case .otro: "Otra actividad no especificada"
        }
    }

    var icon: String {
        switch self {
        case .enJornada: "briefcase.fill"
        case .descanso: "cup.and.saucer.fill"
        case .reunion: "person.2.fill"
        case .horasExtras: "clock.fill"
        case .ausencia: "cross.case.fill"
        case .otro: "ellipsis.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .enJornada: Color(red: 0.22, green: 0.78, blue: 0.45)
        case .descanso: Color(red: 0.96, green: 0.76, blue: 0.28)
        case .reunion: Color(red: 0.62, green: 0.42, blue: 0.95)
        case .horasExtras: Color(red: 0.32, green: 0.62, blue: 0.98)
        case .ausencia: Color(red: 0.95, green: 0.38, blue: 0.38)
        case .otro: Color(red: 0.62, green: 0.64, blue: 0.68)
        }
    }

    /// Tiempo que cuenta como jornada laboral (excluye descanso y ausencia).
    var countsAsWork: Bool {
        switch self {
        case .descanso, .ausencia: false
        default: true
        }
    }
}

struct WorkdaySegment: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: WorkdayActivityKind
    let start: Date
    var end: Date?

    var duration: TimeInterval {
        let finish = end ?? Date()
        return max(0, finish.timeIntervalSince(start))
    }
}

struct WorkdayDayRecord: Codable, Identifiable, Equatable {
    var id: String { dateKey }
    let dateKey: String
    var segments: [WorkdaySegment]
    var callsMade: Int
    var messagesResponded: Int
    var finishedAt: Date?
    var workedSeconds: Int

    var displayDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateKey) else { return dateKey }
        f.dateStyle = .medium
        return f.string(from: d)
    }
}

struct WorkdayWeekDay: Identifiable, Equatable {
    var id: String { dateKey }
    let dateKey: String
    let shortLabel: String
    let workedSeconds: Int
    let callsMade: Int
    let messagesResponded: Int

    var workedHours: Double { Double(workedSeconds) / 3600.0 }
}

private struct WorkdayTodayPayload: Codable {
    var dateKey: String
    var segments: [WorkdaySegment]
    var callsMade: Int
    var messagesResponded: Int
    var isDayFinished: Bool
    var jornadaStartTime: Date?
}

// MARK: - Horario oficial del concesionario

enum DealershipOpeningHours {
    static let locationTitle = "Pozuelo de Alarcón / Las Rozas (Europolis)"

    private struct DayWindow {
        let openHour: Int
        let openMinute: Int
        let closeHour: Int
        let closeMinute: Int
    }

    private static let weekdayWindow = DayWindow(openHour: 10, openMinute: 0, closeHour: 19, closeMinute: 30)
    private static let saturdayWindow = DayWindow(openHour: 11, openMinute: 0, closeHour: 14, closeMinute: 0)

    static let weeklySummary: [(label: String, hours: String)] = [
        ("Lunes a viernes", "10:00 – 19:30 h"),
        ("Sábados", "11:00 – 14:00 h"),
        ("Domingos", "Cerrado"),
    ]

    private static func window(for date: Date = Date()) -> DayWindow? {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: return nil
        case 7: return saturdayWindow
        default: return weekdayWindow
        }
    }

    static func isClosed(on date: Date = Date()) -> Bool {
        window(for: date) == nil
    }

    static func todayLabel(for date: Date = Date()) -> String {
        guard let w = window(for: date) else { return "Cerrado" }
        return "\(clock(w.openHour, w.openMinute)) – \(clock(w.closeHour, w.closeMinute)) h"
    }

    static func isOpenNow(at date: Date = Date()) -> Bool {
        guard let w = window(for: date) else { return false }
        let minutes = Calendar.current.component(.hour, from: date) * 60
            + Calendar.current.component(.minute, from: date)
        let open = w.openHour * 60 + w.openMinute
        let close = w.closeHour * 60 + w.closeMinute
        return minutes >= open && minutes < close
    }

    static func statusLabel(at date: Date = Date()) -> String {
        if isClosed(on: date) { return "Cerrado hoy" }
        if isOpenNow(at: date) { return "Abierto ahora" }
        return "Fuera de horario"
    }

    private static func clock(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - Store

@MainActor
final class WorkdayStore: ObservableObject {
    @Published private(set) var currentKind: WorkdayActivityKind?
    @Published private(set) var isActive = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var jornadaStartTime: Date?
    @Published private(set) var todaySegments: [WorkdaySegment] = []
    @Published private(set) var callsMadeToday = 0
    @Published private(set) var messagesRespondedToday = 0
    @Published private(set) var isDayFinished = false
    @Published private(set) var history: [WorkdayDayRecord] = []

    private var userId: UUID?
    private var tickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .phoneCallDidStart)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recordCall() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .messageDidRespond)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recordMessageResponded() }
            .store(in: &cancellables)
    }

    deinit {
        tickTask?.cancel()
    }

    func attach(userId: UUID?) {
        guard self.userId != userId else {
            rollToTodayIfNeeded()
            return
        }
        self.userId = userId
        loadHistory()
        loadToday()
        refreshElapsed()
    }

    func startJornada() {
        guard !isDayFinished else { return }
        if isActive, currentKind != nil { return }

        isActive = true
        let now = Date()
        jornadaStartTime = now
        switchActivity(.enJornada, at: now)
        startTicking()
        persistToday()
    }

    func switchActivity(_ kind: WorkdayActivityKind) {
        guard !isDayFinished else { return }
        if !isActive {
            isActive = true
            jornadaStartTime = jornadaStartTime ?? Date()
            startTicking()
        }
        switchActivity(kind, at: Date())
    }

    func finishJornada() {
        guard !isDayFinished else { return }
        closeOpenSegment(at: Date())
        isActive = false
        isDayFinished = true
        currentKind = nil
        tickTask?.cancel()
        refreshElapsed()

        let record = WorkdayDayRecord(
            dateKey: todayKey,
            segments: todaySegments,
            callsMade: callsMadeToday,
            messagesResponded: messagesRespondedToday,
            finishedAt: Date(),
            workedSeconds: elapsedSeconds
        )
        history.removeAll { $0.dateKey == todayKey }
        history.insert(record, at: 0)
        saveHistory()
        persistToday()
    }

    /// Permite continuar la jornada del mismo día tras haberla finalizado.
    func reactivateJornada() {
        guard isDayFinished else { return }
        isDayFinished = false
        isActive = true
        history.removeAll { $0.dateKey == todayKey }
        saveHistory()
        switchActivity(.enJornada, at: Date())
        startTicking()
        persistToday()
    }

    func recordCall() {
        guard !isDayFinished else { return }
        callsMadeToday += 1
        persistToday()
    }

    func recordMessageResponded() {
        guard !isDayFinished else { return }
        messagesRespondedToday += 1
        persistToday()
    }

    /// Resumen de los últimos 7 días para el gráfico de Inicio.
    var last7Days: [WorkdayWeekDay] {
        let cal = Calendar.current
        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "es_ES")
        labelFormatter.dateFormat = "EEE"

        return (0 ..< 7).map { offset in
            let day = cal.date(byAdding: .day, value: offset - 6, to: Date()) ?? Date()
            let key = Self.dayKeyFormatter.string(from: day)
            let label = String(labelFormatter.string(from: day).prefix(3)).capitalized
            let record = history.first { $0.dateKey == key }

            if key == todayKey {
                return WorkdayWeekDay(
                    dateKey: key,
                    shortLabel: label,
                    workedSeconds: elapsedSeconds,
                    callsMade: callsMadeToday,
                    messagesResponded: messagesRespondedToday
                )
            }

            return WorkdayWeekDay(
                dateKey: key,
                shortLabel: label,
                workedSeconds: record?.workedSeconds ?? 0,
                callsMade: record?.callsMade ?? 0,
                messagesResponded: record?.messagesResponded ?? 0
            )
        }
    }

    var weekTotalWorkedSeconds: Int {
        last7Days.reduce(0) { $0 + $1.workedSeconds }
    }

    var weekTotalCalls: Int {
        last7Days.reduce(0) { $0 + $1.callsMade }
    }

    var weekTotalMessages: Int {
        last7Days.reduce(0) { $0 + $1.messagesResponded }
    }

    static func formatHoursShort(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "0h"
    }

    // MARK: - Formato

    var elapsedFormatted: String {
        Self.formatDuration(seconds: elapsedSeconds)
    }

    var jornadaStartLabel: String? {
        guard let start = jornadaStartTime else { return nil }
        return Self.timeFormatter.string(from: start)
    }

    static func formatDuration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        formatDuration(seconds: Int(interval))
    }

    static func formatRange(start: Date, end: Date?) -> String {
        let endDate = end ?? Date()
        return "\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: endDate))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String {
        Self.dayKeyFormatter.string(from: Date())
    }

    // MARK: - Interno

    private func switchActivity(_ kind: WorkdayActivityKind, at date: Date) {
        if currentKind == kind, todaySegments.last?.end == nil { return }
        closeOpenSegment(at: date)
        todaySegments.append(WorkdaySegment(id: UUID(), kind: kind, start: date, end: nil))
        currentKind = kind
        refreshElapsed()
        persistToday()
    }

    private func closeOpenSegment(at date: Date) {
        guard var last = todaySegments.last, last.end == nil else { return }
        last.end = date
        todaySegments[todaySegments.count - 1] = last
    }

    private func refreshElapsed() {
        elapsedSeconds = Int(workingSeconds(upTo: Date()))
    }

    private func workingSeconds(upTo date: Date) -> TimeInterval {
        todaySegments.reduce(0) { total, segment in
            guard segment.kind.countsAsWork else { return total }
            let finish = segment.end ?? (segment.id == todaySegments.last?.id && isActive ? date : segment.start)
            return total + max(0, finish.timeIntervalSince(segment.start))
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.refreshElapsed()
                }
            }
        }
    }

    private func rollToTodayIfNeeded() {
        guard let payload = loadTodayPayload(), payload.dateKey != todayKey else { return }
        resetForNewDay()
    }

    private func resetForNewDay() {
        tickTask?.cancel()
        isActive = false
        isDayFinished = false
        currentKind = nil
        jornadaStartTime = nil
        todaySegments = []
        callsMadeToday = 0
        messagesRespondedToday = 0
        elapsedSeconds = 0
        persistToday()
    }

    private func loadToday() {
        if let payload = loadTodayPayload(), payload.dateKey == todayKey {
            todaySegments = payload.segments
            callsMadeToday = payload.callsMade
            messagesRespondedToday = payload.messagesResponded
            isDayFinished = payload.isDayFinished
            jornadaStartTime = payload.jornadaStartTime
            isActive = !isDayFinished && todaySegments.contains { $0.end == nil }
            currentKind = todaySegments.last(where: { $0.end == nil })?.kind
            if isActive, !isDayFinished { startTicking() }
        } else {
            resetForNewDay()
        }
        refreshElapsed()
    }

    private func persistToday() {
        let payload = WorkdayTodayPayload(
            dateKey: todayKey,
            segments: todaySegments,
            callsMade: callsMadeToday,
            messagesResponded: messagesRespondedToday,
            isDayFinished: isDayFinished,
            jornadaStartTime: jornadaStartTime
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: todayStorageKey)
    }

    private func loadTodayPayload() -> WorkdayTodayPayload? {
        guard let data = UserDefaults.standard.data(forKey: todayStorageKey),
              let payload = try? JSONDecoder().decode(WorkdayTodayPayload.self, from: data)
        else { return nil }
        return payload
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey),
              let records = try? JSONDecoder().decode([WorkdayDayRecord].self, from: data)
        else {
            history = []
            return
        }
        history = records.sorted { $0.dateKey > $1.dateKey }
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyStorageKey)
    }

    private var todayStorageKey: String {
        "workday.\(userId?.uuidString ?? "guest").today"
    }

    private var historyStorageKey: String {
        "workday.\(userId?.uuidString ?? "guest").history"
    }
}

extension Notification.Name {
    static let phoneCallDidStart = Notification.Name("CarHub.phoneCallDidStart")
    static let messageDidRespond = Notification.Name("CarHub.messageDidRespond")
}
