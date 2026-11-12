import Foundation

/// Protein in Portionen statt Gramm. Eine Portion ≈ 25 g. Ziel ist der 7-Tage-Schnitt, nicht jeder einzelne Tag:
/// Der Körper speichert kein Protein, aber für den Muskelaufbau zählt vor allem die Menge über die Zeit.
enum ProteinModel {
    static let gramsPerPortion = 25.0
    /// Ziel als Tagesschnitt über 7 Tage (bei 75 kg ≈ 1,2–1,3 g pro kg)
    static let targetLow = 90.0
    static let targetHigh = 100.0
    /// Darunter weist die App darauf hin
    static let warnBelow = 80.0

    struct Food: Identifiable {
        let id: String
        let portions: Double
        let note: String
    }

    /// Grobe Richtwerte, gerundet auf ganze, Dreiviertel- und halbe Portionen
    static let foods: [Food] = [
        Food(id: "250 g Skyr oder Magerquark", portions: 1, note: "~28 g"),
        Food(id: "1 Hähnchenbrust (ca. 120 g)", portions: 1, note: "~28 g"),
        Food(id: "1 Dose Thunfisch", portions: 1, note: "~25 g"),
        Food(id: "Großer Teller Linsen, Bohnen, Chili oder Dal", portions: 1, note: "~25 g"),
        Food(id: "200 g Tofu", portions: 1, note: "~25 g"),
        Food(id: "Handflächengroßes Stück Fleisch oder Fisch", portions: 1, note: "~25 g"),
        Food(id: "4 Eier", portions: 1, note: "~28 g"),
        Food(id: "100 g Käse (Gouda, Emmentaler)", portions: 1, note: "~26 g"),
        Food(id: "500 g Joghurt", portions: 0.75, note: "~18 g"),
        Food(id: "2 Eier", portions: 0.5, note: "~14 g"),
        Food(id: "Großes Glas Milch (400 ml)", portions: 0.5, note: "~13 g"),
        Food(id: "100 g Haferflocken", portions: 0.5, note: "~13 g"),
        Food(id: "Portion Nudeln (125 g roh)", portions: 0.5, note: "~15 g"),
        Food(id: "150 g Kichererbsen oder Bohnen aus der Dose", portions: 0.5, note: "~11 g"),
        Food(id: "3 Scheiben Vollkornbrot", portions: 0.5, note: "~12 g"),
        Food(id: "50 g Käse", portions: 0.5, note: "~13 g"),
        Food(id: "40 g Erdnüsse oder Erdnussbutter", portions: 0.5, note: "~10 g"),
    ]
}

extension Store {
    func addProtein(_ portions: Double, label: String? = nil) {
        state.protein.append(ProteinEntry(id: LogEntry.newId(), ts: nowMs(), portions: portions, label: label))
        save()
    }

    func undoLastProtein() {
        guard let e = state.protein.popLast() else { return }
        state.deleted.append(e.id)
        save()
    }

    func proteinGrams(onDayStarting s: Millis) -> Double {
        let e = s + dayMs
        let p = state.protein.filter { $0.ts >= s && $0.ts < e }.reduce(0) { $0 + $1.portions }
        return p * ProteinModel.gramsPerPortion
    }

    var proteinToday: Double { proteinGrams(onDayStarting: startOfDay()) }

    /// Gramm pro Tag der letzten 7 Tage (älteste zuerst, heute zuletzt)
    var proteinLast7: [Double] {
        let today = startOfDay()
        return (0..<7).reversed().map { i in proteinGrams(onDayStarting: startOfDay(today - Double(i) * dayMs + 12 * hourMs)) }
    }

    /// 7-Tage-Schnitt. Zählt erst ab dem Tag, an dem du angefangen hast einzutragen, damit der Start nicht runterzieht.
    var proteinAverage: Double? {
        guard let first = state.protein.first?.ts else { return nil }
        let today = startOfDay()
        let days = min(7, Int(((today - startOfDay(first)) / dayMs).rounded()) + 1)
        guard days > 0 else { return nil }
        let vals = Array(proteinLast7.suffix(days))
        let all = vals.reduce(0, +) / Double(vals.count)
        // Der heutige Tag ist noch nicht vorbei: zieht er den Schnitt runter, lassen wir ihn erstmal weg
        guard vals.count > 1 else { return all }
        let before = vals.dropLast().reduce(0, +) / Double(vals.count - 1)
        return max(all, before)
    }
}
