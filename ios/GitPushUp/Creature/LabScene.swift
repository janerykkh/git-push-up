import Foundation
import CoreGraphics

/// Pixelbild in RGBA (vormultipliziert), wird zu einem CGImage.
/// `opaque`: Hintergrund, Farben werden deckend gemischt. Sonst Überlagerung mit Transparenz (Glas).
struct PixelCanvas {
    let w: Int, h: Int
    let opaque: Bool
    var d: [UInt8]
    init(_ w: Int, _ h: Int, opaque: Bool) { self.w = w; self.h = h; self.opaque = opaque; d = [UInt8](repeating: 0, count: w * h * 4) }

    mutating func set(_ xf: Double, _ yf: Double, _ c: RGB, _ a: Double = 1) {
        let x = Int(xf.rounded()), y = Int(yf.rounded())
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let i = (y * w + x) * 4
        if opaque {
            d[i] = UInt8(clamping: Int((Double(d[i]) * (1 - a) + Double(c.0) * a).rounded()))
            d[i + 1] = UInt8(clamping: Int((Double(d[i + 1]) * (1 - a) + Double(c.1) * a).rounded()))
            d[i + 2] = UInt8(clamping: Int((Double(d[i + 2]) * (1 - a) + Double(c.2) * a).rounded()))
            d[i + 3] = 255
        } else {
            // "über"-Mischung in vormultiplizierten Werten
            let A = Double(d[i + 3]) / 255
            d[i] = UInt8(clamping: Int((Double(c.0) * a + Double(d[i]) * (1 - a)).rounded()))
            d[i + 1] = UInt8(clamping: Int((Double(c.1) * a + Double(d[i + 1]) * (1 - a)).rounded()))
            d[i + 2] = UInt8(clamping: Int((Double(c.2) * a + Double(d[i + 2]) * (1 - a)).rounded()))
            d[i + 3] = UInt8(clamping: Int(((a + A * (1 - a)) * 255).rounded()))
        }
    }

    mutating func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: RGB, _ a: Double = 1) {
        let ys = Int(y0.rounded()), ye = Int(y1.rounded()), xs = Int(x0.rounded()), xe = Int(x1.rounded())
        guard ye > ys, xe > xs else { return }
        for y in ys..<ye { for x in xs..<xe { set(Double(x), Double(y), c, a) } }
    }

    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: RGB, _ a: Double = 1) {
        let n = Int(max(abs(x1 - x0), abs(y1 - y0)))
        for i in 0...max(0, n) {
            let t = n > 0 ? Double(i) / Double(n) : 0
            set(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c, a)
        }
    }

    /// Konvexes Viereck füllen
    mutating func quad(_ q: [(Double, Double)], _ c: RGB, _ a: Double = 1) {
        var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
        for p in q { x0 = min(x0, p.0); x1 = max(x1, p.0); y0 = min(y0, p.1); y1 = max(y1, p.1) }
        let ys = max(0, Int(floor(y0))), ye = min(h - 1, Int(ceil(y1))), xs = max(0, Int(floor(x0))), xe = min(w - 1, Int(ceil(x1)))
        guard ye >= ys, xe >= xs else { return }
        for y in ys...ye {
            for x in xs...xe where PixelCanvas.inQuad(q, Double(x) + 0.5, Double(y) + 0.5) { set(Double(x), Double(y), c, a) }
        }
    }

    static func inQuad(_ q: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var neg = false, pos = false
        for i in 0..<4 {
            let a = q[i], b = q[(i + 1) % 4]
            let c = (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0)
            if c < 0 { neg = true } else if c > 0 { pos = true }
        }
        return !(neg && pos)
    }

    var image: CGImage? { makeImage(d, w, h) }
}

func makeImage(_ rgba: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
    guard w > 0, h > 0 else { return nil }
    let data = Data(rgba) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Labor mit Tiefe: jeder Pixel schickt einen Sichtstrahl in einen echten 3D-Raum (Wände, Boden, Decke, Geräte).
/// Dadurch stimmt die Perspektive überall. Dunst je nach Entfernung und ein feines Raster (Dithering) machen es schemenhaft
/// und pixelig. Davor steht ein Glaskasten, dessen Hinterkanten zum selben Fluchtpunkt laufen.
enum LabScene {
    struct Geo {
        var cx, hy: Double
        var cb0, cb1, ct: Double         // Rückseite des Kastens
        var yF, yB: Double               // Kastenboden vorne / hinten
        var feetY: Double { (yB + (yF - yB) * 0.5).rounded() }
    }

    static func geo(_ w: Int, _ h: Int) -> Geo {
        let W = Double(w), H = Double(h)
        let cx = W * 0.5, hy = H * 0.42, s = 0.8, yF = H - 3
        return Geo(cx: cx, hy: hy, cb0: cx - cx * s, cb1: cx + (W - cx) * s, ct: hy - hy * s, yF: yF, yB: hy + (yF - hy) * s)
    }

    static let ink: RGB = (24, 24, 24)
    static let slate: RGB = (62, 70, 77)
    static let orange: RGB = (240, 78, 35)
    static let grey: RGB = (154, 154, 150)
    static let white: RGB = (255, 255, 255)

    // MARK: Raum und Geräte

    private static let roomX0 = -4.2, roomX1 = 4.2, floorY = 1.5, ceilY = -2.1, backZ = 24.0

    private enum Shape {
        case box(x0: Double, x1: Double, y0: Double, y1: Double, z0: Double, z1: Double)
        case cyl(x: Double, z: Double, r: Double, y0: Double, y1: Double)     // stehender Zylinder
        case sph(x: Double, y: Double, z: Double, r: Double)
        case ring(x: Double, y: Double, z: Double, r0: Double, r1: Double)    // Ring in einer Ebene quer zur Blickrichtung
        case pipe(x: Double, y: Double, r: Double)                            // Rohr entlang der Tiefe
    }
    private struct Obj { var shape: Shape; var col: RGB; var lamp = false; var glow = false }

    private static func objects() -> [Obj] {
        var O: [Obj] = []
        func box(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ c: RGB) {
            O.append(Obj(shape: .box(x0: x0, x1: x1, y0: y0, y1: y1, z0: z0, z1: z1), col: c))
        }
        func cyl(_ x: Double, _ z: Double, _ r: Double, _ y0: Double, _ y1: Double, _ c: RGB, lamp: Bool = false) {
            O.append(Obj(shape: .cyl(x: x, z: z, r: r, y0: y0, y1: y1), col: c, lamp: lamp))
        }
        func sph(_ x: Double, _ y: Double, _ z: Double, _ r: Double, _ c: RGB) { O.append(Obj(shape: .sph(x: x, y: y, z: z, r: r), col: c)) }

        func c3(_ r: Int, _ g: Int, _ b: Int) -> RGB { (UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b)) }
        /// Topf, daraus sieben gebogene Stiele mit Blättern
        func plant(_ x: Double, _ yBase: Double, _ z: Double, _ s: Double, _ L: (Int, Int, Int)) {
            cyl(x, z, 0.15 * s, yBase - 0.26 * s, yBase, (226, 226, 222))
            cyl(x, z, 0.16 * s, yBase - 0.28 * s, yBase - 0.24 * s, (200, 200, 196))
            for k in 0..<7 {
                let a = Double(k) * 2.4 + x * 3 + z
                let out = 0.35 + Double((k * 37) % 10) / 25, up = 0.55 + Double((k * 53) % 10) / 22
                var t = 0.15
                while t <= 1.001 {
                    let px = x + cos(a) * t * out * s
                    let py = yBase - 0.26 * s - (t * up - t * t * 0.35) * s
                    let pz = z + sin(a) * t * out * s
                    let sh = Double(k % 3) * 18 - 18 + t * 20
                    sph(px, py, pz, (0.075 - 0.03 * t) * s, c3(L.0 + Int(sh), L.1 + Int(sh), L.2 + Int(sh * 0.6)))
                    t += 0.12
                }
            }
        }
        func scope(_ x: Double, _ yb: Double, _ z: Double) {
            box(x - 0.14, x + 0.14, yb - 0.04, yb, z - 0.12, z + 0.12, (60, 66, 72))
            box(x + 0.06, x + 0.11, yb - 0.42, yb - 0.04, z - 0.04, z + 0.04, (70, 76, 82))
            cyl(x - 0.02, z, 0.045, yb - 0.5, yb - 0.22, (230, 232, 234))
            box(x - 0.1, x + 0.08, yb - 0.2, yb - 0.17, z - 0.1, z + 0.1, (200, 204, 206))
            sph(x - 0.02, yb - 0.52, z, 0.05, (40, 44, 48))
        }
        let vivid: [RGB] = [(236, 120, 80), (90, 200, 180), (176, 130, 230), (240, 206, 90), (120, 190, 240)]

        // Links: lange Laborbank mit Pflanzen, Mikroskopen, Kolben, Gläsern, Reagenzgläsern
        box(-4.2, -2.9, 0.62, 1.5, 3.5, 15, (150, 158, 164))
        box(-4.2, -2.85, 0.55, 0.62, 3.5, 15, (236, 236, 233))
        let items = ["plant", "flask", "scope", "jar", "plant2", "tubes", "flask", "scope", "plant", "jar"]
        for (i, it) in items.enumerated() {
            let z = 4.3 + Double(i) * 1.08
            switch it {
            case "plant": plant(-3.45, 0.55, z, 1, (96, 168, 120))
            case "plant2": plant(-3.45, 0.55, z, 1.2, (110, 150, 190))
            case "scope": scope(-3.5, 0.55, z)
            case "flask":
                cyl(-3.5, z, 0.07, 0.05, 0.55, (226, 234, 234))
                let fc: [RGB] = [(230, 120, 60), (90, 190, 170), (160, 120, 220)]
                sph(-3.5, 0.38, z, 0.2, fc[i % 3])
            case "jar":
                let jc: [RGB] = [(240, 200, 80), (230, 110, 90), (110, 200, 190)]
                cyl(-3.55, z, 0.16, 0.12, 0.55, jc[i % 3])
                cyl(-3.55, z, 0.17, 0.07, 0.12, (60, 66, 72))
            default:
                let tc: [RGB] = [(240, 90, 60), (90, 200, 170), (170, 120, 230), (240, 200, 70)]
                for k in 0..<4 { cyl(-3.75 + Double(k) * 0.13, z, 0.04, 0.2, 0.55, tc[k]) }
                box(-3.82, -3.3, 0.38, 0.44, z - 0.06, z + 0.06, (200, 204, 206))
            }
        }
        // Regalbrett links mit bunten Flaschen
        box(-4.2, -3.4, -0.95, -0.88, 3.5, 15, (200, 200, 196))
        var z = 4.2
        while z < 14 {
            cyl(-3.8, z, 0.09, -1.28, -0.95, vivid[Int((z * 10).rounded()) % 5])
            z += 0.7
        }
        // Rechts: drei Kryotanks mit Kuppel, farbigem Sichtfenster und Lämpchen
        for tz in [7.0, 9.6, 12.2] {
            cyl(3.2, tz, 0.6, -0.6, 1.5, (178, 186, 190))
            sph(3.2, -0.6, tz, 0.6, (196, 202, 206))
            let liquids: [RGB] = [(90, 200, 180), (240, 150, 70), (170, 120, 230)]
            let liquid = liquids[Int(tz.rounded()) % 3]
            box(2.56, 2.62, -0.35, 0.95, tz - 0.22, tz + 0.22, (200, 210, 212))
            box(2.55, 2.62, 0.15, 0.95, tz - 0.2, tz + 0.2, liquid)
            box(2.56, 2.62, -0.25, -0.15, tz - 0.06, tz + 0.06, orange)
        }
        box(2.75, 4.2, -1.3, 1.5, 14, 15.6, (78, 86, 92))
        // Regal rechts über den Tanks mit bunten Flaschen
        box(3.5, 4.2, -1.42, -1.36, 5, 13.5, (200, 200, 196))
        z = 5.3
        while z < 13.3 {
            cyl(3.85, z, 0.1, -1.75, -1.42, vivid[Int((z * 7).rounded()) % 5])
            z += 0.55
        }
        // Zuchtregal hinten links: Pflanzen unter violettem Licht
        for y in [-0.9, 0.2] {
            box(-4.2, -3.0, y, y + 0.06, 15.6, 18.8, (180, 186, 190))
            O.append(Obj(shape: .box(x0: -4.2, x1: -3.0, y0: y - 0.95, y1: y - 0.9, z0: 15.6, z1: 18.8), col: (236, 130, 230), glow: true))
            var pz = 16.0
            while pz < 18.6 { plant(-3.6, y, pz, 0.8, (120, 200, 140)); pz += 0.6 }
        }
        // große Pflanzen am Boden
        plant(-2.5, 1.5, 7.2, 1.7, (70, 150, 100))
        plant(2.2, 1.5, 14.6, 2, (80, 160, 150))
        // Mitte hinten: Ringscanner mit Liege
        O.append(Obj(shape: .ring(x: 0, y: -0.05, z: 16, r0: 1.1, r1: 1.5), col: (150, 156, 160)))
        box(-0.7, 0.7, 1.15, 1.5, 15.6, 16.4, (180, 184, 186))
        box(-0.45, 0.45, 0.72, 0.86, 13.2, 18.5, (230, 230, 228))
        box(-0.1, 0.1, 0.86, 1.5, 13.6, 13.8, (170, 174, 176))
        box(-0.1, 0.1, 0.86, 1.5, 18, 18.2, (170, 174, 176))
        // Säulen, Rohre an der Decke, hängende Lampen
        box(-4.2, -3.5, ceilY, 1.5, 19.5, 20.3, (222, 222, 219))
        box(3.5, 4.2, ceilY, 1.5, 19.5, 20.3, (214, 214, 211))
        O.append(Obj(shape: .pipe(x: -1.9, y: -1.85, r: 0.16), col: (200, 204, 206)))
        O.append(Obj(shape: .pipe(x: -1.5, y: -1.9, r: 0.09), col: (214, 216, 218)))
        O.append(Obj(shape: .pipe(x: 2.3, y: -1.88, r: 0.12), col: (196, 200, 202)))
        for lz in [6.0, 11.0, 16.0] {
            cyl(0, lz, 0.03, -2.1, -1.45, (150, 150, 148))
            cyl(0, lz, 0.28, -1.45, -1.32, (240, 240, 238), lamp: true)
        }
        return O
    }

    private enum Surface { case floor, ceil, left, right, back }

    private static func shadeRoom(_ s: Surface, _ x: Double, _ y: Double, _ z: Double) -> RGB {
        switch s {
        case .floor:
            var c: RGB = (206, 206, 202)
            let fx = x - floor(x), fz = z - floor(z)
            if fx < 0.03 * max(1, z * 0.25) || fz < 0.05 { c = (186, 186, 182) }
            if abs(abs(x) - 2.35) < 0.05 && z > 2 { c = orange }   // Markierung am Boden
            return c
        case .ceil:
            if abs(x) < 0.9 && z.truncatingRemainder(dividingBy: 3.2) < 1.4 { return white }
            if z.truncatingRemainder(dividingBy: 1.6) < 0.05 { return (220, 220, 218) }
            return (236, 236, 234)
        case .left, .right:
            var c: RGB = s == .left ? (224, 224, 221) : (214, 214, 211)
            let m = z.truncatingRemainder(dividingBy: 2.4)
            if m < 0.06 { c = (200, 200, 197) }
            if abs(y + 0.2) < 0.025 { c = (204, 204, 200) }
            if s == .right && y > -0.2 && y < 0.5 && m > 1 && m < 2.1 { c = (200, 206, 208) }
            return c
        case .back:
            // großes helles Fenster mit Sprossen
            if abs(x) < 2.6 && y > -1.6 && y < 0.4 {
                if (x + 2.6).truncatingRemainder(dividingBy: 1.3) < 0.05 || (y + 1.6).truncatingRemainder(dividingBy: 1) < 0.05 { return (196, 200, 202) }
                return y > 0.25 ? (214, 218, 220) : (244, 247, 248)
            }
            return (226, 226, 223)
        }
    }

    /// Ein Sichtstrahl: Farbe und Tiefe des ersten Treffers
    private static func trace(_ ox: Double, _ oy: Double, _ dx: Double, _ dy: Double, _ O: [Obj]) -> (RGB, Double) {
        let dz = 1.0
        var bestZ = 1e9
        var col: RGB = (230, 230, 228)
        var n = (0.0, 0.0, -1.0)
        var room = true
        var lamp = false
        var glow = false
        // Raumflächen
        let cand: [(Surface, Double, (Double, Double, Double))] = [
            (.floor, dy > 0 ? (floorY - oy) / dy : 1e9, (0, -1, 0)),
            (.ceil, dy < 0 ? (ceilY - oy) / dy : 1e9, (0, 1, 0)),
            (.left, dx < 0 ? (roomX0 - ox) / dx : 1e9, (1, 0, 0)),
            (.right, dx > 0 ? (roomX1 - ox) / dx : 1e9, (-1, 0, 0)),
            (.back, backZ / dz, (0, 0, -1)),
        ]
        for (s, t, nn) in cand where t > 0 && t * dz < bestZ {
            bestZ = t * dz
            col = shadeRoom(s, ox + dx * t, oy + dy * t, t * dz)
            n = nn
        }
        // Geräte
        for o in O {
            var t = 1e9
            var nn = (0.0, 0.0, -1.0)
            switch o.shape {
            case let .box(x0, x1, y0, y1, z0, z1):
                var tmin = -1e9, tmax = 1e9
                var hitN = (0.0, 0.0, -1.0)
                var ok = true
                let axes: [(Double, Double, Double, Double, (Double, Double, Double), (Double, Double, Double))] = [
                    (ox, dx, x0, x1, (-1, 0, 0), (1, 0, 0)), (oy, dy, y0, y1, (0, -1, 0), (0, 1, 0)), (0, dz, z0, z1, (0, 0, -1), (0, 0, 1)),
                ]
                for (p, d, a, b, na, nb) in axes {
                    if abs(d) < 1e-9 { if p < a || p > b { ok = false; break }; continue }
                    var t1 = (a - p) / d, t2 = (b - p) / d, n1 = na
                    if t1 > t2 { swap(&t1, &t2); n1 = nb }
                    if t1 > tmin { tmin = t1; hitN = n1 }
                    if t2 < tmax { tmax = t2 }
                    if tmin > tmax { ok = false; break }
                }
                if ok && tmin > 0 { t = tmin; nn = hitN }
            case let .cyl(cx, cz, r, y0, y1):
                let px = ox - cx, pz = -cz
                let a = dx * dx + dz * dz, b = 2 * (px * dx + pz * dz), c = px * px + pz * pz - r * r
                let D = b * b - 4 * a * c
                if D >= 0 {
                    let tt = (-b - sqrt(D)) / (2 * a), yy = oy + dy * tt
                    if tt > 0 && yy >= y0 && yy <= y1 {
                        t = tt; nn = ((px + dx * tt) / r, 0, (pz + dz * tt) / r)
                    } else if dy != 0 {
                        let t2 = (y0 - oy) / dy, xx = ox + dx * t2 - cx, zz = dz * t2 - cz
                        if t2 > 0 && xx * xx + zz * zz <= r * r { t = t2; nn = (0, -1, 0) }
                    }
                }
            case let .sph(sx, sy, sz, r):
                let px = ox - sx, py = oy - sy, pz = -sz
                let a = dx * dx + dy * dy + dz * dz, b = px * dx + py * dy + pz * dz, c = px * px + py * py + pz * pz - r * r
                let D = b * b - a * c
                if D >= 0 {
                    let tt = (-b - sqrt(D)) / a
                    if tt > 0 { t = tt; nn = ((px + dx * tt) / r, (py + dy * tt) / r, (pz + dz * tt) / r) }
                }
            case let .ring(rx, ry, rz, r0, r1):
                let tt = rz / dz, xx = ox + dx * tt - rx, yy = oy + dy * tt - ry, r = hypot(xx, yy)
                if r >= r0 && r <= r1 {
                    t = tt
                    let m = (r - (r0 + r1) / 2) / ((r1 - r0) / 2)
                    nn = (xx / r * m * 0.8, yy / r * m * 0.8, -sqrt(max(0, 1 - m * m * 0.64)))
                }
            case let .pipe(px0, py0, r):
                let px = ox - px0, py = oy - py0
                let a = dx * dx + dy * dy, b = 2 * (px * dx + py * dy), c = px * px + py * py - r * r
                let D = b * b - 4 * a * c
                if D >= 0 && a > 0 {
                    let tt = (-b - sqrt(D)) / (2 * a)
                    if tt > 0 { t = tt; nn = ((px + dx * tt) / r, (py + dy * tt) / r, 0) }
                }
            }
            if t < 1e9 && t * dz < bestZ {
                bestZ = t * dz; col = o.col; n = nn; room = false; lamp = o.lamp; glow = o.glow
            }
        }
        // Licht von oben vorne links, dazu Umgebungslicht
        let L = (-0.35, -0.8, -0.45), ll = sqrt(L.0 * L.0 + L.1 * L.1 + L.2 * L.2)
        let lam = max(0, -(n.0 * L.0 + n.1 * L.1 + n.2 * L.2) / ll)
        let k = room ? 0.9 + 0.1 * lam : 0.72 + 0.34 * lam
        if lamp { return (white, bestZ) }
        if glow { return (col, bestZ) }
        return ((UInt8(clamping: Int(Double(col.0) * k)), UInt8(clamping: Int(Double(col.1) * k)), UInt8(clamping: Int(Double(col.2) * k))), bestZ)
    }

    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    static func backdrop(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h, opaque: true)
        let G = geo(w, h), W = Double(w), H = Double(h), F = W * 0.85
        let O = objects()
        let haze: RGB = (238, 238, 235)
        for j in 0..<h {
            for i in 0..<w {
                let dx = (Double(i) + 0.5 - G.cx) / F, dy = (Double(j) + 0.5 - G.hy) / F
                let (col, z) = trace(0.25, 0, dx, dy, O)
                let f = min(0.66, 1 - exp(-(z - 2) / 22))
                let q = (bayer[j & 3][i & 3] / 16 - 0.5) * 10
                func ch(_ v: UInt8, _ hz: UInt8) -> UInt8 {
                    let x = Double(v) * (1 - f) + Double(hz) * f
                    return UInt8(clamping: Int(((x + q) / 8).rounded()) * 8)
                }
                let p = (j * w + i) * 4
                c.d[p] = ch(col.0, haze.0); c.d[p + 1] = ch(col.1, haze.1); c.d[p + 2] = ch(col.2, haze.2); c.d[p + 3] = 255
            }
        }
        // Kastenboden in Perspektive (vorne breit, hinten schmal) und Hinterkanten
        var y = Int(ceil(G.yB))
        while y < h {
            let f = (Double(y) - G.hy) / (G.yF - G.hy)
            let xl = G.cx - G.cx * f, xr = G.cx + (W - G.cx) * f
            for x in max(0, Int(floor(xl)))..<min(w, Int(ceil(xr))) { c.set(Double(x), Double(y), (247, 247, 245), 0.92) }
            y += 1
        }
        for k in 1..<8 {
            let t = Double(k) / 8
            c.line(G.cb0 + (G.cb1 - G.cb0) * t, G.yB, W * t, G.yF, (228, 228, 225))
        }
        c.line(G.cb0, G.yB, G.cb1, G.yB, (178, 180, 182))
        c.line(G.cb0, G.ct, G.cb0, G.yB, (170, 174, 178), 0.8)
        c.line(G.cb1, G.ct, G.cb1, G.yB, (170, 174, 178), 0.8)
        c.line(G.cb0, G.ct, G.cb1, G.ct, (170, 174, 178), 0.8)
        _ = H
        return c
    }

    /// Glas vor dem Wesen: getönte Seitenscheiben, Kanten zur Rückseite, Spiegelungen, schmaler heller Rahmen
    static func glass(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h, opaque: false)
        let G = geo(w, h), W = Double(w), H = Double(h)
        c.quad([(0, 0), (G.cb0, G.ct), (G.cb0, G.yB), (0, G.yF)], (196, 212, 218), 0.09)
        c.quad([(W, 0), (W, G.yF), (G.cb1, G.yB), (G.cb1, G.ct)], (196, 212, 218), 0.13)
        c.quad([(0, 0), (W, 0), (G.cb1, G.ct), (G.cb0, G.ct)], (206, 218, 224), 0.1)
        c.line(0, 0, G.cb0, G.ct, (120, 128, 134))
        c.line(W - 1, 0, G.cb1, G.ct, (120, 128, 134))
        c.line(0, G.yF, G.cb0, G.yB, (150, 156, 160), 0.8)
        c.line(W - 1, G.yF, G.cb1, G.yB, (150, 156, 160), 0.8)
        var y = 4.0
        while y < G.yF - 1 {
            let x = (W * 0.16 + (G.yF - y) * 0.42).rounded()
            c.rect(x, y, x + 3, y + 1, white, 0.33); c.rect(x + 6, y, x + 7, y + 1, white, 0.22)
            if y < G.yF * 0.55 {
                let x2 = (W * 0.78 + (G.yF * 0.55 - y) * 0.42).rounded()
                c.rect(x2, y, x2 + 2, y + 1, white, 0.22)
            }
            y += 1
        }
        c.rect(0, 0, W, 2, (226, 226, 223)); c.rect(0, 2, W, 3, slate); c.rect(0, 0, W, 1, white, 0.8)
        c.rect(0, 0, 2, G.yF, (226, 226, 223)); c.rect(2, 3, 3, G.yF, slate)
        c.rect(W - 2, 0, W, G.yF, (226, 226, 223)); c.rect(W - 3, 3, W - 2, G.yF, slate)
        c.rect(0, G.yF, W, H, (214, 216, 214)); c.rect(0, G.yF, W, G.yF + 1, (170, 174, 176))
        var x = 10.0
        while x < W - 8 { c.rect(x, 0, x + 2, 1, grey); x += 12 }
        c.rect(4, 4, 6, 6, orange); c.rect(W - 6, 4, W - 4, 6, orange)
        return c
    }
}
