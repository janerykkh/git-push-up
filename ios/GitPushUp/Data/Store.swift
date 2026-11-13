import Foundation
import SwiftUI
import Security

/// Zentraler Zustand der App. Speichert alles lokal als JSON im App-Ordner (Application Support).
@MainActor
final class Store: ObservableObject {
    @Published var state = PersistedState()
    @Published var backupStatus: String = ""
    /// "Passt gerade nicht": diese Übungen eine Weile überspringen (nur im Speicher)
    var skipped: [String: Millis] = [:]

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    init() {
        load()
        weeklyReview()
    }

    // MARK: Laden & Speichern

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        state = s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func saveTrainer() {
        state.trainer.updated = nowMs()
        save()
    }

    var token: String {
        get { Keychain.read("github-token") ?? "" }
        set { Keychain.write("github-token", newValue) }
    }

    // MARK: Übungen

    var strengthPool: [Exercise] { pool.filter { $0.kind == .strength } }

    var pool: [Exercise] {
        Exercise.all.filter { !$0.retired && ($0.equipment == nil || state.equipOn[$0.equipment!] == true) }
    }
    var equipmentKinds: [String] {
        Array(Set(Exercise.all.compactMap { $0.equipment })).sorted()
    }

    func logResult(_ ex: Exercise, target: Int, actual: Int, done: Bool, boss: Bool = false) {
        let before = fatigue()
        if !boss { calibrate(ex, target: target, actual: actual, done: done, before: before) }
        state.log.append(LogEntry(id: LogEntry.newId(), ex: ex.id, cat: ex.cat.rawValue,
                                  target: target, actual: actual, done: done, test: nil, ts: nowMs(),
                                  boss: boss ? true : nil))
        state.lastCat = ex.cat.rawValue
        state.lastEx = ex.id
        skipped = [:]
        save()
        Task { await autoBackup() }
    }

    /// Übung von außerhalb der App nachtragen
    func logManual(_ ex: Exercise, actual: Int, hoursAgo: Double) {
        let ts = nowMs() - hoursAgo * hourMs
        state.log.append(LogEntry(id: LogEntry.newId(), ex: ex.id, cat: ex.cat.rawValue,
                                  target: actual, actual: actual, done: true, test: nil, ts: ts, manual: true))
        state.log.sort { $0.ts < $1.ts }
        save()
    }

    func deleteLast() {
        guard let l = state.log.popLast() else { return }
        state.deleted.append(l.id)
        state.lastBackup = 0
        save()
    }
}

// MARK: - Schlüsselbund für den GitHub-Token

enum Keychain {
    private static let service = "de.janerykkh.gitpushup"

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
