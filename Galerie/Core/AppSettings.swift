import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { self == .system ? "Automatique" : (self == .light ? "Clair" : "Sombre") }
    var scheme: ColorScheme? { self == .light ? .light : (self == .dark ? .dark : nil) }
}
enum ThumbAspect: String, Codable, CaseIterable, Identifiable {
    case square, portrait, landscape
    var id: String { rawValue }
    var label: String { self == .square ? "Carré" : (self == .portrait ? "Portrait 4:5" : "Paysage 3:2") }
    var ratio: CGFloat { self == .square ? 1 : (self == .portrait ? 0.8 : 1.5) }
}
enum GroupMode: String, Codable, CaseIterable, Identifiable {
    case day, month, year
    var id: String { rawValue }
    var label: String { self == .day ? "Jours" : (self == .month ? "Mois" : "Années") }
}
enum PanelStyle: String, Codable, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var label: String { self == .glass ? "Verre translucide" : "Opaque" }
}
enum FontWeightPref: String, Codable, CaseIterable, Identifiable {
    case regular, medium, semibold, bold
    var id: String { rawValue }
    var label: String {
        switch self { case .regular: return "Normal"; case .medium: return "Moyen"; case .semibold: return "Demi-gras"; case .bold: return "Gras" }
    }
    var weight: Font.Weight {
        switch self { case .regular: return .regular; case .medium: return .medium; case .semibold: return .semibold; case .bold: return .bold }
    }
}

enum GlassLevel: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { self == .low ? "Faible" : (self == .medium ? "Moyen" : "Élevé") }
    /// Part de la teinte du thème conservée dans le verre (0 = totalement transparent).
    var tintFactor: Double { self == .low ? 0.12 : (self == .medium ? 0.30 : 0.55) }
    /// Intensité des reflets et des contours lumineux.
    var highlight: Double { self == .low ? 0.35 : (self == .medium ? 0.65 : 1.0) }
}

enum HapticIntensity: String, Codable, CaseIterable, Identifiable {
    case light, medium, strong
    var id: String { rawValue }
    var label: String { self == .light ? "Faible" : (self == .medium ? "Moyenne" : "Forte") }
}

/// Onglets de la barre de navigation : identifiants stockés dans les réglages.
enum DockDefaults {
    static let tabs = ["collections", "search", "library", "map", "settings"]
}

struct Prefs: Codable, Equatable {
    var appearance: AppearanceMode = .system
    var themeID: String = "galerie"
    var customAccent: Bool = false
    var accentHex: String = "0A84FFFF"
    var fontBody: String = "system"
    var fontTitle: String = "system"
    var fontCaption: String = "system"
    var fontWeight: FontWeightPref = .regular
    var textScale: Double = 1.0
    var reduceAnimations: Bool = false
    var panelStyle: PanelStyle = .glass
    var gridColumns: Int = 4
    var thumbAspect: ThumbAspect = .square
    var thumbFill: Bool = true
    var gridSpacing: Double = 2
    var groupMode: GroupMode = .month
    var sortAscending: Bool = false
    var showScreenshots: Bool = true
    var showVideos: Bool = true
    var showBadges: Bool = true
    var hiddenCollections: [String] = []
    var albumsAsList: Bool = false
    var albumSort: String = "name"
    var autoPlayLive: Bool = false
    var loopVideos: Bool = false
    var slideshowSeconds: Double = 3
    var hapticsEnabled: Bool = true
    var hapticsIntensity: HapticIntensity = .medium
    var glassLevel: GlassLevel = .medium
    var dockTabs: [String] = DockDefaults.tabs
    var dockSwipe: Bool = true
    var profileFirstName: String = ""
    var profileLastName: String = ""
    var profileContact: String = ""
    var backdropOpacity: Double = 0.6
    var assistantDismissed: [String] = []
    var allowGeocoding: Bool = false
    var intelligenceEnabled: Bool = false
    var intelligenceLimit: Int = 2000
    var searchHistoryEnabled: Bool = true
    var searchHistory: [String] = []
    var memoriesEnabled: Bool = true
    var memOnThisDay: Bool = true
    var memTrips: Bool = true
    var memFavorites: Bool = true
    var memPeriods: Bool = true
    var dismissedMemories: [String] = []
    var profileName: String = ""
    var appleUserID: String = ""
    var appleEmail: String = ""
    var appleName: String = ""
    // Verrouillage Face ID / Touch ID / code de l’iPhone
    var lockApp: Bool = false
    var lockHidden: Bool = false
    var lockPrivate: Bool = false
    var lockDelete: Bool = false
    var lockDelay: Int = 0
    // Galerie distincte (stockée dans l’app, hors photothèque iCloud)
    var privateEnabled: Bool = true

    /// Tout changement de ces champs impose de recharger la photothèque.
    var libraryKey: String { "\(sortAscending)-\(showScreenshots)-\(showVideos)" }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let key = "galerie.prefs.v1"
    @Published var prefs: Prefs {
        didSet {
            Haptics.enabled = prefs.hapticsEnabled
            Haptics.intensity = prefs.hapticsIntensity
            if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: Self.key) }
        }
    }

    init() {
        var p = Prefs()
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let baseData = try? JSONEncoder().encode(Prefs()),
           let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
           let saved = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            // Fusion : les clés absentes (nouvelle version) gardent leur valeur par défaut.
            let merged = base.merging(saved) { _, new in new }
            if let md = try? JSONSerialization.data(withJSONObject: merged),
               let dec = try? JSONDecoder().decode(Prefs.self, from: md) { p = dec }
        }
        prefs = p
        Haptics.enabled = p.hapticsEnabled
        Haptics.intensity = p.hapticsIntensity
    }

    var animationsOn: Bool { !(prefs.reduceAnimations || UIAccessibility.isReduceMotionEnabled) }
    func animate(_ body: () -> Void) {
        if animationsOn { withAnimation(.spring(duration: 0.35, bounce: 0.15)) { body() } } else { body() }
    }
    var spring: Animation? { animationsOn ? .spring(duration: 0.35, bounce: 0.15) : nil }
    func resetAll() { prefs = Prefs() }

    func addSearch(_ q: String) {
        guard prefs.searchHistoryEnabled else { return }
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        prefs.searchHistory.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        prefs.searchHistory.insert(t, at: 0)
        prefs.searchHistory = Array(prefs.searchHistory.prefix(12))
    }
}
