import Foundation

/// Backup in dein privates GitHub-Repo, gleiches Format wie die Web-App (backup.json).
/// So kannst du deinen Verlauf aus der Web-App mit "Aus Backup laden" übernehmen.
extension Store {

    enum BackupError: LocalizedError {
        case missing, http(Int), noFile, bad
        var errorDescription: String? {
            switch self {
            case .missing: return "Trag zuerst Repo und Token ein."
            case .http(401): return "Token ungültig oder abgelaufen. Leg in GitHub einen neuen an."
            case .http(403): return "Der Token darf das Repo nicht beschreiben. Prüfe „Contents: Read and write“."
            case .http(404): return "Repo nicht gefunden. Prüfe den Namen und ob der Token Zugriff auf genau dieses Repo hat."
            case .http(let c): return "GitHub hat mit Fehler \(c) geantwortet. Versuch es später nochmal."
            case .noFile: return "Im Repo liegt noch kein Backup."
            case .bad: return "Das Backup konnte nicht gelesen werden."
            }
        }
    }

    private var contentsURL: URL? {
        let repo = state.backupRepo.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
        return URL(string: "https://api.github.com/repos/\(repo)/contents/backup.json")
    }

    private func request(_ method: String, body: Data? = nil) throws -> URLRequest {
        guard !token.isEmpty, let url = contentsURL else { throw BackupError.missing }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    private struct ContentsResponse: Decodable { let sha: String; let content: String }

    /// Lädt das Backup aus dem Repo (nil, wenn es noch keins gibt)
    private func fetchRemote() async throws -> (sha: String?, file: BackupFile?) {
        let (data, resp) = try await URLSession.shared.data(for: try request("GET"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 {
            // Datei fehlt noch, Repo-Zugriff trotzdem prüfen
            var r = try request("GET")
            r.url = contentsURL?.deletingLastPathComponent().deletingLastPathComponent()
            let (_, r2) = try await URLSession.shared.data(for: r)
            let c2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
            if c2 != 200 { throw BackupError.http(c2) }
            return (nil, nil)
        }
        guard code == 200 else { throw BackupError.http(code) }
        guard let c = try? JSONDecoder().decode(ContentsResponse.self, from: data),
              let raw = Data(base64Encoded: c.content.replacingOccurrences(of: "\n", with: "")),
              let file = try? JSONDecoder().decode(BackupFile.self, from: raw) else { throw BackupError.bad }
        return (c.sha, file)
    }

    /// Fremde Einträge übernehmen, Gelöschtes weglassen, neueren Trainer-Stand behalten
    private func merge(_ remote: BackupFile) {
        let del = Set(state.deleted + (remote.deleted ?? []))
        state.deleted = Array(del)
        var map: [String: LogEntry] = [:]
        for l in state.log + (remote.entries ?? []) where !del.contains(l.id) { map[l.id] = l }
        state.log = map.values.sorted { $0.ts < $1.ts }
        if let t = remote.trainer, t.updated > state.trainer.updated { state.trainer = t }
        save()
    }

    func backupNow() async throws {
        let remote = try await fetchRemote()
        if let f = remote.file { merge(f) }
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = BackupFile(version: 2, exported: iso, entries: state.log, deleted: state.deleted, trainer: state.trainer)
        let json = try JSONEncoder().encode(payload)
        var body: [String: String] = [
            "message": "Backup \(Date().formatted(date: .numeric, time: .omitted)): \(state.log.count) Einträge",
            "content": json.base64EncodedString(),
        ]
        if let sha = remote.sha { body["sha"] = sha }
        let (_, resp) = try await URLSession.shared.data(for: try request("PUT", body: try JSONEncoder().encode(body)))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else { throw BackupError.http(code) }
        state.lastBackup = nowMs()
        save()
    }

    /// Holt das Backup und führt es mit dem lokalen Verlauf zusammen. Gibt die Zahl neuer Einträge zurück.
    func restore() async throws -> Int {
        let before = state.log.count
        let remote = try await fetchRemote()
        guard let f = remote.file else { throw BackupError.noFile }
        merge(f)
        weeklyReview()
        return state.log.count - before
    }

    /// Einmal am Tag automatisch sichern (nach dem Rekordtag sofort)
    func autoBackup(force: Bool = false) async {
        guard !token.isEmpty else { return }
        guard force || nowMs() - state.lastBackup > 20 * hourMs else { return }
        try? await backupNow()
    }
}
