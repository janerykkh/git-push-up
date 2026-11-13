import Foundation

/// Der Trainer: schätzt Maxima aus dem Rekordtag, setzt Ziele, passt sie wöchentlich an,
/// rechnet Erschöpfung pro Muskel und wählt die nächste Übung.
extension Store {

    // MARK: Maximum & Ziele

    func markerValue(_ id: String) -> Int {
        if let v = state.trainer.baseline?[id] { return v }
        return Marker.all.first { $0.id == id }?.fallback ?? 10
    }

    func estMax(_ ex: Exercise) -> Double {
        guard let m = ex.marker else { return Double(ex.base) / Model.workFraction }
        return max(1, Double(markerValue(m)) * ex.factor)
    }

    func roundTarget(_ ex: Exercise, _ v: Double) -> Int {
        if ex.unit == .sec { return max(10, Int((v / 5).rounded()) * 5) }
        return max(1, Int(v.rounded()))
    }

    func targetFor(_ ex: Exercise) -> Int {
        if let st = state.trainer.targets[ex.id] { return st.t }
        return roundTarget(ex, estMax(ex) * Model.workFraction)
    }

    /// Passt ein Ziel nicht in etwa eine Minute (cap), kommt pro Mal nur ein Satz; der Rest bei späteren Malen
    func perTime(_ ex: Exercise) -> Int {
        let target = targetFor(ex)
        guard let cap = ex.cap, target > cap else { return target }
        let n = Int((Double(target) / Double(cap)).rounded(.up))
        var per = Int((Double(target) / Double(n)).rounded(.up))
        if ex.unit == .sec { per = Int((Double(per) / 5).rounded(.up)) * 5 }
        return per
    }

    /// Einmal pro Woche: fast immer geschafft → +10 %, mehrmals nicht geschafft → −10 %
    func weeklyReview() {
        let now = nowMs()
        var changed = false
        for ex in strengthPool {
            guard var st = state.trainer.targets[ex.id] else {
                state.trainer.targets[ex.id] = TargetState(t: targetFor(ex), reviewed: now, change: 0)
                changed = true
                continue
            }
            if now - st.reviewed < 7 * dayMs { continue }
            let recent = state.log.filter { $0.ex == ex.id && !$0.isTest && $0.ts >= st.reviewed }
            let succ = recent.filter { $0.done }.count
            let fail = recent.count - succ
            let old = st.t
            if recent.count >= 2 && Double(succ) / Double(recent.count) >= 0.8 {
                let cap = roundTarget(ex, estMax(ex) * 0.85)
                let step = ex.unit == .sec ? 5.0 : 1.0
                st.t = max(old, min(cap, roundTarget(ex, max(Double(st.t) * 1.1, Double(st.t) + step))))
            } else if fail >= 2 {
                st.t = roundTarget(ex, Double(st.t) * 0.9)
            }
            st.change = st.t - old
            st.reviewed = now
            state.trainer.targets[ex.id] = st
            changed = true
        }
        if changed { saveTrainer() }
    }

    var nextReviewDays: Int {
        let ts = state.trainer.targets.values.map { $0.reviewed }
        guard let first = ts.min() else { return 7 }
        return max(0, Int(((first + 7 * dayMs - nowMs()) / dayMs).rounded(.up)))
    }

    var hasBaseline: Bool { state.trainer.baselineDate > 0 }
    var recordDue: Bool { !hasBaseline || nowMs() - state.trainer.baselineDate >= Model.recordEveryDays * dayMs }
    var daysToRecord: Int {
        max(0, Int(((state.trainer.baselineDate + Model.recordEveryDays * dayMs - nowMs()) / dayMs).rounded(.up)))
    }

    /// Ziele aus den aktuellen Rekorden neu berechnen (nach Rekordtag oder Handeingabe)
    func recomputeTargets(keepReview: Bool) {
        let now = nowMs()
        for ex in pool {
            let reviewed = keepReview ? (state.trainer.targets[ex.id]?.reviewed ?? now) : now
            state.trainer.targets[ex.id] = TargetState(t: roundTarget(ex, estMax(ex) * Model.workFraction), reviewed: reviewed, change: 0)
        }
    }

    // MARK: Rekordtag

    func saveTest(_ marker: Marker, value: Int) {
        guard let ex = Exercise.byId[marker.id] else { return }
        state.trainer.pending[marker.id] = value
        state.log.append(LogEntry(id: LogEntry.newId(), ex: ex.id, cat: ex.cat.rawValue, target: 0,
                                  actual: value, done: true, test: true, ts: nowMs()))
        saveTrainer()
    }

    func finishRecordDay() {
        var b = state.trainer.baseline ?? [:]
        for (k, v) in state.trainer.pending { b[k] = v }
        state.trainer.baseline = b
        state.trainer.baselineDate = nowMs()
        state.trainer.pending = [:]
        recomputeTargets(keepReview: false)
        saveTrainer()
        Task { await autoBackup(force: true) }
    }

    func setRecords(_ values: [String: Int]) {
        var b = state.trainer.baseline ?? [:]
        for (k, v) in values where v > 0 { b[k] = v }
        state.trainer.baseline = b
        if !hasBaseline { state.trainer.baselineDate = nowMs() }
        recomputeTargets(keepReview: true)
        saveTrainer()
        Task { await autoBackup(force: true) }
    }

    // MARK: Erschöpfung

    /// Jeder Satz erschöpft einen Muskel relativ zu deinem Maximum; danach klingt das exponentiell ab
    /// (nach recoveryHours sind noch 10 % übrig).
    func fatigue(at t: Millis = nowMs()) -> [Muscle: Double] {
        var f: [Muscle: Double] = [:]
        for m in Muscle.allCases { f[m] = 0 }
        for l in state.log.reversed() {
            if t - l.ts > 7 * dayMs { break }
            if l.ts > t { continue }
            guard let ex = l.exercise else { continue }
            let rel = Double(l.actual) / estMax(ex)
            let h = (t - l.ts) / hourMs
            for (m, w) in ex.muscles {
                f[m, default: 0] += (w * rel * scale(m) / Model.fullEffort) * pow(10, -h / m.recoveryHours)
            }
        }
        return f
    }

    /// Persönlicher Faktor pro Muskel (1 = wie im Modell, >1 = ermüdet bei dir schneller)
    func scale(_ m: Muscle) -> Double { state.muscleScale[m.rawValue] ?? 1 }

    /// Lernt aus jedem Ergebnis: Nicht geschafft, obwohl die Hauptmuskeln als frisch galten → sie ermüden bei dir
    /// schneller als gedacht. Locker geschafft, obwohl sie als erschöpft galten → langsamer. Kleine Schritte, begrenzt.
    func calibrate(_ ex: Exercise, target: Int, actual: Int, done: Bool, before f: [Muscle: Double]) {
        guard target > 0 else { return }
        for m in ex.primary {
            let v = f[m] ?? 0
            var k = scale(m)
            if !done && v < 0.5 {
                let miss = 1 - Double(actual) / Double(target)
                k *= 1 + 0.12 * max(0, min(1, miss))
            } else if done && v >= 0.8 {
                k *= 0.96
            } else { continue }
            state.muscleScale[m.rawValue] = max(0.6, min(1.8, k))
        }
    }

    // MARK: Wochen-Belastung

    /// Belastung der letzten 7 Tage in "vollen Sätzen": ein Satz bis kurz vor die Grenze zählt etwa 1.
    /// 100 % = 6 solche Sätze pro Woche, ein guter Richtwert für Aufbau (Studien sehen ab etwa 4–10 harte Sätze pro Woche klare Effekte).
    static let weeklyHardSets = 6.0

    func weeklyLoad(at t: Millis = nowMs()) -> [Muscle: Double] {
        var load: [Muscle: Double] = [:]
        for m in Muscle.allCases { load[m] = 0 }
        for l in state.log.reversed() {
            if t - l.ts > 7 * dayMs { break }
            guard let ex = l.exercise else { continue }
            // Sätze weit vor der Grenze zählen weniger: Effekt wächst mit der Nähe zum Maximum
            let rel = min(1.2, Double(l.actual) / estMax(ex))
            let effort = pow(rel, 1.5)
            for (m, w) in ex.muscles { load[m, default: 0] += w * effort }
        }
        for m in Muscle.allCases { load[m] = (load[m] ?? 0) / Self.weeklyHardSets }
        return load
    }

    // MARK: Boss-Satz

    func hoursSinceBoss(_ m: Muscle) -> Double {
        if let l = state.log.last(where: { $0.isBoss && ($0.exercise?.primary.contains(m) ?? false) }) {
            return (nowMs() - l.ts) / hourMs
        }
        return 999
    }

    var bossToday: Bool {
        let s = startOfDay()
        return state.log.contains { $0.isBoss && $0.ts >= s }
    }

    /// Ziel für einen Boss-Satz: etwa 2 vor deiner Grenze
    func bossTarget(_ ex: Exercise) -> Int {
        let mx = estMax(ex)
        return roundTarget(ex, max(mx * 0.6, mx - (ex.unit == .sec ? 10 : 2)))
    }

    /// Lohnt sich hier gerade ein Boss-Satz? Höchstens einer pro Tag, nur mit frischen Hauptmuskeln,
    /// nur wenn die Muskelgruppe in der Woche hinterherhinkt oder lange keinen Boss-Satz hatte,
    /// und nicht bei Übungen, die du schon so oft schaffst, dass es nur noch Ausdauer ist.
    func shouldBoss(_ ex: Exercise, fatigue f: [Muscle: Double]) -> Bool {
        guard ex.kind == .strength, hasBaseline, !bossToday else { return false }
        let mx = estMax(ex)
        if ex.unit == .reps && mx > 40 { return false }
        if ex.unit == .sec && mx > 120 { return false }
        let week = weeklyLoad()
        for m in ex.primary {
            if (f[m] ?? 0) >= 0.3 { return false }
        }
        return ex.primary.contains { (week[$0] ?? 0) < 0.6 || hoursSinceBoss($0) > 72 }
    }

    /// Neuer Rekord im Boss-Satz? Dann wird die Baseline dieser Marker-Übung angehoben.
    @discardableResult
    func checkBossRecord(_ ex: Exercise, actual: Int) -> Bool {
        guard let mk = ex.marker, mk == ex.id else { return false }
        let old = markerValue(mk)
        guard actual > old else { return false }
        var b = state.trainer.baseline ?? [:]
        b[mk] = actual
        state.trainer.baseline = b
        recomputeTargets(keepReview: true)
        saveTrainer()
        return true
    }

    func hoursToRecover(_ m: Muscle, _ f: Double) -> Int {
        f <= 0.1 ? 0 : Int((m.recoveryHours * log10(f / 0.1)).rounded(.up))
    }

    // MARK: Auswahl

    func hoursSince(_ id: String) -> Double {
        if let l = state.log.last(where: { $0.ex == id && !$0.isTest }) { return (nowMs() - l.ts) / hourMs }
        return 96
    }

    /// Hoch = trifft frische Muskeln und ist lange her; niedrig = Hauptmuskel noch erschöpft oder gerade erst gemacht
    func score(_ ex: Exercise, _ f: [Muscle: Double]) -> Double {
        var sum = 0.0, wsum = 0.0, pen = 0.0
        let prim = ex.primary
        for (m, w) in ex.muscles {
            let v = min(1, f[m] ?? 0)
            sum += w * (1 - v); wsum += w
            if prim.contains(m) && v >= 0.8 { pen += 0.6 }
        }
        guard wsum > 0 else { return 0 }
        var s = sum / wsum - pen
        if ex.cat.rawValue == state.lastCat { s -= 0.1 }
        let h = hoursSince(ex.id)
        s += 0.25 * min(1, h / 48)
        if h < 1 { s -= 0.5 }
        return s
    }

    func pickStrength(excluding: String? = nil) -> (ex: Exercise, boss: Bool) {
        let f = fatigue()
        let skip = excluding ?? state.lastEx
        var ranked = strengthPool.filter { $0.id != skip }.map { ($0, score($0, f)) }.sorted { $0.1 > $1.1 }
        if ranked.isEmpty { ranked = strengthPool.map { ($0, 0.0) } }
        guard let best = ranked.first else { return (Exercise.all[0], false) }
        // Kandidat für einen Boss-Satz unter den guten Optionen? Dann den nehmen.
        let good = ranked.filter { $0.1 >= best.1 - 0.2 }
        if let b = good.first(where: { shouldBoss($0.0, fatigue: f) }) { return (b.0, true) }
        let top = ranked.filter { $0.1 >= best.1 - 0.08 }
        return (top.randomElement()?.0 ?? best.0, false)
    }

    func why(_ ex: Exercise) -> String {
        if ex.kind == .stretch {
            let r = ex.relieves.map { $0.label }.joined(separator: " + ")
            return r.isEmpty ? "LABOR: Beweglichkeit." : "LABOR: entlastet \(r)."
        }
        let f = fatigue()
        let main = ex.primary
        let tired = main.filter { (f[$0] ?? 0) >= 0.8 }.map { $0.label }
        let fresh = main.filter { (f[$0] ?? 0) < 0.3 }.map { $0.label }
        if !tired.isEmpty { return "LABOR: \(tired.joined(separator: ", ")) noch erschöpft, mach es locker." }
        if !fresh.isEmpty { return "LABOR: \(fresh.joined(separator: " + ")) \(fresh.count > 1 ? "sind" : "ist") frisch." }
        return "LABOR: gute Verteilung für jetzt."
    }

    func best(for m: Muscle) -> Exercise? {
        let c = pool.filter { $0.weight(m) > 0 }
        guard let top = c.map({ $0.weight(m) }).max() else { return nil }
        return c.filter { $0.weight(m) == top }.max { hoursSince($0.id) < hoursSince($1.id) }
    }

    // MARK: Statistik

    func startOfDay(_ t: Millis = nowMs()) -> Millis {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: t / 1000)).timeIntervalSince1970 * 1000
    }

    var streak: Int {
        let days = Set(state.log.map { startOfDay($0.ts) })
        var d = startOfDay()
        if !days.contains(d) { d = startOfDay(d - 12 * hourMs) }
        var n = 0
        while days.contains(d) { n += 1; d = startOfDay(d - 12 * hourMs) }
        return n
    }

    func periodStart(_ p: Period) -> Millis {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let start: Date
        switch p {
        case .day: start = cal.startOfDay(for: now)
        case .week: start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        case .month: start = cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)
        case .year: start = cal.dateInterval(of: .year, for: now)?.start ?? cal.startOfDay(for: now)
        }
        return start.timeIntervalSince1970 * 1000
    }

    func units(_ l: LogEntry) -> Double {
        guard let ex = l.exercise else { return 0 }
        var u = ex.unit == .sec ? Double(l.actual) / Model.secondsPerRep : Double(l.actual)
        if ex.side { u *= 2 }
        return u
    }
}
