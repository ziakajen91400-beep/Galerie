import SwiftUI
import Photos

/// Liste d’assets : soit un PHFetchResult (paresseux, adapté aux dizaines de milliers d’éléments), soit un tableau.
struct AssetList {
    private enum Storage { case fetch(PHFetchResult<PHAsset>), array([PHAsset]) }
    private let storage: Storage
    static let empty = AssetList([PHAsset]())
    init(_ r: PHFetchResult<PHAsset>) { storage = .fetch(r) }
    init(_ a: [PHAsset]) { storage = .array(a) }
    var count: Int { switch storage { case .fetch(let r): return r.count; case .array(let a): return a.count } }
    var isEmpty: Bool { count == 0 }
    subscript(i: Int) -> PHAsset {
        switch storage { case .fetch(let r): return r.object(at: i); case .array(let a): return a[i] }
    }
    var fetchResult: PHFetchResult<PHAsset>? { if case .fetch(let r) = storage { return r }; return nil }
    func array(limit: Int = .max) -> [PHAsset] { (0..<min(count, limit)).map { self[$0] } }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all, photos, videos, live, favorites, screenshots, selfies, portraits, panoramas, slomo, bursts, notInAlbum, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tout"; case .photos: return "Photos"; case .videos: return "Vidéos"; case .live: return "Live Photos"
        case .favorites: return "Favoris"; case .screenshots: return "Captures d’écran"; case .selfies: return "Selfies"
        case .portraits: return "Portraits"; case .panoramas: return "Panoramas"; case .slomo: return "Ralentis"
        case .bursts: return "Rafales"; case .notInAlbum: return "Hors album"; case .recent: return "Ajoutés récemment"
        }
    }
    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"; case .photos: return "photo"; case .videos: return "video"; case .live: return "livephoto"
        case .favorites: return "heart"; case .screenshots: return "camera.viewfinder"; case .selfies: return "person.crop.square"
        case .portraits: return "person.and.background.dotted"; case .panoramas: return "pano"; case .slomo: return "slowmo"
        case .bursts: return "square.stack.3d.down.right"; case .notInAlbum: return "rectangle.stack.badge.minus"; case .recent: return "clock"
        }
    }
    /// Sous-type de smart album si la catégorie en dépend.
    var smartSubtype: PHAssetCollectionSubtype? {
        switch self {
        case .selfies: return .smartAlbumSelfPortraits
        case .portraits: return .smartAlbumDepthEffect
        case .panoramas: return .smartAlbumPanoramas
        case .slomo: return .smartAlbumSlomoVideos
        case .bursts: return .smartAlbumBursts
        case .recent: return .smartAlbumRecentlyAdded
        default: return nil
        }
    }
}

enum LibraryQuery {
    static func options(prefs: Prefs, filter: MediaFilter = .all, applyPrefs: Bool = true) -> PHFetchOptions {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: prefs.sortAscending)]
        var p: [NSPredicate] = []
        if applyPrefs {
            if !prefs.showScreenshots { p.append(NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)) }
            if !prefs.showVideos { p.append(NSPredicate(format: "mediaType != %d", PHAssetMediaType.video.rawValue)) }
        }
        switch filter {
        case .photos: p.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case .videos: p.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        case .live: p.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue))
        case .favorites: p.append(NSPredicate(format: "favorite == YES"))
        case .screenshots: p.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue))
        default: break
        }
        if !p.isEmpty { o.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: p) }
        return o
    }

    static func assets(prefs: Prefs, filter: MediaFilter) -> AssetList {
        let o = options(prefs: prefs, filter: filter)
        if let sub = filter.smartSubtype {
            guard let col = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject else { return .empty }
            return AssetList(PHAsset.fetchAssets(in: col, options: o))
        }
        if filter == .notInAlbum {
            var ids = Set<String>()
            let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            albums.enumerateObjects { col, _, _ in
                PHAsset.fetchAssets(in: col, options: nil).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
            }
            let all = PHAsset.fetchAssets(with: o)
            var out: [PHAsset] = []
            all.enumerateObjects { a, _, _ in if !ids.contains(a.localIdentifier) { out.append(a) } }
            return AssetList(out)
        }
        return AssetList(PHAsset.fetchAssets(with: o))
    }
}

struct MediaSection: Identifiable, Equatable {
    var id: Int { start }
    var start: Int
    var count: Int
    var minDate: Date
    var maxDate: Date
    func title(_ mode: GroupMode) -> String {
        mode == .day ? Fmt.day(minDate) : Fmt.range(minDate, maxDate)
    }

    /// Regroupe des dates triées (croissant ou décroissant) en sections contiguës.
    static func compute(dates: [Date], mode: GroupMode, calendar: Calendar = .current) -> [MediaSection] {
        var out: [MediaSection] = []
        var currentKey: [Int] = []
        for (i, d) in dates.enumerated() {
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            let key: [Int]
            switch mode {
            case .day: key = [c.year ?? 0, c.month ?? 0, c.day ?? 0]
            case .month: key = [c.year ?? 0, c.month ?? 0]
            case .year: key = [c.year ?? 0]
            }
            if key == currentKey, !out.isEmpty {
                out[out.count - 1].count += 1
                out[out.count - 1].minDate = min(out[out.count - 1].minDate, d)
                out[out.count - 1].maxDate = max(out[out.count - 1].maxDate, d)
            } else {
                currentKey = key
                out.append(MediaSection(start: i, count: 1, minDate: d, maxDate: d))
            }
        }
        return out
    }
    static func compute(list: AssetList, mode: GroupMode) -> [MediaSection] {
        let dates = (0..<list.count).map { list[$0].creationDate ?? Date.distantPast }
        return compute(dates: dates, mode: mode)
    }
}

@MainActor
final class PhotoLibraryModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var list: AssetList = .empty
    @Published var filter: MediaFilter = .all { didSet { reload() } }
    @Published var photoCount = 0
    @Published var videoCount = 0
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var version = 0
    private var prefs = Prefs()
    private var registered = false

    var isAuthorized: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }
    var statusLabel: String {
        switch status {
        case .authorized: return "Accès complet"
        case .limited: return "Accès limité"
        case .denied: return "Refusé"
        case .restricted: return "Restreint"
        default: return "Non demandé"
        }
    }

    func configure(prefs: Prefs) { self.prefs = prefs }

    func start() async {
        refreshAuthorization()
        if status == .notDetermined { await requestAccess() }
        if isAuthorized { reload() }
    }

    func requestAccess() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = s
        if isAuthorized { reload() }
    }

    func refreshAuthorization() {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s != status {
            status = s
            if isAuthorized { reload() } else { list = .empty; photoCount = 0; videoCount = 0 }
        }
    }

    func reload() {
        guard isAuthorized else { return }
        if !registered { PHPhotoLibrary.shared().register(self); registered = true }
        isLoading = true
        let p = prefs, f = filter
        Task.detached(priority: .userInitiated) {
            let l = LibraryQuery.assets(prefs: p, filter: f)
            let photos = PHAsset.fetchAssets(with: .image, options: nil).count
            let videos = PHAsset.fetchAssets(with: .video, options: nil).count
            await MainActor.run {
                self.list = l; self.photoCount = photos; self.videoCount = videos
                self.isLoading = false; self.lastRefresh = Date(); self.version += 1
            }
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if let r = self.list.fetchResult, let d = changeInstance.changeDetails(for: r) {
                self.list = AssetList(d.fetchResultAfterChanges)
                self.photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
                self.videoCount = PHAsset.fetchAssets(with: .video, options: nil).count
                self.lastRefresh = Date()
                self.version += 1
            } else if self.filter == .notInAlbum {
                self.reload()
            } else {
                self.version += 1
            }
        }
    }

    func presentLimitedPicker() {
        guard let vc = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow?.rootViewController else { return }
        var top = vc; while let p = top.presentedViewController { top = p }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}

// MARK: - Métadonnées locales (légendes, mots-clés, notes)
struct LocalMeta: Codable, Equatable {
    var caption = ""
    var keywords: [String] = []
    var note = ""
    var isEmpty: Bool { caption.isEmpty && keywords.isEmpty && note.isEmpty }
}

/// PhotoKit n’expose pas l’écriture des légendes/mots-clés : ils sont stockés localement dans l’app (et utilisés par la recherche).
@MainActor
final class MetadataStore: ObservableObject {
    static let shared = MetadataStore()
    @Published private(set) var items: [String: LocalMeta] = [:]
    private var url: URL { appSupportURL().appendingPathComponent("meta.json") }
    init() { if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: LocalMeta].self, from: d) { items = m } }
    func get(_ id: String) -> LocalMeta { items[id] ?? LocalMeta() }
    func set(_ id: String, _ m: LocalMeta) {
        if m.isEmpty { items.removeValue(forKey: id) } else { items[id] = m }
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: url, options: .atomic) }
    }
    func clear() { items = [:]; try? FileManager.default.removeItem(at: url) }
}

// MARK: - Vignettes
@MainActor
final class Thumbs {
    static let shared = Thumbs()
    let manager = PHCachingImageManager()
    init() { manager.allowsCachingHighQualityImages = false }
    func request(_ asset: PHAsset, pixelSize: CGSize, fill: Bool, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        return manager.requestImage(for: asset, targetSize: pixelSize, contentMode: fill ? .aspectFill : .aspectFit, options: o) { img, _ in
            completion(img)
        }
    }
    func cancel(_ id: PHImageRequestID) { manager.cancelImageRequest(id) }
}

struct AssetThumb: View {
    let asset: PHAsset
    var size: CGSize
    var fill = true
    @State private var image: UIImage?
    @State private var req: PHImageRequestID?
    @Environment(\.pal) private var pal
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Rectangle().fill(pal.card)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(width: size.width, height: size.height).clipped()
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            guard image == nil else { return }
            let px = CGSize(width: size.width * scale, height: size.height * scale)
            req = Thumbs.shared.request(asset, pixelSize: px, fill: fill) { img in image = img }
        }
        .onDisappear { if let r = req { Thumbs.shared.cancel(r); req = nil }; }
    }
}
