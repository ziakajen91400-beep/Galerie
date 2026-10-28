import SwiftUI

/// Palette complète pour un mode (clair ou sombre). Toutes les couleurs sont en hexadécimal RRGGBBAA.
struct ThemePalette: Codable, Equatable {
    var background: String
    var surface: String
    var elevated: String
    var navBar: String
    var menu: String
    var card: String
    var text: String
    var textSecondary: String
    var icon: String
    var border: String
    var separator: String
    var shadow: String
    var accent: String
    var glassTint: String
    var glassOpacity: Double
}

struct Theme: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var isCustom: Bool = false
    var light: ThemePalette
    var dark: ThemePalette

    /// Génère une paire clair/sombre harmonieuse à partir d’une teinte.
    /// - hue : 0...1, tint : intensité de la teinte (0 = gris neutre), darkBrightness : luminosité du fond sombre.
    static func generated(id: String, name: String, hue h: Double, tint t: Double, darkBrightness db: Double = 0.10, accentSat: Double = 0.62) -> Theme {
        let L = ThemePalette(
            background: Color.hsb(h, 0.03 + 0.10 * t, 0.975),
            surface: Color.hsb(h, 0.015 + 0.05 * t, 1.0),
            elevated: Color.hsb(h, 0.01 + 0.03 * t, 1.0),
            navBar: Color.hsb(h, 0.02 + 0.07 * t, 0.99),
            menu: Color.hsb(h, 0.02 + 0.06 * t, 0.99),
            card: Color.hsb(h, 0.01 + 0.04 * t, 1.0),
            text: Color.hsb(h, 0.10 + 0.30 * t, 0.14),
            textSecondary: Color.hsb(h, 0.05 + 0.20 * t, 0.42),
            icon: Color.hsb(h, 0.10 + 0.35 * t, 0.26),
            border: Color.hsb(h, 0.05 + 0.12 * t, 0.88),
            separator: Color.hsb(h, 0.04 + 0.10 * t, 0.91),
            shadow: Color.hsb(h, 0.4, 0.25),
            accent: Color.hsb(h, accentSat * min(1, 0.4 + t), 0.90),
            glassTint: Color.hsb(h, 0.20 * t, 1.0),
            glassOpacity: 0.30)
        let D = ThemePalette(
            background: Color.hsb(h, 0.10 + 0.35 * t, db),
            surface: Color.hsb(h, 0.10 + 0.32 * t, db + 0.05),
            elevated: Color.hsb(h, 0.10 + 0.30 * t, db + 0.10),
            navBar: Color.hsb(h, 0.10 + 0.34 * t, db + 0.02),
            menu: Color.hsb(h, 0.10 + 0.30 * t, db + 0.07),
            card: Color.hsb(h, 0.10 + 0.30 * t, db + 0.08),
            text: Color.hsb(h, 0.05 * t, 0.96),
            textSecondary: Color.hsb(h, 0.05 + 0.12 * t, 0.70),
            icon: Color.hsb(h, 0.10 * t, 0.90),
            border: Color.hsb(h, 0.10 + 0.30 * t, db + 0.19),
            separator: Color.hsb(h, 0.10 + 0.30 * t, db + 0.13),
            shadow: "000000FF",
            accent: Color.hsb(h, 0.30 + 0.25 * t, 0.97),
            glassTint: Color.hsb(h, 0.55 * t, 0.40),
            glassOpacity: 0.40)
        return Theme(id: id, name: name, light: L, dark: D)
    }

    static let presets: [Theme] = {
        var list: [Theme] = []
        // Thème d’origine : neutre, accent bleu iOS.
        var g = Theme.generated(id: "galerie", name: "Galerie", hue: 0.6, tint: 0.05)
        g.light.accent = "0A84FFFF"; g.dark.accent = "0A84FFFF"
        g.light.background = "F2F2F7FF"; g.dark.background = "000000FF"
        list.append(g)
        let defs: [(String, String, Double, Double, Double)] = [
            ("rose", "Rose", 0.93, 0.85, 0.11),
            ("rose-poudre", "Rose poudré", 0.97, 0.45, 0.12),
            ("rouge", "Rouge", 0.0, 1.0, 0.09),
            ("bordeaux", "Bordeaux", 0.97, 1.0, 0.07),
            ("corail", "Corail", 0.03, 0.8, 0.10),
            ("orange", "Orange", 0.07, 1.0, 0.09),
            ("jaune", "Jaune", 0.14, 1.0, 0.09),
            ("sable", "Sable", 0.10, 0.35, 0.11),
            ("vert", "Vert", 0.36, 0.9, 0.08),
            ("foret", "Forêt", 0.39, 1.0, 0.07),
            ("menthe", "Menthe", 0.43, 0.55, 0.10),
            ("turquoise", "Turquoise", 0.48, 1.0, 0.08),
            ("cyan", "Cyan", 0.52, 1.0, 0.08),
            ("ocean", "Océan", 0.56, 1.0, 0.08),
            ("bleu-clair", "Bleu clair", 0.57, 0.6, 0.12),
            ("bleu", "Bleu", 0.61, 0.9, 0.10),
            ("bleu-nuit", "Bleu nuit", 0.65, 1.0, 0.06),
            ("violet", "Violet", 0.76, 0.9, 0.09),
            ("lavande", "Lavande", 0.72, 0.45, 0.12),
            ("crepuscule", "Crépuscule", 0.82, 0.9, 0.08),
            ("gris", "Gris", 0.6, 0.04, 0.12),
        ]
        for d in defs { list.append(Theme.generated(id: d.0, name: d.1, hue: d.2, tint: d.3, darkBrightness: d.4)) }
        // Noir pur (OLED)
        var noir = Theme.generated(id: "noir", name: "Noir", hue: 0.0, tint: 0.0, darkBrightness: 0.0)
        noir.dark.background = "000000FF"; noir.dark.surface = "0C0C0EFF"; noir.dark.card = "141416FF"
        noir.dark.navBar = "000000FF"; noir.dark.elevated = "1C1C1EFF"; noir.dark.menu = "161618FF"
        noir.dark.accent = "FFFFFFFF"; noir.light.accent = "1C1C1EFF"
        list.append(noir)
        // Blanc pur
        var blanc = Theme.generated(id: "blanc", name: "Blanc", hue: 0.0, tint: 0.0, darkBrightness: 0.16)
        blanc.light.background = "FFFFFFFF"; blanc.light.surface = "FFFFFFFF"; blanc.light.card = "F7F7F8FF"
        blanc.light.accent = "111111FF"
        list.append(blanc)
        return list
    }()
}

/// Couleurs résolues pour le mode courant (clair/sombre) : c’est ce que lisent les vues.
struct Pal: Equatable {
    var bg = Color(hex: "F2F2F7"), surface = Color.white, elevated = Color.white, nav = Color.white
    var menu = Color.white, card = Color.white
    var text = Color.black, textSecondary = Color.gray, icon = Color.black
    var border = Color.gray.opacity(0.3), separator = Color.gray.opacity(0.2), shadow = Color.black
    var accent = Color.blue, glassTint = Color.white, glassOpacity = 0.3

    init() {}
    init(_ p: ThemePalette, accentOverride: String? = nil) {
        bg = Color(hex: p.background); surface = Color(hex: p.surface); elevated = Color(hex: p.elevated)
        nav = Color(hex: p.navBar); menu = Color(hex: p.menu); card = Color(hex: p.card)
        text = Color(hex: p.text); textSecondary = Color(hex: p.textSecondary); icon = Color(hex: p.icon)
        border = Color(hex: p.border); separator = Color(hex: p.separator); shadow = Color(hex: p.shadow)
        accent = Color(hex: accentOverride ?? p.accent)
        glassTint = Color(hex: p.glassTint); glassOpacity = p.glassOpacity
    }
}

private struct PalKey: EnvironmentKey { static let defaultValue = Pal() }
extension EnvironmentValues { var pal: Pal { get { self[PalKey.self] } set { self[PalKey.self] = newValue } } }

@MainActor
final class ThemeStore: ObservableObject {
    private static let key = "galerie.customThemes.v1"
    @Published var custom: [Theme] = [] { didSet { persist() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let t = try? JSONDecoder().decode([Theme].self, from: d) { custom = t }
    }
    var all: [Theme] { Theme.presets + custom }
    func theme(_ id: String) -> Theme { all.first { $0.id == id } ?? Theme.presets[0] }
    private func persist() { if let d = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(d, forKey: Self.key) } }

    func palette(id: String, dark: Bool, accent: String?) -> Pal {
        let t = theme(id)
        return Pal(dark ? t.dark : t.light, accentOverride: accent)
    }
    func save(_ t: Theme) {
        var n = t; n.isCustom = true
        if let i = custom.firstIndex(where: { $0.id == n.id }) { custom[i] = n } else { custom.append(n) }
    }
    func duplicate(_ t: Theme) -> Theme {
        var n = t; n.id = "custom-" + String(UUID().uuidString.prefix(8)); n.name = t.name + " copie"; n.isCustom = true
        custom.append(n); return n
    }
    func delete(_ t: Theme) { custom.removeAll { $0.id == t.id } }
    func newTheme() -> Theme {
        var n = Theme.generated(id: "custom-" + String(UUID().uuidString.prefix(8)), name: "Mon thème", hue: 0.6, tint: 0.5)
        n.isCustom = true; return n
    }
}

/// Racine : calcule les couleurs selon le thème, le mode et l’accent, puis les injecte partout.
struct ThemedRoot: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var fonts: FontStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = settings.prefs
        let dark = p.appearance == .dark || (p.appearance == .system && scheme == .dark)
        let pal = themes.palette(id: p.themeID, dark: dark, accent: p.customAccent ? p.accentHex : nil)
        RootView()
            .environment(\.pal, pal)
            .tint(pal.accent)
            .foregroundStyle(pal.text)
            .preferredColorScheme(p.appearance.scheme)
            .background(pal.bg.ignoresSafeArea())
    }
}
