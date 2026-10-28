import SwiftUI
import Photos
import MapKit

struct GeoPoint: Identifiable, Equatable {
    let id: String
    let lat: Double
    let lon: Double
    let date: Date
    let kind: UInt8   // 0 photo, 1 vidéo, 2 live
    var year: Int { Calendar.current.component(.year, from: date) }
}

struct GeoCluster: Identifiable, Equatable {
    let id: String
    let lat: Double
    let lon: Double
    let count: Int
    let ids: [String]
    let repID: String
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    var spread: Double { max(maxLat - minLat, maxLon - minLon) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum Clusterer {
    /// Regroupe les points visibles dans une grille adaptée au niveau de zoom.
    static func cluster(points: [GeoPoint], region: MKCoordinateRegion, cellsAcross: Double = 6) -> (clusters: [GeoCluster], visible: [GeoPoint]) {
        let latSpan = max(region.span.latitudeDelta, 0.00001), lonSpan = max(region.span.longitudeDelta, 0.00001)
        let minLat = region.center.latitude - latSpan * 0.6, maxLat = region.center.latitude + latSpan * 0.6
        let minLon = region.center.longitude - lonSpan * 0.6, maxLon = region.center.longitude + lonSpan * 0.6
        let cellLat = latSpan / cellsAcross, cellLon = lonSpan / cellsAcross
        struct Acc { var sumLat = 0.0, sumLon = 0.0, n = 0, ids: [String] = [], rep: GeoPoint?, mnLat = 90.0, mxLat = -90.0, mnLon = 180.0, mxLon = -180.0 }
        var cells: [String: Acc] = [:]
        var visible: [GeoPoint] = []
        for p in points where p.lat >= minLat && p.lat <= maxLat && p.lon >= minLon && p.lon <= maxLon {
            visible.append(p)
            let key = "\(Int(floor(p.lat / cellLat)))_\(Int(floor(p.lon / cellLon)))"
            var a = cells[key] ?? Acc()
            a.sumLat += p.lat; a.sumLon += p.lon; a.n += 1; a.ids.append(p.id)
            a.mnLat = min(a.mnLat, p.lat); a.mxLat = max(a.mxLat, p.lat); a.mnLon = min(a.mnLon, p.lon); a.mxLon = max(a.mxLon, p.lon)
            if a.rep == nil || p.date > a.rep!.date { a.rep = p }
            cells[key] = a
        }
        let out = cells.map { k, a in
            GeoCluster(id: k, lat: a.sumLat / Double(a.n), lon: a.sumLon / Double(a.n), count: a.n, ids: a.ids, repID: a.rep!.id,
                       minLat: a.mnLat, maxLat: a.mxLat, minLon: a.mnLon, maxLon: a.mxLon)
        }.sorted { $0.count > $1.count }
        return (out, visible)
    }

    static func bounds(of pts: [GeoPoint], padding: Double = 1.3) -> MKCoordinateRegion? {
        guard let f = pts.first else { return nil }
        var mnLat = f.lat, mxLat = f.lat, mnLon = f.lon, mxLon = f.lon
        for p in pts { mnLat = min(mnLat, p.lat); mxLat = max(mxLat, p.lat); mnLon = min(mnLon, p.lon); mxLon = max(mxLon, p.lon) }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (mnLat + mxLat) / 2, longitude: (mnLon + mxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: max((mxLat - mnLat) * padding, 0.01), longitudeDelta: max((mxLon - mnLon) * padding, 0.01)))
    }
}

/// Index local des médias géolocalisés (coordonnées lues dans PhotoKit, jamais déduites ni envoyées).
@MainActor
final class GeoIndex: ObservableObject {
    @Published private(set) var points: [GeoPoint] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var scanned = 0
    private var task: Task<Void, Never>?

    func invalidate() { if loaded { loaded = false; Task { await ensureLoaded(force: true) } } }

    func ensureLoaded(force: Bool = false) async {
        guard force || (!loaded && !loading) else { return }
        task?.cancel()
        loading = true; scanned = 0
        let t = Task.detached(priority: .utility) { () -> [GeoPoint] in
            let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let r = PHAsset.fetchAssets(with: o)
            var out: [GeoPoint] = []
            out.reserveCapacity(r.count / 3)
            r.enumerateObjects { a, i, stop in
                if Task.isCancelled { stop.pointee = true; return }
                if a.hasValidLocation, let l = a.location, let d = a.creationDate {
                    out.append(GeoPoint(id: a.localIdentifier, lat: l.coordinate.latitude, lon: l.coordinate.longitude, date: d,
                                        kind: a.isVideo ? 1 : (a.isLive ? 2 : 0)))
                }
            }
            return out
        }
        let result = await t.value
        points = result; loaded = true; loading = false
    }
}

private struct MapFilter: Equatable {
    var year: Int? = nil
    var kind: UInt8? = nil          // nil = tout
    var albumID: String? = nil
}

struct GeoThumb: View {
    let id: String
    var size: CGFloat = 54
    @State private var asset: PHAsset?
    var body: some View {
        Group {
            if let asset { AssetThumb(asset: asset, size: CGSize(width: size, height: size)) } else { Color.gray.opacity(0.3) }
        }
        .frame(width: size, height: size)
        .onAppear { if asset == nil { asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject } }
    }
}

struct MapExplorerView: View {
    @EnvironmentObject private var geo: GeoIndex
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal

    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var clusters: [GeoCluster] = []
    @State private var visible: [GeoPoint] = []
    @State private var selected: GeoCluster?
    @State private var filter = MapFilter()
    @State private var albumIDs: Set<String> = []
    @State private var albums: [PHAssetCollection] = []
    @State private var panel: CGFloat = 0.28     // fraction de la hauteur
    @State private var dragStart: CGFloat?
    @State private var clusterTask: Task<Void, Never>?
    @State private var didFit = false

    private var filtered: [GeoPoint] {
        geo.points.filter { p in
            if let y = filter.year, p.year != y { return false }
            if let k = filter.kind, p.kind != k { return false }
            if filter.albumID != nil, !albumIDs.contains(p.id) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !library.isAuthorized {
                    EmptyState(icon: "lock.shield", title: "Accès requis", message: "Autorise l’accès à la photothèque pour voir tes photos sur la carte.")
                } else if geo.loaded && geo.points.isEmpty {
                    EmptyState(icon: "mappin.slash", title: "Aucune photo géolocalisée", message: "Aucun média de ta photothèque ne contient de coordonnées GPS. Active « Lieux » dans Réglages › Confidentialité › Service de localisation › Appareil photo pour que tes prochaines photos apparaissent ici.")
                } else {
                    mapContent
                }
            }
            .themedScreen()
            .navigationTitle("Carte").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { filterMenu } }
        }
        .task { await geo.ensureLoaded() }
        .onChange(of: geo.loaded) { _, l in if l { fitAll(); recompute() } }
        .onChange(of: filter) { _, _ in selected = nil; Task { await refreshAlbumIDs(); fitAll(); recompute() } }
    }

    private var mapContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    ForEach(clusters) { c in
                        MapKit.Annotation("", coordinate: c.coordinate, anchor: .center) {
                            ClusterMarker(cluster: c, isSelected: selected?.id == c.id)
                                .onTapGesture { tap(c) }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { ctx in region = ctx.region; recompute() }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        GlassIconButton(system: "globe.europe.africa", label: "Vue globale") { selected = nil; fitAll() }
                        GlassIconButton(system: "plus", label: "Zoomer") { zoom(0.5) }
                        GlassIconButton(system: "minus", label: "Dézoomer") { zoom(2) }
                    }.padding(12)
                }
                .overlay(alignment: .top) { if self.geo.loading { ProgressView("Lecture des lieux…").gFont(.caption).padding(10).glass(Capsule()).padding(.top, 8) } }

                panelView(height: geo.size.height)
            }
        }
    }

    // MARK: Panneau inférieur
    private func panelView(height: CGFloat) -> some View {
        let ids: [String] = selected?.ids ?? visible.map(\.id)
        let h = max(88, height * panel)
        return VStack(spacing: 0) {
            Capsule().fill(pal.textSecondary.opacity(0.5)).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 6)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected == nil ? "Dans cette zone" : "Ce lieu").gFont(.headline)
                    Text("\(ids.count) média\(ids.count > 1 ? "s" : "")").gFont(.caption).foregroundStyle(pal.textSecondary)
                }
                Spacer()
                if selected != nil { Button("Zone visible") { Haptics.shared.light(); selected = nil }.gFont(.caption) }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            if panel > 0.2 { PanelGrid(ids: ids) }
            Spacer(minLength: 0)
        }
        .frame(height: h)
        .frame(maxWidth: .infinity)
        .glass(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .gesture(DragGesture().onChanged { v in
            if dragStart == nil { dragStart = panel }
            panel = min(0.85, max(0.1, (dragStart ?? panel) - v.translation.height / height))
        }.onEnded { _ in
            dragStart = nil
            let snaps: [CGFloat] = [0.12, 0.3, 0.6, 0.85]
            let target = snaps.min { abs($0 - panel) < abs($1 - panel) } ?? 0.3
            Haptics.shared.light(); settings.animate { panel = target }
        })
    }

    // MARK: Logique
    private func tap(_ c: GeoCluster) {
        Haptics.shared.selection()
        if c.count == 1 { openViewer(ids: c.ids, startID: c.repID); return }
        settings.animate { selected = c; if panel < 0.3 { panel = 0.3 } }
        if c.spread > 0.0005 {
            let region = MKCoordinateRegion(center: c.coordinate, span: MKCoordinateSpan(latitudeDelta: max(c.spread * 1.8, 0.004), longitudeDelta: max(c.spread * 1.8, 0.004)))
            withAnimation(.easeInOut(duration: 0.5)) { position = .region(region) }
        }
    }

    private func openViewer(ids: [String], startID: String) {
        let assets = AssetFetch.sorted(ids: Array(ids.prefix(600)))
        guard !assets.isEmpty else { return }
        let i = assets.firstIndex { $0.localIdentifier == startID } ?? 0
        app.open(AssetList(assets), at: i, prefix: "map")
    }

    private func zoom(_ factor: Double) {
        guard let r = region else { return }
        Haptics.shared.selection()
        let n = MKCoordinateRegion(center: r.center, span: MKCoordinateSpan(latitudeDelta: min(170, r.span.latitudeDelta * factor), longitudeDelta: min(340, r.span.longitudeDelta * factor)))
        withAnimation(.easeInOut(duration: 0.35)) { position = .region(n) }
    }

    private func fitAll() {
        guard let r = Clusterer.bounds(of: filtered) else { return }
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(r) }
    }

    private func recompute() {
        guard let r = region else { return }
        let pts = filtered
        clusterTask?.cancel()
        clusterTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            let res = await Task.detached(priority: .userInitiated) { Clusterer.cluster(points: pts, region: r) }.value
            if Task.isCancelled { return }
            clusters = Array(res.clusters.prefix(80))
            visible = res.visible.sorted { $0.date > $1.date }
            if let s = selected, !clusters.contains(where: { $0.id == s.id }) { selected = nil }
        }
    }

    private func refreshAlbumIDs() async {
        guard let aid = filter.albumID, let col = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [aid], options: nil).firstObject else { albumIDs = []; return }
        var s = Set<String>()
        PHAsset.fetchAssets(in: col, options: nil).enumerateObjects { a, _, _ in s.insert(a.localIdentifier) }
        albumIDs = s
    }

    private var filterMenu: some View {
        let years = Array(Set(geo.points.map(\.year))).sorted(by: >)
        return Menu {
            Picker("Année", selection: $filter.year) {
                Text("Toutes les années").tag(Int?.none)
                ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            Picker("Type", selection: $filter.kind) {
                Text("Tout").tag(UInt8?.none); Text("Photos").tag(UInt8?.some(0)); Text("Vidéos").tag(UInt8?.some(1)); Text("Live Photos").tag(UInt8?.some(2))
            }
            Menu("Album") {
                Button("Tous") { filter.albumID = nil }
                ForEach(Albums.userAlbums(), id: \.localIdentifier) { c in Button(c.localizedTitle ?? "Album") { filter.albumID = c.localIdentifier } }
            }
            Button("Réinitialiser les filtres", role: .destructive) { filter = MapFilter() }
        } label: { Image(systemName: filter == MapFilter() ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
        .accessibilityLabel("Filtres de la carte")
    }
}

enum AssetFetch {
    static func sorted(ids: [String], ascending: Bool = false) -> [PHAsset] {
        var out: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in out.append(a) }
        return out.sorted { (ascending ? ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) : ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)) }
    }
}

struct ClusterMarker: View {
    let cluster: GeoCluster
    let isSelected: Bool
    @Environment(\.pal) private var pal
    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeoThumb(id: cluster.repID, size: cluster.count > 1 ? 58 : 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? pal.accent : .white, lineWidth: isSelected ? 3 : 2))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            if cluster.count > 1 {
                Text(cluster.count > 999 ? "999+" : "\(cluster.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(pal.accent)).offset(x: 8, y: -8)
            }
        }
        .accessibilityLabel(cluster.count > 1 ? "\(cluster.count) médias" : "1 média")
    }
}

struct PanelGrid: View {
    let ids: [String]
    @EnvironmentObject private var app: AppState
    @State private var assets: [PHAsset] = []
    var body: some View {
        GeometryReader { geo in
            let cell = floor((geo.size.width - 3) / 4)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 1), count: 4), spacing: 1) {
                    ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, a in
                        GridCell(asset: a, size: CGSize(width: cell, height: cell), fill: true, selecting: false, isSelected: false, showBadges: true)
                            .onTapGesture { Haptics.shared.light(); app.open(AssetList(assets), at: i, prefix: "map") }
                    }
                }
                if ids.count > assets.count { Text("+ \(ids.count - assets.count) autres : zoome pour les voir").font(.caption).padding() }
            }
        }
        .task(id: ids.count) {
            let list = Array(ids.prefix(400))
            assets = await Task.detached { AssetFetch.sorted(ids: list) }.value
        }
    }
}
