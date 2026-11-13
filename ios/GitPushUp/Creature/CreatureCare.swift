import Foundation

/// Wie es dem Wesen geht, berechnet aus dem Protokoll. Nichts davon wird gespeichert.
///
/// Wachstum: jede Einheit bringt Punkte (Kraft 1, Teilprobe 0,6, Boss 1,2, Dehnen 1, Meditation je nach Minuten).
/// Die ersten 5 Punkte eines Tages zählen voll, jeder weitere noch 30 %: jede Übung bringt etwas, Regelmäßigkeit mehr.
/// Serienbonus: pro Tag in Folge +5 %, höchstens +50 % (ab Tag 11).
/// Rund 320 Punkte = ausgewachsen, also etwa zwei Monate mit 4 Einheiten am Tag und laufender Serie.
/// Jeder Punkt wird über 3 Stunden eingeblendet: das Wesen springt nie, die Zahl läuft sichtbar hoch.
///
/// Prägung (Tonus, Elastizität, Resonanz): Punkte der jeweiligen Art mit langsamem Vergessen (Zeitkonstante 3 Wochen).
/// Die Sättigung ist der Stand, der sich bei regelmäßiger Pflege einpendelt; darüber wächst die Prägung nicht weiter.
struct CreatureVitals {
    var g: Double             // Wachstum 0…1
    var strengthPts: Double   // Prägungspunkte
    var stretchPts: Double
    var mindPts: Double
    var health: Double        // 0…1
    var ageDays: Int
    var todayPts: Double      // heute verdiente Wachstumspunkte (mit Bonus)
    var streakBonus: Double   // aktueller Serienbonus, z. B. 0,2 = +20 %

    var strength: Double { min(1, strengthPts / CreatureModel.strengthGoal) }
    var stretch: Double { min(1, stretchPts / CreatureModel.stretchGoal) }
    var mind: Double { min(1, mindPts / CreatureModel.mindGoal) }
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
    static let growthGoal = 320.0
    static let fullPerDay = 5.0
    static let extraFactor = 0.3
    static let bonusPerDay = 0.05
    static let bonusMax = 0.5
    static let absorbMs = 3 * hourMs
    static let memoryMs = 21 * dayMs
    static let healthMs = 36 * hourMs
    // Sättigung: so viel steht bei regelmäßiger Pflege (~3–4 Einheiten am Tag nach GO-Mischung) im Gedächtnis
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
            return CreatureVitals(g: 0, strengthPts: 0, stretchPts: 0, mindPts: 0, health: 1, ageDays: 0, todayPts: 0, streakBonus: 0)
        }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
        var used: [Date: Double] = [:]
        var growth = 0.0, sk = 0.0, st = 0.0, mi = 0.0, today = 0.0
        // Serie pro Tag: wie viele Tage in Folge (bis einschließlich diesem) etwas gemacht wurde
        var streakAt: [Date: Int] = [:]
        var lastDay: Date? = nil
        var run = 0
        // Frisch geschlüpft ist es munter
        var hp = 4 * exp(-max(0, now - c.born) / CreatureModel.healthMs)
        for l in state.log where l.ts >= c.born && l.ts <= now {
            let (kind, w) = CreatureModel.weight(l)
            if w <= 0 { continue }
            let age = now - l.ts
            let absorb = smoothstep(0, CreatureModel.absorbMs, age)
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: l.ts / 1000))
            if streakAt[day] == nil {
                if let ld = lastDay, let next = cal.date(byAdding: .day, value: 1, to: ld), next == day { run += 1 } else { run = 1 }
                streakAt[day] = run
                lastDay = day
            }
            let bonus = 1 + min(CreatureModel.bonusMax, CreatureModel.bonusPerDay * Double((streakAt[day] ?? 1) - 1))
            let u = used[day] ?? 0
            let full = max(0, min(w, CreatureModel.fullPerDay - u))
            let pts = (full + (w - full) * CreatureModel.extraFactor) * bonus
            used[day] = u + w
            growth += pts * absorb
            if day == todayStart { today += pts }
            let mem = w * absorb * exp(-age / CreatureModel.memoryMs)
            switch kind {
            case .strength: sk += mem
            case .stretch: st += mem
            case .mind: mi += mem
            }
            hp += w * smoothstep(0, 0.25 * hourMs, age) * exp(-age / CreatureModel.healthMs)
        }
        // Bonus, der jetzt gerade gilt (Serie bis heute oder gestern)
        var bonusNow = 0.0
        if let ld = lastDay, let s = streakAt[ld] {
            let gap = cal.dateComponents([.day], from: ld, to: todayStart).day ?? 99
            if gap <= 1 { bonusNow = min(CreatureModel.bonusMax, CreatureModel.bonusPerDay * Double(s - (gap == 0 ? 1 : 0))) }
        }
        return CreatureVitals(
            g: min(1, growth / CreatureModel.growthGoal),
            strengthPts: sk, stretchPts: st, mindPts: mi,
            health: min(1, hp / 4.5),
            ageDays: max(0, Int((now - c.born) / dayMs)),
            todayPts: today, streakBonus: bonusNow
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
            return sums[d] ?? 0
        }
    }

    /// Hirnströme: wie ruhig, abhängig davon, wann zuletzt meditiert wurde (1 = gerade eben, fällt über ~1,5 Tage ab)
    var eegCalm: Double {
        let h = hoursSinceKind(.mind)
        return h >= 999 ? 0 : exp(-h / 30)
    }
}

