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

/// Labor mit Tiefe: ein Raum mit Fluchtpunkt hinter einem Glaskasten, der selbst Tiefe hat
/// (sichtbare Hinterkanten, Boden in Perspektive, getönte Seitenscheiben). Alles als Pixelbild.
enum LabScene {
    struct Geo {
        var cx, vy: Double
        var bx0, bx1, by0, by1: Double   // Rückwand des Raums
        var cb0, cb1, ct: Double         // Rückseite des Kastens
        var yF, yB: Double               // Kastenboden vorne / hinten
        /// Wo das Wesen steht: Mitte des Kastenbodens
        var feetY: Double { (yB + (yF - yB) * 0.5).rounded() }
    }

    static func geo(_ w: Int, _ h: Int) -> Geo {
        let W = Double(w), H = Double(h)
        return Geo(cx: W / 2, vy: H * 0.40,
                   bx0: (W * 0.27).rounded(), bx1: (W * 0.73).rounded(), by0: (H * 0.13).rounded(), by1: (H * 0.52).rounded(),
                   cb0: (W * 0.13).rounded(), cb1: (W * 0.87).rounded(), ct: (H * 0.09).rounded(),
                   yF: H - max(8, (H * 0.1).rounded()), yB: (H * 0.70).rounded())
    }

    static let paper: RGB = (233, 233, 230)
    static let ink: RGB = (24, 24, 24)
    static let slate: RGB = (62, 70, 77)
    static let orange: RGB = (240, 78, 35)
    static let grey: RGB = (154, 154, 150)
    static let light: RGB = (246, 246, 244)
    static let white: RGB = (255, 255, 255)

    static func backdrop(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h, opaque: true)
        let G = geo(w, h), W = Double(w), H = Double(h)
        let cx = G.cx, bx0 = G.bx0, bx1 = G.bx1, by0 = G.by0, by1 = G.by1

        // Raum: Decke, Wände, Boden, Rückwand
        c.quad([(0, 0), (W, 0), (bx1, by0), (bx0, by0)], (242, 242, 240))
        c.quad([(0, 0), (bx0, by0), (bx0, by1), (0, H)], (224, 224, 221))
        c.quad([(W, 0), (W, H), (bx1, by1), (bx1, by0)], (214, 214, 211))
        c.quad([(0, H), (bx0, by1), (bx1, by1), (W, H)], (206, 206, 202))
        c.rect(bx0, by0, bx1, by1, (230, 230, 227))

        // Bodenfliesen: Fluchtlinien und Tiefenlinien
        for k in -8...8 {
            let xb = cx + Double(k) * (bx1 - bx0) / 16, xf = cx + Double(k) * W / 8
            c.line(xf, H, xb, by1, (192, 192, 188))
        }
        for i in 1..<9 {
            let t = 1 - 1 / (1 + Double(i) * 0.45)
            let y = by1 + (H - by1) * (1 - t)
            let f = (y - by1) / (H - by1)
            c.line(bx0 - bx0 * f, y, bx1 + (W - bx1) * f, y, (194, 194, 188))
        }

        // Decke: Leuchtfelder in Perspektive
        func ceilX(_ yy: Double) -> (Double, Double) {
            let half = (cx - bx0) + (W * 0.5 - (cx - bx0)) * (1 - yy / by0)
            return (cx - half * 0.45, cx + half * 0.45)
        }
        for (t0, t1) in [(0.08, 0.22), (0.38, 0.5), (0.62, 0.7)] {
            let yy0 = by0 * t0, yy1 = by0 * t1
            let a = ceilX(yy0), b = ceilX(yy1)
            c.quad([(a.0, yy0), (a.1, yy0), (b.1, yy1), (b.0, yy1)], white)
        }

        // Linke Wand: Regalbretter in Perspektive mit Gläsern
        func leftY(_ x: Double, _ yBack: Double, _ yScreen: Double) -> Double { yScreen + (yBack - yScreen) * (x / bx0) }
        let liquids: [RGB] = [(150, 190, 186), (236, 170, 140), (186, 180, 214), (200, 200, 196)]
        for (ys, yb) in [(H * 0.30, by0 + (by1 - by0) * 0.28), (H * 0.48, by0 + (by1 - by0) * 0.5), (H * 0.66, by0 + (by1 - by0) * 0.72)] {
            c.line(8, leftY(8, yb, ys), bx0 - 3, leftY(bx0 - 3, yb, ys), (176, 176, 172))
            var x = 10.0
            while x < bx0 - 5 {
                let y = leftY(x, yb, ys), s = 1 - x / bx0 * 0.5
                let hh = max(2, (5 * s).rounded())
                let xi = Int(x)
                c.rect(x, y - hh, x + max(1, (2 * s).rounded()), y, liquids[(xi * 5) % 4])
                x += Double(4 + (xi * 7) % 3)
            }
        }

        // Rechte Wand: Paneel mit Punktraster und ein Gerät
        func rightY(_ x: Double, _ yBack: Double, _ yScreen: Double) -> Double { yScreen + (yBack - yScreen) * ((W - x) / (W - bx1)) }
        var x = bx1 + 4
        while x < W - 6 {
            let y0 = rightY(x, by0 + (by1 - by0) * 0.2, H * 0.22), y1 = rightY(x, by0 + (by1 - by0) * 0.55, H * 0.6)
            for j in 0..<5 { c.set(x, y0 + (y1 - y0) * Double(j) / 4, (170, 170, 166)) }
            x += 3
        }
        let mxa = W - 26, mxb = W - 10
        c.quad([(mxa, rightY(mxa, by0 + (by1 - by0) * 0.6, H * 0.62)), (mxb, rightY(mxb, by0 + (by1 - by0) * 0.6, H * 0.62)),
                (mxb, rightY(mxb, by0 + (by1 - by0) * 0.9, H * 0.86)), (mxa, rightY(mxa, by0 + (by1 - by0) * 0.9, H * 0.86))], slate)

        // Rückwand: Tür mit Bändern, Schaltschrank mit Lämpchen, runde Anzeige
        let bw = bx1 - bx0, bh = by1 - by0
        c.rect(bx0 + bw * 0.38, by0 + bh * 0.18, bx0 + bw * 0.62, by1, (214, 214, 210))
        c.rect(bx0 + bw * 0.38, by0 + bh * 0.18, bx0 + bw * 0.62, by0 + bh * 0.18 + 1, grey)
        for k in 1..<4 {
            let yy = by0 + bh * (0.18 + Double(k) * 0.2)
            c.rect(bx0 + bw * 0.38, yy, bx0 + bw * 0.62, yy + 1, (200, 200, 196))
        }
        c.rect(bx0 + bw * 0.08, by0 + bh * 0.3, bx0 + bw * 0.28, by1, slate)
        c.rect(bx0 + bw * 0.12, by0 + bh * 0.38, bx0 + bw * 0.12 + 2, by0 + bh * 0.38 + 1, orange)
        let rcx = bx0 + bw * 0.8, rcy = by0 + bh * 0.35, rr = max(3, bw * 0.08)
        var ang = 0.0
        while ang < 6.28 { c.set(rcx + cos(ang) * rr, rcy + sin(ang) * rr, grey); ang += 0.12 }
        c.line(rcx, rcy, rcx + rr * 0.6, rcy - rr * 0.5, ink)
        c.rect(bx0, by1 - 2, bx1, by1, (196, 196, 192))

        // Tiefe: je weiter hinten, desto mehr Dunst
        for y in 0..<h {
            for xx in 0..<w {
                var t: Double
                if Double(xx) >= bx0 && Double(xx) < bx1 && Double(y) >= by0 && Double(y) < by1 {
                    t = 1
                } else {
                    let dx = abs(Double(xx) + 0.5 - cx) / (W / 2)
                    let dy = Double(y) < G.vy ? (G.vy - Double(y)) / G.vy : (Double(y) - G.vy) / (H - G.vy)
                    t = 1 - max(dx, dy)
                }
                let f = 0.12 + 0.5 * clampD(t, 0, 1)
                let i = (y * w + xx) * 4
                c.d[i] = UInt8((Double(c.d[i]) * (1 - f) + Double(paper.0) * f).rounded())
                c.d[i + 1] = UInt8((Double(c.d[i + 1]) * (1 - f) + Double(paper.1) * f).rounded())
                c.d[i + 2] = UInt8((Double(c.d[i + 2]) * (1 - f) + Double(paper.2) * f).rounded())
            }
        }

        // Kasten hinten: Boden in Perspektive, Rückkanten (liegen hinter dem Wesen)
        let cb0 = G.cb0, cb1 = G.cb1, ct = G.ct, yF = G.yF, yB = G.yB
        c.quad([(0, yF), (cb0, yB), (cb1, yB), (W, yF)], light)
        for k in 1..<6 {
            let t = Double(k) / 6
            c.line(cb0 + (cb1 - cb0) * t, yB, W * t, yF, (226, 226, 223))
        }
        c.line(cb0, yB, cb1, yB, (180, 180, 176))
        c.line(cb0, ct, cb0, yB, (176, 180, 182), 0.8)
        c.line(cb1, ct, cb1, yB, (176, 180, 182), 0.8)
        c.line(cb0, ct, cb1, ct, (176, 180, 182), 0.8)
        // Seitenscheiben und Deckel leicht kühl getönt
        c.quad([(0, 0), (cb0, ct), (cb0, yB), (0, yF)], (200, 214, 218), 0.16)
        c.quad([(W, 0), (W, yF), (cb1, yB), (cb1, ct)], (200, 214, 218), 0.22)
        c.quad([(0, 0), (W, 0), (cb1, ct), (cb0, ct)], (210, 220, 224), 0.14)
        return c
    }

    /// Glas vor dem Wesen: Kanten zur Rückseite, Spiegelungen, Frontrahmen, Sockel
    static func glass(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h, opaque: false)
        let G = geo(w, h), W = Double(w), H = Double(h)
        let cb0 = G.cb0, cb1 = G.cb1, ct = G.ct, yF = G.yF, yB = G.yB
        c.line(0, 0, cb0, ct, (120, 128, 134))
        c.line(W - 1, 0, cb1, ct, (120, 128, 134))
        c.line(0, yF, cb0, yB, (150, 156, 160), 0.8)
        c.line(W - 1, yF, cb1, yB, (150, 156, 160), 0.8)
        // Spiegelungen auf der Frontscheibe
        var y = 4.0
        while y < yF - 1 {
            let x = (W * 0.16 + (yF - y) * 0.42).rounded()
            c.rect(x, y, x + 3, y + 1, white, 0.35); c.rect(x + 6, y, x + 7, y + 1, white, 0.25)
            if y < yF * 0.55 {
                let x2 = (W * 0.78 + (yF * 0.55 - y) * 0.42).rounded()
                c.rect(x2, y, x2 + 2, y + 1, white, 0.25)
            }
            y += 1
        }
        // Frontrahmen: feine dunkle Linie, oben ein Deckel mit Schrauben
        c.rect(0, 0, W, 3, (226, 226, 223)); c.rect(0, 3, W, 4, slate); c.rect(0, 0, W, 1, white, 0.8)
        c.rect(0, 0, 2, yF, (226, 226, 223)); c.rect(2, 3, 3, yF, slate)
        c.rect(W - 2, 0, W, yF, (226, 226, 223)); c.rect(W - 3, 3, W - 2, yF, slate)
        var x = 10.0
        while x < W - 8 { c.rect(x, 1, x + 2, 2, grey); x += 12 }
        // Sockel vorne
        c.rect(0, yF, W, H, slate); c.rect(0, yF, W, yF + 1, ink); c.rect(0, yF + 1, W, yF + 2, (96, 104, 110))
        x = 6
        while x < W * 0.3 { c.rect(x, yF + 4, x + 1, yF + 5, (120, 128, 134)); x += 3 }
        c.rect(W - 12, yF + 3, W - 9, yF + 6, orange)
        c.rect(4, 4, 6, 6, orange); c.rect(W - 6, 4, W - 4, 6, orange)
        return c
    }
}
