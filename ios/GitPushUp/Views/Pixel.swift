import SwiftUI

// Pixel-Bausteine: alles außer Schrift soll aussehen wie auf einem groben Bildschirm.
// Ein "Pixel" ist hier 2 Punkte groß.

let PX: CGFloat = 2

@inline(__always) func snap(_ v: CGFloat) -> CGFloat { (v / PX).rounded(.down) * PX }

/// Rahmen aus Pixeln, die Ecken sind abgeknipst (fehlendes Eckpixel)
struct PixelFrame: Shape {
    var t: CGFloat = PX
    func path(in r0: CGRect) -> Path {
        let r = CGRect(x: snap(r0.minX), y: snap(r0.minY), width: snap(r0.width), height: snap(r0.height))
        var p = Path()
        p.addRect(CGRect(x: r.minX + t, y: r.minY, width: r.width - 2 * t, height: t))
        p.addRect(CGRect(x: r.minX + t, y: r.maxY - t, width: r.width - 2 * t, height: t))
        p.addRect(CGRect(x: r.minX, y: r.minY + t, width: t, height: r.height - 2 * t))
        p.addRect(CGRect(x: r.maxX - t, y: r.minY + t, width: t, height: r.height - 2 * t))
        return p
    }
}

/// Gefüllte Fläche mit abgeknipsten Ecken
struct PixelBlock: Shape {
    func path(in r0: CGRect) -> Path {
        let r = CGRect(x: snap(r0.minX), y: snap(r0.minY), width: snap(r0.width), height: snap(r0.height))
        var p = Path()
        p.addRect(CGRect(x: r.minX + PX, y: r.minY, width: r.width - 2 * PX, height: r.height))
        p.addRect(CGRect(x: r.minX, y: r.minY + PX, width: PX, height: r.height - 2 * PX))
        p.addRect(CGRect(x: r.maxX - PX, y: r.minY + PX, width: PX, height: r.height - 2 * PX))
        return p
    }
}

extension View {
    func pixelBorder(_ c: Color = .line2) -> some View { overlay(PixelFrame().fill(c)) }
}

/// Balken aus einzelnen Blöcken
struct PixelBar: View {
    let value: Double
    var color: Color = .signal
    var height: CGFloat = 8
    var block: CGFloat = 3 * PX
    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                let inner = CGRect(x: PX * 2, y: PX * 2, width: size.width - PX * 4, height: size.height - PX * 4)
                let n = Int((inner.width + PX) / (block + PX))
                let lit = Int((Double(n) * min(1, max(0, value))).rounded())
                for i in 0..<max(0, n) {
                    let r = CGRect(x: inner.minX + CGFloat(i) * (block + PX), y: inner.minY, width: block, height: inner.height)
                    ctx.fill(Path(r), with: .color(i < lit ? color : Color.line.opacity(0.6)))
                }
                ctx.fill(PixelFrame().path(in: CGRect(origin: .zero, size: size)), with: .color(Color.line2))
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .frame(height: height + PX * 4)
    }
}

/// Symbol aus Pixeln. Muster: "#" = gesetzt, alles andere leer.
struct PixelIcon: View {
    let rows: [String]
    var color: Color = .fg
    var cell: CGFloat = PX
    var body: some View {
        let h = rows.count, w = rows.map { $0.count }.max() ?? 0
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(w) * cell, height: CGFloat(h) * cell)
    }

    static let plus = ["...#...", "...#...", "...#...", "#######", "...#...", "...#...", "...#..."]
    static let pulse = ["........#......", "........#......", ".......#.#.....", "##.....#.#...##", "..#...#...#.#..", "...#.#....#....", "....#.........."]
    static let gear = ["...#.#...", ".#######.", ".##...##.", "###...###", ".#.....#.", "###...###", ".##...##.", ".#######.", "...#.#..."]
    static let arrow = ["....#...", ".....#..", "########", ".....#..", "....#..."]
    static let close = ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"]
    static let back = ["...#....", "..#.....", "########", "..#.....", "...#...."]
}

/// Linien auf dem Pixelraster: sammelt Strecken und malt sie als Pixel
struct PixelPath {
    var lines: [[CGPoint]] = []
    mutating func move(to p: CGPoint) { lines.append([p]) }
    mutating func addLine(to p: CGPoint) {
        if lines.isEmpty { lines.append([p]) } else { lines[lines.count - 1].append(p) }
    }
}

extension GraphicsContext {
    /// Strecken pixelig zeichnen: in Pixelschritten abtasten, jedes Pixel als Quadrat
    func pixelStroke(_ pp: PixelPath, _ color: Color, size: CGFloat = PX) {
        var path = Path()
        var seen = Set<Int>()
        for poly in pp.lines where poly.count > 1 {
            for i in 0..<(poly.count - 1) {
                let a = poly[i], b = poly[i + 1]
                let n = max(1, Int(max(abs(b.x - a.x), abs(b.y - a.y)) / PX))
                for s in 0...n {
                    let t = CGFloat(s) / CGFloat(n)
                    let x = snap(a.x + (b.x - a.x) * t), y = snap(a.y + (b.y - a.y) * t)
                    let key = Int(x / PX) &* 73_856_093 ^ Int(y / PX) &* 19_349_663
                    if seen.insert(key).inserted { path.addRect(CGRect(x: x, y: y, width: size, height: size)) }
                }
            }
        }
        fill(path, with: .color(color))
    }
}

/// Hirnströme als Pixel-Linie: kurz nach einer Meditation ruhige Alpha-Wellen, je länger her,
/// desto schneller und verrauschter, mit gelegentlichen Ausschlägen
struct ResonanceWave: View {
    let calm: Double
    var color: Color = .fg
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let mid = Double(size.height) / 2, H = Double(size.height) / 2
                let c = max(0, min(1, calm))
                var pp = PixelPath()
                var x = 0.0
                var first = true
                while x <= Double(size.width) {
                    let u = x + t * 28
                    let alpha = sin(u * 0.22) * (0.35 + 0.45 * c)
                    let beta = (sin(u * 0.91 + 1.3) * 0.5 + sin(u * 1.73 + 0.4) * 0.35 + sin(u * 2.9) * 0.25) * (1 - c) * 0.55
                    let k = sin(u * 0.037) * sin(u * 0.053 + 2)
                    let spike = (k > 0.93 ? (k - 0.93) * 12 : 0) * (1 - c) * sin(u * 3.1)
                    let y = mid - (alpha + beta + spike) * H * 0.85
                    let pt = CGPoint(x: x, y: y)
                    if first { pp.move(to: pt); first = false } else { pp.addLine(to: pt) }
                    x += Double(PX)
                }
                ctx.pixelStroke(pp, color)
            }
        }
    }
}

/// Kleiner Knopf mit Pixelrahmen und Pixelsymbol
struct PixelToolButton: View {
    let icon: [String]
    let label: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PixelIcon(rows: icon, color: enabled ? .fg : .dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.panel)
                .pixelBorder()
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
