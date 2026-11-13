import Foundation

/// Der GO-Knopf: entscheidet zwischen Kraft, Dehnen und Meditation, damit es über die Woche ausgewogen bleibt.
/// Grundmischung etwa 60 % Kraft, 25 % Dehnen, 15 % Meditation. Was zuletzt zu kurz kam, wird wahrscheinlicher.
/// Viel Erschöpfung → mehr Dehnen, abends → mehr Ruhe, Meditation höchstens alle paar Stunden.
extension Store {

    static let kindTarget: [ActivityKind: Double] = [.strength: 0.6, .stretch: 0.25, .mind: 0.15]

    func hoursSinceKind(_ k: ActivityKind) -> Double {
        if let l = state.log.last(where: { !$0.isTest && $0.exercise?.kind == k }) { return (nowMs() - l.ts) / hourMs }
        return 999
    }

    func kindWeights() -> [ActivityKind: Double] {
        let since = nowMs() - 7 * dayMs
        let recent = state.log.filter { $0.ts >= since && !$0.isTest && $0.exercise != nil }
        let total = Double(recent.count)
        var w: [ActivityKind: Double] = [:]
        for (k, t) in Self.kindTarget {
            let share = total > 0 ? Double(recent.filter { $0.exercise?.kind == k }.count) / total : t
            w[k] = max(0.03, t + (t - share))
        }

        // Erschöpfung: je mehr Muskeln platt sind, desto weniger Kraft und desto mehr Dehnen
        let f = fatigue()
        let ms = Muscle.allCases
        let avgF = ms.reduce(0.0) { $0 + min(1, f[$1] ?? 0) } / Double(ms.count)
        w[.strength, default: 0] *= max(0.15, 1 - avgF * 1.2)
        w[.stretch, default: 0] *= 1 + avgF

        // Meditation nicht mehrmals kurz hintereinander, nach langer Pause eher
        let hm = hoursSinceKind(.mind)
        if hm < 3 { w[.mind] = 0.01 } else if hm > 20 { w[.mind, default: 0] *= 1.8 }

        // Abends eher Ruhe
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 19 || hour < 6 {
            w[.mind, default: 0] *= 1.5
            w[.stretch, default: 0] *= 1.3
            w[.strength, default: 0] *= 0.7
        }

        // Nicht zweimal Dehnen direkt hintereinander
        if let le = state.lastEx, Exercise.byId[le]?.kind == .stretch { w[.stretch, default: 0] *= 0.4 }
        return w
    }

    func pick(excluding: String? = nil) -> (ex: Exercise, boss: Bool) {
        var w = kindWeights()
        // "Passt gerade nicht" bei Dehnen oder Meditation: dann etwas anderes
        if let id = excluding, let k = Exercise.byId[id]?.kind, k != .strength { w[k] = 0 }
        let total = w.values.reduce(0, +)
        var r = Double.random(in: 0..<max(total, 0.0001))
        var kind: ActivityKind = .strength
        for k in [ActivityKind.strength, .stretch, .mind] {
            r -= w[k] ?? 0
            if r < 0 { kind = k; break }
        }
        switch kind {
        case .strength: return pickStrength(excluding: excluding)
        case .stretch: return (pickStretch(excluding: excluding), false)
        case .mind: return (Exercise.byId["meditation"] ?? pickStretch(excluding: excluding), false)
        }
    }

    /// Dehnübung: am liebsten eine, die erschöpfte Muskeln entlastet und lange nicht dran war
    func pickStretch(excluding: String? = nil) -> Exercise {
        let f = fatigue()
        let cands = pool.filter { $0.kind == .stretch && $0.id != excluding }
        let scored = cands.map { ex -> (Exercise, Double) in
            let relief = ex.relieves.reduce(0.0) { $0 + min(1, f[$1] ?? 0) }
            let s = min(1, hoursSince(ex.id) / 24) + 0.6 * relief + Double.random(in: 0..<0.25)
            return (ex, s)
        }
        return scored.max { $0.1 < $1.1 }?.0 ?? Exercise.all[0]
    }

    // MARK: Biomarker für die Laborakte

    /// Wochenwerte mit echten Einheiten und festen Zielen; Erholung ist ein Zustand (0…1)
    struct Biomarkers {
        static let strengthTarget = 15
        static let stretchTarget = 7
        static let mindTarget = 35
        static let daysTarget = 7
        var strengthSets: Int
        var stretchCount: Int
        var neuroMinutes: Int
        var activeDays: Int
        var regeneration: Double
    }

    func biomarkers() -> Biomarkers {
        let since = nowMs() - 7 * dayMs
        let recent = state.log.filter { $0.ts >= since }
        let ms = Muscle.allCases
        let f = fatigue()
        let reg = 1 - ms.reduce(0.0) { $0 + min(1, f[$1] ?? 0) } / Double(ms.count)
        return Biomarkers(
            strengthSets: recent.filter { $0.exercise?.kind == .strength }.count,
            stretchCount: recent.filter { $0.exercise?.kind == .stretch }.count,
            neuroMinutes: recent.filter { $0.exercise?.kind == .mind }.reduce(0) { $0 + $1.actual } / 60,
            activeDays: Set(recent.map { startOfDay($0.ts) }).count,
            regeneration: reg
        )
    }
}
