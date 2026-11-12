import Foundation

/// Zeit in Millisekunden seit 1970, wie in der Web-App. So bleiben Backups zwischen beiden Versionen austauschbar.
typealias Millis = Double
func nowMs() -> Millis { Date().timeIntervalSince1970 * 1000 }
let hourMs: Double = 3_600_000
let dayMs: Double = 86_400_000

struct LogEntry: Codable, Identifiable, Equatable {
    var id: String
    var ex: String
    var cat: String
    var target: Int
    var actual: Int
    var done: Bool
    var test: Bool?
    var ts: Millis

    var isTest: Bool { test ?? false }
    var exercise: Exercise? { Exercise.byId[ex] }

    static func newId() -> String {
        String(Int(nowMs()), radix: 36) + String(UInt32.random(in: 0...UInt32.max), radix: 36)
    }
}

struct TargetState: Codable, Equatable {
    var t: Int
    var reviewed: Millis
    var change: Int?
}

struct TrainerState: Codable, Equatable {
    var baseline: [String: Int]?
    var baselineDate: Millis = 0
    var pending: [String: Int] = [:]
    var targets: [String: TargetState] = [:]
    var updated: Millis = 0
}

enum Period: String, CaseIterable, Codable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "TAG"
        case .week: return "WOCHE"
        case .month: return "MONAT"
        case .year: return "JAHR"
        }
    }
}

struct PulseReading: Codable, Identifiable, Equatable {
    var id: String
    var ts: Millis
    var bpm: Int
    var quality: Double
    var motion: Double
    var mode: String
}

/// Alles, was lokal gespeichert wird (eine JSON-Datei im App-Ordner, nirgends sonst)
struct PersistedState: Codable {
    var log: [LogEntry] = []
    var deleted: [String] = []
    var trainer = TrainerState()
    var lastCat: String?
    var lastEx: String?
    var equipOn: [String: Bool] = [:]
    var period: Period = .day
    var backupRepo: String = "janerykkh/git-push-up-private"
    var lastBackup: Millis = 0
    var pulse: [PulseReading] = []
}

/// Format der backup.json im privaten Repo (gleich wie bei der Web-App)
struct BackupFile: Codable {
    var version: Int?
    var exported: String?
    var entries: [LogEntry]?
    var deleted: [String]?
    var trainer: TrainerState?
}

// Fehlende Felder (ältere Backups, neue Versionen) einfach mit Standardwerten füllen statt abzubrechen
extension TrainerState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseline = try c.decodeIfPresent([String: Int].self, forKey: .baseline)
        baselineDate = try c.decodeIfPresent(Millis.self, forKey: .baselineDate) ?? 0
        pending = try c.decodeIfPresent([String: Int].self, forKey: .pending) ?? [:]
        targets = try c.decodeIfPresent([String: TargetState].self, forKey: .targets) ?? [:]
        updated = try c.decodeIfPresent(Millis.self, forKey: .updated) ?? 0
    }
}

extension PersistedState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? []
        deleted = try c.decodeIfPresent([String].self, forKey: .deleted) ?? []
        trainer = try c.decodeIfPresent(TrainerState.self, forKey: .trainer) ?? TrainerState()
        lastCat = try c.decodeIfPresent(String.self, forKey: .lastCat)
        lastEx = try c.decodeIfPresent(String.self, forKey: .lastEx)
        equipOn = try c.decodeIfPresent([String: Bool].self, forKey: .equipOn) ?? [:]
        period = try c.decodeIfPresent(Period.self, forKey: .period) ?? .day
        backupRepo = try c.decodeIfPresent(String.self, forKey: .backupRepo) ?? "janerykkh/git-push-up-private"
        lastBackup = try c.decodeIfPresent(Millis.self, forKey: .lastBackup) ?? 0
        pulse = try c.decodeIfPresent([PulseReading].self, forKey: .pulse) ?? []
    }
}
