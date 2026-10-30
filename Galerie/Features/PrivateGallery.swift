import SwiftUI
import PhotosUI
import AVKit
import Photos
import ImageIO
import UniformTypeIdentifiers

struct PrivateItem: Identifiable, Hashable {
    let url: URL
    let date: Date
    let isVideo: Bool
    var id: String { url.lastPathComponent }
}

/// Galerie distincte : médias stockés dans l’app (stockage de l’iPhone), exclus de la sauvegarde iCloud,
/// jamais ajoutés à la photothèque système sauf si tu le demandes explicitement.
@MainActor
final class PrivateStore: ObservableObject {
    @Published private(set) var items: [PrivateItem] = []
    @Published var lastImported = 0

    private let fm = FileManager.default
    private let thumbs = NSCache<NSString, UIImage>()

    private var dir: URL {
        var u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GalerieDistincte", isDirectory: true)
        if !fm.fileExists(atPath: u.path) {
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true   // pas de sauvegarde iCloud
            try? u.setResourceValues(rv)
        }
        return u
    }
    /// Dossier visible dans l’app Fichiers (« Sur mon iPhone › Galerie › Dépôt ») pour « Enregistrer dans Fichiers ».
    private var dropDir: URL {
        let u = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Dépôt", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func reload() {
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        items = urls.filter { SharedGroup.isSupported($0) }.map { u in
            let d = (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return PrivateItem(url: u, date: d, isVideo: SharedGroup.videoExtensions.contains(u.pathExtension.lowercased()))
        }.sorted { $0.date > $1.date }
    }

    /// Récupère ce qui a été déposé par l’extension de partage ou par « Enregistrer dans Fichiers ».
    @discardableResult
    func importPending() -> Int {
        var n = 0
        var sources = [dropDir]
        if let inbox = SharedGroup.inboxURL() { sources.append(inbox) }
        for s in sources {
            for u in (try? fm.contentsOfDirectory(at: s, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] where SharedGroup.isSupported(u) {
                let dst = dir.appendingPathComponent(UUID().uuidString + "." + u.pathExtension.lowercased())
                if (try? fm.moveItem(at: u, to: dst)) != nil { n += 1 }
            }
        }
        if n > 0 { reload(); lastImported = n }
        return n
    }

    @discardableResult
    func add(copying src: URL) -> Bool {
        guard SharedGroup.isSupported(src) else { return false }
        let ok = (try? SharedGroup.deposit(src, in: dir)) != nil
        if ok { reload() }
        return ok
    }

    func delete(_ list: [PrivateItem]) {
        for i in list { try? fm.removeItem(at: i.url); thumbs.removeObject(forKey: i.id as NSString) }
        reload()
    }

    /// Copie dans la photothèque système (action explicite de l’utilisateur).
    func saveToPhotos(_ item: PrivateItem) async -> Bool {
        let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard st == .authorized || st == .limited else { return false }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                if item.isVideo { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: item.url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: item.url) }
            }) { ok, _ in cont.resume(returning: ok) }
        }
    }

    func thumbnail(_ item: PrivateItem, side: CGFloat = 300) async -> UIImage? {
        if let c = thumbs.object(forKey: item.id as NSString) { return c }
        let url = item.url, video = item.isVideo
        let img: UIImage? = await Task.detached(priority: .utility) {
            if video {
                let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                g.appliesPreferredTrackTransform = true
                g.maximumSize = CGSize(width: side, height: side)
                return (try? g.copyCGImage(at: .zero, actualTime: nil)).map { UIImage(cgImage: $0) }
            }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let img { thumbs.setObject(img, forKey: item.id as NSString) }
        return img
    }
}

/// Fichier choisi dans le sélecteur de photos, copié dans un dossier temporaire.
private struct PickedMedia: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let ext = received.file.pathExtension.isEmpty ? "jpg" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMedia(url: dst)
        }
    }
}

struct PrivateGalleryView: View {
    @EnvironmentObject private var store: PrivateStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lock: AppLock
    @Environment(\.pal) private var pal
    @Environment(\.scenePhase) private var scenePhase
    @State private var picks: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var viewing: PrivateItem?
    @State private var toDelete: PrivateItem?
    @State private var shareURL: URL?

    private let cols = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        NavigationStack {
            LockedContent(scope: .privateGallery, enabled: settings.prefs.lockPrivate, title: "Galerie distincte verrouillée") {
                content
            }
            .themedScreen()
            .navigationTitle("Galerie distincte")
        }
    }

    private var content: some View {
        ScrollView {
            if store.items.isEmpty {
                VStack(spacing: 12) {
                    EmptyState(icon: "lock.rectangle.stack", title: "Galerie vide", message: "Depuis une autre app (Facebook, Safari…), touche Partager puis « Galerie distincte ». Tu peux aussi importer ci-dessus.").frame(height: 300)
                    Text("Ces médias restent dans le stockage de l’iPhone, hors de la photothèque et de la sauvegarde iCloud.").gFont(.small).foregroundStyle(pal.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            } else {
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(store.items) { it in
                        PrivateThumb(item: it).onTapGesture { viewing = it }
                            .contextMenu {
                                Button { shareURL = it.url } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                                Button { Task { app.showToast(await store.saveToPhotos(it) ? "Copié dans la photothèque" : "Accès à la photothèque refusé") } } label: { Label("Copier dans la photothèque", systemImage: "photo.badge.plus") }
                                Button(role: .destructive) { askDelete(it) } label: { Label("Supprimer", systemImage: "trash") }
                            }
                    }
                }.padding(.horizontal, 2)
                Text("\(store.items.count) élément(s) · stockés sur l’iPhone, hors iCloud").gFont(.small).foregroundStyle(pal.textSecondary).padding(12)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PhotosPicker(selection: $picks, matching: .any(of: [.images, .videos])) { Label("Depuis les Photos", systemImage: "photo") }
                    Button { showFiles = true } label: { Label("Depuis Fichiers", systemImage: "folder") }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Importer")
            }
        }
        .onAppear { store.reload(); store.importPending() }
        .onChange(of: scenePhase) { _, p in if p == .active { store.importPending() } }
        .onChange(of: store.lastImported) { _, n in if n > 0 { app.showToast("\(n) élément(s) ajouté(s)"); store.lastImported = 0 } }
        .onChange(of: picks) { _, new in importPicks(new) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { res in
            guard case .success(let urls) = res else { return }
            var n = 0
            for u in urls { let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }; if store.add(copying: u) { n += 1 } }
            if n > 0 { app.showToast("\(n) élément(s) ajouté(s)") }
        }
        .fullScreenCover(item: $viewing) { it in PrivateViewer(start: it) { viewing = nil } }
        .sheet(item: Binding(get: { shareURL.map { ShareURLItem(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { ShareSheet(items: [$0.url]) }
        .confirmationDialog("Supprimer définitivement ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let d = toDelete { Task { if await lock.authorize(.delete, prefs: settings.prefs) { store.delete([d]) } } }
                toDelete = nil
            }
            Button("Annuler", role: .cancel) { toDelete = nil }
        } message: { Text("Ce média est supprimé de la galerie distincte et ne pourra pas être récupéré.") }
    }

    private func askDelete(_ it: PrivateItem) { toDelete = it }

    private func importPicks(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var n = 0
            for p in items {
                if let m = try? await p.loadTransferable(type: PickedMedia.self) {
                    if store.add(copying: m.url) { n += 1 }
                    try? FileManager.default.removeItem(at: m.url)
                }
            }
            picks = []
            if n > 0 { app.showToast("\(n) élément(s) ajouté(s)") }
        }
    }
}

private struct ShareURLItem: Identifiable { let url: URL; var id: String { url.path } }

private struct PrivateThumb: View {
    let item: PrivateItem
    @EnvironmentObject private var store: PrivateStore
    @State private var img: UIImage?
    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
            .overlay(alignment: .bottomLeading) { if item.isVideo { Image(systemName: "video.fill").font(.system(size: 12)).foregroundStyle(.white).padding(5).shadow(radius: 2) } }
            .clipped().contentShape(Rectangle())
            .task(id: item.id) { img = await store.thumbnail(item) }
    }
}

struct PrivateViewer: View {
    let start: PrivateItem
    let close: () -> Void
    @EnvironmentObject private var store: PrivateStore
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @State private var current: String = ""
    @State private var confirmDelete = false

    private var item: PrivateItem? { store.items.first { $0.id == current } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(store.items) { it in
                    PrivatePage(item: it).tag(it.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea()
            VStack {
                HStack {
                    Button { close() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 48, height: 48).background(Circle().fill(.black.opacity(0.45))).contentShape(Circle()) }
                    Spacer()
                    if let it = item {
                        Button { Task { app.showToast(await store.saveToPhotos(it) ? "Copié dans la photothèque" : "Accès à la photothèque refusé") } } label: { Image(systemName: "photo.badge.plus").foregroundStyle(.white).frame(width: 48, height: 48).background(Circle().fill(.black.opacity(0.45))).contentShape(Circle()) }
                        Button { confirmDelete = true } label: { Image(systemName: "trash").foregroundStyle(.white).frame(width: 48, height: 48).background(Circle().fill(.black.opacity(0.45))).contentShape(Circle()) }
                    }
                }.padding(.horizontal, 12).padding(.top, 6)
                Spacer()
            }
        }
        .onAppear { current = start.id }
        .confirmationDialog("Supprimer définitivement ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                guard let it = item else { return }
                Task { if await lock.authorize(.delete, prefs: settings.prefs) { store.delete([it]); if store.items.isEmpty { close() } else { current = store.items[0].id } } }
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}

private struct PrivatePage: View {
    let item: PrivateItem
    @State private var player: AVPlayer?
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        Group {
            if item.isVideo {
                VideoPlayer(player: player)
                    .onAppear { player = AVPlayer(url: item.url) }
                    .onDisappear { player?.pause(); player = nil }
            } else if let ui = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: ui).resizable().scaledToFit()
                    .scaleEffect(max(1, scale * pinch))
                    .gesture(MagnificationGesture().updating($pinch) { v, s, _ in s = v }.onEnded { v in scale = min(max(1, scale * v), 5) })
                    .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.white)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
