import Foundation

/// Wie es dem Wesen geht, berechnet aus dem Protokoll. Nichts davon wird gespeichert.
///
/// Wachstum: jede Einheit seit dem Schlüpfen bringt Wachstumspunkte (Kraft 1, Teilprobe 0,6, Boss 1,2, Dehnen 1,
/// Meditation je nach Minuten). Pro Tag zählen höchstens 5 Punkte: Regelmäßigkeit schlägt Menge.
/// Rund 230 Punkte = ausgewachsen, also etwa zwei Monate mit 4 Einheiten am Tag.
/// Jeder Punkt wird über 10 Stunden eingeblendet: das Wesen springt nie, es wächst zwischen zwei Blicken nur ein kleines Stück.
///
/// Prägung: was in den letzten Wochen überwiegt (Kraft, Dehnen, Geist), mit langsamem Vergessen (Zeitkonstante 3 Wochen).
/// Zustand: wie viel in den letzten ~2 Tagen los war. Wachstum geht nie verloren; vernachlässigt wird es nur blass und schläfrig.
struct CreatureVitals {
    var g: Double             // Wachstum 0…1
    var strength: Double      // Pflege-Niveau 0…1
    var stretch: Double
    var mind: Double
    var health: Double        // 0…1
    var ageDays: Int
    var traits: Traits { Traits.from(strength: strength, stretch: stretch, mind: mind) }
    /// Farbkraft: unter ~60 % Zustand werden die Farben blasser
    var vigor: Double { 0.3 + 0.7 * min(1, health / 0.6) }

    var stage: String {
        switch g {
        case ..<0.12: return "ZELLE"
        case ..<0.3: return "KEIM"
        case ..<0.55: return "LARVE"
        case ..<0.8: return "JUNGTIER"
        default: return "KREATUR"
        }
    }
    var healthLabel: String {
        switch health {
        case 0.7...: return "MUNTER"
        case 0.4...: return "WACH"
        case 0.15...: return "MATT"
        default: return "SCHLÄFT"
        }
    }
}

enum CreatureModel {
    static let growthGoal = 230.0
    static let dailyCap = 5.0
    static let absorbMs = 10 * hourMs
    static let memoryMs = 21 * dayMs
    static let healthMs = 36 * hourMs
    // Niveau 100 %: so viel steht bei regelmäßiger Pflege (~3–4 Einheiten am Tag nach GO-Mischung) im Gedächtnis
    static let strengthGoal = 38.0
    static let stretchGoal = 15.0
    static let mindGoal = 9.0

    static func weight(_ l: LogEntry) -> (ActivityKind, Double) {
        guard let ex = l.exercise else { return (.strength, 0) }
        if l.isTest { return (.strength, 1) }
        switch ex.kind {
        case .strength: return (.strength, l.isBoss ? 1.2 : (l.done ? 1 : 0.6))
        case .stretch: return (.stretch, l.done ? 1 : 0.6)
        case .mind: return (.mind, min(1.2, Double(l.actual) / 300))
        }
    }

    static func syllableName(_ seed: Int) -> String {
        var r = Mulberry32(seed &+ 4242)
        let on = ["k", "v", "z", "th", "m", "r", "sh", "x", "l", "n", "q", "dr", "ph", "y", "gr", "b"]
        let nu = ["a", "o", "u", "e", "i", "y", "ae", "oo", "ia", "ui"]
        let co = ["", "", "", "n", "x", "l", "sk", "th", "m", "r"]
        let count = r.next() < 0.6 ? 2 : (r.next() < 0.7 ? 1 : 3)
        var s = ""
        for i in 0..<count {
            s += r.pick(on) + r.pick(nu)
            if i == count - 1 || r.next() < 0.3 { s += r.pick(co) }
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

extension Store {

    /// Beim ersten Start ein Ei legen
    func ensureCreature() {
        guard state.creature == nil else { return }
        let seed = Int.random(in: 1...999_998)
        state.creature = CreatureState(seed: seed, born: nowMs(), name: CreatureModel.syllableName(seed))
        save()
    }

    /// Neues Ei: anderes Wesen, Wachstum beginnt von vorn (das Trainingsprotokoll bleibt)
    func layNewEgg() {
        let seed = Int.random(in: 1...999_998)
        let now = nowMs()
        state.creature = CreatureState(seed: seed, born: now, name: CreatureModel.syllableName(seed), updated: now)
        save()
    }

    func renameCreature(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, var c = state.creature else { return }
        c.name = String(n.prefix(18))
        c.updated = nowMs()
        state.creature = c
        save()
    }

    func vitals(at now: Millis = nowMs()) -> CreatureVitals {
        guard let c = state.creature else {
            return CreatureVitals(g: 0, strength: 0, stretch: 0, mind: 0, health: 1, ageDays: 0)
        }
        let cal = Calendar.current
        var used: [Date: Double] = [:]
        var growth = 0.0, sk = 0.0, st = 0.0, mi = 0.0
        // Frisch geschlüpft ist es munter
        var hp = 4 * exp(-max(0, now - c.born) / CreatureModel.healthMs)
        for l in state.log where l.ts >= c.born && l.ts <= now {
            let (kind, w) = CreatureModel.weight(l)
            if w <= 0 { continue }
            let age = now - l.ts
            let absorb = smoothstep(0, CreatureModel.absorbMs, age)
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: l.ts / 1000))
            let u = used[day] ?? 0
            let add = max(0, min(w, CreatureModel.dailyCap - u))
            used[day] = u + add
            growth += add * absorb
            let mem = w * absorb * exp(-age / CreatureModel.memoryMs)
            switch kind {
            case .strength: sk += mem
            case .stretch: st += mem
            case .mind: mi += mem
            }
            hp += w * smoothstep(0, 0.25 * hourMs, age) * exp(-age / CreatureModel.healthMs)
        }
        return CreatureVitals(
            g: min(1, growth / CreatureModel.growthGoal),
            strength: min(1, sk / CreatureModel.strengthGoal),
            stretch: min(1, st / CreatureModel.stretchGoal),
            mind: min(1, mi / CreatureModel.mindGoal),
            health: min(1, hp / 4.5),
            ageDays: max(0, Int((now - c.born) / dayMs))
        )
    }

    /// Pflegepunkte pro Tag (gedeckelt auf 5), die letzten `n` Tage, ältester zuerst. nil = vor dem Schlüpfen.
    func carePoints(days n: Int) -> [Double?] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let born = state.creature.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0.born / 1000)) } ?? today
        var sums: [Date: Double] = [:]
        let from = cal.date(byAdding: .day, value: -(n - 1), to: today) ?? today
        for l in state.log where l.ts >= from.timeIntervalSince1970 * 1000 {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: l.ts / 1000))
            sums[d, default: 0] += CreatureModel.weight(l).1
        }
        return (0..<n).map { i in
            let d = cal.date(byAdding: .day, value: i - (n - 1), to: today) ?? today
            if d < born { return nil }
            return min(CreatureModel.dailyCap, sums[d] ?? 0)
        }
    }

    /// Hirnströme: wie ruhig, abhängig davon, wann zuletzt meditiert wurde (1 = gerade eben, fällt über ~1,5 Tage ab)
    var eegCalm: Double {
        let h = hoursSinceKind(.mind)
        return h >= 999 ? 0 : exp(-h / 30)
    }
}

