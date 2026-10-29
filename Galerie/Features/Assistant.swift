import SwiftUI
import Photos

/// Assistant de la galerie : suggestions calculées LOCALEMENT à partir des dates, lieux, favoris et types de médias
/// déjà lus par PhotoKit. Ce n’est pas une IA générative : aucun modèle distant, aucune photo envoyée, aucun suivi.
struct AssistantSuggestion: Identifiable {
    enum Kind { case favorites, wallpapers, trip, place, month, live }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let assets: [PHAsset]
    /// Nom proposé si la suggestion peut devenir un album.
    var albumName: String?
    var icon: String {
        switch kind {
        case .favorites: return "heart.fill"; case .wallpapers: return "iphone"; case .trip: return "airplane"
        case .place: return "mappin.and.ellipse"; case .month: return "calendar"; case .live: return "livephoto"
        }
    }
}

@MainActor
final class AssistantEngine: ObservableObject {
    @Published private(set) var suggestions: [AssistantSuggestion] = []
    @Published private(set) var loading = false
    @Published private(set) var computed = false

    func refresh(geo: GeoIndex, force: Bool = false) async {
        if computed && !force { return }
        loading = true
        await geo.ensureLoaded()
        let pts = geo.points
        let out: [AssistantSuggestion] = await Task.detached(priority: .userInitiated) { Self.compute(points: pts) }.value
        suggestions = out
        computed = true; loading = false
    }
    func invalidate() { computed = false }
    func remove(_ id: String) { suggestions.removeAll { $0.id == id } }

    nonisolated static func compute(points: [GeoPoint]) -> [AssistantSuggestion] {
        var out: [AssistantSuggestion] = []
        let cal = Calendar.current

        // 1. Photos mises en avant : les favoris (seul critère réellement connu de l’app).
        let fo = PHFetchOptions(); fo.predicate = NSPredicate(format: "favorite == YES AND mediaType == %d", PHAssetMediaType.image.rawValue)
        fo.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fo.fetchLimit = 60
        let fav = PHAsset.fetchAssets(with: fo)
        if fav.count >= 3 {
            var a: [PHAsset] = []; fav.enumerateObjects { x, _, _ in a.append(x) }
            out.append(AssistantSuggestion(id: "fav", kind: .favorites, title: "Tes photos mises en avant",
                                           detail: "\(a.count) favoris récents. Une base pour un album « Les plus belles ».", assets: a, albumName: "Mes favoris du moment"))
        }

        // 2. Fonds d’écran : photos portrait, haute résolution, hors captures d’écran.
        let po = PHFetchOptions(); po.predicate = NSPredicate(format: "mediaType == %d AND pixelHeight >= 2000 AND pixelHeight > pixelWidth", PHAssetMediaType.image.rawValue)
        po.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        po.fetchLimit = 400
        var walls: [PHAsset] = []
        PHAsset.fetchAssets(with: po).enumerateObjects { a, _, _ in
            let r = Double(a.pixelHeight) / Double(max(a.pixelWidth, 1))
            if r >= 1.3 && r <= 2.4 && !a.isScreenshot { walls.append(a) }
        }
        walls.sort { ($0.isFavorite ? 1 : 0, $0.creationDate ?? .distantPast) > ($1.isFavorite ? 1 : 0, $1.creationDate ?? .distantPast) }
        if walls.count >= 3 {
            out.append(AssistantSuggestion(id: "wall", kind: .wallpapers, title: "Idées de fonds d’écran",
                                           detail: "Photos verticales en haute résolution. iOS n’autorise pas une app à changer le fond d’écran : ouvre la photo, appuie sur Partager puis « Utiliser comme fond d’écran ».",
                                           assets: Array(walls.prefix(40))))
        }

        // 3. Voyages détectés (séries de photos géolocalisées loin de chez toi).
        for t in MemoryMath.trips(points: points).sorted(by: { $0.first!.date > $1.first!.date }).prefix(3) {
            guard let f = t.first?.date, let l = t.last?.date else { continue }
            let assets = AssetFetch.sorted(ids: Array(t.map(\.id).prefix(400)), ascending: true)
            guard assets.count >= 8 else { continue }
            let label = Fmt.range(f, l)
            out.append(AssistantSuggestion(id: "trip-\(Int(f.timeIntervalSince1970))", kind: .trip, title: "Voyage · \(label)",
                                           detail: "\(t.count) médias géolocalisés regroupés. Idéal pour un album.", assets: assets, albumName: "Voyage \(label)"))
        }

        // 4. Photos prises au même endroit (cases d’environ 5 km, au moins 15 médias).
        var cells: [String: [GeoPoint]] = [:]
        for p in points { cells["\(Int((p.lat / 0.05).rounded(.down)))_\(Int((p.lon / 0.05).rounded(.down)))", default: []].append(p) }
        let tripIDs = Set(out.filter { $0.kind == .trip }.flatMap { $0.assets.map(\.localIdentifier) })
        for (k, v) in cells.sorted(by: { $0.value.count > $1.value.count }).prefix(6) where v.count >= 15 {
            let fresh = v.filter { !tripIDs.contains($0.id) }
            guard fresh.count >= 15 else { continue }
            let dates = fresh.map(\.date)
            guard let f = dates.min(), let l = dates.max() else { continue }
            let assets = AssetFetch.sorted(ids: Array(fresh.map(\.id).prefix(400)), ascending: true)
            out.append(AssistantSuggestion(id: "place-\(k)", kind: .place, title: "Même lieu · \(fresh.count) médias",
                                           detail: "Pris au même endroit entre \(f.formatted(.dateTime.month(.abbreviated).year())) et \(l.formatted(.dateTime.month(.abbreviated).year())).",
                                           assets: assets, albumName: "Lieu \(f.formatted(.dateTime.month(.wide).year()))"))
            if out.filter({ $0.kind == .place }).count >= 3 { break }
        }

        // 5. Mois chargés (au moins 40 médias) : collections à créer.
        let all = PHAsset.fetchAssets(with: nil)
        var buckets: [DateComponents: [PHAsset]] = [:]
        all.enumerateObjects { a, _, _ in
            if let d = a.creationDate { buckets[cal.dateComponents([.year, .month], from: d), default: []].append(a) }
        }
        for (k, v) in buckets.sorted(by: { $0.value.count > $1.value.count }).prefix(2) where v.count >= 40 {
            guard let d = cal.date(from: k) else { continue }
            let name = d.formatted(.dateTime.month(.wide).year())
            out.append(AssistantSuggestion(id: "month-\(k.year ?? 0)-\(k.month ?? 0)", kind: .month, title: "Un mois à garder : \(name)",
                                           detail: "\(v.count) médias : un de tes mois les plus remplis.",
                                           assets: v.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }, albumName: name.prefix(1).uppercased() + name.dropFirst()))
        }

        // 6. Live Photos à revoir.
        let lo = PHFetchOptions(); lo.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)
        lo.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; lo.fetchLimit = 60
        let live = PHAsset.fetchAssets(with: lo)
        if live.count >= 3 {
            var a: [PHAsset] = []; live.enumerateObjects { x, _, _ in a.append(x) }
            out.append(AssistantSuggestion(id: "live", kind: .live, title: "Live Photos à revoir",
                                           detail: "Maintiens ton doigt sur une Live Photo pour la lire.", assets: a, albumName: "Live Photos récentes"))
        }
        return out
    }
}

struct AssistantView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var geo: GeoIndex
    @EnvironmentObject private var app: AppState
    @StateObject private var engine = AssistantEngine()
    @Environment(\.pal) private var pal
    @State private var busyID: String?
    @State private var dest: AssistantDest?

    private var visible: [AssistantSuggestion] { engine.suggestions.filter { !settings.prefs.assistantDismissed.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    if !library.isAuthorized {
                        EmptyState(icon: "lock.shield", title: "Accès requis", message: "Autorise l’accès à ta photothèque pour recevoir des suggestions.").frame(height: 260)
                    } else if engine.loading && visible.isEmpty {
                        HStack { Spacer(); ProgressView("Analyse des dates et des lieux…").gFont(.caption); Spacer() }.padding(.vertical, 30)
                    } else if visible.isEmpty {
                        GCard { Text("Rien à suggérer pour l’instant. Ajoute des favoris ou prends des photos géolocalisées : l’assistant s’appuie sur ces informations.").gFont(.caption).foregroundStyle(pal.textSecondary) }
                    }
                    ForEach(visible) { s in card(s) }
                    shortcuts
                }.padding(14)
            }
            .themedScreen().navigationTitle("Assistant").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.shared.light(); Task { await engine.refresh(geo: geo, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualiser les suggestions")
                }
            }
            .navigationDestination(item: $dest) { d in
                switch d { case .theme: ThemePickerView(); case .dock: DockSettingsView(); case .icon: IconPickerView() }
            }
            .task { if library.isAuthorized { await engine.refresh(geo: geo) } }
            .onChange(of: library.version) { _, _ in engine.invalidate() }
        }
    }

    private var intro: some View {
        GCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Suggestions locales", systemImage: "sparkles").gFont(.headline)
                Text("Calculées sur ton iPhone à partir des dates, des lieux, des favoris et des types de médias. Aucune photo n’est envoyée, aucune publicité, aucun suivi. Ce n’est pas une IA générative : ce sont des regroupements et des tris, présentés comme tels.").gFont(.caption).foregroundStyle(pal.textSecondary)
            }
        }
    }

    private func card(_ s: AssistantSuggestion) -> some View {
        GCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: s.icon).foregroundStyle(pal.accent).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).gFont(.headline)
                        Text(s.detail).gFont(.caption).foregroundStyle(pal.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button { Haptics.shared.light(); settings.animate { settings.prefs.assistantDismissed.append(s.id) } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(pal.textSecondary).frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Masquer cette suggestion")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(s.assets.prefix(8).enumerated()), id: \.element.localIdentifier) { _, a in
                            AssetThumb(asset: a, size: CGSize(width: 64, height: 64)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                HStack(spacing: 10) {
                    NavigationLink { SuggestionDetail(suggestion: s) } label: {
                        Text("Voir (\(s.assets.count))").gFont(.caption).fontWeight(.semibold).padding(.horizontal, 14).frame(minHeight: 38)
                            .background(Capsule().fill(pal.accent.opacity(0.14))).foregroundStyle(pal.accent).contentShape(Capsule())
                    }.buttonStyle(.plain)
                    if let name = s.albumName {
                        Button { create(s, name: name) } label: {
                            HStack(spacing: 4) { if busyID == s.id { ProgressView().controlSize(.small) }; Text("Créer l’album").gFont(.caption).fontWeight(.semibold) }
                                .padding(.horizontal, 14).frame(minHeight: 38).background(Capsule().fill(pal.accent)).foregroundStyle(.white).contentShape(Capsule())
                        }.buttonStyle(PressableStyle()).disabled(busyID != nil)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func create(_ s: AssistantSuggestion, name: String) {
        busyID = s.id
        Task {
            let ok = await MediaActions.createAlbum(named: name, with: s.assets)
            busyID = nil
            app.showToast(ok ? "Album « \(name) » créé" : "Création de l’album impossible")
            if ok { settings.prefs.assistantDismissed.append(s.id) }
        }
    }

    /// Raccourcis vers de vrais écrans : retrouver des photos et personnaliser la galerie.
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Retrouver et personnaliser")
            GCard(padding: 0) {
                VStack(spacing: 0) {
                    row("magnifyingglass", "Retrouver une photo", "Date, lieu, légende, texte, objets") { app.select(.search) }
                    Divider2().padding(.leading, 14)
                    row("paintpalette", "Thèmes", "Palettes, fonds, aperçu") { nav(.theme) }
                    Divider2().padding(.leading, 14)
                    row("dock.rectangle", "Barre de navigation", "Ordre et onglets") { nav(.dock) }
                    Divider2().padding(.leading, 14)
                    row("app.badge", "Icône de l’app", "Icônes alternatives") { nav(.icon) }
                }
            }
        }
    }

    private func nav(_ d: AssistantDest) { Haptics.shared.light(); dest = d }

    private func row(_ icon: String, _ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.shared.light(); action() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(pal.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) { Text(title).gFont(.body); Text(sub).gFont(.small).foregroundStyle(pal.textSecondary) }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.textSecondary)
            }.padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

enum AssistantDest: Int, Identifiable {
    case theme, dock, icon
    var id: Int { rawValue }
}

struct SuggestionDetail: View {
    let suggestion: AssistantSuggestion
    var body: some View {
        MediaGridView(list: AssetList(suggestion.assets), token: "ast-\(suggestion.id)-\(suggestion.assets.count)", prefix: "ast",
                      emptyIcon: "sparkles", emptyTitle: "Aucun média", emptyMessage: "")
            .themedScreen().navigationTitle(suggestion.title).navigationBarTitleDisplayMode(.inline)
    }
}
