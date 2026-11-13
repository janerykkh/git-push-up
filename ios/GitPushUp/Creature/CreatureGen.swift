import Foundation

// Prozedurales Wesen: 1:1 aus dem Brutkasten-Prototyp übertragen.
// Gleicher Samen ergibt dasselbe Wesen wie im Browser (gleicher Zufallsgenerator, gleiche Reihenfolge der Würfe).
// Alles in normierten Koordinaten (-1…1), am Ende auf ein N×N-Pixelraster gerastert.

// MARK: - Hilfen

@inline(__always) func clampD(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
@inline(__always) func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clampD((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
}
@inline(__always) private func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

/// mulberry32, bitgleich zur JavaScript-Version
struct Mulberry32 {
    var a: UInt32
    init(_ seed: Int) { a = UInt32(truncatingIfNeeded: Int64(seed) &* 9973 &+ 17) }
    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    mutating func pick<T>(_ arr: [T]) -> T { arr[Int(floor(next() * Double(arr.count)))] }
}

// MARK: - Erbgut

enum Posture: String { case stehend, liegend, hockend }
enum BodyProfile: String { case kopflastig, bauchig, verjuengt, gleich }
enum AppKind: String { case tentakel, bein, fuehler, flosse }

struct SpineSeg { var bend, r, sx, gap: Double }
struct Harmonic { var k, a, p: Double }
struct Warp { var a, f1, f2, p1, p2: Double }
struct Appendage { var kind: AppKind; var ball: Int; var th, len, thick, curl, phase, sprout: Double }
struct EyeGene { var u, v, s: Double; var stalk: Bool; var at: Double }

struct Genome {
    var seed: Int
    var hue, hue2: Double
    var sym: Bool
    var posture: Posture
    var facing: Double
    var baseAng: Double
    var profile: BodyProfile
    var spine: [SpineSeg]
    var harm: [Harmonic]
    var warp: Warp
    var apps: [Appendage]
    var eyes: [EyeGene]
    var sat, light: Double
    var eyeStyle: String
    var mouth: String
    var mouthW, mouthU: Double
    var top: String
    var topSize: Double
    var pattern: String
    var pat: Double
    var glowSpots: [(Double, Double)]

    init(seed: Int) {
        var r = Mulberry32(seed)
        self.seed = seed
        hue = r.next() * 360
        hue2 = (hue + r.pick([45.0, -45, 150, 180, 200, -160]) + 360).truncatingRemainder(dividingBy: 360)
        sym = r.next() < 0.25
        posture = Posture(rawValue: r.pick(["stehend", "stehend", "liegend", "liegend", "hockend"]))!
        facing = r.next() < 0.5 ? 1 : -1
        switch posture {
        case .stehend: baseAng = -Double.pi / 2 + r.range(-0.3, 0.3)
        case .liegend: baseAng = (facing > 0 ? 0 : Double.pi) + r.range(-0.25, 0.15) * facing
        case .hockend: baseAng = (facing > 0 ? -Double.pi / 4 : -3 * Double.pi / 4) + r.range(-0.2, 0.2)
        }
        let nS = r.pick([1, 2, 2, 3, 3, 4, 5])
        profile = BodyProfile(rawValue: r.pick(["kopflastig", "bauchig", "verjuengt", "gleich"]))!
        var sp: [SpineSeg] = []
        for _ in 0..<nS {
            let bend = r.range(-0.7, 0.7), rr = r.range(0.82, 1.2), sx = r.range(0.82, 1.22), gap = r.range(0.5, 0.75)
            sp.append(SpineSeg(bend: bend, r: rr, sx: sx, gap: gap))
        }
        spine = sp
        var hs: [Harmonic] = []
        for k in [2.0, 3, 4, 5, 7] {
            let a = r.range(0, k < 4 ? 0.14 : 0.06), p = r.range(0, 6.283)
            hs.append(Harmonic(k: k, a: a, p: p))
        }
        harm = hs
        let wa = r.range(0.4, 1.3), f1 = r.range(4, 9), f2 = r.range(4, 9), p1 = r.next() * 6.28, p2 = r.next() * 6.28
        warp = Warp(a: wa, f1: f1, f2: f2, p1: p1, p2: p2)

        var aps: [Appendage] = []
        let nA = r.pick([2, 3, 3, 4, 4, 5, 6])
        for _ in 0..<nA {
            let kind = AppKind(rawValue: r.pick(["tentakel", "tentakel", "bein", "bein", "fuehler", "flosse"]))!
            let ball = kind == .fuehler ? nS - 1 : Int(floor(r.next() * Double(nS)))
            let th: Double
            switch kind {
            case .fuehler: th = r.range(-2.6, -0.5)
            case .bein: th = Double.pi / 2 + r.range(-0.55, 0.55)
            case .flosse: th = r.next() < 0.5 ? r.range(-0.6, 0.5) : Double.pi + r.range(-0.5, 0.6)
            case .tentakel: th = r.range(0.2, 2.9)
            }
            let len = r.range(0.3, 0.6), thick = r.range(0.05, 0.095), curl = r.range(-1, 1)
            let phase = r.range(0, 6.28), sprout = r.range(0.28, 0.72)
            let ap = Appendage(kind: kind, ball: ball, th: th, len: len, thick: thick, curl: curl, phase: phase, sprout: sprout)
            aps.append(ap)
            if sym && abs(cos(th)) > 0.25 {
                var m = ap; m.th = Double.pi - th; m.curl = -ap.curl
                aps.append(m)
            }
        }
        apps = aps

        var es: [EyeGene] = []
        let nE = r.pick([1, 2, 2, 3, 3, 4, 5])
        var tries = 0
        while es.count < nE && tries < 60 {
            let u = r.range(-0.6, 0.6), v = r.range(-0.62, 0.15)
            let s = r.range(0.14, 0.3) * (es.isEmpty ? 1.2 : 1)
            let stalk = r.next() < 0.22
            let at = r.range(0.08, 0.6)
            var e = EyeGene(u: u, v: v, s: s, stalk: stalk, at: at)
            if es.isEmpty { e.at = 0.08; if sym { e.u = 0 } }
            if es.allSatisfy({ hypot($0.u - e.u, $0.v - e.v) > $0.s + e.s + 0.06 }) { es.append(e) }
            tries += 1
        }
        eyes = es

        sat = r.range(20, 46)
        light = r.range(50, 66)
        eyeStyle = r.pick(["glanz", "glanz", "iris", "facette", "ring"])
        mouth = r.pick(["spalt", "poren", "keiner", "mandibeln", "strich", "spalt"])
        mouthW = r.range(0.12, 0.26)
        mouthU = sym ? 0 : r.range(-0.2, 0.2)
        top = r.pick(["keiner", "keiner", "kamm", "knospen"])
        topSize = r.range(0.8, 1.25)
        pattern = r.pick(["keins", "flecken", "adern", "adern", "bauch", "leuchtpunkte"])
        pat = r.next() * 1000
        var gs: [(Double, Double)] = []
        for _ in 0..<7 { let a = r.range(-0.7, 0.7), b = r.range(-0.6, 0.6); gs.append((a, b)) }
        glowSpots = gs
    }
}

// MARK: - Pflege → Ausprägung

/// Ausprägung der drei Pflegearten (0…1) plus Schweben.
struct Traits: Equatable {
    var s: Double   // Kraft
    var t: Double   // Dehnen
    var m: Double   // Geist
    var f: Double   // Schweben

    static let zero = Traits(s: 0, t: 0, m: 0, f: 0)

    /// Jeder Wert zählt absolut (Geist bleibt groß, auch wenn Kraft dazukommt), dazu kommt der Abstand zum Mittelwert,
    /// verstärkt je besser alles gepflegt ist: bei rundum guter Pflege entscheiden kleine Unterschiede.
    /// Schweben nur, wenn Geist anteilig klar vorn liegt.
    static func from(strength a: Double, stretch b: Double, mind c: Double) -> Traits {
        let mean = (a + b + c) / 3, gain = 0.6 + 1.4 * mean, sum = a + b + c
        func e(_ v: Double) -> Double { clampD(0.65 * v + (v - mean) * gain, 0, 1) }
        let share = sum > 0 ? c / sum : 0
        return Traits(s: e(a), t: e(b), m: e(c), f: clampD((share - 0.4) * 2.2, 0, 1) * smoothstep(0.2, 0.6, c))
    }
}

// MARK: - Farben

typealias RGB = (UInt8, UInt8, UInt8)

func hslToRgb(_ h0: Double, _ s0: Double, _ l0: Double) -> RGB {
    let h = ((h0.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    let s = clampD(s0, 0, 100) / 100, l = clampD(l0, 0, 100) / 100
    let a = s * min(l, 1 - l)
    func f(_ n: Double) -> UInt8 {
        let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
        let v = l - a * max(-1, min(k - 3, min(9 - k, 1)))
        return UInt8(clamping: jsRound(v * 255))
    }
    return (f(0), f(8), f(4))
}

struct Ramp { var hi, base, sh, deep, line: RGB }

func makeRamp(_ h: Double, _ s: Double, _ l: Double) -> Ramp {
    // Lichtseite wärmer, Schattenseite kühler: klassischer Pixel-Art-Trick
    Ramp(hi: hslToRgb(h - 10, s - 4, l + 13), base: hslToRgb(h, s, l), sh: hslToRgb(h + 18, s + 6, l - 16),
         deep: hslToRgb(h + 24, s - 2, l - 30), line: hslToRgb(h + 26, s - 12, 12))
}

enum RampKey { case a, b, bone, glow }

struct Palette {
    var a, b, bone, glow: Ramp
    var eyeW, pupil, iris, shine, mouth, inner: RGB
    var glowHue: Double

    /// vigor < 1: vernachlässigt, die Farben werden blasser
    init(_ G: Genome, vigor: Double = 1) {
        let v = clampD(vigor, 0, 1)
        let sat = G.sat * (0.45 + 0.55 * v)
        let light = lerpD(62, G.light, 0.5 + 0.5 * v)
        a = makeRamp(G.hue, sat, light)
        b = makeRamp(G.hue2, sat + 10 * v, min(78, light + 6))
        bone = makeRamp(48, 22, 80)
        glow = makeRamp(G.hue2, 80 * (0.4 + 0.6 * v), 66)
        eyeW = hslToRgb(G.hue2, 30, 88); pupil = (20, 18, 26); iris = hslToRgb(G.hue2, 62, 48); shine = (250, 252, 246)
        mouth = hslToRgb(G.hue + 26, 30, 16); inner = hslToRgb(G.hue2 + 20, 45, 40)
        glowHue = G.hue2
    }
    func ramp(_ k: RampKey) -> Ramp {
        switch k { case .a: return a; case .b: return b; case .bone: return bone; case .glow: return glow }
    }
}

// MARK: - Formen (Distanzfunktionen)

@inline(__always) func sdEll(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ n: Double) -> Double {
    let u = abs(x - cx) / rx, v = abs(y - cy) / ry
    if n == 2 { return (sqrt(u * u + v * v) - 1) * min(rx, ry) }
    return (pow(pow(u, n) + pow(v, n), 1 / n) - 1) * min(rx, ry)
}

@inline(__always) func sdSeg(_ x: Double, _ y: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ r0: Double, _ r1: Double) -> Double {
    let dx = bx - ax, dy = by - ay
    var l2 = dx * dx + dy * dy
    if l2 == 0 { l2 = 1e-9 }
    let t = clampD(((x - ax) * dx + (y - ay) * dy) / l2, 0, 1)
    return hypot(ax + dx * t - x, ay + dy * t - y) - (r0 + (r1 - r0) * t)
}

func sdChain(_ x: Double, _ y: Double, _ pts: [(Double, Double)], _ r0: Double, _ r1: Double) -> Double {
    var d = 1e9
    let n = pts.count - 1
    for i in 0..<n {
        let a = r0 + (r1 - r0) * Double(i) / Double(n), b = r0 + (r1 - r0) * Double(i + 1) / Double(n)
        d = min(d, sdSeg(x, y, pts[i].0, pts[i].1, pts[i + 1].0, pts[i + 1].1, a, b))
    }
    return d
}

/// Glied mit Muskelbäuchen: in der Mitte jedes Abschnitts dicker (Kraft)
func sdLimb(_ x: Double, _ y: Double, _ pts: [(Double, Double)], _ r0: Double, _ r1: Double, _ bulge: Double) -> Double {
    var d = 1e9
    let n = pts.count - 1
    for i in 0..<n {
        let ra = r0 + (r1 - r0) * Double(i) / Double(n), rb = r0 + (r1 - r0) * Double(i + 1) / Double(n)
        let rm = (ra + rb) / 2 * (1 + bulge)
        let mx = (pts[i].0 + pts[i + 1].0) / 2, my = (pts[i].1 + pts[i + 1].1) / 2
        d = min(d, sdSeg(x, y, pts[i].0, pts[i].1, mx, my, ra, rm), sdSeg(x, y, mx, my, pts[i + 1].0, pts[i + 1].1, rm, rb))
    }
    return d
}

@inline(__always) func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
    let h = clampD(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)
}

private func profileMul(_ p: BodyProfile, _ i: Int, _ n: Int) -> Double {
    if n == 1 { return 1 }
    let f = Double(i) / Double(n - 1)
    switch p {
    case .kopflastig: return 0.75 + 0.5 * f
    case .verjuengt: return 1.2 - 0.5 * f
    case .bauchig: return 0.8 + 0.45 * sin(Double.pi * f)
    case .gleich: return 1
    }
}

// MARK: - Bauplan zu einem Alter

struct Part {
    var z: Int
    var order: Int
    var ramp: RampKey
    var core = false
    var limb = false
    /// grobe Hülle, außerhalb wird die Distanzfunktion gar nicht erst ausgewertet
    var x0, y0, x1, y1: Double
    var sdf: (Double, Double) -> Double
    @inline(__always) func inside(_ x: Double, _ y: Double) -> Bool {
        x >= x0 && x <= x1 && y >= y0 && y <= y1 && sdf(x, y) < 0
    }
}

struct Ball { var i: Int; var x, y, rx, ry: Double }
struct EyeSpot { var x, y, r: Double }

struct Built {
    var parts: [Part]
    var eyes: [EyeSpot]
    var face: (x: Double, y: Double, r: Double)
    var belly: Ball
    var box: (x: Double, y: Double, rx: Double, ry: Double)
    var mouth: (x: Double, y: Double, w: Double, g: Double)
    var m, s, float: Double
}

private func bounds(_ pts: [(Double, Double)], pad: Double) -> (Double, Double, Double, Double) {
    var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
    for p in pts { x0 = min(x0, p.0); x1 = max(x1, p.0); y0 = min(y0, p.1); y1 = max(y1, p.1) }
    return (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
}

func buildCreature(_ G: Genome, _ g: Double, _ T: Traits, _ time: Double) -> Built {
    let k = smoothstep(0.45, 1, g) // Pflege prägt erst in der zweiten Hälfte
    let s = T.s * k, t = T.t * k, m = T.m * k
    let float = T.f * k // Geist deutlich vorn: es schwebt
    let morph = smoothstep(0.04, 0.5, g)
    let n = G.spine.count

    // Wirbelsäule auslegen
    var ang = G.baseAng, x = 0.0, y = 0.0, prevR = 0.0
    var raw: [(x: Double, y: Double, rx: Double, ry: Double, i: Int)] = []
    for i in 0..<n {
        let S = G.spine[i], head = i == n - 1 && n > 1
        var R = 0.34 * profileMul(G.profile, i, n) * S.r * (1 + 0.15 * s)
        if head { R *= 1 + 0.28 * m }
        if i > 0 {
            ang += S.bend * 0.55
            let step = (prevR + R) * S.gap * (1 + 0.22 * t)
            x += cos(ang) * step; y += sin(ang) * step
        }
        raw.append((x, y, R * S.sx, R / S.sx, i))
        prevR = R
    }
    // Einpassen: in die Mitte, so groß wie möglich
    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
    for b in raw { x0 = min(x0, b.x - b.rx); x1 = max(x1, b.x + b.rx); y0 = min(y0, b.y - b.ry); y1 = max(y1, b.y + b.ry) }
    let sc = min(1, 1.45 / max(x1 - x0, y1 - y0))
    let lift = G.posture == .liegend ? 0.22 : (G.posture == .hockend ? 0.1 : -0.02)
    let oy = lerpD(0.12, lift - 0.25 * float + sin(time * 0.8) * 0.03 * float, morph)
    let balls: [Ball] = raw.map { b in
        Ball(i: b.i, x: lerpD(0, (b.x - (x0 + x1) / 2) * sc, morph), y: oy + lerpD(0, (b.y - (y0 + y1) / 2) * sc, morph),
             rx: lerpD(0.5, b.rx * sc, morph), ry: lerpD(0.5, b.ry * sc, morph))
    }
    let W = G.warp, wa = W.a * 0.045 * morph * (1 + 0.15 * sin(time * 0.7))
    let harm = G.harm
    let sdBall: (Double, Double, Ball) -> Double = { x, y, b in
        let dx = (x - b.x) / b.rx, dy = (y - b.y) / b.ry, th = atan2(dy, dx)
        var c = 1.0
        for h in harm { c += h.a * morph * sin(h.k * th + h.p + Double(b.i) * 1.7) }
        return (hypot(dx, dy) - c) * min(b.rx, b.ry)
    }
    let st1 = W.p1 + time * 0.5, st2 = W.p2 + time * 0.4
    let body: (Double, Double) -> Double = { x, y in
        let wx = x + wa * sin(y * W.f1 + st1), wy = y + wa * sin(x * W.f2 + st2)
        var d = 1e9
        for b in balls { d = smin(d, sdBall(wx, wy, b), 0.17) }
        return d
    }

    var bx0 = 1e9, bx1 = -1e9, by0 = 1e9, by1 = -1e9
    for b in balls { bx0 = min(bx0, b.x - b.rx); bx1 = max(bx1, b.x + b.rx); by0 = min(by0, b.y - b.ry); by1 = max(by1, b.y + b.ry) }
    // Hülle großzügig: Beulen (bis ~45 %), Verschmelzung und Verzerrung
    let maxR = balls.reduce(0.0) { max($0, max($1.rx, $1.ry)) }
    let pad = maxR * 0.5 + 0.12
    var parts: [Part] = [Part(z: 5, order: 0, ramp: .a, core: true, x0: bx0 - pad, y0: by0 - pad, x1: bx1 + pad, y1: by1 + pad, sdf: body)]

    let hb = balls[n - 1]
    let big = balls.reduce(balls[0]) { $0.rx * $0.ry > $1.rx * $1.ry ? $0 : $1 }
    let face: (x: Double, y: Double, r: Double) = n == 1
        ? (hb.x, hb.y - hb.ry * 0.25, min(hb.rx, hb.ry) * 0.85)
        : (hb.x, hb.y, min(hb.rx, hb.ry))

    // Anhängsel
    for A in G.apps {
        let gr = smoothstep(A.sprout, A.sprout + 0.35, g)
        if gr < 0.03 { continue }
        let B = balls[min(A.ball, n - 1)]
        let kind = A.kind
        var th = A.th
        if float > 0 && (kind == .tentakel || kind == .bein) { th = lerpD(th, Double.pi / 2, 0.5 * float) } // schwebend: hängen nach unten
        let c = cos(th), sn = sin(th)
        let ax = B.x + c * B.rx * 0.82, ay = B.y + sn * B.ry * 0.82
        var len = A.len * gr * (1 + 0.75 * t)
        var th0 = A.thick * (1 + 0.5 * s) * lerpD(0.6, 1, gr)
        if kind == .bein { len *= 1 - 0.85 * float }
        if kind == .tentakel { len *= 1 + 0.35 * float }
        if kind == .flosse { len *= 0.5 }
        if kind == .fuehler { len *= 1 + 0.8 * m; th0 *= 1 + 0.3 * m }
        let N2 = 5
        var pts: [(Double, Double)] = [(ax, ay)]
        var a2 = th
        for i in 1...N2 {
            if kind == .bein { a2 = lerpD(a2, Double.pi / 2, 0.35) }
            a2 += A.curl * 0.32 * (kind == .fuehler ? 0.5 : 1)
            if kind == .tentakel { a2 += sin(time * 1.3 + A.phase + Double(i) * 0.9) * (0.16 + 0.1 * float) }
            if kind == .fuehler { a2 += sin(time * 0.9 + A.phase + Double(i)) * 0.05 }
            let p = pts[pts.count - 1]
            pts.append((p.0 + cos(a2) * len / Double(N2), p.1 + sin(a2) * len / Double(N2)))
        }
        let end = pts[N2], bulge = 0.45 * s
        let z = sn < -0.2 ? 3 : (sn > 0.55 ? 4 : 9)
        let thk = th0
        let sdf: (Double, Double) -> Double
        switch kind {
        case .tentakel: sdf = { x, y in sdLimb(x, y, pts, thk, thk * 0.25, bulge) }
        case .bein: sdf = { x, y in min(sdLimb(x, y, pts, thk, thk * 0.8, bulge), sdEll(x, y, end.0, end.1 + 0.02, thk * 1.3, thk * 0.8, 2)) }
        case .fuehler: sdf = { x, y in min(sdChain(x, y, pts, thk * 0.45, thk * 0.3), sdEll(x, y, end.0, end.1, thk * (1.1 + 0.8 * m), thk * (1.1 + 0.8 * m), 2)) }
        case .flosse: sdf = { x, y in sdChain(x, y, pts, thk * 1.9, thk * 0.2) }
        }
        let bb = bounds(pts, pad: thk * 2.6 + 0.04)
        parts.append(Part(z: z, order: parts.count, ramp: kind == .flosse ? .b : .a, limb: true, x0: bb.0, y0: bb.1, x1: bb.2, y1: bb.3, sdf: sdf))
    }

    // Kopfschmuck wächst mit Geist
    let hg = smoothstep(0.48, 0.85, g) * G.topSize * (1 + 0.7 * m)
    let topY = face.y - face.r * 0.85
    if G.top == "kamm" && hg > 0.02 {
        let spikes: [(Double, Double)] = [(-0.18, 0.16), (-0.04, 0.27), (0.1, 0.21), (0.22, 0.12)]
        let f = face
        parts.append(Part(z: 3, order: parts.count, ramp: .b, x0: f.x - f.r - 0.2, y0: topY - 0.5 * hg - 0.1, x1: f.x + f.r + 0.2, y1: topY + 0.2, sdf: { x, y in
            var d = 1e9
            for (o, h) in spikes { d = min(d, sdSeg(x, y, f.x + o * f.r * 2, topY + 0.08, f.x + o * f.r * 2.4, topY - h * hg, 0.06, 0.01)) }
            return d
        }))
    }
    if G.top == "knospen" && hg > 0.02 {
        let buds: [(Double, Double, Double)] = [(-0.2, 0.1, 0.07), (0.05, 0.17, 0.09), (0.24, 0.08, 0.06)]
        let f = face
        parts.append(Part(z: 3, order: parts.count, ramp: .b, x0: f.x - f.r - 0.3, y0: topY - 0.4 * hg - 0.2, x1: f.x + f.r + 0.3, y1: topY + 0.2, sdf: { x, y in
            var d = 1e9
            for (o, h, rr) in buds { d = min(d, sdEll(x, y, f.x + o * f.r * 2, topY - h * hg, rr * hg, rr * hg, 2)) }
            return d
        }))
    }

    // Augen, manche auf Stielen; Geist macht sie größer
    var eyes: [EyeSpot] = []
    for E in G.eyes {
        let eg = smoothstep(E.at, E.at + 0.2, g)
        if eg <= 0 { continue }
        let er = E.s * face.r * (1 + 0.6 * m) * lerpD(0.4, 1, eg)
        var ex = face.x + E.u * face.r, ey = face.y + E.v * face.r
        if E.stalk && g > 0.4 {
            let sg = smoothstep(0.4, 0.75, g) * (1 + 0.6 * m), bx = ex, by = ey
            ex += E.u * 0.12 * sg; ey -= 0.3 * sg
            let tx = ex, ty = ey
            parts.append(Part(z: 11, order: parts.count, ramp: .a, x0: min(bx, tx) - er * 1.3 - 0.06, y0: min(by, ty) - er * 1.3 - 0.06,
                              x1: max(bx, tx) + er * 1.3 + 0.06, y1: max(by, ty) + er * 1.3 + 0.06, sdf: { x, y in
                min(sdSeg(x, y, bx, by, tx, ty, 0.045, 0.035), sdEll(x, y, tx, ty, er * 1.25, er * 1.2, 2))
            }))
        }
        eyes.append(EyeSpot(x: ex, y: ey, r: er))
    }
    let mg = smoothstep(0.25, 0.42, g)
    let mx = face.x + G.mouthU * face.r, my = face.y + face.r * 0.5, mw = G.mouthW * face.r * 2 * mg
    if G.mouth == "mandibeln" && mg > 0.05 {
        parts.append(Part(z: 15, order: parts.count, ramp: .bone, x0: mx - mw - 0.08, y0: my - 0.1, x1: mx + mw + 0.08, y1: my + 0.25, sdf: { x, y in
            min(sdSeg(x, y, mx - mw * 0.35, my - 0.02, mx - mw * 0.1, my + 0.14 * mg, 0.04, 0.01),
                sdSeg(x, y, mx + mw * 0.35, my - 0.02, mx + mw * 0.1, my + 0.14 * mg, 0.04, 0.01))
        }))
    }
    return Built(parts: parts, eyes: eyes, face: face, belly: big,
                 box: ((bx0 + bx1) / 2, (by0 + by1) / 2, (bx1 - bx0) / 2, (by1 - by0) / 2),
                 mouth: (mx, my, mw, mg), m: m, s: s, float: float)
}

// MARK: - Pixel rendern

struct CreatureFrame {
    var n: Int
    var rgba: [UInt8]
    /// unterste belegte Zeile (0…n-1), um das Wesen auf den Boden zu stellen
    var bottomRow: Int
    var float: Double
}

func pixelSize(_ g: Double) -> Int { jsRound(8 + 72 * pow(g, 1.05)) }
func frameSpan(_ g: Double) -> Double { lerpD(1.5, 2.5, smoothstep(0, 0.5, g)) }

/// `n`: Pixel pro Seite. Ohne Angabe wie im Prototyp (8 bis 80); die App gibt sie vor, damit ein Sprite-Pixel
/// genauso groß ist wie jedes andere Pixel auf dem Bildschirm.
func renderCreature(_ G: Genome, g: Double, traits T: Traits, time: Double, blink: Bool, vigor: Double = 1, n: Int? = nil) -> CreatureFrame {
    let N = max(6, n ?? pixelSize(g))
    let C = buildCreature(G, g, T, time), pal = Palette(G, vigor: vigor)
    let span = frameSpan(g), px = span / Double(N), h0 = span / 2 // Rahmen: früh enger, damit die Zelle ein paar Pixel füllt
    let parts = C.parts.sorted { ($0.z, $0.order) < ($1.z, $1.order) }
    var top = [Int](repeating: -1, count: N * N)        // Index in parts
    var col = [RGB](repeating: (0, 0, 0), count: N * N)
    let L = 0.075, S = 0.095 * (1 + 0.5 * C.s) // Licht- und Schattenkante; Kraft vertieft die Schatten: definierter
    let det = g > 0.66
    let pg = smoothstep(0.5, 0.8, g)

    for j in 0..<N {
        let y = -h0 + (Double(j) + 0.5) * px
        for i in 0..<N {
            let x = -h0 + (Double(i) + 0.5) * px, idx = j * N + i
            var hit = -1
            var pi = parts.count - 1
            while pi >= 0 { if parts[pi].inside(x, y) { hit = pi; break }; pi -= 1 }
            if hit < 0 { continue }
            let p = parts[hit]
            var rk = p.ramp
            var tone: Int = 0 // 0 normal, 1 Schatten
            if p.core {
                let B = C.belly
                if G.pattern == "bauch" && pg > 0 && sdEll(x, y, B.x, B.y + B.ry * 0.25, B.rx * 0.6 * pg, B.ry * 0.55 * pg, 2) < 0 { rk = .b }
                if G.pattern == "flecken" && pg > 0 {
                    let cs = 0.22, cx = floor(x / cs), cyy = floor(y / cs)
                    let h = sin(cx * 127.1 + cyy * 311.7 + G.pat) * 43758.5453, f = h - floor(h)
                    if f > 0.5 {
                        let ox = (cx + 0.25 + 0.5 * f) * cs
                        let fr = (h * 7).truncatingRemainder(dividingBy: 1)
                        let oy = (cyy + 0.25 + 0.5 * ((fr + 1).truncatingRemainder(dividingBy: 1))) * cs
                        if hypot((x - ox) * 1.3, y - oy) < 0.06 * pg * (0.7 + f) { rk = .b }
                    }
                }
                let veins = (G.pattern == "adern" ? 0.09 * pg : 0) + 0.07 * max(0, C.s - 0.25)
                if veins > 0 {
                    let v = abs(sin(x * 6.5 + sin(y * 4.3 + G.pat) * 1.8 + y * 2.2))
                    if v < veins { tone = 1 }
                }
                if G.pattern == "leuchtpunkte" && pg > 0 {
                    let cs = 0.2, cx = floor((x + 5) / cs), cyy = floor((y + 5) / cs)
                    let h = sin(cx * 91.3 + cyy * 47.9 + G.pat) * 9999.1, f = h - floor(h)
                    if f > 0.72 && hypot(x + 5 - (cx + 0.5) * cs, y + 5 - (cyy + 0.5) * cs) < 0.035 * pg { rk = .glow }
                }
                if C.m > 0.15 {
                    let gr = 0.05 * smoothstep(0.15, 0.6, C.m)
                    for (gx, gy) in G.glowSpots where hypot(x - (C.box.x + gx * C.box.rx), y - (C.box.y + gy * C.box.ry)) < gr { rk = .glow; break }
                }
            }
            // Kraft: Anhängsel werden adrig und definiert
            if p.limb && C.s > 0.2 {
                let v = abs(sin(x * 11 + sin(y * 9 + G.pat) * 2.2 + y * 4))
                if v < 0.16 * C.s { tone = 1 }
            }
            let r = pal.ramp(rk)
            let lit = p.sdf(x - L, y - L * 1.25) >= 0, dark = p.sdf(x + S, y + S * 1.25) >= 0
            var c: RGB = tone == 1 ? r.sh : (lit ? r.hi : (dark ? r.sh : r.base))
            if rk == .glow {
                let pu = 0.5 + 0.5 * sin(time * 2.4 + x * 3)
                c = lit ? r.hi : hslToRgb(pal.glowHue, 80, 56 + 16 * pu)
            }
            col[idx] = c
            top[idx] = hit
        }
    }

    // Augen und Mund aufmalen
    for j in 0..<N {
        let y = -h0 + (Double(j) + 0.5) * px
        for i in 0..<N {
            let idx = j * N + i
            if top[idx] < 0 { continue }
            let x = -h0 + (Double(i) + 0.5) * px
            for e in C.eyes {
                let rpx = e.r / px
                let dx = (x - e.x) / e.r, dy = (y - e.y) / (e.r * 1.08), d = dx * dx + dy * dy
                if d >= 1 { continue }
                if blink { if abs(y - e.y) < px * 0.75 { col[idx] = pal.pupil }; continue }
                if rpx < 1.8 { col[idx] = pal.pupil; continue }
                var c = pal.pupil
                switch G.eyeStyle {
                case "iris": c = (abs(dy) < 0.2 && abs(dx) < 0.55) ? pal.pupil : (d < 0.72 ? pal.iris : pal.eyeW)
                case "ring": c = d < 0.3 ? pal.pupil : (d < 0.6 ? pal.eyeW : pal.iris)
                case "facette": c = ((i + j) % 2 == 0 && d < 0.75) ? pal.iris : pal.pupil
                default: break
                }
                if rpx >= 2.6 && d > 0.78 { c = pal.pupil }
                if det && rpx >= 2.2 && hypot(x - (e.x - e.r * 0.32), y - (e.y - e.r * 0.34)) < max(px * 0.7, e.r * 0.2) { c = pal.shine }
                col[idx] = c
            }
            let M = C.mouth
            if M.g > 0.05 && M.w > 0 {
                let th = max(px * 0.55, 0.02), u = (x - M.x) / M.w
                switch G.mouth {
                case "spalt": if abs(x - M.x) < th && abs(y - M.y) < M.w * 0.45 { col[idx] = pal.mouth }
                case "strich": if abs(y - M.y - u * u * M.w * 0.06) < th && abs(u) < 0.55 { col[idx] = pal.mouth }
                case "poren":
                    for o in [-0.5, 0, 0.5] where hypot(x - (M.x + o * M.w * 0.7), y - (M.y + abs(o) * 0.04)) < max(px * 0.6, 0.028) { col[idx] = pal.mouth }
                default: break
                }
            }
        }
    }

    // Umrisse: außen dunkle Linie, innen zwischen Teilen eine tiefe Farbe
    var out = [UInt8](repeating: 0, count: N * N * 4)
    var bottom = 0
    for j in 0..<N {
        for i in 0..<N {
            let idx = j * N + i
            let me = top[idx]
            if me < 0 { continue }
            let mp = parts[me]
            var edge = false, inner = false
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let ii = i + di, jj = j + dj
                if ii < 0 || jj < 0 || ii >= N || jj >= N || top[jj * N + ii] < 0 { edge = true; break }
                let o = top[jj * N + ii]
                if o != me && parts[o].z < mp.z && !(mp.core && parts[o].core && N < 20) { inner = true }
            }
            let rr = pal.ramp(mp.ramp)
            var c = col[idx]
            // Winzige Zellen ohne schwarzen Rand, sonst verschwindet die Form; der Rand wächst erst mit der Auflösung
            if edge { c = N < 18 ? rr.sh : (N < 26 ? rr.deep : rr.line) } else if inner && N >= 16 { c = rr.deep }
            out[idx * 4] = c.0; out[idx * 4 + 1] = c.1; out[idx * 4 + 2] = c.2; out[idx * 4 + 3] = 255
            bottom = max(bottom, j)
        }
    }
    return CreatureFrame(n: N, rgba: out, bottomRow: bottom, float: C.float)
}
