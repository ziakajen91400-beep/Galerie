import SwiftUI
import Photos

struct CollectionDef: Identifiable, Hashable {
    enum Source: Hashable { case filter(MediaFilter), smart(PHAssetCollectionSubtype), documents, qr }
    let id: String
    let title: String
    let icon: String
    let source: Source
    static func == (l: CollectionDef, r: CollectionDef) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [CollectionDef] = [
        .init(id: "favorites", title: "Favoris", icon: "heart.fill", source: .filter(.favorites)),
        .init(id: "recent", title: "Ajoutés récemment", icon: "clock.fill", source: .filter(.recent)),
        .init(id: "videos", title: "Vidéos", icon: "video.fill", source: .filter(.videos)),
        .init(id: "live", title: "Live Photos", icon: "livephoto", source: .filter(.live)),
        .init(id: "selfies", title: "Selfies", icon: "person.crop.square.fill", source: .filter(.selfies)),
        .init(id: "portraits", title: "Portraits", icon: "person.and.background.dotted", source: .filter(.portraits)),
        .init(id: "panoramas", title: "Panoramas", icon: "pano.fill", source: .filter(.panoramas)),
        .init(id: "slomo", title: "Ralentis", icon: "slowmo", source: .filter(.slomo)),
        .init(id: "bursts", title: "Rafales", icon: "square.stack.3d.down.right.fill", source: .filter(.bursts)),
        .init(id: "screenshots", title: "Captures d’écran", icon: "camera.viewfinder", source: .filter(.screenshots)),
        .init(id: "animated", title: "Animations", icon: "play.square.stack.fill", source: .smart(.smartAlbumAnimated)),
        .init(id: "hidden", title: "Masqués", icon: "eye.slash.fill", source: .smart(.smartAlbumAllHidden)),
        .init(id: "documents", title: "Documents et texte", icon: "doc.text.viewfinder", source: .documents),
        .init(id: "qr", title: "QR codes", icon: "qrcode", source: .qr),
    ]

    @MainActor func load(prefs: Prefs, index: IntelligenceIndex) -> AssetList {
        switch source {
        case .filter(let f): return LibraryQuery.assets(prefs: prefs, filter: f)
        case .smart(let s):
            guard let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: s, options: nil).firstObject else { return .empty }
            let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            o.includeHiddenAssets = (s == .smartAlbumAllHidden)
            return AssetList(PHAsset.fetchAssets(in: c, options: o))
        case .documents: return AssetList(AssetFetch.sorted(ids: index.documentIDs))
        case .qr: return AssetList(AssetFetch.sorted(ids: index.qrIDs))
        }
    }
}

struct AlbumInfo: Identifiable {
    var id: String { col.localIdentifier }
    let col: PHAssetCollection
    let count: Int
    let cover: PHAsset?
    let last: Date
}

struct CollectionsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var memories: MemoriesEngine
    @EnvironmentObject private var geo: GeoIndex
    @EnvironmentObject private var intelligence: IntelligenceIndex
    @Environment(\.pal) private var pal
    @State private var albums: [AlbumInfo] = []
    @State private var shared: [AlbumInfo] = []
    @State private var counts: [String: Int] = [:]
    @State private var showNew = false
    @State private var newName = ""
    @State private var renaming: PHAssetCollection?
    @State private var renameText = ""
    @State private var deleting: PHAssetCollection?

    private var prefs: Prefs { settings.prefs }
    private var visibleDefs: [CollectionDef] {
        CollectionDef.all.filter { d in
            if prefs.hiddenCollections.contains(d.id) { return false }
            if d.id == "documents" || d.id == "qr" { return !intelligence.entries.isEmpty }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !library.isAuthorized {
                        EmptyState(icon: "lock.shield", title: "Accès requis", message: "Autorise l’accès à ta photothèque pour voir tes collections.").frame(height: 360)
                    } else {
                        if prefs.memoriesEnabled && (!memories.memories.isEmpty || memories.loading) { memoriesSection }
                        albumsSection
                        if !shared.isEmpty { sharedSection }
                        categoriesSection
                        Text("« Supprimés récemment », les personnes, animaux et l’album partagé en famille ne sont pas accessibles aux apps tierces : iOS ne les expose pas via PhotoKit.").gFont(.small).foregroundStyle(pal.textSecondary).padding(.horizontal, 6)
                    }
                }.padding(14)
            }
            .themedScreen()
            .navigationTitle("Collections")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Haptics.shared.light(); showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nouvel album") } }
            .navigationDestination(for: CollectionDef.self) { d in CollectionDetail(def: d) }
            .navigationDestination(for: String.self) { id in
                if let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject { AlbumDetailView(collection: c) }
            }
            .navigationDestination(for: MemoryRef.self) { r in if let m = memories.memories.first(where: { $0.id == r.id }) { MemoryDetailView(memory: m) } }
            .alert("Nouvel album", isPresented: $showNew) {
                TextField("Nom", text: $newName)
                Button("Créer") { let n = newName.trimmingCharacters(in: .whitespaces); newName = ""; if !n.isEmpty { Task { _ = await MediaActions.createAlbum(named: n); await loadAlbums() } } }
                Button("Annuler", role: .cancel) {}
            }
            .alert("Renommer l’album", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nom", text: $renameText)
                Button("Renommer") { if let r = renaming { let n = renameText; Task { _ = await MediaActions.rename(r, to: n); await loadAlbums() } }; renaming = nil }
                Button("Annuler", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Supprimer cet album ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Supprimer l’album", role: .destructive) { if let d = deleting { Task { _ = await MediaActions.deleteAlbum(d); await loadAlbums() } }; deleting = nil }
                Button("Annuler", role: .cancel) { deleting = nil }
            } message: { Text("Seul l’album est supprimé : les photos restent dans ta photothèque.") }
        }
        .task(id: library.version) {
            guard library.isAuthorized else { return }
            await loadAlbums()
            await memories.refresh(prefs: prefs, geo: geo)
        }
        .task(id: geo.loaded) { if library.isAuthorized { await geo.ensureLoaded(); await memories.refresh(prefs: prefs, geo: geo, force: true) } }
        .onChange(of: prefs.memoriesEnabled) { _, _ in Task { await memories.refresh(prefs: prefs, geo: geo, force: true) } }
    }

    // MARK: Sections
    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Souvenirs")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(memories.memories) { m in
                        NavigationLink(value: MemoryRef(id: m.id)) { MemoryCard(memory: m) }.buttonStyle(PressableStyle())
                            .contextMenu { Button(role: .destructive) { settings.prefs.dismissedMemories.append(m.id); Task { await memories.refresh(prefs: settings.prefs, geo: geo, force: true) } } label: { Label("Ne plus afficher", systemImage: "eye.slash") } }
                    }
                    if memories.loading && memories.memories.isEmpty { ProgressView().frame(width: 80, height: 280) }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { SectionTitle(text: "Mes albums"); Spacer()
                Menu {
                    Picker("Trier", selection: $settings.prefs.albumSort) { Text("Nom").tag("name"); Text("Nombre de médias").tag("count"); Text("Récents").tag("recent") }
                    Toggle("Afficher en liste", isOn: $settings.prefs.albumsAsList)
                } label: { Image(systemName: "arrow.up.arrow.down.circle") }
            }
            if albums.isEmpty {
                GCard { Text("Aucun album pour l’instant. Touche + pour en créer un.").gFont(.caption).foregroundStyle(pal.textSecondary) }
            } else if prefs.albumsAsList {
                VStack(spacing: 8) { ForEach(sortedAlbums) { a in albumLink(a) { AlbumRow(info: a) } } }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(sortedAlbums) { a in albumLink(a) { AlbumTile(info: a) } }
                }
            }
        }
    }

    private var sharedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Albums partagés")
            VStack(spacing: 8) { ForEach(shared) { a in NavigationLink(value: a.col.localIdentifier) { AlbumRow(info: a) }.buttonStyle(PressableStyle()) } }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Catégories")
            VStack(spacing: 0) {
                let defs = visibleDefs
                ForEach(Array(defs.enumerated()), id: \.element.id) { i, d in
                    NavigationLink(value: d) {
                        HStack(spacing: 12) {
                            Image(systemName: d.icon).foregroundStyle(pal.accent).frame(width: 28)
                            Text(d.title).gFont(.body)
                            Spacer()
                            if let n = counts[d.id] { Text("\(n)").gFont(.caption).foregroundStyle(pal.textSecondary) }
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.textSecondary)
                        }.padding(.vertical, 12).padding(.horizontal, 14).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if i < defs.count - 1 { Divider2().padding(.leading, 54) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 0.5))
            if intelligence.entries.isEmpty { Text("« Documents » et « QR codes » apparaissent après l’analyse locale (Réglages › Confidentialité).").gFont(.small).foregroundStyle(pal.textSecondary).padding(.horizontal, 6) }
        }
    }

    private func albumLink<L: View>(_ a: AlbumInfo, @ViewBuilder label: () -> L) -> some View {
        NavigationLink(value: a.col.localIdentifier) { label() }.buttonStyle(PressableStyle())
            .contextMenu {
                Button { renameText = a.col.localizedTitle ?? ""; renaming = a.col } label: { Label("Renommer", systemImage: "pencil") }
                Button(role: .destructive) { deleting = a.col } label: { Label("Supprimer", systemImage: "trash") }
            }
    }

    private var sortedAlbums: [AlbumInfo] {
        switch prefs.albumSort {
        case "count": return albums.sorted { $0.count > $1.count }
        case "recent": return albums.sorted { $0.last > $1.last }
        default: return albums.sorted { ($0.col.localizedTitle ?? "").localizedCaseInsensitiveCompare($1.col.localizedTitle ?? "") == .orderedAscending }
        }
    }

    private func loadAlbums() async {
        let p = prefs
        let (a, s, c) = await Task.detached(priority: .userInitiated) { () -> ([AlbumInfo], [AlbumInfo], [String: Int]) in
            func info(_ c: PHAssetCollection) -> AlbumInfo {
                let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let r = PHAsset.fetchAssets(in: c, options: o)
                return AlbumInfo(col: c, count: r.count, cover: r.firstObject, last: r.firstObject?.creationDate ?? .distantPast)
            }
            var counts: [String: Int] = [:]
            for d in CollectionDef.all where d.source != .documents && d.source != .qr {
                switch d.source {
                case .filter(let f): counts[d.id] = LibraryQuery.assets(prefs: p, filter: f).count
                case .smart(let sub):
                    if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject {
                        let o = PHFetchOptions(); o.includeHiddenAssets = (sub == .smartAlbumAllHidden)
                        counts[d.id] = PHAsset.fetchAssets(in: c, options: o).count
                    }
                default: break
                }
            }
            return (Albums.userAlbums().map(info), Albums.sharedAlbums().map(info), counts)
        }.value
        albums = a; shared = s; counts = c
        counts["documents"] = intelligence.documentIDs.count; counts["qr"] = intelligence.qrIDs.count
    }
}

struct MemoryRef: Hashable { let id: String }

struct AlbumTile: View {
    let info: AlbumInfo
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                if let c = info.cover { AssetThumb(asset: c, size: CGSize(width: g.size.width, height: g.size.width)) }
                else { ZStack { pal.card; Image(systemName: "photo").foregroundStyle(pal.textSecondary) } }
            }
            .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(info.col.localizedTitle ?? "Sans titre").gFont(.body).lineLimit(1)
            Text("\(info.count)").gFont(.caption).foregroundStyle(pal.textSecondary)
        }
    }
}
struct AlbumRow: View {
    let info: AlbumInfo
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 12) {
            Group { if let c = info.cover { AssetThumb(asset: c, size: CGSize(width: 56, height: 56)) } else { pal.card } }
                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) { Text(info.col.localizedTitle ?? "Sans titre").gFont(.body); Text("\(info.count) média\(info.count > 1 ? "s" : "")").gFont(.caption).foregroundStyle(pal.textSecondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(pal.textSecondary)
        }.padding(10).background(RoundedRectangle(cornerRadius: 16).fill(pal.card))
    }
}

struct CollectionDetail: View {
    let def: CollectionDef
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var intelligence: IntelligenceIndex
    @State private var list: AssetList = .empty
    var body: some View {
        MediaGridView(list: list, token: "\(def.id)-\(library.version)-\(intelligence.entries.count)", prefix: "col", emptyIcon: def.icon, emptyTitle: "Aucun élément", emptyMessage: "Cette catégorie est vide pour l’instant.")
            .themedScreen().navigationTitle(def.title).navigationBarTitleDisplayMode(.inline)
            .task(id: library.version) { list = def.load(prefs: settings.prefs, index: intelligence) }
    }
}

struct AlbumDetailView: View {
    let collection: PHAssetCollection
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: PhotoLibraryModel
    @State private var list: AssetList = .empty
    var body: some View {
        MediaGridView(list: list, token: "alb-\(collection.localIdentifier)-\(library.version)", album: collection, prefix: "alb", emptyIcon: "rectangle.stack", emptyTitle: "Album vide", emptyMessage: "Ajoute des photos depuis la photothèque (Sélectionner › Ajouter à un album).")
            .themedScreen().navigationTitle(collection.localizedTitle ?? "Album").navigationBarTitleDisplayMode(.inline)
            .task(id: library.version) {
                let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: settings.prefs.sortAscending)]
                list = AssetList(PHAsset.fetchAssets(in: collection, options: o))
            }
    }
}
