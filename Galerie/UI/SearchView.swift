import SwiftUI
import Photos
import MapKit

struct SearchSpec: Equatable {
    var text = ""
    var from: Date?
    var to: Date?
    var kind: MediaFilter = .all
    var favoritesOnly = false
    var hasLocation = false
    var albumID: String?
    var filenames = false
    var placeLat: Double?
    var placeLon: Double?
    var placeKm: Double = 30
    var placeName: String?
}

enum SearchParser {
    static let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    /// Extrait année / mois / mots-clés de type depuis la saisie ; le reste est le texte libre.
    static func parse(_ raw: String, into spec: SearchSpec, cal: Calendar = .current) -> SearchSpec {
        var s = spec
        var rest: [String] = []
        var year: Int?, month: Int?
        for w in raw.split(separator: " ").map(String.init) {
            let l = w.lowercased()
            if let y = Int(l), (1990...2100).contains(y) { year = y }
            else if let m = months.firstIndex(where: { $0.folding(options: .diacriticInsensitive, locale: nil) == l.folding(options: .diacriticInsensitive, locale: nil) }) { month = m + 1 }
            else if ["vidéo", "vidéos", "video", "videos"].contains(l) { s.kind = .videos }
            else if ["photo", "photos"].contains(l) { s.kind = .photos }
            else if ["favori", "favoris"].contains(l) { s.favoritesOnly = true }
            else if ["capture", "captures"].contains(l) { s.kind = .screenshots }
            else if l == "live" { s.kind = .live }
            else { rest.append(w) }
        }
        s.text = rest.joined(separator: " ")
        if year != nil || month != nil {
            let y = year ?? cal.component(.year, from: Date())
            var c = DateComponents(); c.year = y; c.month = month ?? 1; c.day = 1
            if let start = cal.date(from: c) {
                s.from = start
                s.to = cal.date(byAdding: month != nil ? .month : .year, value: 1, to: start)
            }
        }
        return s
    }
}

enum SearchEngine {
    static func run(spec: SearchSpec, meta: [String: LocalMeta], vision: Set<String>, geo: [GeoPoint], prefs: Prefs) -> [PHAsset] {
        var candidates: Set<String>?
        let q = spec.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if !q.isEmpty && !spec.filenames {
            var ids = vision
            for (id, m) in meta {
                let hay = ([m.caption, m.note] + m.keywords).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if hay.contains(q) { ids.insert(id) }
            }
            candidates = ids
        }
        if let lat = spec.placeLat, let lon = spec.placeLon {
            let near = Set(geo.filter { MemoryMath.distanceKm((lat, lon), ($0.lat, $0.lon)) <= spec.placeKm }.map(\.id))
            candidates = candidates.map { $0.intersection(near) } ?? near
        }
        if let aid = spec.albumID, let col = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [aid], options: nil).firstObject {
            var s = Set<String>(); PHAsset.fetchAssets(in: col, options: nil).enumerateObjects { a, _, _ in s.insert(a.localIdentifier) }
            candidates = candidates.map { $0.intersection(s) } ?? s
        }
        var out: [PHAsset] = []
        func passes(_ a: PHAsset) -> Bool {
            if let f = spec.from, let d = a.creationDate, d < f { return false }
            if let t = spec.to, let d = a.creationDate, d >= t { return false }
            if spec.favoritesOnly && !a.isFavorite { return false }
            if spec.hasLocation && !a.hasValidLocation { return false }
            switch spec.kind {
            case .photos: if a.isVideo { return false }
            case .videos: if !a.isVideo { return false }
            case .live: if !a.isLive { return false }
            case .screenshots: if !a.isScreenshot { return false }
            default: break
            }
            return true
        }
        if let c = candidates {
            if c.isEmpty { return [] }
            PHAsset.fetchAssets(withLocalIdentifiers: Array(c), options: nil).enumerateObjects { a, _, _ in if passes(a) { out.append(a) } }
        } else {
            let o = LibraryQuery.options(prefs: prefs, filter: [.photos, .videos, .live, .screenshots].contains(spec.kind) ? spec.kind : .all, applyPrefs: false)
            var preds: [NSPredicate] = []
            if let p = o.predicate { preds.append(p) }
            if let f = spec.from { preds.append(NSPredicate(format: "creationDate >= %@", f as NSDate)) }
            if let t = spec.to { preds.append(NSPredicate(format: "creationDate < %@", t as NSDate)) }
            if spec.favoritesOnly { preds.append(NSPredicate(format: "favorite == YES")) }
            o.predicate = preds.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: preds)
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            PHAsset.fetchAssets(with: o).enumerateObjects { a, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                if spec.hasLocation && !a.hasValidLocation { return }
                if spec.filenames && !q.isEmpty && !a.originalFilename.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) { return }
                if let c = candidates, !c.contains(a.localIdentifier) { return }
                out.append(a)
            }
        }
        return out.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }
}

struct SearchView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var intelligence: IntelligenceIndex
    @EnvironmentObject private var geo: GeoIndex
    @Environment(\.pal) private var pal
    @State private var query = ""
    @State private var spec = SearchSpec()
    @State private var results: [PHAsset] = []
    @State private var searching = false
    @State private var task: Task<Void, Never>?
    @State private var placeError: String?
    @State private var hasSearched = false
    @FocusState private var focused: Bool

    private var active: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || spec != SearchSpec() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                filterBar
                if !library.isAuthorized {
                    EmptyState(icon: "lock.shield", title: "Accès requis", message: "Autorise l’accès à ta photothèque pour pouvoir chercher.")
                } else if !active {
                    suggestions
                } else if searching && results.isEmpty {
                    ProgressView("Recherche…").frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack { Text("\(results.count) résultat\(results.count > 1 ? "s" : "")").gFont(.caption).foregroundStyle(pal.textSecondary); Spacer() }.padding(.horizontal, 16).padding(.bottom, 4)
                        MediaGridView(list: AssetList(results), token: "search-\(results.count)-\(results.first?.localIdentifier ?? "")", prefix: "sea", emptyIcon: "magnifyingglass", emptyTitle: "Aucun résultat", emptyMessage: "Essaie d’autres mots, une année (« 2024 »), un mois, ou active l’analyse locale dans Réglages pour chercher dans le texte et les objets des images.")
                    }
                }
            }
            .themedScreen().navigationTitle("Recherche").navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: query) { _, _ in schedule() }
        .onChange(of: spec) { _, _ in schedule() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(pal.textSecondary)
            TextField("Date, lieu, légende, texte, objet…", text: $query).focused($focused).gFont(.body).submitLabel(.search)
                .onSubmit { settings.addSearch(query) }.autocorrectionDisabled()
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(pal.textSecondary) }.accessibilityLabel("Effacer") }
        }
        .padding(12).glass(RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.horizontal, 14).padding(.top, 6)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Toute période") { spec.from = nil; spec.to = nil }
                    Button("Cette semaine") { setRange(.weekOfYear) }
                    Button("Ce mois-ci") { setRange(.month) }
                    Button("Cette année") { setRange(.year) }
                    Menu("Année") { ForEach((0..<15).map { Calendar.current.component(.year, from: Date()) - $0 }, id: \.self) { y in Button(String(y)) { setYear(y) } } }
                } label: { chipLabel(spec.from == nil ? "Période" : "Période ✓", "calendar", spec.from != nil) }
                Menu {
                    ForEach([MediaFilter.all, .photos, .videos, .live, .screenshots]) { f in Button(f.label) { spec.kind = f } }
                } label: { chipLabel(spec.kind == .all ? "Type" : spec.kind.label, "photo.on.rectangle", spec.kind != .all) }
                Chip(title: "Favoris", icon: "heart", selected: spec.favoritesOnly) { spec.favoritesOnly.toggle() }
                Chip(title: "Avec lieu", icon: "mappin", selected: spec.hasLocation) { spec.hasLocation.toggle() }
                Menu {
                    Button("Tous") { spec.albumID = nil }
                    ForEach(Albums.userAlbums(), id: \.localIdentifier) { c in Button(c.localizedTitle ?? "Album") { spec.albumID = c.localIdentifier } }
                } label: { chipLabel(spec.albumID == nil ? "Album" : "Album ✓", "rectangle.stack", spec.albumID != nil) }
                Chip(title: "Noms de fichiers", icon: "doc", selected: spec.filenames) { spec.filenames.toggle() }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Chip(title: "Lieu : \(query)", icon: "mappin.and.ellipse", selected: false) { Task { await searchPlace() } }
                }
                if let n = spec.placeName { Chip(title: "📍 \(n) ✕", selected: true) { spec.placeLat = nil; spec.placeLon = nil; spec.placeName = nil } }
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func chipLabel(_ t: String, _ icon: String, _ sel: Bool) -> some View {
        HStack(spacing: 5) { Image(systemName: icon).font(.system(size: 12, weight: .semibold)); Text(t).gFont(.caption) }
            .padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(sel ? Color.white : pal.text)
            .background(Capsule().fill(sel ? pal.accent : pal.card)).overlay(Capsule().stroke(pal.border, lineWidth: sel ? 0 : 0.5))
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if settings.prefs.searchHistoryEnabled && !settings.prefs.searchHistory.isEmpty {
                    HStack { SectionTitle(text: "Recherches récentes"); Spacer(); Button("Effacer") { settings.prefs.searchHistory = [] }.gFont(.small) }
                    FlowChips(items: settings.prefs.searchHistory) { query = $0 }
                }
                SectionTitle(text: "Essaie")
                FlowChips(items: ["vidéos 2024", "favoris", "captures", "août", "chat", "plage", "QR"]) { query = $0 }
                GCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comment ça marche").gFont(.headline)
                        Text("Tape une année, un mois, « vidéos », « favoris »… Les légendes et mots-clés ajoutés dans Galerie sont indexés. Le texte visible et les objets des images sont trouvés après l’analyse locale (Réglages › Confidentialité). Ce n’est pas la recherche sémantique privée d’Apple Photos.").gFont(.caption).foregroundStyle(pal.textSecondary)
                    }
                }
            }.padding(14)
        }
    }

    /// Recherche de lieu à la demande de l’utilisateur : le texte saisi est envoyé au service de cartes d’Apple (pas les photos).
    private func searchPlace() async {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = query
        do {
            let resp = try await MKLocalSearch(request: r).start()
            if let item = resp.mapItems.first {
                let c = item.placemark.coordinate
                spec.placeLat = c.latitude; spec.placeLon = c.longitude; spec.placeName = item.name ?? query
                query = ""
                await geo.ensureLoaded()
                Haptics.shared.success()
            } else { Haptics.shared.warning() }
        } catch { Haptics.shared.error() }
    }

    private func setRange(_ comp: Calendar.Component) {
        let cal = Calendar.current
        if let i = cal.dateInterval(of: comp, for: Date()) { spec.from = i.start; spec.to = i.end }
    }
    private func setYear(_ y: Int) {
        var c = DateComponents(); c.year = y; c.month = 1; c.day = 1
        if let s = Calendar.current.date(from: c) { spec.from = s; spec.to = Calendar.current.date(byAdding: .year, value: 1, to: s) }
    }

    private func schedule() {
        task?.cancel()
        guard active, library.isAuthorized else { results = []; return }
        let q = query.trimmingCharacters(in: .whitespaces)
        var s = SearchParser.parse(q, into: SearchSpec(from: spec.from, to: spec.to, kind: spec.kind, favoritesOnly: spec.favoritesOnly, hasLocation: spec.hasLocation, albumID: spec.albumID, filenames: spec.filenames, placeLat: spec.placeLat, placeLon: spec.placeLon, placeName: spec.placeName))
        s.placeKm = spec.placeKm
        let meta = MetadataStore.shared.items
        let vision = intelligence.match(s.text)
        let pts = geo.points
        let prefs = settings.prefs
        searching = true
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            if s.placeLat != nil { await geo.ensureLoaded() }
            let r = await Task.detached(priority: .userInitiated) { SearchEngine.run(spec: s, meta: meta, vision: vision, geo: pts, prefs: prefs) }.value
            if Task.isCancelled { return }
            results = r; searching = false
        }
    }
}

struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack { ForEach(items, id: \.self) { i in Chip(title: i, selected: false) { tap(i) } } }
        }
    }
}
