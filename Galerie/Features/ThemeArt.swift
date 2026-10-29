import SwiftUI
import UIKit

// MARK: - Fond décoratif des thèmes
//
// Les thèmes « inspirés d’animés » sont des créations ORIGINALES : palettes et motifs décoratifs dessinés par
// code (rubans, étoiles, flocons, lune, oreilles de lapin stylisées). Aucun personnage ni illustration officielle
// n’est reproduit ou embarqué. Pour voir un personnage, l’utilisateur peut ajouter sa propre image (dont il détient
// les droits) comme fond du thème : elle reste sur l’iPhone, aucune connexion n’est nécessaire.

struct BackdropSpec: Equatable {
    var art: String?
    var image: UIImage?
    var opacity: Double
    var dark: Bool = false
    /// Identifiant d’un personnage fictif embarqué (assets « Char-<id> »).
    var character: String? = nil
}

private struct BackdropKey: EnvironmentKey { static let defaultValue: BackdropSpec? = nil }
extension EnvironmentValues { var backdrop: BackdropSpec? { get { self[BackdropKey.self] } set { self[BackdropKey.self] = newValue } } }

struct BackdropView: View {
    let spec: BackdropSpec
    let pal: Pal
    let dark: Bool

    var body: some View {
        ZStack {
            if let img = spec.image {
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().opacity(spec.opacity) }.clipped()
                // L’image s’estompe vers le bas : la grille et les listes restent lisibles.
                LinearGradient(colors: [pal.bg.opacity(0.0), pal.bg.opacity(0.55), pal.bg.opacity(0.94)], startPoint: .top, endPoint: .bottom)
            } else if let art = spec.art {
                ThemeArtCanvas(art: art, pal: pal, dark: dark)
            }
            // Personnage fictif du thème, en bas à droite, sans jamais capter les touches.
            if spec.image == nil, let ch = spec.character, UIImage(named: "Char-" + ch) != nil {
                GeometryReader { g in
                    Image("Char-" + ch).resizable().scaledToFit()
                        .frame(height: min(g.size.height * 0.62, g.size.width * 1.35))
                        .opacity(min(max(spec.opacity, 0.15), 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .offset(x: g.size.width * 0.08, y: 0)
                }
                .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Couleurs des cinq variantes « quintessence » (interprétation libre, modifiables via un thème personnalisé).
enum QuintPalette {
    /// Les cinq sœurs fictives (identifiants des personnages, dans l’ordre des couleurs).
    static let ids = ["sakura", "sora", "midori", "akane", "murasaki"]
    static let names = ["Sakura", "Sora", "Midori", "Akane", "Murasaki"]
    static let hues: [Double] = [0.93, 0.55, 0.35, 0.02, 0.76]
    static let colors: [Color] = [
        Color(hex: "F277A8"), Color(hex: "5BB8E8"), Color(hex: "4CC26B"), Color(hex: "F25C54"), Color(hex: "8B64D8"),
    ]
}

struct ThemeArtCanvas: View {
    let art: String
    let pal: Pal
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            if art.hasPrefix("quint") {
                let idx = Int(art.split(separator: "-").last ?? "0") ?? 0
                drawQuint(&ctx, size, min(max(idx, 0), 4))
            } else if art == "yuki" { drawSnow(&ctx, size) }
            else if art == "luna" { drawNight(&ctx, size) }
            else if art == "hikari" { drawStars(&ctx, size) }
            else if art == "nekomi" { drawCafe(&ctx, size) }
        }
        .drawingGroup(opaque: false)
    }

    // MARK: Outils de dessin
    private func star(_ c: CGPoint, _ r: CGFloat, points: Int = 5, inner: CGFloat = 0.45, rotation: CGFloat = -.pi / 2) -> Path {
        var p = Path()
        let n = points * 2
        for i in 0..<n {
            let rad = i % 2 == 0 ? r : r * inner
            let a = rotation + CGFloat(i) * .pi / CGFloat(points)
            let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func wash(_ ctx: inout GraphicsContext, _ size: CGSize, _ color: Color, _ strength: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [color.opacity(strength), color.opacity(0)]),
                                       startPoint: CGPoint(x: size.width / 2, y: 0), endPoint: CGPoint(x: size.width / 2, y: size.height * 0.6)))
    }

    // MARK: Quintessence : cinq rubans, une couleur mise en avant
    private func drawQuint(_ ctx: inout GraphicsContext, _ size: CGSize, _ main: Int) {
        let cols = QuintPalette.colors
        wash(&ctx, size, cols[main], dark ? 0.22 : 0.16)
        for i in 0..<5 {
            let y0 = size.height * 0.05 + CGFloat(i) * 22
            var band = Path()
            band.move(to: CGPoint(x: -20, y: y0 + 60))
            band.addCurve(to: CGPoint(x: size.width + 20, y: y0 - 10),
                          control1: CGPoint(x: size.width * 0.3, y: y0 + 150), control2: CGPoint(x: size.width * 0.65, y: y0 - 90))
            band.addLine(to: CGPoint(x: size.width + 20, y: y0 + 12))
            band.addCurve(to: CGPoint(x: -20, y: y0 + 82),
                          control1: CGPoint(x: size.width * 0.65, y: y0 - 68), control2: CGPoint(x: size.width * 0.3, y: y0 + 172))
            band.closeSubpath()
            ctx.fill(band, with: .color(cols[i].opacity(i == main ? 0.34 : 0.13)))
        }
        var g = SeededRNG(seed: UInt64(40 + main))
        for _ in 0..<16 {
            let c = CGPoint(x: Double.random(in: 0...Double(size.width), using: &g), y: Double.random(in: 0...Double(size.height * 0.55), using: &g))
            let r = CGFloat(Double.random(in: 3...9, using: &g))
            ctx.fill(star(c, r), with: .color(cols[main].opacity(Double.random(in: 0.18...0.40, using: &g))))
        }
        // Cinq petits pétales en bas à droite : rappel des cinq sœurs.
        for i in 0..<5 {
            let a = CGFloat(i) * 2 * .pi / 5 - .pi / 2
            let c = CGPoint(x: size.width - 54 + cos(a) * 20, y: size.height - 130 + sin(a) * 20)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(cols[i].opacity(i == main ? 0.34 : 0.18)))
        }
    }

    // MARK: Neige russe : flocons, ruban cramoisi
    private func drawSnow(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let flake = dark ? Color(hex: "DCE6FF") : Color(hex: "7F98C8")
        wash(&ctx, size, dark ? Color(hex: "3A4F8F") : Color(hex: "BFD0F2"), dark ? 0.35 : 0.40)
        var g = SeededRNG(seed: 77)
        for _ in 0..<64 {
            let c = CGPoint(x: Double.random(in: 0...Double(size.width), using: &g), y: Double.random(in: 0...Double(size.height), using: &g))
            let r = CGFloat(Double.random(in: 1.2...3.6, using: &g))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(flake.opacity(Double.random(in: 0.18...0.45, using: &g))))
        }
        for _ in 0..<9 {
            let c = CGPoint(x: Double.random(in: 10...Double(size.width - 10), using: &g), y: Double.random(in: 10...Double(size.height * 0.7), using: &g))
            let r = CGFloat(Double.random(in: 9...18, using: &g))
            var p = Path()
            for k in 0..<3 {
                let a = CGFloat(k) * .pi / 3
                p.move(to: CGPoint(x: c.x - cos(a) * r, y: c.y - sin(a) * r)); p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            ctx.stroke(p, with: .color(flake.opacity(0.42)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        // Ruban cramoisi discret dans le coin.
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: size.width, y: size.height * 0.62))
        ribbon.addCurve(to: CGPoint(x: size.width * 0.55, y: size.height), control1: CGPoint(x: size.width * 0.82, y: size.height * 0.74), control2: CGPoint(x: size.width * 0.66, y: size.height * 0.95))
        ctx.stroke(ribbon, with: .color(pal.accent.opacity(0.22)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
    }

    // MARK: Minuit : lune, étoiles et oreilles de lapin stylisées
    private func drawNight(_ ctx: inout GraphicsContext, _ size: CGSize) {
        wash(&ctx, size, pal.accent, dark ? 0.20 : 0.12)
        let moon = CGPoint(x: size.width - 70, y: 110)
        ctx.drawLayer { l in
            l.fill(Path(ellipseIn: CGRect(x: moon.x - 40, y: moon.y - 40, width: 80, height: 80)), with: .color(pal.accent.opacity(0.30)))
            l.blendMode = .destinationOut
            l.fill(Path(ellipseIn: CGRect(x: moon.x - 22, y: moon.y - 48, width: 74, height: 74)), with: .color(.black))
        }
        var g = SeededRNG(seed: 99)
        for _ in 0..<22 {
            let c = CGPoint(x: Double.random(in: 0...Double(size.width), using: &g), y: Double.random(in: 0...Double(size.height * 0.6), using: &g))
            let r = CGFloat(Double.random(in: 2...6, using: &g))
            ctx.fill(star(c, r, points: 4, inner: 0.3), with: .color((dark ? Color.white : pal.accent).opacity(Double.random(in: 0.20...0.50, using: &g))))
        }
        // Deux oreilles qui dépassent du bord inférieur droit.
        for (i, ang) in [-14.0, 10.0].enumerated() {
            var c = ctx
            c.translateBy(x: size.width - 90 + CGFloat(i) * 56, y: size.height + 10)
            c.rotate(by: .degrees(ang))
            c.fill(Path(roundedRect: CGRect(x: -22, y: -190, width: 44, height: 200), cornerRadius: 22), with: .color(pal.accent.opacity(0.16)))
            c.fill(Path(roundedRect: CGRect(x: -11, y: -170, width: 22, height: 160), cornerRadius: 11), with: .color(pal.accent.opacity(0.14)))
        }
    }

    // MARK: Étoile : confettis d’étoiles dorées
    private func drawStars(_ ctx: inout GraphicsContext, _ size: CGSize) {
        wash(&ctx, size, Color(hex: "FFB347"), dark ? 0.22 : 0.20)
        var g = SeededRNG(seed: 12)
        for i in 0..<26 {
            let c = CGPoint(x: Double.random(in: 0...Double(size.width), using: &g), y: Double.random(in: 0...Double(size.height * 0.75), using: &g))
            let r = CGFloat(Double.random(in: 4...13, using: &g))
            let col = i % 3 == 0 ? pal.accent : Color(hex: "FFD166")
            ctx.fill(star(c, r, points: i % 2 == 0 ? 5 : 4, inner: i % 2 == 0 ? 0.45 : 0.3), with: .color(col.opacity(Double.random(in: 0.22...0.5, using: &g))))
        }
        var arc = Path()
        arc.addArc(center: CGPoint(x: size.width * 0.2, y: size.height * 0.22), radius: 90, startAngle: .degrees(190), endAngle: .degrees(330), clockwise: false)
        ctx.stroke(arc, with: .color(pal.accent.opacity(0.25)), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [1, 14]))
    }

    // MARK: Café : pattes de chat et petits cœurs
    private func drawCafe(_ ctx: inout GraphicsContext, _ size: CGSize) {
        wash(&ctx, size, Color(hex: "D9A066"), dark ? 0.20 : 0.18)
        var g = SeededRNG(seed: 31)
        for _ in 0..<14 {
            let c = CGPoint(x: Double.random(in: 10...Double(size.width - 10), using: &g), y: Double.random(in: 10...Double(size.height * 0.7), using: &g))
            let r = CGFloat(Double.random(in: 7...13, using: &g))
            let col = pal.accent.opacity(Double.random(in: 0.14...0.30, using: &g))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.5)), with: .color(col))
            for dx in [-1.1, 0.0, 1.1] {
                let px = c.x + CGFloat(dx) * r, py = c.y - r * 1.15
                ctx.fill(Path(ellipseIn: CGRect(x: px - r * 0.38, y: py - r * 0.45, width: r * 0.76, height: r * 0.9)), with: .color(col))
            }
        }
    }
}

// MARK: - Image de fond personnelle (facultative)
@MainActor
final class BackdropStore: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    private var dir: URL { appSupportURL("backdrops") }

    init() {
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includeHiddenFiles: false) {
            for f in files where f.pathExtension == "jpg" {
                if let d = try? Data(contentsOf: f), let img = UIImage(data: d) { images[f.deletingPathExtension().lastPathComponent] = img }
            }
        }
    }
    private func key(_ themeID: String) -> String { themeID.filter { $0.isLetter || $0.isNumber || $0 == "-" } }
    func image(_ themeID: String) -> UIImage? { images[key(themeID)] }

    /// Réduit l’image (1600 px max) pour limiter la mémoire ; l’original dans Photos n’est jamais touché.
    func set(_ data: Data, for themeID: String) {
        guard let img = UIImage(data: data) else { return }
        let maxSide: CGFloat = 1600
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let out = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        let k = key(themeID)
        images[k] = out
        try? out.jpegData(compressionQuality: 0.85)?.write(to: dir.appendingPathComponent(k + ".jpg"), options: .atomic)
    }
    func remove(for themeID: String) {
        let k = key(themeID)
        images[k] = nil
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(k + ".jpg"))
    }
}
