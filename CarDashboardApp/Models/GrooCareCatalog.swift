import Foundation

/// C.A.R.E+U pillars (GROO methodology / The Unwritten Book).
enum GrooCarePillar: String, CaseIterable, Identifiable, Codable, Hashable {
    case communication
    case attitude
    case relationships
    case execution
    case foundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .communication: return "Patients"
        case .attitude: return "Operations"
        case .relationships: return "Team"
        case .execution: return "Billing"
        case .foundation: return "Practice"
        }
    }

    var shortLabel: String {
        switch self {
        case .communication: return "C"
        case .attitude: return "A"
        case .relationships: return "R"
        case .execution: return "E"
        case .foundation: return "U"
        }
    }

    var subtitle: String {
        switch self {
        case .communication: return "Patient experience and chair-side communication"
        case .attitude: return "Daily workflows, scheduling, and efficiency"
        case .relationships: return "Team coordination and internal culture"
        case .execution: return "Collections, insurance, and revenue rhythm"
        case .foundation: return "Practice vision, compliance, and sustainability"
        }
    }

    var growthHint: String {
        switch self {
        case .communication: return "Confirm tomorrow's patients with a short reminder message."
        case .attitude: return "Block 15 minutes to review chair utilization for the week."
        case .relationships: return "Align the front desk and clinical team on one daily priority."
        case .execution: return "Review outstanding balances and plan two follow-up calls."
        case .foundation: return "Protect time for compliance checks or equipment maintenance this week."
        }
    }

    /// Index in the row of 4 CARE icons (nil = YOU pillar).
    var pillarIconIndex: Int? {
        switch self {
        case .communication: return 0
        case .attitude: return 1
        case .relationships: return 2
        case .execution: return 3
        case .foundation: return nil
        }
    }

    var iconAsset: String? {
        switch self {
        case .communication: return "LibroIcon"
        case .attitude: return "CopaIcon"
        case .relationships: return "VerdeIcon"
        case .execution: return "PhysicsIcon"
        case .foundation: return "GraduationCap"
        }
    }
}

struct GrooCareQuestion: Identifiable, Hashable {
    let id: Int
    let pillar: GrooCarePillar
    let text: String
    let trait: String
}

enum GrooCareCatalog {
    /// 25 statements (1–5 scale), 5 per pillar.
    static let questions: [GrooCareQuestion] = [
        .init(id: 1, pillar: .communication, text: "I express clearly what I need, even when it's uncomfortable.", trait: "Clarity"),
        .init(id: 2, pillar: .communication, text: "I influence decisions without imposing or staying silent.", trait: "Influence"),
        .init(id: 3, pillar: .communication, text: "I listen to understand, not just to respond.", trait: "Listening"),
        .init(id: 4, pillar: .communication, text: "I address difficult conversations in time.", trait: "Difficult conversations"),
        .init(id: 5, pillar: .communication, text: "I can articulate the value of my work to others.", trait: "Self-worth"),

        .init(id: 6, pillar: .attitude, text: "I stay calm and clear-headed under pressure.", trait: "Pressure"),
        .init(id: 7, pillar: .attitude, text: "After a setback, I regain momentum quickly.", trait: "Resilience"),
        .init(id: 8, pillar: .attitude, text: "I see feedback as useful information, not a threat.", trait: "Learning"),
        .init(id: 9, pillar: .attitude, text: "I allow myself to ask for what I need without minimizing myself.", trait: "Self-advocacy"),
        .init(id: 10, pillar: .attitude, text: "I believe I can grow in what challenges me today.", trait: "Growth mindset"),

        .init(id: 11, pillar: .relationships, text: "I build trust-based relationships before I need them.", trait: "Network"),
        .init(id: 12, pillar: .relationships, text: "My reputation reflects how I work and how I treat people.", trait: "Reputation"),
        .init(id: 13, pillar: .relationships, text: "I ask for help or partnerships when it speeds up results.", trait: "Collaboration"),
        .init(id: 14, pillar: .relationships, text: "I give genuine recognition to those who contribute.", trait: "Generosity"),
        .init(id: 15, pillar: .relationships, text: "I manage conflict without damaging the long-term relationship.", trait: "Conflict"),

        .init(id: 16, pillar: .execution, text: "I decide with incomplete information when it's time to move forward.", trait: "Decision"),
        .init(id: 17, pillar: .execution, text: "I deliver concrete results, not just activity.", trait: "Delivery"),
        .init(id: 18, pillar: .execution, text: "I prioritize what matters over noisy urgency.", trait: "Priority"),
        .init(id: 19, pillar: .execution, text: "I keep my commitments even when no one is watching.", trait: "Consistency"),
        .init(id: 20, pillar: .execution, text: "I close loops: I start and finish what matters.", trait: "Closure"),

        .init(id: 21, pillar: .foundation, text: "I manage my energy (rest, focus, boundaries) realistically.", trait: "Balance"),
        .init(id: 22, pillar: .foundation, text: "I have clarity on why I work (purpose).", trait: "Purpose"),
        .init(id: 23, pillar: .foundation, text: "I maintain habits that sustain my performance.", trait: "Discipline"),
        .init(id: 24, pillar: .foundation, text: "I know when to stop and recover before burning out.", trait: "Self-care"),
        .init(id: 25, pillar: .foundation, text: "My personal life supports, not sabotages, my career.", trait: "Foundation"),
    ]

    static func questions(for pillar: GrooCarePillar) -> [GrooCareQuestion] {
        questions.filter { $0.pillar == pillar }
    }
}

struct GrooPillarScore: Identifiable, Hashable, Codable {
    var pillar: GrooCarePillar
    var average: Double
    var lowestTrait: String
    var id: String { pillar.rawValue }
}

struct GrooDiagnosticResult: Hashable, Codable {
    var overall: Double
    var nickname: String
    var summary: String
    var pillars: [GrooPillarScore]
    var completedAt: Date

    var recommendedAction: String {
        guard let weakest = pillars.min(by: { $0.average < $1.average }) else {
            return "Talk to \(GrooBrand.appName) and define a concrete plan for this week."
        }
        return weakest.pillar.growthHint
    }
}

enum GrooCareScoring {
    static func result(from answers: [Int: Int]) -> GrooDiagnosticResult {
        var pillarScores: [GrooPillarScore] = []
        for pillar in GrooCarePillar.allCases {
            let qs = GrooCareCatalog.questions(for: pillar)
            let values = qs.compactMap { answers[$0.id] }
            let avg = values.isEmpty ? 3.0 : Double(values.reduce(0, +)) / Double(values.count)
            let lowest = qs.min { (answers[$0.id] ?? 3) < (answers[$1.id] ?? 3) }
            pillarScores.append(
                GrooPillarScore(
                    pillar: pillar,
                    average: (avg * 10).rounded() / 10,
                    lowestTrait: lowest?.trait ?? pillar.title
                )
            )
        }
        let overall = pillarScores.map(\.average).reduce(0, +) / Double(max(pillarScores.count, 1))
        let rounded = (overall * 10).rounded() / 10
        return GrooDiagnosticResult(
            overall: rounded,
            nickname: nickname(for: rounded, pillars: pillarScores),
            summary: summary(for: rounded, pillars: pillarScores),
            pillars: pillarScores,
            completedAt: Date()
        )
    }

    private static func nickname(for overall: Double, pillars: [GrooPillarScore]) -> String {
        let strongest = pillars.max(by: { $0.average < $1.average })?.pillar
        if overall < 2.6 { return "Building Foundations" }
        if overall < 3.4 {
            switch strongest {
            case .communication: return "Patient-Centered Start"
            case .attitude: return "Steady Operations"
            case .relationships: return "Team Builder"
            case .execution: return "Revenue Watcher"
            default: return "Steady Practice"
            }
        }
        if overall < 4.2 {
            switch strongest {
            case .communication: return "Trusted Chairside"
            case .attitude: return "Efficient Operator"
            case .relationships: return "Aligned Team"
            case .execution: return "Strong Collections"
            default: return "Balanced Clinic"
            }
        }
        return "Clinic Momentum"
    }

    private static func summary(for overall: Double, pillars: [GrooPillarScore]) -> String {
        let weak = pillars.min(by: { $0.average < $1.average })
        let strong = pillars.max(by: { $0.average < $1.average })
        let weakTitle = weak?.pillar.title ?? "Practice"
        let strongTitle = strong?.pillar.title ?? "Billing"
        let trait = weak?.lowestTrait ?? "growth"
        return "Your overall clinic profile is \(String(format: "%.1f", overall))/5 (\(nickname(for: overall, pillars: pillars))). " +
            "You stand out in \(strongTitle), and your biggest opportunity is in \(weakTitle) " +
            "(especially \(trait)). \(GrooBrand.appName) will help you turn that into a concrete clinic action plan — " +
            "operational guidance only, not clinical treatment advice."
    }
}
