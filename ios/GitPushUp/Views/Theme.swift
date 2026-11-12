import SwiftUI

/// Hangar-Look: Schwarz, kaltes Wireframe-Cyan, Phosphor-Grün für erschöpfte Muskeln, Bernstein für Highlights.
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
    static let bg = Color(hex: 0x04070a)
    static let panel = Color(hex: 0x070c10)
    static let line = Color(hex: 0x14222a)
    static let line2 = Color(hex: 0x1d3038)
    static let fg = Color(hex: 0xdcecef)
    static let muted = Color(hex: 0x6f8a93)
    static let dim = Color(hex: 0x3e545c)
    static let wire = Color(hex: 0xa8dde6)
    static let phos = Color(hex: 0x7ef0a6)
    static let amber = Color(hex: 0xf2a85a)
    static let danger = Color(hex: 0xff6b6b)
}

extension ExCategory {
    var color: Color {
        switch self {
        case .beine: return Color(hex: 0x7ef0a6)
        case .druecken: return Color(hex: 0xf2a85a)
        case .ziehen: return Color(hex: 0x7fd3ff)
        case .rumpf: return Color(hex: 0xc69cff)
        }
    }
}

func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

/// Kleine Großbuchstaben-Beschriftung mit Sperrung
struct Label12: View {
    let text: String
    var color: Color = .muted
    var size: CGFloat = 10.5
    var body: some View {
        Text(text).font(mono(size, .medium)).tracking(1.6).foregroundStyle(color)
    }
}

/// Leuchten wie Phosphor auf einem alten Bildschirm
extension View {
    func glow(_ c: Color, _ r: CGFloat = 8) -> some View {
        shadow(color: c.opacity(0.55), radius: r)
    }
}

/// Umrandeter Knopf im Hangar-Stil
struct HangarButtonStyle: ButtonStyle {
    var color: Color = .fg
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(mono(13, .bold)).tracking(1.4)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(color.opacity(filled ? 0.1 : 0).background(Color.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(filled ? color : Color.line2, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Trennlinie oben, wie bei den Blöcken der Web-App
struct Block<Content: View>: View {
    let title: String?
    var trailing: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Color.line2).frame(height: 1)
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Label12(text: title, color: .wire, size: 12)
                    Spacer()
                    if let trailing { Text(trailing).font(mono(11)).foregroundStyle(Color.muted) }
                }
            }
            content
        }
    }
}

func fmtTime(_ ts: Millis) -> String {
    let d = Date(timeIntervalSince1970: ts / 1000)
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateFormat = "dd.MM. · HH:mm"
    return f.string(from: d)
}
