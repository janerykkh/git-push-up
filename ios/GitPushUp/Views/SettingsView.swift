import SwiftUI

/// Einstellungen: Backup, Rekorde von Hand, Geräte, letzten Eintrag löschen
struct SettingsView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void
    let onRecordDay: () -> Void

    @State private var repo = ""
    @State private var tokenInput = ""
    @State private var status = ""
    @State private var busy = false
    @State private var records: [String: String] = [:]
    @State private var recordInfo = ""
    @State private var confirmDelete = false
    @State private var confirmEgg = false
    @State private var creatureName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button(action: onClose) {
                        Text("← ZURÜCK").font(mono(12)).tracking(1).foregroundStyle(Color.muted).frame(minHeight: 44)
                    }
                    Spacer()
                    Text("EINSTELLUNGEN").font(mono(15, .bold)).tracking(2).foregroundStyle(Color.wire)
                    Spacer()
                    Color.clear.frame(width: 70, height: 1)
                }

                if let c = store.state.creature {
                    let v = store.vitals()
                    Block(title: "BRUTKASTEN", trailing: "#\(c.seed)") {
                        Text("Geschlüpft am \(Date(timeIntervalSince1970: c.born / 1000).formatted(date: .numeric, time: .omitted)), Tag \(v.ageDays). Wachstum \(Int((v.g * 100).rounded())) %. Lange auf den Glaskasten drücken zeigt im Zeitraffer, wie es bei deiner jetzigen Pflege wächst.")
                            .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                        field("NAME") {
                            TextField(c.name, text: $creatureName)
                                .submitLabel(.done)
                                .onSubmit { store.renameCreature(creatureName) }
                        }
                        HStack(spacing: 10) {
                            Button("NAME SPEICHERN") { store.renameCreature(creatureName) }
                                .buttonStyle(HangarButtonStyle(color: .wire, filled: true))
                            Button("NEUES EI") { confirmEgg = true }
                                .buttonStyle(HangarButtonStyle(color: .danger))
                        }
                    }
                }

                Block(title: "BACKUP AUF GITHUB") {
                    Text("Sichert deinen Verlauf einmal am Tag in dein privates Repo. Der Token liegt nur im Schlüsselbund dieses iPhones. Mit „Aus Backup laden“ holst du auch deinen Verlauf aus der Web-App.")
                        .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    field("REPO") {
                        TextField("janerykkh/git-push-up-private", text: $repo)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    field("TOKEN") {
                        SecureField(store.token.isEmpty ? "github_pat_…" : "gespeichert", text: $tokenInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    HStack(spacing: 10) {
                        Button("SPEICHERN & SICHERN") { Task { await saveAndBackup() } }
                            .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                        Button("AUS BACKUP LADEN") { Task { await restore() } }
                            .buttonStyle(HangarButtonStyle())
                    }
                    .disabled(busy)
                    Text(status).font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }

                Block(title: "REKORDE") {
                    Text(store.hasBaseline
                         ? "Letzter Rekordtag: \(Date(timeIntervalSince1970: store.state.trainer.baselineDate / 1000).formatted(date: .numeric, time: .omitted)). Nächster in \(store.daysToRecord) Tagen."
                         : "Noch keine Baseline gemessen.")
                        .font(mono(12)).foregroundStyle(Color.muted)
                    ForEach(Marker.all) { m in
                        field(m.label.uppercased() + (m.unit == .sec ? " (SEKUNDEN)" : "")) {
                            TextField("\(m.fallback) (Schätzwert)", text: Binding(
                                get: { records[m.id] ?? "" },
                                set: { records[m.id] = $0 }
                            ))
                            .keyboardType(.numberPad)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("REKORDE SPEICHERN") {
                            var v: [String: Int] = [:]
                            for (k, s) in records { if let n = Int(s), n > 0 { v[k] = n } }
                            store.setRecords(v)
                            recordInfo = "Gespeichert. Ziele neu berechnet."
                        }
                        .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
                        Button("REKORDTAG MACHEN", action: onRecordDay)
                            .buttonStyle(HangarButtonStyle())
                    }
                    if !recordInfo.isEmpty { Text(recordInfo).font(mono(12)).foregroundStyle(Color.phos) }
                }

                if !store.equipmentKinds.isEmpty {
                    Block(title: "GERÄTE") {
                        Text("Übungen mit diesen Geräten kommen nur, wenn sie eingeschaltet sind.")
                            .font(mono(12)).foregroundStyle(Color.muted)
                        ForEach(store.equipmentKinds, id: \.self) { q in
                            Toggle(q.uppercased(), isOn: Binding(
                                get: { store.state.equipOn[q] ?? false },
                                set: { store.state.equipOn[q] = $0; store.save() }
                            ))
                            .font(mono(13)).tint(.phos)
                        }
                    }
                }

                Block(title: "DATEN") {
                    Text("\(store.state.log.count) Einträge auf diesem iPhone.").font(mono(12)).foregroundStyle(Color.muted)
                    Text("App-Stand: \(AppBuild.id)").font(mono(11)).foregroundStyle(Color.dim)
                    Button("LETZTEN EINTRAG LÖSCHEN") { confirmDelete = true }
                        .buttonStyle(HangarButtonStyle(color: .danger))
                        .disabled(store.state.log.isEmpty)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LabBackdrop())
        .confirmationDialog("Neues Ei legen? Das jetzige Wesen verschwindet, das neue wächst von vorn. Dein Trainingsverlauf bleibt.", isPresented: $confirmEgg, titleVisibility: .visible) {
            Button("Neues Ei legen", role: .destructive) { store.layNewEgg(); creatureName = store.state.creature?.name ?? "" }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(deleteText, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { store.deleteLast() }
            Button("Abbrechen", role: .cancel) {}
        }
        .onAppear {
            creatureName = store.state.creature?.name ?? ""
            repo = store.state.backupRepo
            status = statusText
            for m in Marker.all { if let v = store.state.trainer.baseline?[m.id] { records[m.id] = "\(v)" } }
        }
    }

    private var deleteText: String {
        guard let l = store.state.log.last else { return "" }
        return "\(l.exercise?.name ?? l.ex) vom \(fmtTime(l.ts)) löschen?"
    }

    private var statusText: String {
        if store.token.isEmpty { return "Noch kein Backup eingerichtet." }
        return store.state.lastBackup > 0 ? "Letztes Backup: \(fmtTime(store.state.lastBackup))" : "Eingerichtet, aber noch kein Backup gemacht."
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label12(text: label)
            content()
                .font(mono(16)).foregroundStyle(Color.fg)
                .padding(.horizontal, 12).frame(height: 46)
                .background(Color.panel)
                .overlay(PixelFrame().fill(Color.line2))
        }
    }

    private func applyFields() {
        store.state.backupRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tokenInput.isEmpty { store.token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines) }
        store.save()
    }

    private func saveAndBackup() async {
        applyFields()
        busy = true; status = "Sichere …"
        do {
            try await store.backupNow()
            status = "Gesichert. \(store.state.log.count) Einträge im Repo."
            tokenInput = ""
        } catch {
            status = error.localizedDescription
        }
        busy = false
    }

    private func restore() async {
        applyFields()
        busy = true; status = "Lade Backup …"
        do {
            let n = try await store.restore()
            status = "Backup geladen. \(n) neue Einträge übernommen."
        } catch {
            status = error.localizedDescription
        }
        busy = false
    }
}
