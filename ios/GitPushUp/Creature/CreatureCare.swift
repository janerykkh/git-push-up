import Foundation

/// Wie es dem Wesen geht, berechnet aus dem Protokoll. Nichts davon wird gespeichert.
///
/// Wachstum ist eine Simulation über den ganzen Verlauf seit dem Schlüpfen. Jede Übung bringt Punkte, abhängig von
/// Art und Schwere der Übung, ob sie geschafft wurde, wie belastet die Muskelgruppe schon war, wie viel an dem Tag schon
/// passiert ist (zu viel bringt kaum noch etwas), der laufenden Serie, erfüllten Wochenzielen und einer kleinen
/// Streuung pro Übung. Das Wesen hat einen Grundumsatz, und nach zwei Tagen Pause baut es zunehmend ab: es kann schrumpfen.
/// Neue Punkte werden über 90 Minuten eingeblendet, damit nichts springt.
struct CreatureVitals {
    var g: Double             // Wachstum 0…1
    var ratePerDay: Double    // Netto-Wachstum der letzten Tage in Punkten pro Tag
    var etaDays: Double?      // so lange bis 100 %, wenn es so weitergeht (nil: wächst nicht)
    var shares: (s: Double, t: Double, m: Double)  // Anteile Tonus/Flexibilität/Resonanz, Summe 1
    var health: Double        // 0…1
    var ageDays: Int
    var todayCount: Int       // heute absolvierte Übungen
    var streakBonus: Double

    /// Für das Aussehen: Anteile mal drei (ausgewogen = 1) und gedeckelt durch das Wachstum
    var traits: Traits {
        Traits.from(strength: min(1, 3 * shares.s * g), stretch: min(1, 3 * shares.t * g), mind: min(1, 3 * shares.m * g))
    }
    var vigor: Double { 0.3 + 0.7 * min(1, health / 0.6) }

    /// Wachstumstempo relativ zu gutem Training: >0 wächst, ~0 steht, <0 schrumpft
    var trend: Double { ratePerDay / CreatureModel.goodRate }

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
    static let growthGoal = 420.0
    static let goodRate = 7.0                // Punkte pro Tag bei gutem, regelmäßigem Training
    static let absorbMs = 1.5 * hourMs
    static let shareMemoryMs = 30 * dayMs
    static let healthMs = 36 * hourMs
    static let upkeepPerDay = 0.4            // Grundumsatz
    static let graceMs = 48 * hourMs         // so lange Pause ohne Abbau
    static let decayPerDay = 0.006 * growthGoal
    static let weeklyBonus = 3.0
    // Mischung, die GO anstrebt: daran gemessen ergibt "immer GO" etwa 33/33/33
    static let mix: [ActivityKind: Double] = [.strength: 0.6, .stretch: 0.25, .mind: 0.15]

    static func weight(_ l: LogEntry) -> (ActivityKind, Double) {
        guard let ex = l.exercise else { return (.strength, 0) }
        if l.isTest { return (.strength, 1) }
        switch ex.kind {
        case .strength: return (.strength, l.isBoss ? 1.2 : (l.done ? 1 : 0.6))
        case .stretch: return (.stretch, l.done ? 1 : 0.6)
        case .mind: return (.mind, min(1.2, Double(l.actual) / 300))
        }
    }

    /// Feste Streuung pro Eintrag (0,85…1,15), damit sich nichts genau vorhersagen lässt
    static func jitter(_ id: String) -> Double {
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return 0.85 + 0.3 * Double(h % 10000) / 10000
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

    /// Muss die Brutstätte gezeigt werden? (noch kein Wesen oder nur ein automatisch gelegtes)
    var needsHatching: Bool { state.creature?.hatched != true }

    /// Neues Ei: zurück in die Brutstätte (das Trainingsprotokoll bleibt)
    func layNewEgg() {
        state.creature = nil
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

    struct GrowthSim { var points: Double; var kind: [ActivityKind: Double]; var pending: Double }

    /// Wachstumspunkte zu einem Zeitpunkt, durchgerechnet ab dem Schlüpfen
    func simulateGrowth(until now: Millis) -> GrowthSim {
        guard let c = state.creature else { return GrowthSim(points: 0, kind: [:], pending: 0) }
        let cal = Calendar.current
        let M = CreatureModel.self
        var G = 0.0, pending = 0.0
        var kind: [ActivityKind: Double] = [:]
        var last = c.born
        var dayUnits: [Date: Double] = [:]
        var streakAt: [Date: Int] = [:]
        var lastDay: Date? = nil
        var run = 0
        var recentCat: [(Millis, String)] = []
        // Wochenziele: Kraftsätze, Dehnen, Meditationsminuten, aktive Tage
        var week: [String: (s: Int, t: Int, m: Int, days: Set<Date>, done: Set<Int>)] = [:]

        func idle(_ from: Millis, _ to: Millis) {
            guard to > from else { return }
            G -= M.upkeepPerDay * (to - from) / dayMs
            let start = from + M.graceMs
            if to > start {
                // Abbau wird mit der Dauer der Pause stärker (bis 2,5-fach)
                var t = start
                while t < to {
                    let step = min(6 * hourMs, to - t)
                    let f = min(2.5, 1 + (t - start) / (3 * dayMs))
                    G -= M.decayPerDay * f * step / dayMs
                    t += step
                }
            }
            G = max(0, G)
        }

        for l in state.log where l.ts >= c.born && l.ts <= now {
            let (k, w) = M.weight(l)
            guard w > 0, let ex = l.exercise else { continue }
            idle(last, l.ts)
            last = l.ts
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: l.ts / 1000))
            if streakAt[day] == nil {
                if let ld = lastDay, let next = cal.date(byAdding: .day, value: 1, to: ld), next == day { run += 1 } else { run = 1 }
                streakAt[day] = run
                lastDay = day
            }
            // Schwere: Ganzkörperübungen zählen mehr
            let load = ex.muscles.values.reduce(0, +)
            let difficulty = k == .strength ? 0.85 + 0.15 * min(2, load) : 1
            // Vorbelastung: dieselbe Kategorie in den letzten 8 Stunden
            recentCat.removeAll { l.ts - $0.0 > 8 * hourMs }
            let same = recentCat.filter { $0.1 == ex.cat.rawValue }.count
            let preload = 1 / (1 + 0.3 * Double(same))
            recentCat.append((l.ts, ex.cat.rawValue))
            // Tagesmenge: die ersten fünf voll, danach schnell weniger
            let u = dayUnits[day] ?? 0
            dayUnits[day] = u + w
            let dayF = u < 5 ? 1 : 0.3 / (1 + 0.25 * (u - 5))
            let streakF = 1 + min(0.5, 0.05 * Double((streakAt[day] ?? 1) - 1))
            var pts = w * difficulty * preload * dayF * streakF * M.jitter(l.id)
            // Wochenziele: einmal pro Woche und Ziel ein Bonus, sobald erreicht
            let wk = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date(timeIntervalSince1970: l.ts / 1000))
            let key = "\(wk.yearForWeekOfYear ?? 0)-\(wk.weekOfYear ?? 0)"
            var W = week[key] ?? (s: 0, t: 0, m: 0, days: Set<Date>(), done: Set<Int>())
            switch k {
            case .strength: W.s += 1
            case .stretch: W.t += 1
            case .mind: W.m += l.actual / 60
            }
            W.days.insert(day)
            let reached = [W.s >= Store.Biomarkers.strengthTarget, W.t >= Store.Biomarkers.stretchTarget,
                           W.m >= Store.Biomarkers.mindTarget, W.days.count >= Store.Biomarkers.daysTarget]
            for (i, ok) in reached.enumerated() where ok && !W.done.contains(i) {
                W.done.insert(i); pts += M.weeklyBonus
            }
            week[key] = W
            G += pts
            kind[k, default: 0] += pts * exp(-(now - l.ts) / M.shareMemoryMs)
            pending += pts * (1 - smoothstep(0, M.absorbMs, now - l.ts))
        }
        idle(last, now)
        return GrowthSim(points: min(M.growthGoal, G), kind: kind, pending: pending)
    }

    func vitals(at now: Millis = nowMs()) -> CreatureVitals {
        guard let c = state.creature else {
            return CreatureVitals(g: 0, ratePerDay: 0, etaDays: nil, shares: (1.0 / 3, 1.0 / 3, 1.0 / 3), health: 1, ageDays: 0, todayCount: 0, streakBonus: 0)
        }
        let M = CreatureModel.self
        let sim = simulateGrowth(until: now)
        let shown = max(0, sim.points - sim.pending)
        // Tempo: Netto-Änderung der letzten 5 Tage (bei jungen Wesen seit dem Schlüpfen)
        let span = min(5 * dayMs, max(dayMs, now - c.born))
        let before = simulateGrowth(until: now - span)
        let rate = (sim.points - (now - span < c.born ? 0 : before.points)) / (span / dayMs)
        var eta: Double? = nil
        if rate > 0.05 { eta = max(0, (M.growthGoal - sim.points) / rate) }

        // Anteile, gemessen an der Mischung, die GO anstrebt
        var rel: [ActivityKind: Double] = [:]
        for (k, t) in M.mix { rel[k] = (sim.kind[k] ?? 0) / t }
        let tot = rel.values.reduce(0, +)
        let shares = tot > 0 ? ((rel[.strength] ?? 0) / tot, (rel[.stretch] ?? 0) / tot, (rel[.mind] ?? 0) / tot) : (1.0 / 3, 1.0 / 3, 1.0 / 3)

        // Zustand: wie viel in den letzten ~2 Tagen los war
        var hp = 4 * exp(-max(0, now - c.born) / M.healthMs)
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date(timeIntervalSince1970: now / 1000)).timeIntervalSince1970 * 1000
        var today = 0
        for l in state.log where l.ts <= now && now - l.ts < 7 * dayMs {
            let (_, w) = M.weight(l)
            hp += w * smoothstep(0, 0.25 * hourMs, now - l.ts) * exp(-(now - l.ts) / M.healthMs)
            if l.ts >= todayStart { today += 1 }
        }
        let st = streak
        let bonus = min(0.5, 0.05 * Double(max(0, st - (today > 0 ? 1 : 0))))
        return CreatureVitals(
            g: shown / M.growthGoal, ratePerDay: rate, etaDays: eta,
            shares: (shares.0, shares.1, shares.2),
            health: min(1, hp / 4.5),
            ageDays: max(0, Int((now - c.born) / dayMs)),
            todayCount: today, streakBonus: bonus
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

