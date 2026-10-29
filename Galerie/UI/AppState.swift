import SwiftUI
import Photos

enum AppTab: String, CaseIterable, Identifiable {
    case collections, search, library, map, settings, assistant, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .collections: return "Collections"; case .search: return "Recherche"; case .library: return "Photothèque"
        case .map: return "Carte"; case .settings: return "Réglages"; case .assistant: return "Assistant"; case .profile: return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .collections: return "square.stack.fill"; case .search: return "magnifyingglass"; case .library: return "photo.on.rectangle.angled"
        case .map: return "map.fill"; case .settings: return "gearshape.fill"; case .assistant: return "sparkles"; case .profile: return "person.crop.circle.fill"
        }
    }
    /// Photothèque et Réglages ne peuvent pas être retirés de la barre : l’app resterait inaccessible.
    var isEssential: Bool { self == .library || self == .settings }
    /// Sections gardées en mémoire quand on les quitte (position, résultats). Les autres sont reconstruites à l’ouverture.
    var keepsState: Bool { self == .library || self == .map || self == .collections || self == .search }
    var subtitle: String {
        switch self {
        case .collections: return "Albums, catégories, souvenirs"; case .search: return "Date, lieu, texte, objets"
        case .library: return "Toute la photothèque"; case .map: return "Photos géolocalisées"
        case .settings: return "Apparence, haptique, confidentialité"; case .assistant: return "Suggestions locales"; case .profile: return "Photo, nom, compte"
        }
    }
}

struct ViewerContext: Identifiable {
    let id = UUID()
    let list: AssetList
    let start: Int
    var prefix: String = "lib"
}

@MainActor
final class AppState: ObservableObject {
    @Published var tab: AppTab = .library
    var loaded: Set<AppTab> = [.library]
    @Published var viewer: ViewerContext?
    @Published var tabBarHidden = false
    @Published var scrollToLatestTick = 0
    @Published var toast: String?

    func select(_ t: AppTab) {
        // Toujours fermer le clavier : un champ du ou des onglets précédents ne doit jamais le garder ouvert.
        Keyboard.dismiss()
        if t == tab { if t == .library { scrollToLatestTick += 1 }; return }
        loaded.insert(t); tab = t
    }
    /// Ouvre la visionneuse. Un second appel pendant qu’elle est ouverte (double appui, geste en double) est ignoré :
    /// sinon deux visionneuses s’empilent, avec des boutons en double et une flèche de retour qui « ne fait rien ».
    func open(_ list: AssetList, at i: Int, prefix: String = "lib") {
        guard viewer == nil, list.count > 0 else { return }
        Keyboard.dismiss()
        viewer = ViewerContext(list: list, start: min(max(i, 0), list.count - 1), prefix: prefix)
    }
    func closeViewer() { viewer = nil }
    func showToast(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 2_200_000_000); if toast == s { toast = nil } }
    }
}

private struct ZoomNSKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues { var zoomNS: Namespace.ID? { get { self[ZoomNSKey.self] } set { self[ZoomNSKey.self] = newValue } } }

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: PhotoLibraryModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var geo: GeoIndex
    @EnvironmentObject var memories: MemoriesEngine
    @EnvironmentObject var intelligence: IntelligenceIndex
    @Environment(\.pal) private var pal
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoomNS

    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            ForEach(AppTab.allCases) { t in
                // Les sections légères sont reconstruites à l’ouverture : une section masquée ne se redessine plus
                // à chaque changement d’état global (c’était une source de latence) et ne peut plus garder le clavier.
                if app.loaded.contains(t) && (t.keepsState || app.tab == t) {
                    let active = app.tab == t
                    tabContent(t)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                        .zIndex(active ? 1 : 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.tabBarHidden { GalerieTabBar().transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(settings.spring, value: app.tabBarHidden)
        .environment(\.zoomNS, zoomNS)
        .onChange(of: app.tab) { _, _ in Keyboard.dismiss() }
        .fullScreenCover(item: $app.viewer) { ctx in
            ViewerView(context: ctx, ns: zoomNS)
        }
        .overlay(alignment: .top) {
            if let t = app.toast {
                Text(t).gFont(.caption).padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(Capsule()).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
            }
        }
        .animation(settings.spring, value: app.toast)
        .task {
            library.configure(prefs: settings.prefs)
            await library.start()
        }
        .onChange(of: settings.prefs.libraryKey) { _, _ in library.configure(prefs: settings.prefs); library.reload() }
        .onChange(of: library.version) { _, _ in geo.invalidate(); memories.invalidate() }
        .onChange(of: scenePhase) { _, p in if p == .active { library.refreshAuthorization() } }
    }

    @ViewBuilder private func tabContent(_ t: AppTab) -> some View {
        switch t {
        case .collections: CollectionsView()
        case .search: SearchView()
        case .library: LibraryView()
        case .map: MapExplorerView()
        case .settings: SettingsView()
        case .assistant: AssistantView()
        case .profile: NavigationStack { ProfileView(embedded: true) }
        }
    }
}

