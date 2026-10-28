import UIKit

/// Point d’entrée unique pour tous les retours haptiques de l’app.
/// Le réglage « Retour haptique » est lu à chaque appel : il s’applique immédiatement.
@MainActor
final class Haptics {
    static let shared = Haptics()
    /// Mis à jour par AppSettings (persisté dans UserDefaults).
    nonisolated(unsafe) static var enabled: Bool = true

    private let selectionGen = UISelectionFeedbackGenerator()
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let notifGen = UINotificationFeedbackGenerator()

    func selection() { guard Haptics.enabled else { return }; selectionGen.selectionChanged(); selectionGen.prepare() }
    func light() { guard Haptics.enabled else { return }; lightGen.impactOccurred(); lightGen.prepare() }
    func medium() { guard Haptics.enabled else { return }; mediumGen.impactOccurred(); mediumGen.prepare() }
    func rigid() { guard Haptics.enabled else { return }; rigidGen.impactOccurred(); rigidGen.prepare() }
    func success() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.success) }
    func warning() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.warning) }
    func error() { guard Haptics.enabled else { return }; notifGen.notificationOccurred(.error) }
}
