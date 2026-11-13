import SwiftUI

/// Erster Start: eine fremde Lichtung, ein Lichtstrahl fällt auf ein Moosbett mit sechs Eiern.
/// Jedes Ei trägt die Farben eines möglichen Wesens (Farbschema aus dessen Erbgut). Eins wählen, benennen, ausbrüten.
enum Clearing {
    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    /// Der Lichtstrahl: von oben rechts schräg auf die Mitte des Moosbetts
    static func beam(_ w: Int, _ h: Int) -> (top: (Double, Double), bottom: (Double, Double), wTop: Double, wBottom: Double) {
        let W = Double(w), H = Double(h)
        return ((W * 0.64, -4), (W * 0.5, H * 0.74), W * 0.10, W * 0.36)
    }

    static func moundCenter(_ w: Int, _ h: Int) -> (Double, Double, Double, Double) {
        (Double(w) * 0.5, Double(h) * 0.77, Double(w) * 0.44, Double(h) * 0.075)
    }

    static func scene(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h, opaque: true)
        let W = Double(w), H = Double(h)
        var rnd = Mulberry32(90210)

        // Himmel unter dem Blätterdach: oben trübes Petrol, unten fast schwarz
        for y in 0..<h {
            let t = Double(y) / H
            for x in 0..<w {
                let q = (bayer[y & 3][x & 3] / 16 - 0.5) * 0.08
                let k = clampD(t + q, 0, 1)
                c.set(Double(x), Double(y), (UInt8(26 - 20 * k), UInt8(60 - 46 * k), UInt8(66 - 50 * k)))
            }
        }

        /// Wedel: gebogener Stiel mit Fiederblättchen links und rechts
        func frond(_ bx: Double, _ by: Double, _ ang: Double, _ len: Double, _ col: RGB, _ curl: Double, leaf: Double = 1) {
            var x = bx, y = by, a = ang
            let steps = Int(len)
            for i in 0..<steps {
                let t = Double(i) / Double(steps)
                let nx = x + cos(a), ny = y + sin(a)
                c.line(x, y, nx, ny, col)
                if i % 2 == 0 && t > 0.08 {
                    let l = (1 - t) * 7 * leaf + 1
                    for side in [-1.0, 1.0] {
                        let la = a + side * 1.1 - curl * 0.3
                        c.line(nx, ny, nx + cos(la) * l, ny + sin(la) * l, col)
                    }
                }
                a += curl / Double(steps)
                x = nx; y = ny
            }
        }

        /// Fremde Leuchtpflanze: dünner Stiel, oben eine leuchtende Knospe
        func bulb(_ bx: Double, _ by: Double, _ hgt: Double, _ lean: Double, _ glow: RGB) {
            let tx = bx + lean, ty = by - hgt
            c.line(bx, by, tx, ty, (34, 70, 62))
            c.rect(tx - 1, ty - 1, tx + 2, ty + 2, glow)
            c.set(tx, ty - 2, glow, 0.5); c.set(tx - 2, ty, glow, 0.4); c.set(tx + 2, ty, glow, 0.4)
            c.set(tx, ty, (255, 255, 255), 0.7)
        }

        // Hinterste Schicht: dunkle Wedel von oben und den Seiten, fast im Dunst
        let far: [RGB] = [(28, 66, 66), (34, 74, 70), (40, 62, 76)]
        for _ in 0..<26 {
            let side = rnd.next() < 0.5
            let bx = side ? rnd.range(-10, W * 0.3) : rnd.range(W * 0.7, W + 10)
            let by = rnd.range(-10, H * 0.55)
            let ang = side ? rnd.range(-0.4, 0.9) : Double.pi - rnd.range(-0.4, 0.9)
            frond(bx, by, ang, rnd.range(25, 55), far[Int(rnd.next() * 3)], rnd.range(-0.8, 0.8), leaf: 1.2)
        }
        // Blätterdach oben
        for _ in 0..<18 {
            let bx = rnd.range(-10, W + 10)
            frond(bx, -6, rnd.range(0.6, 2.5), rnd.range(25, 50), (22, 54, 50), rnd.range(-1, 1), leaf: 1.4)
        }

        // Lichtstrahl: weicher Kegel, gerastert
        let B = beam(w, h)
        for y in 0..<h {
            let t = clampD((Double(y) - B.top.1) / (B.bottom.1 - B.top.1), 0, 1.15)
            let cx = B.top.0 + (B.bottom.0 - B.top.0) * t, half = (B.wTop + (B.wBottom - B.wTop) * t) / 2
            for x in 0..<w {
                let d = abs(Double(x) - cx) / half
                if d >= 1 { continue }
                let streak = 0.75 + 0.25 * sin(Double(x) * 0.9 + Double(y) * 0.12)
                var a = (1 - d * d) * 0.42 * streak * (t > 1 ? max(0, 1 - (t - 1) * 8) : 1)
                a += (bayer[y & 3][x & 3] / 16 - 0.5) * 0.12
                if a > 0.02 { c.set(Double(x), Double(y), (200, 255, 228), min(0.6, (a * 10).rounded() / 10)) }
            }
        }

        // Mittlere Schicht: fremde Wedel in Türkis, Grün und Violett, angeleuchtet nahe dem Strahl
        let mid: [RGB] = [(52, 128, 104), (70, 150, 120), (96, 84, 150), (44, 110, 120)]
        for i in 0..<14 {
            let left = i % 2 == 0
            let bx = left ? rnd.range(-6, W * 0.32) : rnd.range(W * 0.68, W + 6)
            let by = rnd.range(H * 0.45, H * 0.82)
            let ang = left ? rnd.range(-1.4, -0.5) : -Double.pi + rnd.range(0.5, 1.4)
            frond(bx, by, ang, rnd.range(28, 60), mid[Int(rnd.next() * 4)], left ? rnd.range(0.4, 1.2) : -rnd.range(0.4, 1.2))
        }
        // Leuchtpflanzen
        let glows: [RGB] = [(120, 255, 220), (240, 140, 255), (255, 210, 120)]
        for i in 0..<9 {
            let bx = i % 2 == 0 ? rnd.range(W * 0.05, W * 0.3) : rnd.range(W * 0.7, W * 0.95)
            bulb(bx, rnd.range(H * 0.7, H * 0.86), rnd.range(10, 26), rnd.range(-4, 4), glows[i % 3])
        }

        // Moosbett, in der Mitte vom Licht getroffen
        let (mx, my, rx, ry) = moundCenter(w, h)
        for y in Int(my - ry * 1.4)..<min(h, Int(my + ry * 3)) {
            for x in 0..<w {
                let dx = (Double(x) - mx) / rx, dy = (Double(y) - my) / ry
                let top = dy < 0 ? dx * dx + dy * dy : dx * dx + (dy / 2.2) * (dy / 2.2)
                if top > 1 { continue }
                let lit = max(0, 1 - hypot(dx * 1.6, dy * 0.9))
                let q = bayer[y & 3][x & 3] / 16
                var col: RGB = (22, 44, 38)
                if lit > 0.15 + q * 0.3 { col = (40, 80, 64) }
                if lit > 0.45 + q * 0.3 { col = (70, 124, 92) }
                if lit > 0.75 + q * 0.2 { col = (120, 170, 120) }
                if dy > 0.6 { col = dy > 1.4 ? (10, 22, 20) : (14, 30, 26) }
                c.set(Double(x), Double(y), col)
            }
        }
        // Grashalme am Rand des Mooses
        for _ in 0..<60 {
            let a = rnd.range(-Double.pi, 0)
            let x = mx + cos(a) * rx * rnd.range(0.7, 1.02), y = my + sin(a) * ry * rnd.range(0.4, 1)
            c.line(x, y, x + rnd.range(-2, 2), y - rnd.range(2, 6), (60, 120, 90))
        }

        // Vorderste Schicht: dunkle, große Wedel unten in den Ecken
        let front: [RGB] = [(18, 44, 38), (24, 52, 46), (30, 40, 58)]
        for i in 0..<16 {
            let left = i % 2 == 0
            let bx = left ? rnd.range(-12, W * 0.35) : rnd.range(W * 0.65, W + 12)
            frond(bx, H + 4, left ? rnd.range(-1.3, -0.6) : -Double.pi + rnd.range(0.6, 1.3), rnd.range(40, 80),
                  front[i % 3], left ? rnd.range(0.3, 0.9) : -rnd.range(0.3, 0.9), leaf: 1.5)
        }
        return c
    }

    /// Ein Ei in den Farben eines Wesens: Grundfarbe mit Licht und Schatten, Flecken in der Zweitfarbe, dunkler Umriss
    static func egg(seed: Int, w: Int = 16, h: Int = 20) -> PixelCanvas {
        let pal = Palette(Genome(seed: seed))
        var c = PixelCanvas(w, h, opaque: false)
        var r = Mulberry32(seed &+ 77)
        let spots = (0..<5).map { _ in (r.range(-0.6, 0.6), r.range(-0.7, 0.5), r.range(0.12, 0.22)) }
        func inside(_ x: Double, _ y: Double) -> Bool {
            let u = x / (Double(w) / 2), v = y / (Double(h) / 2)
            let rxv = v < 0 ? 1 - 0.22 * (-v) : 1     // oben schmaler
            return (u / rxv) * (u / rxv) + v * v <= 1
        }
        for j in 0..<h {
            for i in 0..<w {
                let x = Double(i) + 0.5 - Double(w) / 2, y = Double(j) + 0.5 - Double(h) / 2
                guard inside(x, y) else { continue }
                let edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
                var col = pal.a.base
                if !inside(x + 1.6, y - 1.6) { col = pal.a.hi }                 // Licht von oben rechts
                else if !inside(x - 1.8, y + 1.8) { col = pal.a.sh }            // Schatten unten links
                let u = x / (Double(w) / 2), v = y / (Double(h) / 2)
                for s in spots where hypot(u - s.0, (v - s.1) * 0.9) < s.2 { col = pal.b.base }
                if edge { col = pal.a.line }
                c.set(Double(i), Double(j), col)
            }
        }
        // Glanzpunkt
        c.set(Double(w) * 0.66, Double(h) * 0.25, (255, 255, 250))
        return c
    }

    /// Sechs Samen mit deutlich verschiedenen Grundfarben
    static func clutch() -> [Int] {
        var seeds: [Int] = []
        var hues: [Double] = []
        var tries = 0
        while seeds.count < 6 && tries < 400 {
            tries += 1
            let s = Int.random(in: 1...999_998)
            let h = Genome(seed: s).hue
            if hues.allSatisfy({ min(abs($0 - h), 360 - abs($0 - h)) > 32 }) || tries > 300 {
                seeds.append(s); hues.append(h)
            }
        }
        return seeds
    }
}

struct EggSelectView: View {
    @EnvironmentObject var store: Store
    @State private var seeds: [Int] = Clearing.clutch()
    @State private var chosen: Int? = nil
    @State private var name = ""
    @State private var bg: (CGImage?, Int, Int)? = nil
    @State private var eggs: [Int: CGImage] = [:]
    @FocusState private var nameFocus: Bool

    /// Lage der Eier auf dem Moosbett (Anteil vom Radius)
    private let spots: [(Double, Double)] = [(-0.62, -0.1), (-0.36, 0.25), (-0.1, -0.25), (0.14, 0.2), (0.4, -0.15), (0.64, 0.22)]

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let H = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let w = Int(ceil(W / PX)), h = Int(ceil(H / PX))
            ZStack(alignment: .topLeading) {
                Color(hex: 0x061210)
                if let b = bg, let img = b.0 {
                    Image(decorative: img, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(b.1) * PX, height: CGFloat(b.2) * PX)
                }
                dust(w: w, h: h)
                eggLayer(w: w, h: h)
                overlayUI(topInset: geo.safeAreaInsets.top, bottomInset: geo.safeAreaInsets.bottom, W: W, H: H)
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .onAppear { build(w, h) }
        }
        .ignoresSafeArea()
    }

    private func build(_ w: Int, _ h: Int) {
        guard bg == nil else { return }
        let s = seeds
        Task {
            let out = await Task.detached(priority: .userInitiated) { () -> (CGImage?, [Int: CGImage]) in
                var e: [Int: CGImage] = [:]
                for sd in s { if let i = Clearing.egg(seed: sd).image { e[sd] = i } }
                return (Clearing.scene(w, h).image, e)
            }.value
            eggs = out.1
            withAnimation(.easeOut(duration: 0.6)) { bg = (out.0, w, h) }
        }
    }

    /// Staub im Lichtstrahl, langsam schwebend
    private func dust(w: Int, h: Int) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { tl in
            Canvas { ctx, _ in
                let t = tl.date.timeIntervalSinceReferenceDate
                let B = Clearing.beam(w, h)
                var r = Mulberry32(7)
                for _ in 0..<40 {
                    let ty = r.next(), off = r.range(-0.4, 0.4), sp = r.range(0.01, 0.03), ph = r.range(0, 6.28)
                    let tt = (ty + t * sp).truncatingRemainder(dividingBy: 1)
                    let cx = B.top.0 + (B.bottom.0 - B.top.0) * tt, half = (B.wTop + (B.wBottom - B.wTop) * tt) / 2
                    let x = cx + off * half * 2 + sin(t * 0.7 + ph) * 2
                    let y = B.top.1 + (B.bottom.1 - B.top.1) * tt
                    let a = 0.35 + 0.35 * sin(t * 2 + ph)
                    ctx.fill(Path(CGRect(x: snap(CGFloat(x) * PX), y: snap(CGFloat(y) * PX), width: PX, height: PX)),
                             with: .color(Color(red: 0.85, green: 1, blue: 0.92).opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func eggLayer(w: Int, h: Int) -> some View {
        let (mx, my, rx, ry) = Clearing.moundCenter(w, h)
        return TimelineView(.animation(minimumInterval: 1 / 10)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(Array(seeds.enumerated()), id: \.offset) { i, s in
                    if let img = eggs[s] {
                        let p = spots[i]
                        let ex = mx + p.0 * rx * 0.95 - 8, ey = my + p.1 * ry * 1.6 - 18
                        let sel = chosen == s
                        // gewähltes Ei wackelt pixelweise
                        let wob: CGFloat = sel ? (Int(t * 6) % 4 == 0 ? PX : (Int(t * 6) % 4 == 2 ? -PX : 0)) : 0
                        ZStack(alignment: .top) {
                            Image(decorative: img, scale: 1).resizable().interpolation(.none)
                                .frame(width: 16 * PX, height: 20 * PX)
                            if sel {
                                PixelIcon(rows: ["#####", ".###.", "..#.."], color: .signal).offset(y: -PX * 6)
                            }
                        }
                        .offset(x: snap(CGFloat(ex) * PX) + wob, y: snap(CGFloat(ey) * PX))
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            chosen = s
                            name = CreatureModel.syllableName(s)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func overlayUI(topInset: CGFloat, bottomInset: CGFloat, W: CGFloat, H: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BRUTSTÄTTE").font(display(30)).tracking(1).foregroundStyle(Color(hex: 0xe9f5ee))
                Text("SEKTOR 7 // SECHS EIER // UNBEKANNTE ART").font(mono(10)).foregroundStyle(Color(hex: 0x9cc6b4))
            }
            .padding(.top, topInset + 14).padding(.horizontal, 16)
            Spacer()
            if let s = chosen {
                let pal = Palette(Genome(seed: s))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("EI \(String(format: "%02d", (seeds.firstIndex(of: s) ?? 0) + 1)) // SCHEMA").font(labelFont(10)).tracking(0.8)
                        Spacer()
                        ForEach(Array([pal.a.hi, pal.a.base, pal.a.sh, pal.b.base, pal.glow.base].enumerated()), id: \.offset) { _, c in
                            Rectangle().fill(Color(.sRGB, red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255, opacity: 1))
                                .frame(width: PX * 6, height: PX * 6)
                        }
                    }
                    TextField("Name", text: $name)
                        .font(display(26)).foregroundStyle(Color.fg)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .focused($nameFocus)
                        .submitLabel(.done)
                        .padding(.horizontal, 10).frame(height: 46)
                        .background(PixelBlock().fill(Color.panel))
                        .pixelBorder()
                    Button {
                        store.hatch(seed: s, name: name)
                    } label: {
                        Text("AUSBRÜTEN").font(display(22)).tracking(1).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(PixelBlock().fill(Color.signal))
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(12)
                .background(PixelBlock().fill(Color.bg))
                .pixelBorder()
                .padding(.horizontal, 12).padding(.bottom, bottomInset + 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tippe auf ein Ei.").font(mono(13)).foregroundStyle(Color(hex: 0xcfe6dc))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, bottomInset + 28)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .animation(.easeOut(duration: 0.25), value: chosen)
    }
}

extension Store {
    /// Gewähltes Ei ausbrüten: ab jetzt wächst dieses Wesen
    func hatch(seed: Int, name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = nowMs()
        state.creature = CreatureState(seed: seed, born: now, name: String((n.isEmpty ? CreatureModel.syllableName(seed) : n).prefix(18)),
                                       updated: now, hatched: true)
        save()
    }
}
