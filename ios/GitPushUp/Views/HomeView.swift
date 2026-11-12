import SwiftUI
import Charts

/// Dashboard: Kurzstatistik, ÜBUNG, Körperscan mit Erschöpfung, darunter die Statistik nach Zeitraum.
struct HomeView: View {
    @EnvironmentObject var store: Store
    let onGo: () -> Void
    let onExercise: (Exercise) -> Void
    let onManual: () -> Void
    let onProtein: () -> Void
    let onRecord: () -> Void
    let onSettings: () -> Void
    let onPulse: () -> Void

    @State private var selected: Muscle? = nil

    private struct MuscleGroup: Identifiable { let id: String; let muscles: [Muscle] }
    private let groups: [MuscleGroup] = [
        MuscleGroup(id: "OBERKÖRPER", muscles: [.chest, .frontDelt, .rearDelt, .upperBack, .lats, .biceps, .triceps]),
        MuscleGroup(id: "RUMPF", muscles: [.abs, .obliques, .lowerBack]),
        MuscleGroup(id: "BEINE", muscles: [.glutes, .quads, .hamstrings, .calves]),
    ]
    private struct CatCount: Identifiable { let id: ExCategory; let n: Int }

    var body: some View {
        // Erschöpfung klingt ab: jede Minute neu rechnen
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let f = store.fatigue()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        quick
                        if store.hasBaseline && store.recordDue {
                            Button(action: onRecord) {
                                HStack {
                                    Text("REKORDTAG FÄLLIG").font(mono(12, .bold)).tracking(1.6)
                                    Spacer()
                                    Text("5 TESTS · ~12 MIN").font(mono(11)).foregroundStyle(Color.muted)
                                }
                                .foregroundStyle(Color.amber)
                                .padding(14)
                                .background(Color.amber.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.amber, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 10) {
                            goButton
                            proteinButton
                        }
                        if store.hasBaseline {
                            Button(action: onManual) {
                                Text("+ ÜBUNG NACHTRAGEN").font(mono(11)).tracking(1.6).foregroundStyle(Color.muted)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, -10)
                        }
                        scan(f)
                        if let m = selected { muscleInfo(m, f).id("info") }
                        muscleList(f)
                        periodTabs
                        stats
                        Text("* Halteübungen: 1 Wdh. pro 3 s · Übungen pro Seite zählen doppelt")
                            .font(mono(10)).foregroundStyle(Color.dim)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
                }
                .onChange(of: selected) { m in
                    if m != nil { withAnimation { proxy.scrollTo("info", anchor: .center) } }
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
    }

    // MARK: Kopf & Kurzstatistik

    private var header: some View {
        HStack {
            Text("GIT PUSH-UP").font(mono(16, .bold)).tracking(2.2).foregroundStyle(Color.wire)
            Spacer()
            let today = todayEntries.count
            Text(!store.hasBaseline ? "KALIBRIERUNG NÖTIG" : today > 0 ? "SYSTEME ONLINE" : "BEREIT")
                .font(mono(11)).tracking(1.8).foregroundStyle(Color.phos).glow(.phos, 6).lineLimit(1).minimumScaleFactor(0.6)
            Button(action: onPulse) {
                Image(systemName: "heart.text.square").font(.system(size: 18)).foregroundStyle(Color.danger.opacity(0.85)).frame(width: 40, height: 44)
            }
            .accessibilityLabel("Pulstest")
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Color.muted).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Einstellungen")
        }
    }

    private var todayEntries: [LogEntry] {
        let s = store.startOfDay()
        return store.state.log.filter { $0.ts >= s }
    }

    private var quick: some View {
        let today = todayEntries
        let normal = today.filter { !$0.isTest }
        let rate: Int? = normal.isEmpty ? nil : Int((Double(normal.filter { $0.done }.count) / Double(normal.count) * 100).rounded())
        let s = store.streak
        return HStack(spacing: 0) {
            quickCell("SERIE", "\(s)", s == 1 ? "TAG" : "TAGE", s > 0 ? .amber : .fg)
            Rectangle().fill(Color.line).frame(width: 1)
            quickCell("HEUTE", "\(today.count)", "ÜB.", today.isEmpty ? .fg : .phos)
            Rectangle().fill(Color.line).frame(width: 1)
            quickCell("GESCHAFFT", rate.map { "\($0)" } ?? "–", rate == nil ? "" : "%", .fg)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { Rectangle().fill(Color.line2).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line2).frame(height: 1) }
    }

    private func quickCell(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label12(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(mono(30, .heavy)).monospacedDigit().foregroundStyle(color)
                    .glow(color == .fg ? .clear : color, 10)
                Text(unit).font(mono(11)).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.leading, 10)
    }

    private var goButton: some View {
        let first = !store.hasBaseline
        let c: Color = first ? .amber : .phos
        return Button(action: { first ? onRecord() : onGo() }) {
            VStack(spacing: 5) {
                Text(first ? "REKORDTAG" : "ÜBUNG").font(mono(first ? 17 : 22, .heavy)).tracking(first ? 3 : 6)
                    .foregroundStyle(c).glow(c, 10).lineLimit(1).minimumScaleFactor(0.7)
                Text(first ? "BASELINE MESSEN" : "EINE RUNDE").font(mono(9.5)).tracking(1.6).foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(c.opacity(0.09))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(c, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var proteinButton: some View {
        let today = Int(store.proteinToday.rounded())
        let avgText = store.proteinAverage.map { String(Int($0.rounded())) } ?? "–"
        let c: Color = .ziehen
        return Button(action: onProtein) {
            VStack(spacing: 5) {
                Text("PROTEIN").font(mono(22, .heavy)).tracking(4).foregroundStyle(c).glow(c, 10)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("HEUTE \(today) G · Ø \(avgText)")
                    .font(mono(9.5)).tracking(1).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(c.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(c, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Körperscan

    private func scan(_ f: [Muscle: Double]) -> some View {
        let tired = f.values.filter { $0 >= 0.5 }.count
        return BodyScanView(fatigue: f, selected: $selected)
            .background(RadialGradient(colors: [Color(hex: 0x0b161c), .bg], center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: 300))
            .overlay(alignment: .topLeading) { Label12(text: "BODY SCAN · JETZT", color: .wire).padding(10) }
            .overlay(alignment: .topTrailing) { Label12(text: "\(tired)/\(Muscle.allCases.count) AUSGELASTET", color: .phos).padding(10) }
            .overlay(alignment: .bottomLeading) { Label12(text: "TIPPEN · ZIEHEN", color: .dim).padding(10) }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func muscleInfo(_ m: Muscle, _ f: [Muscle: Double]) -> some View {
        let v = f[m] ?? 0
        let h = store.hoursToRecover(m, v)
        let hitters = store.pool.filter { $0.weight(m) > 0 }.sorted { $0.weight(m) > $1.weight(m) }
        let best = store.best(for: m)
        let info = muscleInfoText(m, hitters)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(m.label.uppercased()).font(mono(15, .heavy)).tracking(1.6).foregroundStyle(Color.amber).glow(.amber, 6)
                Spacer()
                Button { selected = nil } label: {
                    Image(systemName: "xmark").foregroundStyle(Color.muted).frame(width: 36, height: 36)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(pct(v)).font(mono(34, .heavy)).monospacedDigit().foregroundStyle(Color.fg)
                Text(h > 0 ? "ERSCHÖPFT · ERHOLT IN CA. \(h) H" : "ERHOLT · BEREIT").font(mono(11)).foregroundStyle(Color.muted)
            }
            meter(v, color: .phos, height: 4)
            Text(info)
                .font(mono(12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if let ex = best, store.hasBaseline {
                Button("ÜBUNG: \(ex.name.uppercased())") { onExercise(ex) }
                    .buttonStyle(HangarButtonStyle(color: .phos, filled: true))
            }
        }
        .padding(14)
        .background(Color.amber.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.amber, lineWidth: 1))
    }

    private func muscleInfoText(_ m: Muscle, _ hitters: [Exercise]) -> String {
        var parts: [String] = []
        for ex in hitters {
            let w = ex.weight(m)
            let role = w >= 1 ? "Haupt" : (w >= 0.5 ? "Neben" : "hilft mit")
            parts.append("\(ex.name) (\(role))")
        }
        let first = parts.isEmpty ? "Keine Übung im Pool trifft diesen Muskel." : "Trainiert durch: " + parts.joined(separator: ", ") + "."
        return first + " Volle Erholung dauert etwa \(Int(m.recoveryHours)) h."
    }

    private func groupAverage(_ g: MuscleGroup, _ f: [Muscle: Double]) -> Double {
        var sum = 0.0
        for m in g.muscles { sum += min(1, f[m] ?? 0) }
        return sum / Double(g.muscles.count)
    }

    private func muscleList(_ f: [Muscle: Double]) -> some View {
        let week = store.weeklyLoad()
        return Block(title: "AUSLASTUNG", trailing: "JETZT · WOCHE") {
            Text("Jetzt = wie erschöpft, Woche = wie viel der Muskel in den letzten 7 Tagen gearbeitet hat (100 % ≈ 6 harte Sätze).")
                .font(mono(10.5)).foregroundStyle(Color.dim).fixedSize(horizontal: false, vertical: true)
            ForEach(groups) { g in
                HStack(spacing: 6) {
                    Label12(text: g.id)
                    Spacer()
                    Text(pct(groupAverage(g, f))).font(mono(11, .bold)).foregroundStyle(Color.phos)
                    Text("·").font(mono(11)).foregroundStyle(Color.dim)
                    Text(pct(groupAverage(g, week))).font(mono(11, .bold)).foregroundStyle(Color.amber)
                }
                .padding(.top, 6)
                ForEach(g.muscles) { m in muscleRow(m, f[m] ?? 0, week[m] ?? 0) }
            }
        }
    }

    private func muscleRow(_ m: Muscle, _ v: Double, _ wk: Double) -> some View {
        let h = store.hoursToRecover(m, v)
        let c: Color = v >= 0.8 ? .phos : (v > 0.05 ? .wire : .muted)
        return Button { selected = (selected == m) ? nil : m } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.label.uppercased()).font(mono(13, .bold)).tracking(0.8)
                        .foregroundStyle(selected == m ? Color.amber : Color.fg)
                    Spacer()
                    Text(pct(v)).font(mono(12, .bold)).monospacedDigit().foregroundStyle(c).glow(v >= 0.8 ? .phos : .clear, 6)
                    Text("·").font(mono(11)).foregroundStyle(Color.dim)
                    Text(pct(wk)).font(mono(12, .bold)).monospacedDigit().foregroundStyle(wk >= 1 ? Color.amber : Color.amber.opacity(0.7))
                        .frame(width: 44, alignment: .trailing)
                }
                meter(v, color: v >= 0.8 ? .phos : .wire, height: 3)
                meter(wk, color: .amber, height: 2).opacity(0.8)
                if h > 0 { Text("erholt in ca. \(h) h").font(mono(10)).foregroundStyle(Color.dim) }
            }
            .padding(.vertical, 6).padding(.leading, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meter(_ v: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.line)
                Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, v))).glow(color, 4)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func pct(_ v: Double) -> String { "\(Int((min(1, v) * 100).rounded()))%" }

    // MARK: Zeitraum-Statistik

    private var periodTabs: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases) { p in
                let on = store.state.period == p
                Button { store.state.period = p; store.save() } label: {
                    Text(p.label).font(mono(12, on ? .bold : .regular)).tracking(1.8)
                        .foregroundStyle(on ? Color.amber : Color.muted).glow(on ? .amber : .clear, 6)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? Color.amber : Color.line2).frame(height: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var periodEntries: [LogEntry] {
        let s = store.periodStart(store.state.period)
        return store.state.log.filter { $0.ts >= s }
    }

    @ViewBuilder private var stats: some View {
        let entries = periodEntries
        let normal = entries.filter { !$0.isTest }
        let doneN = normal.filter { $0.done }.count
        let days = Set(entries.map { store.startOfDay($0.ts) }).count
        let reps = Int(entries.reduce(0) { $0 + store.units($1) }.rounded())

        Block(title: nil) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                kpi("\(entries.count)", "ÜBUNGEN")
                kpi(normal.isEmpty ? "–" : "\(Int((Double(doneN) / Double(normal.count) * 100).rounded()))%", "GESCHAFFT")
                kpi("\(reps)", "WIEDERHOLUNGEN*")
                kpi("\(days)", days == 1 ? "AKTIVER TAG" : "AKTIVE TAGE")
            }
        }

        Block(title: chartTitle) { activityChart(entries) }

        Block(title: "KATEGORIEN") {
            let counts = categoryCounts(entries)
            let cmax = max(1, counts.map { $0.n }.max() ?? 1)
            ForEach(counts) { cc in
                let c = cc.id, n = cc.n
                HStack(spacing: 10) {
                    Text(c.label.uppercased()).font(mono(11)).tracking(1).foregroundStyle(Color.fg).frame(width: 76, alignment: .leading)
                    meter(Double(n) / Double(cmax), color: c.color, height: 6)
                    Text("\(n)").font(mono(11)).monospacedDigit().foregroundStyle(Color.muted).frame(width: 28, alignment: .trailing)
                }
            }
        }

        Block(title: "ZIELE & REKORDE", trailing: store.hasBaseline
              ? "Anpassung in \(store.nextReviewDays) T · Rekordtag in \(store.daysToRecord) T"
              : "Noch keine Baseline") {
            VStack(spacing: 0) {
                ForEach(store.pool) { ex in progressRow(ex) }
            }
        }

        Block(title: "VERLAUF") {
            let recent = Array(entries.suffix(40).reversed())
            if recent.isEmpty {
                Text("Noch keine Übungen \(store.state.period == .day ? "heute" : "in diesem Zeitraum").")
                    .font(mono(12)).foregroundStyle(Color.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { l in logRow(l) }
                }
            }
        }
    }

    private func categoryCounts(_ entries: [LogEntry]) -> [CatCount] {
        ExCategory.allCases.map { c in CatCount(id: c, n: entries.filter { $0.cat == c.rawValue }.count) }
    }

    private func kpi(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).font(mono(24, .bold)).monospacedDigit().foregroundStyle(Color.fg)
            Label12(text: label)
        }
    }

    private var chartTitle: String {
        switch store.state.period {
        case .day: return "AKTIVITÄT NACH UHRZEIT"
        case .week, .month: return "ÜBUNGEN PRO TAG"
        case .year: return "ÜBUNGEN PRO MONAT"
        }
    }

    private struct Bucket: Identifiable { let id: Int; let label: String; let count: Int }

    private func buckets(_ entries: [LogEntry]) -> [Bucket] {
        let cal = Calendar(identifier: .iso8601)
        let start = Date(timeIntervalSince1970: store.periodStart(store.state.period) / 1000)
        func comp(_ l: LogEntry) -> Int {
            let d = Date(timeIntervalSince1970: l.ts / 1000)
            switch store.state.period {
            case .day: return cal.component(.hour, from: d)
            case .week: return cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: d)).day ?? 0
            case .month: return cal.component(.day, from: d) - 1
            case .year: return cal.component(.month, from: d) - 1
            }
        }
        let n: Int
        let label: (Int) -> String
        switch store.state.period {
        case .day: n = 24; label = { "\($0)" }
        case .week: n = 7; label = { ["MO", "DI", "MI", "DO", "FR", "SA", "SO"][$0] }
        case .month: n = cal.range(of: .day, in: .month, for: start)?.count ?? 31; label = { "\($0 + 1)" }
        case .year: n = 12; label = { ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"][$0] }
        }
        var counts = Array(repeating: 0, count: n)
        for l in entries { let i = comp(l); if i >= 0 && i < n { counts[i] += 1 } }
        return (0..<n).map { Bucket(id: $0, label: label($0), count: counts[$0]) }
    }

    private func activityChart(_ entries: [LogEntry]) -> some View {
        let data = buckets(entries)
        let every: Int = {
            switch store.state.period { case .day: return 6; case .week: return 1; case .month: return 7; case .year: return 2 }
        }()
        return Chart(data) { b in
            BarMark(x: .value("Zeit", b.id), y: .value("Anzahl", b.count))
                .foregroundStyle(Color.phos.opacity(0.85))
        }
        .chartXAxis {
            AxisMarks(values: data.map { $0.id }.filter { $0 % every == 0 }) { v in
                AxisValueLabel {
                    if let i = v.as(Int.self), i < data.count { Text(data[i].label).font(mono(9)).foregroundStyle(Color.muted) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel().font(mono(9)).foregroundStyle(Color.muted)
            }
        }
        .frame(height: 130)
    }

    private func progressRow(_ ex: Exercise) -> some View {
        let all = store.state.log.filter { $0.ex == ex.id && !$0.isTest }
        let u = ex.unit == .sec ? " s" : ""
        let rate = all.isEmpty ? "noch nicht gemacht" : "\(Int((Double(all.filter { $0.done }.count) / Double(all.count) * 100).rounded()))% geschafft"
        let change = store.state.trainer.targets[ex.id]?.change ?? 0
        let record = store.state.trainer.baseline?[ex.id]
        return HStack(spacing: 12) {
            Circle().fill(ex.cat.color).frame(width: 6, height: 6).glow(ex.cat.color, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(mono(13)).foregroundStyle(Color.fg)
                HStack(spacing: 4) {
                    Text("\(all.count)× · \(rate)")
                    if let r = record { Text("· Rekord \(r)\(u)").foregroundStyle(Color.amber) }
                }
                .font(mono(10.5)).foregroundStyle(Color.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(store.perTime(ex))\(u)\(ex.side ? "/S" : "")").foregroundStyle(Color.fg)
                if change > 0 { Text("▲\(change)").foregroundStyle(Color.phos) }
                if change < 0 { Text("▼\(-change)").foregroundStyle(Color.amber) }
            }
            .font(mono(12)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func logRow(_ l: LogEntry) -> some View {
        let ex = l.exercise
        let u = ex?.unit == .sec ? " s" : ""
        let color = ex?.cat.color ?? .muted
        return HStack(spacing: 12) {
            Circle().fill(color).frame(width: 6, height: 6).glow(color, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? l.ex).font(mono(13)).foregroundStyle(Color.fg)
                Text(fmtTime(l.ts)).font(mono(10.5)).foregroundStyle(Color.muted)
            }
            Spacer()
            Group {
                if l.isTest { Text("REKORD \(l.actual)\(u)").foregroundStyle(Color.amber).bold() }
                else if l.isBoss { Text("BOSS \(l.actual)\(u)").foregroundStyle(Color.amber).bold() }
                else if l.manual == true { Text("+ \(l.actual)\(u)").foregroundStyle(Color.wire) }
                else if l.done { Text("✓ \(l.target)\(u)").foregroundStyle(Color.phos) }
                else { Text("\(l.actual) / \(l.target)\(u)").foregroundStyle(Color.muted) }
            }
            .font(mono(12)).monospacedDigit()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}
