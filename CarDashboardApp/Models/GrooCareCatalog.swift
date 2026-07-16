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
        case .communication: return "Communication"
        case .attitude: return "Attitude"
        case .relationships: return "Relationships"
        case .execution: return "Execution"
        case .foundation: return "YOU"
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
        case .communication: return "Clarity and influence in decisions"
        case .attitude: return "Mindset under pressure and setbacks"
        case .relationships: return "Trust network and reputation"
        case .execution: return "Decide and deliver with incomplete information"
        case .foundation: return "Discipline, purpose, and balance"
        }
    }

    var growthHint: String {
        switch self {
        case .communication: return "Practice saying what you need clearly in your next important conversation."
        case .attitude: return "When a setback appears, name the fact and the next small step."
        case .relationships: return "Invest in a key relationship before you need it."
        case .execution: return "Pick a pending decision and close it with a concrete deadline."
        case .foundation: return "Protect a short block of energy (sleep, focus, or purpose) this week."
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
            return "Talk to GROO and define a concrete plan for this week."
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
        if overall < 2.6 { return "Emerging Foundation" }
        if overall < 3.4 {
            switch strongest {
            case .communication: return "Quiet Communicator"
            case .attitude: return "Steady Baseline"
            case .relationships: return "Relational Builder"
            case .execution: return "Quiet Executor"
            default: return "Steady Baseline"
            }
        }
        if overall < 4.2 {
            switch strongest {
            case .communication: return "Rising Communicator"
            case .attitude: return "Resilient Climber"
            case .relationships: return "Trusted Connector"
            case .execution: return "Decisive Operator"
            default: return "Balanced Professional"
            }
        }
        return "CARE Momentum"
    }

    private static func summary(for overall: Double, pillars: [GrooPillarScore]) -> String {
        let weak = pillars.min(by: { $0.average < $1.average })
        let strong = pillars.max(by: { $0.average < $1.average })
        let weakTitle = weak?.pillar.title ?? "YOU"
        let strongTitle = strong?.pillar.title ?? "Execution"
        let trait = weak?.lowestTrait ?? "growth"
        return "Your overall profile is \(String(format: "%.1f", overall))/5 (\(nickname(for: overall, pillars: pillars))). " +
            "You stand out in \(strongTitle), and your biggest area of professional friction is in \(weakTitle) " +
            "(especially \(trait)). GROO will help you turn that friction into a concrete plan — " +
            "not therapy or clinical advice: career mentorship and human skills."
    }
}
