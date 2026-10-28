import SwiftUI
import Photos

enum AppTab: String, CaseIterable, Identifiable {
    case collections, search, library, map, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .collections: return "Collections"; case .search: return "Recherche"; case .library: return "Photothèque"; case .map: return "Carte"; case .settings: return "Réglages" }
    }
    var icon: String {
        switch self { case .collections: return "square.stack.fill"; case .search: return "magnifyingglass"; case .library: return "photo.on.rectangle.angled"; case .map: return "map.fill"; case .settings: return "gearshape.fill" }
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
    @Published var loaded: Set<AppTab> = [.library]
    @Published var viewer: ViewerContext?
    @Published var tabBarHidden = false
    @Published var scrollToLatestTick = 0
    @Published var toast: String?

    func select(_ t: AppTab) {
        if t == tab { if t == .library { scrollToLatestTick += 1 }; return }
        loaded.insert(t); tab = t
    }
    func open(_ list: AssetList, at i: Int, prefix: String = "lib") { viewer = ViewerContext(list: list, start: i, prefix: prefix) }
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
                if app.loaded.contains(t) {
                    tabContent(t)
                        .opacity(app.tab == t ? 1 : 0)
                        .allowsHitTesting(app.tab == t)
                        .accessibilityHidden(app.tab != t)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !app.tabBarHidden { GalerieTabBar().transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(settings.spring, value: app.tabBarHidden)
        .environment(\.zoomNS, zoomNS)
        .fullScreenCover(item: $app.viewer) { ctx in
            ViewerView(context: ctx, ns: zoomNS)
        }
        .overlay(alignment: .top) {
            if let t = app.toast {
                Text(t).gFont(.caption).padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(Capsule()).padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
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
        }
    }
}

struct GalerieTabBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.pal) private var pal
    @Namespace private var indicator
    private let order: [AppTab] = [.collections, .search, .library, .map, .settings]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(order) { t in
                Button {
                    Haptics.shared.selection()
                    settings.animate { app.select(t) }
                } label: {
                    if t == .library { center(t) } else { regular(t) }
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(app.tab == t ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 34, style: .continuous), tint: pal.nav)
        .padding(.horizontal, 14).padding(.bottom, 4)
    }

    private func regular(_ t: AppTab) -> some View {
        let sel = app.tab == t
        return VStack(spacing: 3) {
            Image(systemName: t.icon).font(.system(size: 20, weight: .semibold))
                .symbolVariant(sel ? .fill : .none)
            Text(t.title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(sel ? pal.accent : pal.textSecondary)
        .frame(height: 48).frame(maxWidth: .infinity)
        .background {
            if sel { Capsule().fill(pal.accent.opacity(0.14)).matchedGeometryEffect(id: "sel", in: indicator).padding(.horizontal, 2) }
        }
    }

    private func center(_ t: AppTab) -> some View {
        let sel = app.tab == t
        return ZStack {
            Circle().fill(LinearGradient(colors: [pal.accent, pal.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 60, height: 60)
                .shadow(color: pal.accent.opacity(sel ? 0.5 : 0.25), radius: sel ? 10 : 4, y: 3)
            Image(systemName: "photo.fill.on.rectangle.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
        }
        .scaleEffect(sel ? 1.06 : 1)
        .offset(y: -6).frame(height: 48)
    }
}
