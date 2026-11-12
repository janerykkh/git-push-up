// Automatisch aus der Web-App (exercises.js) übernommen. Neue Übungen einfach unten in `all` ergänzen.

import CoreGraphics

enum Muscle: String, CaseIterable, Codable, Identifiable {
    case chest, frontDelt, rearDelt, biceps, triceps, upperBack, lats, abs, obliques, lowerBack, glutes, quads, hamstrings, calves
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chest: return "Brust"
        case .frontDelt: return "Schulter vorne"
        case .rearDelt: return "Schulter hinten"
        case .biceps: return "Bizeps"
        case .triceps: return "Trizeps"
        case .upperBack: return "Oberer Rücken"
        case .lats: return "Latissimus"
        case .abs: return "Bauch"
        case .obliques: return "Seitlicher Bauch"
        case .lowerBack: return "Unterer Rücken"
        case .glutes: return "Po"
        case .quads: return "Oberschenkel vorne"
        case .hamstrings: return "Oberschenkel hinten"
        case .calves: return "Waden"
        }
    }
    /// Stunden, bis ein voll erschöpfter Muskel wieder fast frisch ist (unter 10 %)
    var recoveryHours: Double {
        switch self {
        case .chest: return 48
        case .frontDelt: return 36
        case .rearDelt: return 36
        case .biceps: return 36
        case .triceps: return 36
        case .upperBack: return 48
        case .lats: return 48
        case .abs: return 24
        case .obliques: return 24
        case .lowerBack: return 36
        case .glutes: return 48
        case .quads: return 48
        case .hamstrings: return 48
        case .calves: return 30
        }
    }
}

enum ExCategory: String, CaseIterable, Codable {
    case beine, druecken, ziehen, rumpf
    var label: String {
        switch self {
        case .beine: return "Beine"
        case .druecken: return "Drücken"
        case .ziehen: return "Ziehen"
        case .rumpf: return "Rumpf"
        }
    }
}

enum ExUnit: String, Codable { case reps, sec }

enum Model {
    /// Arbeitsziel = Anteil des geschätzten Maximums (deutlich vor dem Muskelversagen)
    static let workFraction = 0.6
    /// Ein Satz erschöpft einen Muskel um Gewicht × (gemacht / Maximum) / fullEffort
    static let fullEffort = 1.8
    static let recordEveryDays = 28.0
    static let secondsPerRep = 3.0
}

struct Marker: Identifiable {
    let id: String
    let label: String
    let unit: ExUnit
    let fallback: Int
    let how: String

    static let all: [Marker] = [
        Marker(id: "pushup", label: "Liegestütze", unit: .reps, fallback: 15,
               how: "So viele saubere Liegestütze wie möglich am Stück. Aufhören, sobald die Hüfte durchhängt oder die Schulter sich unsicher anfühlt."),
        Marker(id: "squat", label: "Kniebeugen", unit: .reps, fallback: 25,
               how: "So viele Kniebeugen wie möglich am Stück, Oberschenkel mindestens parallel zum Boden."),
        Marker(id: "plank", label: "Unterarmstütz", unit: .sec, fallback: 45,
               how: "So lange halten wie möglich. Ende, sobald das Becken absackt oder nach oben wandert."),
        Marker(id: "tablerow", label: "Tischrudern", unit: .reps, fallback: 10,
               how: "Unter den Tisch, Kante schulterbreit greifen, Knie angewinkelt. So oft wie möglich die Brust zur Kante ziehen, Körper gerade von Knie bis Schulter."),
        Marker(id: "superman", label: "Superman", unit: .sec, fallback: 40,
               how: "Arme und Beine angehoben halten, so lange es sauber geht."),
    ]
}

struct Exercise: Identifiable {
    let id: String
    let name: String
    let cat: ExCategory
    let unit: ExUnit
    let base: Int
    let step: Int
    var side: Bool = false
    var marker: String? = nil
    var factor: Double = 1
    var cap: Int? = nil
    var retired: Bool = false
    var equipment: String? = nil
    var note: String? = nil
    let cue: String
    let muscles: [Muscle: Double]
    /// Zwei Posen der Strichfigur. Gelenke: Kopf, Hals, Hüfte, Knie1, Fuß1, Knie2, Fuß2, Ellbogen1, Hand1, Ellbogen2, Hand2
    let a: [CGPoint]
    let b: [CGPoint]
    /// Hilfslinien (Tisch, Türrahmen) als x1, y1, x2, y2
    var prop: [[CGFloat]] = []

    func weight(_ m: Muscle) -> Double { muscles[m] ?? 0 }
}

private func pose(_ v: [[CGFloat]]) -> [CGPoint] { v.map { CGPoint(x: $0[0], y: $0[1]) } }

extension Exercise {
    static let all: [Exercise] = [
        Exercise(id: "squat",
                 name: "Kniebeugen",
                 cat: .beine,
                 unit: .reps,
                 base: 12,
                 step: 1,
                 marker: "squat",
                 factor: 1,
                 cap: 30,
                 cue: "Füße schulterbreit, Po nach hinten, Knie über die Zehen. Unten kurz halten.",
                 muscles: [.quads: 1, .glutes: 1, .hamstrings: 0.5, .lowerBack: 0.25, .calves: 0.25, .abs: 0.25],
                 a: pose([[120, 28], [120, 44], [120, 95], [121, 122], [121, 150], [119, 122], [119, 150], [136, 56], [156, 56], [134, 58], [154, 58]]),
                 b: pose([[124, 60], [118, 74], [100, 116], [132, 120], [124, 150], [130, 121], [122, 150], [136, 80], [158, 80], [134, 82], [156, 82]])),
        Exercise(id: "lunge",
                 name: "Ausfallschritt rückwärts",
                 cat: .beine,
                 unit: .reps,
                 base: 8,
                 step: 1,
                 side: true,
                 marker: "squat",
                 factor: 0.5,
                 cap: 15,
                 cue: "Ein Bein weit nach hinten setzen, hinteres Knie fast zum Boden. Oberkörper aufrecht.",
                 muscles: [.quads: 1, .glutes: 1, .hamstrings: 0.5, .calves: 0.25, .obliques: 0.25],
                 a: pose([[120, 28], [120, 44], [120, 95], [121, 122], [121, 150], [119, 122], [119, 150], [121, 70], [121, 94], [119, 70], [119, 94]]),
                 b: pose([[116, 50], [116, 66], [114, 114], [138, 118], [140, 150], [96, 142], [74, 150], [118, 90], [120, 112], [114, 90], [112, 112]])),
        Exercise(id: "bridge",
                 name: "Einbeinige Glute Bridge",
                 cat: .beine,
                 unit: .reps,
                 base: 10,
                 step: 1,
                 side: true,
                 marker: "squat",
                 factor: 0.55,
                 cap: 15,
                 cue: "Rückenlage, ein Fuß aufgestellt, das andere Bein gestreckt. Becken hoch, Po fest anspannen.",
                 muscles: [.glutes: 1, .hamstrings: 1, .lowerBack: 0.5, .abs: 0.25],
                 a: pose([[40, 138], [56, 142], [110, 146], [138, 120], [150, 150], [142, 140], [172, 134], [76, 148], [98, 149], [76, 148], [98, 149]]),
                 b: pose([[40, 138], [56, 142], [114, 118], [144, 114], [150, 150], [160, 104], [192, 94], [76, 148], [98, 149], [76, 148], [98, 149]])),
        Exercise(id: "pushup",
                 name: "Liegestütze",
                 cat: .druecken,
                 unit: .reps,
                 base: 8,
                 step: 1,
                 marker: "pushup",
                 factor: 1,
                 cap: 25,
                 cue: "Körper wie ein Brett, Ellbogen etwa 45° am Körper. Langsam runter, kontrolliert hoch.",
                 muscles: [.chest: 1, .triceps: 1, .frontDelt: 0.5, .abs: 0.5],
                 a: pose([[176, 94], [162, 102], [106, 124], [78, 136], [50, 148], [78, 136], [50, 148], [164, 126], [165, 150], [166, 126], [167, 150]]),
                 b: pose([[178, 124], [162, 130], [106, 139], [78, 143], [50, 148], [78, 143], [50, 148], [142, 134], [165, 150], [144, 134], [167, 150]])),
        Exercise(id: "closepush",
                 name: "Enge Liegestütze",
                 cat: .druecken,
                 unit: .reps,
                 base: 6,
                 step: 1,
                 marker: "pushup",
                 factor: 0.45,
                 cap: 15,
                 cue: "Hände knapp schulterbreit, Ellbogen streifen beim Runtergehen die Rippen. Fokus auf den Trizeps.",
                 muscles: [.triceps: 1, .chest: 0.5, .frontDelt: 0.5, .abs: 0.5],
                 a: pose([[176, 94], [162, 102], [106, 124], [78, 136], [50, 148], [78, 136], [50, 148], [160, 126], [160, 150], [162, 126], [162, 150]]),
                 b: pose([[176, 124], [160, 130], [106, 139], [78, 143], [50, 148], [78, 143], [50, 148], [136, 138], [160, 150], [138, 138], [162, 150]])),
        Exercise(id: "pike",
                 name: "Pike Push-ups",
                 cat: .druecken,
                 unit: .reps,
                 base: 5,
                 step: 1,
                 marker: "pushup",
                 factor: 0.4,
                 cap: 10,
                 retired: true,
                 note: "Nur wenn sich die Schulter sicher anfühlt. Bei Unsicherheit lieber Liegestütze.",
                 cue: "Po hoch, Körper wie ein umgedrehtes V. Kopf zwischen den Händen Richtung Boden senken.",
                 muscles: [.frontDelt: 1, .triceps: 1, .upperBack: 0.5, .chest: 0.25],
                 a: pose([[164, 116], [152, 108], [110, 84], [86, 117], [62, 150], [88, 117], [64, 150], [158, 130], [162, 150], [160, 130], [164, 150]]),
                 b: pose([[166, 140], [154, 132], [110, 90], [86, 120], [62, 150], [88, 120], [64, 150], [140, 134], [162, 150], [142, 134], [164, 150]])),
        Exercise(id: "tablerow",
                 name: "Tischrudern",
                 cat: .ziehen,
                 unit: .reps,
                 base: 6,
                 step: 1,
                 marker: "tablerow",
                 factor: 1,
                 cap: 20,
                 note: "Vorher prüfen, dass der Tisch nicht zu dir kippen kann.",
                 cue: "Rücklings unter den Tisch, Kante schulterbreit greifen, Knie 90°. Brust zur Kante ziehen, Schulterblätter zusammen, langsam ablassen.",
                 muscles: [.lats: 1, .upperBack: 1, .biceps: 0.5, .rearDelt: 0.5, .glutes: 0.25],
                 a: pose([[60, 130], [74, 126], [118, 128], [150, 104], [160, 150], [152, 104], [162, 150], [74, 102], [76, 78], [76, 102], [78, 78]]),
                 b: pose([[60, 94], [76, 98], [118, 108], [150, 102], [160, 150], [152, 102], [162, 150], [96, 104], [80, 78], [98, 104], [82, 78]]),
                 prop: [[30, 76, 128, 76], [32, 76, 32, 150]]),
        Exercise(id: "doorrow",
                 name: "Türrahmen-Rudern",
                 cat: .ziehen,
                 unit: .reps,
                 base: 8,
                 step: 1,
                 side: true,
                 marker: "tablerow",
                 factor: 1,
                 cap: 15,
                 retired: true,
                 cue: "Türrahmen mit einer Hand auf Brusthöhe greifen, Füße nah am Rahmen, zurücklehnen. Mit dem Ellbogen am Körper zum Rahmen ziehen. Je weiter die Füße vorne, desto schwerer.",
                 muscles: [.lats: 1, .upperBack: 0.5, .biceps: 0.5, .rearDelt: 0.5, .obliques: 0.25],
                 a: pose([[86, 46], [92, 60], [110, 106], [120, 128], [130, 150], [118, 128], [126, 150], [116, 62], [140, 62], [96, 82], [100, 104]]),
                 b: pose([[106, 42], [110, 56], [118, 104], [124, 127], [130, 150], [122, 127], [126, 150], [102, 72], [136, 62], [112, 78], [114, 100]]),
                 prop: [[142, 20, 142, 150], [150, 20, 150, 150]]),
        Exercise(id: "superman",
                 name: "Superman",
                 cat: .ziehen,
                 unit: .sec,
                 base: 20,
                 step: 5,
                 marker: "superman",
                 factor: 1,
                 cap: 60,
                 cue: "Bauchlage, Arme lang nach vorne. Arme und Beine gleichzeitig anheben und halten.",
                 muscles: [.lowerBack: 1, .glutes: 0.5, .upperBack: 0.5, .rearDelt: 0.25, .hamstrings: 0.25],
                 a: pose([[184, 138], [170, 142], [110, 146], [80, 147], [50, 148], [80, 147], [50, 148], [192, 143], [214, 143], [192, 144], [214, 144]]),
                 b: pose([[184, 126], [168, 134], [110, 146], [80, 142], [50, 134], [80, 143], [50, 136], [190, 128], [212, 120], [190, 129], [212, 121]])),
        Exercise(id: "ytw",
                 name: "Y-T-W-Raises",
                 cat: .ziehen,
                 unit: .reps,
                 base: 5,
                 step: 1,
                 marker: "superman",
                 factor: 0.2,
                 cap: 10,
                 cue: "Bauchlage, Stirn knapp über dem Boden. Arme als Y, dann T, dann W anheben. Eine Runde = Y + T + W.",
                 muscles: [.rearDelt: 1, .upperBack: 1, .lats: 0.25, .lowerBack: 0.25],
                 a: pose([[184, 136], [170, 141], [110, 146], [80, 147], [50, 148], [80, 147], [50, 148], [150, 138], [128, 138], [150, 139], [128, 139]]),
                 b: pose([[184, 136], [170, 141], [110, 146], [80, 147], [50, 148], [80, 147], [50, 148], [190, 126], [214, 118], [178, 124], [196, 108]])),
        Exercise(id: "birddog",
                 name: "Superman Plank",
                 cat: .rumpf,
                 unit: .reps,
                 base: 6,
                 step: 1,
                 side: true,
                 marker: "plank",
                 factor: 0.2,
                 cap: 12,
                 cue: "Hoher Stütz. Diagonal einen Arm nach vorne und das andere Bein nach hinten strecken, Becken bleibt ruhig.",
                 muscles: [.abs: 1, .lowerBack: 0.5, .glutes: 0.5, .frontDelt: 0.5, .obliques: 0.5],
                 a: pose([[176, 94], [162, 102], [106, 124], [78, 136], [50, 148], [78, 136], [50, 148], [164, 126], [165, 150], [166, 126], [167, 150]]),
                 b: pose([[176, 94], [162, 102], [106, 124], [78, 136], [50, 148], [78, 118], [46, 112], [164, 126], [165, 150], [188, 100], [214, 98]])),
        Exercise(id: "plank",
                 name: "Unterarmstütz",
                 cat: .rumpf,
                 unit: .sec,
                 base: 30,
                 step: 5,
                 marker: "plank",
                 factor: 1,
                 cap: 90,
                 cue: "Unterarme unter den Schultern, Körper eine gerade Linie. Bauch und Po fest, ruhig weiteratmen.",
                 muscles: [.abs: 1, .obliques: 0.5, .frontDelt: 0.25, .glutes: 0.25, .quads: 0.25],
                 a: pose([[176, 108], [162, 116], [106, 130], [78, 139], [50, 148], [78, 139], [50, 148], [160, 148], [184, 148], [162, 148], [186, 148]]),
                 b: pose([[176, 106], [162, 114], [106, 127], [78, 137], [50, 148], [78, 137], [50, 148], [160, 148], [184, 148], [162, 148], [186, 148]])),
        Exercise(id: "sideplank",
                 name: "Seitstütz",
                 cat: .rumpf,
                 unit: .sec,
                 base: 20,
                 step: 5,
                 side: true,
                 marker: "plank",
                 factor: 0.5,
                 cap: 45,
                 cue: "Unterarm unter der Schulter, Körper eine Linie von Kopf bis Fuß. Becken nicht absacken lassen.",
                 muscles: [.obliques: 1, .abs: 0.5, .glutes: 0.25, .frontDelt: 0.25],
                 a: pose([[172, 100], [160, 108], [106, 134], [78, 142], [50, 148], [78, 143], [50, 149], [160, 148], [184, 148], [132, 112], [110, 128]]),
                 b: pose([[172, 92], [160, 100], [106, 124], [78, 137], [50, 148], [78, 138], [50, 149], [160, 148], [184, 148], [132, 104], [110, 118]])),
        Exercise(id: "deadbug",
                 name: "Dead Bug",
                 cat: .rumpf,
                 unit: .reps,
                 base: 6,
                 step: 1,
                 side: true,
                 marker: "plank",
                 factor: 0.25,
                 cap: 15,
                 cue: "Rückenlage, Arme zur Decke, Knie 90°. Unteren Rücken in den Boden drücken, gegengleich Arm und Bein strecken.",
                 muscles: [.abs: 1, .obliques: 0.5, .quads: 0.25],
                 a: pose([[42, 140], [58, 143], [114, 146], [114, 114], [144, 114], [116, 114], [146, 114], [60, 120], [60, 96], [62, 120], [62, 96]]),
                 b: pose([[42, 140], [58, 143], [114, 146], [114, 114], [144, 114], [146, 138], [180, 140], [60, 120], [60, 96], [40, 134], [18, 138]])),
    ]
    static let byId: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
