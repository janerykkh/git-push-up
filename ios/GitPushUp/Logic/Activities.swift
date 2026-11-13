import Foundation

/// Der GO-Knopf: kein Zufall. Zu jedem Zeitpunkt gibt es eine beste Übung, berechnet aus dem Verlauf.
/// Erst die Art (Kraft, Dehnen, Meditation): angestrebt sind etwa 60/25/15 %, es kommt die Art, die gemessen daran
/// am weitesten hinterherhinkt. Erschöpfung, Tageszeit und Abstand zur letzten Meditation verschieben das.
/// Dann die beste Übung dieser Art: frische Muskeln, lange nicht gemacht; Dehnen bevorzugt, was die zuletzt
/// belasteten Muskeln entlastet. "Passt gerade nicht" nimmt die nächstbeste, schließen ändert nichts.
extension Store {

    static let kindTarget: [ActivityKind: Double] = [.strength: 0.6, .stretch: 0.25, .mind: 0.15]

    func hoursSinceKind(_ k: ActivityKind) -> Double {
        if let l = state.log.last(where: { !$0.isTest && $0.exercise?.kind == k }) { return (nowMs() - l.ts) / hourMs }
        return 999
    }

    /// Angestrebter Anteil je Art, angepasst an Erschöpfung, Tageszeit und Pausen
    func kindTargets() -> [ActivityKind: Double] {
        var w = Self.kindTarget
        let f = fatigue()
        let ms = Muscle.allCases
        let avgF = ms.reduce(0.0) { $0 + min(1, f[$1] ?? 0) } / Double(ms.count)
        w[.strength, default: 0] *= max(0.15, 1 - avgF * 1.2)
        w[.stretch, default: 0] *= 1 + avgF
        let hm = hoursSinceKind(.mind)
        if hm < 3 { w[.mind] = 0.001 } else if hm > 20 { w[.mind, default: 0] *= 1.8 }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 19 || hour < 6 {
            w[.mind, default: 0] *= 1.5
            w[.stretch, default: 0] *= 1.3
            w[.strength, default: 0] *= 0.7
        }
        if let le = state.lastEx, Exercise.byId[le]?.kind == .stretch { w[.stretch, default: 0] *= 0.4 }
        return w
    }

    /// Reihenfolge der Arten: wer gemessen an seinem Ziel am wenigsten dran war, kommt zuerst
    func kindOrder() -> [ActivityKind] {
        let since = nowMs() - 7 * dayMs
        let recent = state.log.filter { $0.ts >= since && !$0.isTest }
        let t = kindTargets()
        let prio: [(ActivityKind, Double)] = [ActivityKind.strength, .stretch, .mind].map { k in
            let n = Double(recent.filter { $0.exercise?.kind == k }.count)
            return (k, (t[k] ?? 0) / (n + 1))
        }
        return prio.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// Alle Kandidaten in der Reihenfolge, in der GO sie anbieten würde
    func ranking() -> [(ex: Exercise, boss: Bool)] {
        let f = fatigue()
        var out: [(ex: Exercise, boss: Bool)] = []
        for k in kindOrder() {
            switch k {
            case .strength:
                var ranked = strengthPool.filter { $0.id != state.lastEx }.map { ($0, score($0, f)) }.sorted { $0.1 > $1.1 }
                if ranked.isEmpty { ranked = strengthPool.map { ($0, 0.0) } }
                // Boss-Satz unter den guten Optionen? Dann der zuerst.
                if let best = ranked.first, let i = ranked.firstIndex(where: { $0.1 >= best.1 - 0.2 && shouldBoss($0.0, fatigue: f) }) {
                    out.append((ranked[i].0, true))
                    ranked.remove(at: i)
                }
                out += ranked.map { ($0.0, false) }
            case .stretch:
                out += stretchRanking(f).map { ($0, false) }
            case .mind:
                if let m = Exercise.byId["meditation"] { out.append((m, false)) }
            }
        }
        return out
    }

    func pick(excluding: String? = nil) -> (ex: Exercise, boss: Bool) {
        let now = nowMs()
        if let id = excluding { skipped[id] = now }
        skipped = skipped.filter { now - $0.value < 45 * 60_000 }
        let r = ranking()
        return r.first { skipped[$0.ex.id] == nil } ?? r.first ?? (Exercise.all[0], false)
    }

    /// Dehnübungen: am liebsten eine, die gerade belastete Muskeln entlastet und lange nicht dran war
    func stretchRanking(_ f: [Muscle: Double]) -> [Exercise] {
        let cands = pool.filter { $0.kind == .stretch }
        let scored = cands.map { ex -> (Exercise, Double) in
            let relief = ex.relieves.reduce(0.0) { $0 + min(1, f[$1] ?? 0) }
            let s = min(1, hoursSince(ex.id) / 24) + 0.6 * relief - (ex.id == state.lastEx ? 2 : 0)
            return (ex, s)
        }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    func pickStretch(excluding: String? = nil) -> Exercise {
        stretchRanking(fatigue()).first { $0.id != excluding } ?? Exercise.all[0]
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
