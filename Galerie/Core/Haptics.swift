import UIKit

/// Point d’entrée unique pour tous les retours haptiques de l’app.
/// Les réglages (activé, intensité) sont lus à chaque appel : ils s’appliquent immédiatement.
///
/// Intensité : iOS ne permet pas de régler librement chaque type de retour, mais
/// `UIImpactFeedbackGenerator` accepte une intensité (0…1) et plusieurs styles physiques
/// (léger, moyen, rigide). Les trois niveaux combinent donc style ET intensité, ce qui produit
/// une vibration réellement différente. Les retours « notification » (succès, erreur…) sont
/// des motifs système fixes : ils ne sont pas modulables.
@MainActor
final class Haptics {
    static let shared = Haptics()
    /// Mis à jour par AppSettings (persisté dans UserDefaults).
    nonisolated(unsafe) static var enabled: Bool = true
    nonisolated(unsafe) static var intensity: HapticIntensity = .medium

    private let selectionGen = UISelectionFeedbackGenerator()
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private let notifGen = UINotificationFeedbackGenerator()
    private var lastFire = Date.distantPast

    /// Évite les rafales (gestes répétés, défilement) : un retour au plus toutes les 55 ms.
    private func allowed(_ minGap: TimeInterval = 0.055) -> Bool {
        guard Haptics.enabled else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastFire) >= minGap else { return false }
        lastFire = now
        return true
    }

    /// Les trois niveaux : style de l’impact + intensité.
    private func fire(soft: (UIImpactFeedbackGenerator, CGFloat), medium: (UIImpactFeedbackGenerator, CGFloat), strong: (UIImpactFeedbackGenerator, CGFloat)) {
        let pick: (UIImpactFeedbackGenerator, CGFloat)
        switch Haptics.intensity {
        case .light: pick = soft
        case .medium: pick = medium
        case .strong: pick = strong
        }
        pick.0.impactOccurred(intensity: pick.1)
        pick.0.prepare()
    }

    /// Changement de sélection (onglets, puces, curseurs).
    func selection() {
        guard allowed() else { return }
        switch Haptics.intensity {
        case .light: selectionGen.selectionChanged(); selectionGen.prepare()
        case .medium: fire(soft: (lightGen, 0.6), medium: (lightGen, 0.85), strong: (mediumGen, 0.8))
        case .strong: fire(soft: (lightGen, 0.6), medium: (lightGen, 0.85), strong: (rigidGen, 0.9))
        }
    }
    /// Appui sur un bouton courant.
    func light() {
        guard allowed() else { return }
        fire(soft: (softGen, 0.6), medium: (lightGen, 0.9), strong: (mediumGen, 1.0))
    }
    /// Action marquante (ouverture, confirmation).
    func medium() {
        guard allowed() else { return }
        fire(soft: (lightGen, 0.8), medium: (mediumGen, 0.9), strong: (heavyGen, 1.0))
    }
    func rigid() {
        guard allowed() else { return }
        fire(soft: (lightGen, 0.9), medium: (rigidGen, 0.8), strong: (rigidGen, 1.0))
    }
    /// Appui sur un bouton de la barre de navigation : un cran plus net qu’un bouton courant.
    func dock() {
        guard allowed(0.04) else { return }
        fire(soft: (lightGen, 0.8), medium: (mediumGen, 0.75), strong: (rigidGen, 1.0))
    }
    func success() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.success) }
    func warning() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.warning) }
    func error() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.error) }

    /// Démonstration depuis les réglages (ignore le filtre anti-rafale).
    func preview() {
        guard Haptics.enabled else { return }
        lastFire = .distantPast
        _ = allowed(0)
        fire(soft: (softGen, 0.6), medium: (mediumGen, 0.9), strong: (heavyGen, 1.0))
    }
}
