import SwiftUI
import LocalAuthentication

/// Verrouillage par Face ID (ou Touch ID, ou code de l’iPhone en repli).
/// Réellement appliqué par iOS : l’app ne stocke aucun secret.
@MainActor
final class AppLock: ObservableObject {
    enum Scope: String { case hidden, privateGallery, delete }

    @Published private(set) var locked: Bool
    @Published private(set) var shield = false
    @Published var lastError: String?
    @Published private(set) var backgroundTick = 0
    var covered: Bool { enabled && (locked || shield) }

    private(set) var enabled: Bool
    private var delay: Int
    private var backgroundedAt: Date?
    private var graceUntil: [String: Date] = [:]
    private var authenticating = false
    private var window: UIWindow?

    init() {
        var on = false, d = 0
        if let data = UserDefaults.standard.data(forKey: "galerie.prefs.v1"),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            on = o["lockApp"] as? Bool ?? false; d = o["lockDelay"] as? Int ?? 0
        }
        enabled = on; delay = d; locked = on
    }

    /// Nom de la méthode disponible, pour les textes de l’interface.
    static var methodName: String {
        let c = LAContext(); var e: NSError?
        _ = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
        switch c.biometryType { case .faceID: return "Face ID"; case .touchID: return "Touch ID"; default: return "le code de l’iPhone" }
    }
    static var canAuthenticate: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func configure(_ p: Prefs) {
        let was = enabled
        enabled = p.lockApp; delay = p.lockDelay
        if !enabled { locked = false; shield = false }
        else if !was { locked = false }   // activation depuis les réglages : l’utilisateur est déjà dedans
        syncWindow()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { backgroundTick += 1; graceUntil = [:] }
        guard enabled else { return }
        switch phase {
        case .inactive: shield = true
        case .background:
            shield = true; backgroundedAt = backgroundedAt ?? Date()
            graceUntil = [:]
        case .active:
            if let t = backgroundedAt, Date().timeIntervalSince(t) >= Double(delay) { locked = true }
            backgroundedAt = nil
            if locked { Task { await unlock() } } else { shield = false }
        @unknown default: break
        }
        syncWindow()
    }

    /// Demande l’authentification pour déverrouiller l’app.
    func unlock() async {
        guard locked else { shield = false; syncWindow(); return }
        if await authenticate(reason: "Déverrouiller Galerie") { locked = false; shield = false }
        syncWindow()
    }

    /// Autorise l’accès à une zone sensible (réglage correspondant actif) ; true si on peut continuer.
    func authorize(_ scope: Scope, prefs: Prefs, grace: TimeInterval = 120) async -> Bool {
        let needed: Bool
        switch scope {
        case .hidden: needed = prefs.lockHidden
        case .privateGallery: needed = prefs.lockPrivate
        case .delete: needed = prefs.lockDelete
        }
        guard needed else { return true }
        if scope != .delete, let u = graceUntil[scope.rawValue], u > Date() { return true }
        let reason: String
        switch scope {
        case .hidden: reason = "Afficher les photos masquées"
        case .privateGallery: reason = "Ouvrir la galerie distincte"
        case .delete: reason = "Confirmer la suppression"
        }
        let ok = await authenticate(reason: reason)
        if ok && scope != .delete { graceUntil[scope.rawValue] = Date().addingTimeInterval(grace) }
        return ok
    }

    private func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true; defer { authenticating = false }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Annuler"
        var err: NSError?
        // Si aucun code n’est défini sur l’iPhone, iOS ne peut rien vérifier : on n’enferme pas l’utilisateur dehors.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            lastError = "Aucun code ni Face ID configuré sur cet iPhone : le verrouillage ne peut pas être appliqué."
            return true
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return ok
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
            return false
        }
    }

    // MARK: Fenêtre de protection au-dessus de tout (feuilles, visionneuse, sélecteur d’apps)
    func syncWindow() {
        if covered {
            if window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                let host = UIHostingController(rootView: LockScreenView(lock: self))
                host.view.backgroundColor = .clear
                w.rootViewController = host
                window = w
            }
            window?.isHidden = false
        } else {
            window?.isHidden = true
        }
    }
}

struct LockScreenView: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Color(.systemBackground).opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 46, weight: .semibold)).foregroundStyle(.secondary)
                Text("Galerie verrouillée").font(.title2.weight(.semibold))
                if lock.locked {
                    Button { Task { await lock.unlock() } } label: {
                        Label("Déverrouiller avec \(AppLock.methodName)", systemImage: "faceid").font(.headline)
                            .padding(.horizontal, 22).frame(minHeight: 48)
                            .background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
                            .contentShape(Capsule())
                    }
                    if let e = lock.lastError { Text(e).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30) }
                }
            }
        }
    }
}

/// Protège un contenu sensible : demande l’authentification à l’ouverture et propose de réessayer.
struct LockedContent<Content: View>: View {
    let scope: AppLock.Scope
    let enabled: Bool
    let title: String
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    @State private var ok = false

    var body: some View {
        Group {
            if !enabled || ok { content() }
            else {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(pal.textSecondary)
                    Text(title).gFont(.headline)
                    Button { attempt() } label: {
                        Label("Déverrouiller avec \(AppLock.methodName)", systemImage: "faceid").gFont(.body)
                            .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(pal.accent.opacity(0.15)))
                            .contentShape(Capsule())
                    }.buttonStyle(PressableStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if enabled && !ok { attempt() } }
        .onChange(of: lock.locked) { _, v in if v { ok = false } }
        .onChange(of: lock.backgroundTick) { _, _ in ok = false }
    }
    private func attempt() { Task { if await lock.authorize(scope, prefs: settings.prefs) { ok = true } } }
}
