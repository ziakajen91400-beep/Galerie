import SwiftUI
import UIKit

extension Notification.Name {
    /// Envoyée à chaque changement d’onglet / ouverture de la visionneuse : tout champ de texte doit lâcher le focus.
    static let galerieResignFocus = Notification.Name("galerie.resignFocus")
}

/// Fermeture explicite du clavier iOS.
/// `sendAction(resignFirstResponder)` retire le focus du champ réellement actif, quel qu’il soit
/// (SwiftUI ou UIKit), même si la vue qui le contient est masquée ou hors écran.
enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        NotificationCenter.default.post(name: .galerieResignFocus, object: nil)
    }
}
