import Foundation
import CoreGraphics

/// Pixelbild in RGBA (vormultipliziert), wird zu einem CGImage
struct PixelCanvas {
    let w: Int, h: Int
    var d: [UInt8]
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h; d = [UInt8](repeating: 0, count: w * h * 4) }

    /// Deckend mischen (Hintergrund)
    mutating func set(_ x: Int, _ y: Int, _ c: RGB, _ a: Double = 1) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let i = (y * w + x) * 4
        d[i] = UInt8(clamping: Int((Double(d[i]) * (1 - a) + Double(c.0) * a).rounded()))
        d[i + 1] = UInt8(clamping: Int((Double(d[i + 1]) * (1 - a) + Double(c.1) * a).rounded()))
        d[i + 2] = UInt8(clamping: Int((Double(d[i + 2]) * (1 - a) + Double(c.2) * a).rounded()))
        d[i + 3] = 255
    }
    mutating func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: RGB, _ a: Double = 1) {
        let ys = Int(y0.rounded()), ye = Int(y1.rounded()), xs = Int(x0.rounded()), xe = Int(x1.rounded())
        guard ye > ys, xe > xs else { return }
        for y in ys..<ye { for x in xs..<xe { set(x, y, c, a) } }
    }

    /// Durchsichtig darüberlegen (Glas): "über"-Mischung in vormultiplizierten Werten
    mutating func over(_ x: Int, _ y: Int, _ c: RGB, _ a: Double) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        let i = (y * w + x) * 4
        let A = Double(d[i + 3]) / 255
        d[i] = UInt8(clamping: Int((Double(c.0) * a + Double(d[i]) * (1 - a)).rounded()))
        d[i + 1] = UInt8(clamping: Int((Double(c.1) * a + Double(d[i + 1]) * (1 - a)).rounded()))
        d[i + 2] = UInt8(clamping: Int((Double(c.2) * a + Double(d[i + 2]) * (1 - a)).rounded()))
        d[i + 3] = UInt8(clamping: Int(((a + A * (1 - a)) * 255).rounded()))
    }
    mutating func overRect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: RGB, _ a: Double) {
        let ys = Int(y0.rounded()), ye = Int(y1.rounded()), xs = Int(x0.rounded()), xe = Int(x1.rounded())
        guard ye > ys, xe > xs else { return }
        for y in ys..<ye { for x in xs..<xe { over(x, y, c, a) } }
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

/// Weißes Labor hinter dem Glaskasten, als Pixelbild. Bewusst blass: es soll nur schemenhaft im Hintergrund stehen.
enum LabScene {
    static let wall: RGB = (234, 239, 238)

    static func floorRow(_ h: Int) -> Int { h - max(9, Int((Double(h) * 0.13).rounded())) }

    static func backdrop(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h)
        let W = Double(w), H = Double(h)
        let seam: RGB = (220, 227, 226), ceil: RGB = (246, 248, 248), lamp: RGB = (255, 255, 255)
        let pipe: RGB = (208, 216, 215), pipeH: RGB = (238, 242, 242), pipeD: RGB = (190, 199, 198)
        let win: RGB = (214, 231, 238), win2: RGB = (226, 239, 243), frame: RGB = (205, 213, 212), shelf: RGB = (200, 208, 207)
        let counter: RGB = (218, 224, 223), cTop: RGB = (244, 246, 246), cEdge: RGB = (196, 205, 204)
        let glassC: RGB = (236, 242, 242), screen: RGB = (224, 240, 237), dark: RGB = (150, 162, 160)
        let teal: RGB = (120, 196, 184), orange: RGB = (236, 178, 146), violet: RGB = (188, 176, 232), lime: RGB = (178, 214, 140)
        let counterY = (H * 0.66).rounded(), floorY = Double(floorRow(h))

        c.rect(0, 0, W, H, wall)
        // Deckenstreifen mit Leuchten
        c.rect(0, 0, W, 4, ceil); c.rect(0, 4, W, 5, seam)
        for f in [0.18, 0.5, 0.82] { let cx = W * f; c.rect(cx - 9, 1, cx + 9, 3, lamp); c.rect(cx - 12, 5, cx + 12, 7, lamp, 0.35) }
        // Wandpaneele
        var sx = 10.0
        while sx < W { c.rect(sx, 9, sx + 1, counterY, seam, 0.8); sx += 26 }
        let band = (H * 0.34).rounded()
        c.rect(0, band, W, band + 1, seam, 0.7)
        // Rohr unter der Decke, eins senkrecht rechts
        c.rect(0, 10, W, 12, pipe); c.rect(0, 10, W, 11, pipeH); c.rect(0, 12, W, 13, pipeD, 0.6)
        var cx = 6.0
        while cx < W { c.rect(cx, 9, cx + 2, 14, pipeD); cx += 31 }
        let px = W - 9
        c.rect(px, 12, px + 3, counterY, pipe); c.rect(px, 12, px + 1, counterY, pipeH); c.rect(px + 2, 12, px + 3, counterY, pipeD, 0.6)
        // Fenster in der Mitte, mit Lamellen und Lichtstreifen
        let wx0 = (W * 0.32).rounded(), wx1 = (W * 0.68).rounded(), wy0 = (H * 0.17).rounded(), wy1 = (H * 0.48).rounded()
        c.rect(wx0 - 2, wy0 - 2, wx1 + 2, wy1 + 2, frame)
        var y = wy0
        while y < wy1 {
            c.rect(wx0, y, wx1, y + 1, (y - wy0) / (wy1 - wy0) < 0.5 ? win2 : win)
            if Int(y - wy0) % 4 == 3 { c.rect(wx0, y, wx1, y + 1, frame, 0.25) }
            let lx = wx0 + 6 + (wy1 - y) * 0.7
            c.rect(lx, y, min(wx1, lx + 3), y + 1, lamp, 0.5); c.rect(lx + 6, y, min(wx1, lx + 7), y + 1, lamp, 0.4)
            y += 1
        }
        c.rect(((wx0 + wx1) / 2).rounded(), wy0, ((wx0 + wx1) / 2).rounded() + 1, wy1, frame)
        // Regal links mit Gläsern
        let s0 = 4.0, s1 = (W * 0.24).rounded()
        let liquids = [teal, orange, violet, lime]
        var li = 0
        for f in [0.24, 0.4, 0.56] {
            let sy = (H * f).rounded()
            c.rect(s0, sy, s1, sy + 1, shelf); c.rect(s0, sy + 1, s1, sy + 2, pipeD, 0.4)
            var x = s0 + 2
            while x < s1 - 5 {
                // einfache Streuung statt Gleichtakt
                let k = (li * 5 + Int(x) * 3 + Int(f * 10)) % 5
                let col = liquids[(li * 3 + k) % 4]
                li += 1
                switch k {
                case 0: c.rect(x, sy - 6, x + 2, sy, glassC); c.rect(x, sy - 3, x + 2, sy, col)                    // Reagenzglas
                case 1: c.rect(x + 1, sy - 7, x + 3, sy - 3, glassC); c.rect(x, sy - 3, x + 4, sy, col)            // Kolben
                case 2: c.rect(x, sy - 5, x + 3, sy - 4, glassC); c.rect(x, sy - 4, x + 3, sy, col)                // Becher
                case 3: c.rect(x, sy - 8, x + 1, sy, glassC); c.rect(x, sy - 2, x + 1, sy, col)                    // Pipette
                default: break                                                                                     // Lücke
                }
                x += k == 1 ? 6 : (k == 4 ? 3 : 4)
            }
        }
        // Monitor rechts mit Kurve
        let mx0 = (W * 0.76).rounded(), mx1 = min(W - 14, mx0 + 24), my0 = (H * 0.18).rounded(), my1 = my0 + 15
        c.rect(mx0 - 1, my0 - 1, mx1 + 1, my1 + 1, frame); c.rect(mx0, my0, mx1, my1, screen)
        var x = mx0 + 1
        while x < mx1 - 1 {
            let yy = (my0 + 8 - sin((x - mx0) * 0.5) * 3 - (x - mx0) * 0.12).rounded()
            c.set(Int(x), Int(yy), teal)
            x += 1
        }
        let mmid = ((mx0 + mx1) / 2).rounded()
        c.rect(mmid - 1, my1 + 1, mmid + 1, my1 + 4, frame)
        let dy0 = (H * 0.4).rounded()
        c.rect(mx0 + 2, dy0, mx0 + 12, dy0 + 5, frame); c.rect(mx0 + 3, dy0 + 1, mx0 + 11, dy0 + 4, screen)
        // Arbeitsplatte
        c.rect(0, counterY, W, H, counter); c.rect(0, counterY, W, counterY + 2, cTop); c.rect(0, counterY + 2, W, counterY + 3, cEdge, 0.7)
        var dx = 18.0
        while dx < W { c.rect(dx, counterY + 5, dx + 1, H, cEdge, 0.5); dx += 30 }
        // Geräte: Mikroskop links, Zentrifuge rechts
        let m0 = (W * 0.08).rounded()
        c.rect(m0, counterY - 2, m0 + 8, counterY, dark); c.rect(m0 + 5, counterY - 9, m0 + 7, counterY - 2, dark)
        c.rect(m0 + 2, counterY - 10, m0 + 7, counterY - 8, dark); c.rect(m0 + 1, counterY - 6, m0 + 5, counterY - 5, dark)
        let c0 = (W * 0.83).rounded()
        c.rect(c0, counterY - 6, c0 + 11, counterY, frame); c.rect(c0 + 1, counterY - 6, c0 + 10, counterY - 5, cTop); c.rect(c0 + 8, counterY - 4, c0 + 10, counterY - 2, teal)

        // Alles schemenhaft: Richtung Wandfarbe ziehen
        var i = 0
        while i < w * h * 4 {
            c.d[i] = UInt8((Double(c.d[i]) * 0.62 + Double(wall.0) * 0.38).rounded())
            c.d[i + 1] = UInt8((Double(c.d[i + 1]) * 0.62 + Double(wall.1) * 0.38).rounded())
            c.d[i + 2] = UInt8((Double(c.d[i + 2]) * 0.62 + Double(wall.2) * 0.38).rounded())
            i += 4
        }
        // Sockel des Glaskastens (scharf, vorne), mit Leuchtleiste
        let pl: RGB = (248, 250, 250), pf: RGB = (226, 232, 231), pe: RGB = (184, 194, 193), led: RGB = (92, 196, 178)
        c.rect(0, floorY - 2, W, floorY + 1, pl); c.rect(0, floorY - 3, W, floorY - 2, pe, 0.5)
        c.rect(0, floorY + 1, W, H, pf); c.rect(0, floorY + 1, W, floorY + 2, pe)
        c.rect((W * 0.12).rounded(), floorY + 4, (W * 0.88).rounded(), floorY + 5, led)
        c.rect((W * 0.12).rounded(), floorY + 5, (W * 0.88).rounded(), floorY + 6, led, 0.3)
        c.rect(0, H - 1, W, H, pe)
        return c
    }

    /// Glas vor dem Wesen: leichter Schimmer, Spiegelungen, Rahmen
    static func glass(_ w: Int, _ h: Int) -> PixelCanvas {
        var c = PixelCanvas(w, h)
        let W = Double(w), floorY = Double(floorRow(h))
        let white: RGB = (255, 255, 255), f: RGB = (196, 206, 205), fd: RGB = (168, 180, 179), tint: RGB = (200, 232, 228)
        c.overRect(0, 0, W, floorY - 2, tint, 0.07)
        var y = 0.0
        while y < floorY - 2 {
            let x = (W * 0.08 + (floorY - y) * 0.45).rounded()
            c.overRect(x, y, x + 4, y + 1, white, 0.28); c.overRect(x + 7, y, x + 8, y + 1, white, 0.22)
            if y < floorY * 0.6 {
                let x2 = (W * 0.8 + (floorY * 0.6 - y) * 0.45).rounded()
                c.overRect(x2, y, x2 + 2, y + 1, white, 0.2)
            }
            y += 1
        }
        // Pfosten links und rechts, Deckel oben
        c.overRect(0, 0, 3, floorY - 2, f, 1); c.overRect(2, 0, 3, floorY - 2, white, 0.8); c.overRect(0, 0, 1, floorY - 2, fd, 1)
        c.overRect(W - 3, 0, W, floorY - 2, f, 1); c.overRect(W - 3, 0, W - 2, floorY - 2, white, 0.8); c.overRect(W - 1, 0, W, floorY - 2, fd, 1)
        c.overRect(0, 0, W, 3, f, 1); c.overRect(0, 2, W, 3, fd, 1); c.overRect(0, 0, W, 1, white, 0.6)
        var x = 8.0
        while x < W - 6 { c.overRect(x, 1, x + 1, 2, fd, 1); x += 14 }
        return c
    }
}
