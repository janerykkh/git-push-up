import SwiftUI
import CoreMotion

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

    /// Tiefe der Ebenen für den Parallax-Effekt (0 = ganz hinten, >1 = vor den Eiern)
    static let depths: [CGFloat] = [0.15, 0.3, 0.55, 0.8, 1.3]

    /// Die Lichtung in fünf Ebenen: Hintergrund, Lichtstrahl, mittlere Pflanzen, Moosbett, vordere Wedel.
    /// Alle Ebenen außer der hintersten sind durchsichtig. `eggs`: Lage der Eier (für Schatten im Moos).
    static func layers(_ w: Int, _ h: Int, eggs: [(Double, Double)]) -> [PixelCanvas] {
        let W = Double(w), H = Double(h)
        var rnd = Mulberry32(90210)

        func frond(_ c: inout PixelCanvas, _ bx: Double, _ by: Double, _ ang: Double, _ len: Double, _ col: RGB, _ curl: Double, leaf: Double = 1) {
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
        func bulb(_ c: inout PixelCanvas, _ bx: Double, _ by: Double, _ hgt: Double, _ lean: Double, _ glow: RGB) {
            let tx = bx + lean, ty = by - hgt
            c.line(bx, by, tx, ty, (34, 70, 62))
            c.rect(tx - 1, ty - 1, tx + 2, ty + 2, glow)
            c.set(tx, ty - 2, glow, 0.5); c.set(tx - 2, ty, glow, 0.4); c.set(tx + 2, ty, glow, 0.4)
            c.set(tx, ty, (255, 255, 255), 0.7)
        }

        // 0: Himmel unter dem Blätterdach, dunkle Wedel im Dunst
        var far = PixelCanvas(w, h, opaque: true)
        for y in 0..<h {
            let t = Double(y) / H
            for x in 0..<w {
                let q = (bayer[y & 3][x & 3] / 16 - 0.5) * 0.08
                let k = clampD(t + q, 0, 1)
                far.set(Double(x), Double(y), (UInt8(26 - 20 * k), UInt8(60 - 46 * k), UInt8(66 - 50 * k)))
            }
        }
        let farCols: [RGB] = [(28, 66, 66), (34, 74, 70), (40, 62, 76)]
        for _ in 0..<26 {
            let side = rnd.next() < 0.5
            let bx = side ? rnd.range(-10, W * 0.3) : rnd.range(W * 0.7, W + 10)
            let by = rnd.range(-10, H * 0.55)
            let ang = side ? rnd.range(-0.4, 0.9) : Double.pi - rnd.range(-0.4, 0.9)
            frond(&far, bx, by, ang, rnd.range(25, 55), farCols[Int(rnd.next() * 3)], rnd.range(-0.8, 0.8), leaf: 1.2)
        }
        for _ in 0..<18 {
            let bx = rnd.range(-10, W + 10)
            frond(&far, bx, -6, rnd.range(0.6, 2.5), rnd.range(25, 50), (22, 54, 50), rnd.range(-1, 1), leaf: 1.4)
        }

        // 1: Lichtstrahl
        var beamL = PixelCanvas(w, h, opaque: false)
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
                if a > 0.02 { beamL.set(Double(x), Double(y), (200, 255, 228), min(0.6, (a * 10).rounded() / 10)) }
            }
        }

        // 2: mittlere Pflanzen und Leuchtknospen
        var mid = PixelCanvas(w, h, opaque: false)
        let midCols: [RGB] = [(52, 128, 104), (70, 150, 120), (96, 84, 150), (44, 110, 120)]
        for i in 0..<14 {
            let left = i % 2 == 0
            let bx = left ? rnd.range(-6, W * 0.32) : rnd.range(W * 0.68, W + 6)
            let by = rnd.range(H * 0.45, H * 0.82)
            let ang = left ? rnd.range(-1.4, -0.5) : -Double.pi + rnd.range(0.5, 1.4)
            frond(&mid, bx, by, ang, rnd.range(28, 60), midCols[Int(rnd.next() * 4)], left ? rnd.range(0.4, 1.2) : -rnd.range(0.4, 1.2))
        }
        let glows: [RGB] = [(120, 255, 220), (240, 140, 255), (255, 210, 120)]
        for i in 0..<9 {
            let bx = i % 2 == 0 ? rnd.range(W * 0.05, W * 0.3) : rnd.range(W * 0.7, W * 0.95)
            bulb(&mid, bx, rnd.range(H * 0.7, H * 0.86), rnd.range(10, 26), rnd.range(-4, 4), glows[i % 3])
        }

        // 3: Moosbett, in der Mitte vom Licht getroffen, mit Schatten unter den Eiern
        var bed = PixelCanvas(w, h, opaque: false)
        let (mx, my, rx, ry) = moundCenter(w, h)
        for y in max(0, Int(my - ry * 1.4))..<min(h, Int(my + ry * 3)) {
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
                // Kante oben heller (Licht von oben), Flanke unten dunkel: wirkt wie ein Hügel
                if dy < 0 && top > 0.82 { col = (col.0 / 2 + 40, col.1 / 2 + 70, col.2 / 2 + 54) }
                if dy > 0.6 { col = dy > 1.4 ? (10, 22, 20) : (14, 30, 26) }
                bed.set(Double(x), Double(y), col)
            }
        }
        for e in eggs {
            // weicher Schatten rechts unterhalb (Licht kommt von oben rechts)
            let sx = e.0 - 2, sy = e.1 + 1
            for yy in -2...2 { for xx in -8...8 where Double(xx * xx) / 64 + Double(yy * yy) / 5 <= 1 {
                bed.set(sx + Double(xx), sy + Double(yy), (6, 16, 14), 0.55)
            } }
        }
        for _ in 0..<70 {
            let a = rnd.range(-Double.pi, 0)
            let x = mx + cos(a) * rx * rnd.range(0.7, 1.02), y = my + sin(a) * ry * rnd.range(0.4, 1)
            bed.line(x, y, x + rnd.range(-2, 2), y - rnd.range(2, 6), (60, 120, 90))
        }

        // 4: vordere Wedel, groß und dunkel, ganz nah
        var front = PixelCanvas(w, h, opaque: false)
        let frontCols: [RGB] = [(14, 36, 32), (20, 44, 40), (26, 34, 50)]
        for i in 0..<16 {
            let left = i % 2 == 0
            let bx = left ? rnd.range(-12, W * 0.35) : rnd.range(W * 0.65, W + 12)
            frond(&front, bx, H + 4, left ? rnd.range(-1.3, -0.6) : -Double.pi + rnd.range(0.6, 1.3), rnd.range(40, 80),
                  frontCols[i % 3], left ? rnd.range(0.3, 0.9) : -rnd.range(0.3, 0.9), leaf: 1.6)
        }
        return [far, beamL, mid, bed, front]
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

/// Neigung des iPhones, geglättet, für den Parallax-Effekt
final class Tilt: ObservableObject {
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0
    private let mm = CMMotionManager()
    func start() {
        guard mm.isDeviceMotionAvailable else { return }
        mm.deviceMotionUpdateInterval = 1.0 / 30
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            // Ruhelage: iPhone leicht schräg in der Hand
            let tx = CGFloat(max(-1, min(1, g.x * 2.2)))
            let ty = CGFloat(max(-1, min(1, (g.y + 0.6) * 2.2)))
            self.x += (tx - self.x) * 0.12
            self.y += (ty - self.y) * 0.12
        }
    }
    func stop() { mm.stopDeviceMotionUpdates() }
}

struct EggSelectView: View {
    @EnvironmentObject var store: Store
    @StateObject private var tilt = Tilt()
    @State private var seeds: [Int] = Clearing.clutch()
    @State private var chosen: Int? = nil
    @State private var name = ""
    @State private var layers: [CGImage] = []
    @State private var dims: (Int, Int) = (0, 0)
    @State private var eggs: [Int: CGImage] = [:]
    @FocusState private var nameFocus: Bool

    /// Rand in Pixeln, damit sich die Ebenen verschieben können, ohne dass Lücken entstehen
    private let margin = 14
    /// Lage der Eier auf dem Moosbett (Anteil vom Radius)
    private let spots: [(Double, Double)] = [(-0.62, -0.1), (-0.36, 0.25), (-0.1, -0.25), (0.14, 0.2), (0.4, -0.15), (0.64, 0.22)]

    private func eggPos(_ i: Int, _ w: Int, _ h: Int) -> (Double, Double) {
        let (mx, my, rx, ry) = Clearing.moundCenter(w, h)
        let p = spots[i]
        return (mx + p.0 * rx * 0.95, my + p.1 * ry * 1.6)    // Fußpunkt des Eis
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let w = Int(ceil(geo.size.width / PX)) + 2 * margin, h = Int(ceil(geo.size.height / PX)) + 2 * margin
                ZStack(alignment: .topLeading) {
                    Color(hex: 0x061210)
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        // leichtes Atmen, auch ohne Neigung
                        let ix = tilt.x + CGFloat(sin(t * 0.35)) * 0.15, iy = tilt.y + CGFloat(cos(t * 0.27)) * 0.1
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(layers.enumerated()), id: \.offset) { i, img in
                                layerView(img, depth: Clearing.depths[i], ix: ix, iy: iy)
                                if i == 2 { dust(w: w, h: h).offset(shift(Clearing.depths[2], ix, iy)) }
                                if i == 3 { eggLayer(w: w, h: h, t: t).offset(shift(Clearing.depths[3], ix, iy)) }
                            }
                        }
                    }
                }
                .onAppear { build(w, h) }
            }
            .ignoresSafeArea()

            overlayUI
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }

    /// Verschiebung einer Ebene: tiefer liegende bewegen sich weniger, alles auf ganze Pixel gerundet
    private func shift(_ depth: CGFloat, _ ix: CGFloat, _ iy: CGFloat) -> CGSize {
        let m = CGFloat(margin) * PX
        return CGSize(width: snap(-m + ix * depth * m * 0.9), height: snap(-m + iy * depth * m * 0.6))
    }

    private func layerView(_ img: CGImage, depth: CGFloat, ix: CGFloat, iy: CGFloat) -> some View {
        Image(decorative: img, scale: 1).resizable().interpolation(.none)
            .frame(width: CGFloat(dims.0) * PX, height: CGFloat(dims.1) * PX)
            .offset(shift(depth, ix, iy))
            .allowsHitTesting(false)
    }

    private func build(_ w: Int, _ h: Int) {
        guard layers.isEmpty else { return }
        let s = seeds
        let pos = (0..<6).map { eggPos($0, w, h) }
        Task {
            let out = await Task.detached(priority: .userInitiated) { () -> ([CGImage], [Int: CGImage]) in
                var e: [Int: CGImage] = [:]
                for sd in s { if let i = Clearing.egg(seed: sd).image { e[sd] = i } }
                let ls = Clearing.layers(w, h, eggs: pos).compactMap { $0.image }
                return (ls, e)
            }.value
            eggs = out.1
            dims = (w, h)
            withAnimation(.easeOut(duration: 0.6)) { layers = out.0 }
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
        .frame(width: CGFloat(w) * PX, height: CGFloat(h) * PX)
        .allowsHitTesting(false)
    }

    private func eggLayer(w: Int, h: Int, t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(seeds.enumerated()), id: \.offset) { i, s in
                if let img = eggs[s] {
                    let p = eggPos(i, w, h)
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
                    .frame(width: 16 * PX, height: 20 * PX)
                    .contentShape(Rectangle())
                    .offset(x: snap(CGFloat(p.0 - 8) * PX) + wob, y: snap(CGFloat(p.1 - 18) * PX))
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        chosen = s
                        name = CreatureModel.syllableName(s)
                    }
                }
            }
        }
        .frame(width: CGFloat(w) * PX, height: CGFloat(h) * PX, alignment: .topLeading)
    }

    /// Bedienung: oben der Titel, unten das Namensfeld. Liegt außerhalb der Szene und rückt mit der Tastatur hoch.
    private var overlayUI: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BRUTSTÄTTE").font(display(30)).tracking(1).foregroundStyle(Color(hex: 0xe9f5ee))
                Text("SEKTOR 7 // SECHS EIER // UNBEKANNTE ART").font(mono(10)).foregroundStyle(Color(hex: 0x9cc6b4))
            }
            .padding(.top, 14).padding(.horizontal, 16)
            .allowsHitTesting(false)
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
                        .onSubmit { nameFocus = false }
                        .padding(.horizontal, 10).frame(height: 46)
                        .background(PixelBlock().fill(Color.panel))
                        .pixelBorder()
                    Button {
                        nameFocus = false
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
                .padding(.horizontal, 12).padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tippe auf ein Ei.").font(mono(13)).foregroundStyle(Color(hex: 0xcfe6dc))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
                    .allowsHitTesting(false)
            }
        }
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
        rescheduleReminders()
    }
}
