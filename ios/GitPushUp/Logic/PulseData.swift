import Foundation

/// Wozu gemessen wird. Bestimmt Dauer, Ablauf und wie die Messung später ausgewertet wird.
enum PulseContext: Equatable {
    case free                 // einfach so
    case rest                 // Ruhepuls am Morgen
    case medBefore, medAfter  // vor und nach der Meditation
    case recovery(String)     // Erholungspuls nach Boss-Satz oder Rekordtest: direkt danach und eine Minute später

    var code: String {
        switch self {
        case .free: return "frei"
        case .rest: return "rest"
        case .medBefore: return "med-vor"
        case .medAfter: return "med-nach"
        case .recovery(let id): return "hrr:" + id
        }
    }
    var title: String {
        switch self {
        case .free: return "PULS"
        case .rest: return "RUHEPULS"
        case .medBefore: return "PULS VOR DER MEDITATION"
        case .medAfter: return "PULS NACH DER MEDITATION"
        case .recovery: return "ERHOLUNGSPULS"
        }
    }
    var hint: String {
        switch self {
        case .free: return "Finger leicht auf Kamera und Blitz legen, nicht drücken. Die Messung startet, sobald alles ruhig ist."
        case .rest: return "Am besten morgens, im Sitzen, bevor du viel gemacht hast. Finger leicht auf Kamera und Blitz."
        case .medBefore: return "Kurz vor dem Hinsetzen. Danach misst du noch einmal und siehst, wie weit du runterkommst."
        case .medAfter: return "Gleich nach dem Gong, noch im Sitzen."
        case .recovery: return "Direkt nach der Übung messen, dann Finger liegen lassen: nach einer Minute kommt die zweite Messung. Je stärker der Puls fällt, desto besser erholst du dich."
        }
    }
    /// Messdauer der Kamera
    var seconds: Double { if case .recovery = self { return 10 } else { return 20 } }
    var isRecovery: Bool { if case .recovery = self { return true } else { return false } }
}

extension PulseReading {
    var label: String {
        if mode.hasPrefix("hrr:") { return "Erholung · \(Exercise.byId[String(mode.dropFirst(4))]?.name ?? "Übung")" }
        if mode.hasPrefix("nach:") { return "nach \(Exercise.byId[String(mode.dropFirst(5))]?.name ?? "Übung")" }
        switch mode {
        case "rest": return "Ruhepuls"
        case "med-vor": return "vor Meditation"
        case "med-nach": return "nach Meditation"
        case "count": return "gezählt"
        default: return source == "tasten" ? "gezählt" : "Kamera"
        }
    }
}

extension Store {
    /// Morgens noch kein Ruhepuls gemessen?
    var restPulseDue: Bool {
        guard state.pulseAfter else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 5 && hour < 12 else { return false }
        let s = startOfDay()
        return !state.pulse.contains { $0.ts >= s && $0.mode == "rest" }
    }

    struct PulseStats {
        var restLast: Int?
        var restDaily: [Double?]      // 14 Tage, ältester zuerst
        var medDrop: Double?          // Durchschnitt vorher − nachher
        var medPairs: Int
        var recoveryDrop: Double?     // Durchschnitt Abfall in einer Minute
        var recoveryN: Int
    }

    func pulseStats() -> PulseStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let rest = state.pulse.filter { $0.mode == "rest" }
        var daily: [Double?] = []
        for i in 0..<14 {
            let d = cal.date(byAdding: .day, value: i - 13, to: today) ?? today
            let a = d.timeIntervalSince1970 * 1000, b = a + dayMs
            let v = rest.filter { $0.ts >= a && $0.ts < b }.map { Double($0.bpm) }
            daily.append(v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
        }
        // Meditation: jede Nachher-Messung mit der letzten Vorher-Messung innerhalb von 40 Minuten davor
        var drops: [Double] = []
        for after in state.pulse where after.mode == "med-nach" {
            if let before = state.pulse.last(where: { $0.mode == "med-vor" && $0.ts < after.ts && after.ts - $0.ts < 40 * 60_000 }) {
                drops.append(Double(before.bpm - after.bpm))
            }
        }
        let rec = state.pulse.filter { $0.mode.hasPrefix("hrr:") && $0.bpm2 != nil }.suffix(10).map { Double($0.bpm - ($0.bpm2 ?? $0.bpm)) }
        let md = Array(drops.suffix(10))
        return PulseStats(restLast: rest.last?.bpm, restDaily: daily,
                          medDrop: md.isEmpty ? nil : md.reduce(0, +) / Double(md.count), medPairs: drops.count,
                          recoveryDrop: rec.isEmpty ? nil : rec.reduce(0, +) / Double(rec.count), recoveryN: rec.count)
    }
}
