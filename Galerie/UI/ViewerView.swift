import SwiftUI
import Photos
import PhotosUI
import AVKit

// MARK: - Image zoomable (UIScrollView)
final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 { imageView.frame = bounds; contentSize = bounds.size }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: () -> Void
    var onZoom: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ZoomScrollView {
        let sv = ZoomScrollView()
        sv.delegate = context.coordinator
        sv.minimumZoomScale = 1; sv.maximumZoomScale = 6
        sv.showsHorizontalScrollIndicator = false; sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.imageView.contentMode = .scaleAspectFit
        sv.imageView.isUserInteractionEnabled = true
        sv.addSubview(sv.imageView)
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        let one = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        one.require(toFail: dbl)
        sv.addGestureRecognizer(dbl); sv.addGestureRecognizer(one)
        return sv
    }
    func updateUIView(_ sv: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        if sv.imageView.image !== image { sv.imageView.image = image; sv.setNeedsLayout() }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage
        init(_ p: ZoomableImage) { parent = p }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomScrollView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            parent.onZoom(scrollView.zoomScale > 1.01)
            if let iv = (scrollView as? ZoomScrollView)?.imageView {
                // centre l’image quand elle est plus petite que l’écran
                let x = max(0, (scrollView.bounds.width - iv.frame.width) / 2)
                let y = max(0, (scrollView.bounds.height - iv.frame.height) / 2)
                scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
            }
        }
        @objc func singleTap() { parent.onSingleTap() }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? ZoomScrollView else { return }
            if sv.zoomScale > 1.01 { sv.setZoomScale(1, animated: true) }
            else {
                let p = g.location(in: sv.imageView)
                let w = sv.bounds.width / 2.5, h = sv.bounds.height / 2.5
                sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
            }
        }
    }
}

struct LivePhotoRepresentable: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let autoplay: Bool
    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = PHLivePhotoView(); v.contentMode = .scaleAspectFit; return v
    }
    func updateUIView(_ v: PHLivePhotoView, context: Context) {
        if v.livePhoto !== livePhoto { v.livePhoto = livePhoto; if autoplay { v.startPlayback(with: .hint) } }
    }
}

struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController(); c.player = player; c.showsPlaybackControls = true
        c.videoGravity = .resizeAspect; c.allowsPictureInPicturePlayback = true; return c
    }
    func updateUIViewController(_ c: AVPlayerViewController, context: Context) {}
}

// MARK: - Pages
struct PhotoPage: View {
    let asset: PHAsset
    let active: Bool
    var onTap: () -> Void
    var onZoom: (Bool) -> Void
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    @State private var image: UIImage?
    @State private var live: PHLivePhoto?
    @State private var req: PHImageRequestID?
    @State private var failed = false
    @State private var progress: Double?

    var body: some View {
        ZStack {
            if let live, asset.isLive {
                LivePhotoRepresentable(livePhoto: live, autoplay: settings.prefs.autoPlayLive && active)
                    .onTapGesture { onTap() }
            } else if let image {
                ZoomableImage(image: image, onSingleTap: onTap, onZoom: onZoom)
            } else if failed {
                VStack(spacing: 8) { Image(systemName: "exclamationmark.icloud").font(.largeTitle); Text("Impossible de charger ce média.").gFont(.caption) }.foregroundStyle(.white)
            } else {
                VStack(spacing: 8) { ProgressView(); if let p = progress { Text("iCloud \(Int(p * 100)) %").gFont(.caption) } }.tint(.white).foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: load)
        .onDisappear { if let r = req { PHImageManager.default().cancelImageRequest(r) }; req = nil }
    }

    private func load() {
        guard image == nil else { return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic; o.isNetworkAccessAllowed = true; o.resizeMode = .fast
        o.progressHandler = { p, _, _, _ in DispatchQueue.main.async { progress = p } }
        let side = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale * 2
        let target = CGSize(width: min(side, 4096), height: min(side, 4096))
        req = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: o) { img, info in
            DispatchQueue.main.async {
                if let img { image = img } else if (info?[PHImageErrorKey] as? NSError) != nil { failed = true }
            }
        }
        if asset.isLive {
            let lo = PHLivePhotoRequestOptions(); lo.deliveryMode = .highQualityFormat; lo.isNetworkAccessAllowed = true
            PHImageManager.default().requestLivePhoto(for: asset, targetSize: target, contentMode: .aspectFit, options: lo) { lp, _ in
                DispatchQueue.main.async { if let lp { live = lp } }
            }
        }
    }
}

struct VideoPage: View {
    let asset: PHAsset
    let active: Bool
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var observer: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player { PlayerController(player: player).ignoresSafeArea() }
            else if failed { Text("Vidéo indisponible (iCloud ou erreur de lecture).").gFont(.caption).foregroundStyle(.white) }
            else { ProgressView().tint(.white) }
        }
        .onAppear(perform: load)
        .onChange(of: active) { _, a in if a { player?.play() } else { player?.pause() } }
        .onChange(of: scenePhase) { _, p in if p != .active { player?.pause() } }
        .onDisappear { player?.pause(); if let o = observer { NotificationCenter.default.removeObserver(o) } }
    }
    private func load() {
        guard player == nil else { return }
        let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { item, _ in
            DispatchQueue.main.async {
                guard let item else { failed = true; return }
                let p = AVPlayer(playerItem: item)
                observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    if settings.prefs.loopVideos { p.seek(to: .zero); p.play() }
                }
                player = p
                if active { p.play() }
            }
        }
    }
}

// MARK: - Visionneuse
struct ViewerView: View {
    let context: ViewerContext
    let ns: Namespace.ID
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: Int?
    @State private var chrome = true
    @State private var zoomed = false
    @State private var refreshed: [String: PHAsset] = [:]
    @State private var showInfo = false
    @State private var share: ShareItems?
    @State private var confirmDelete = false
    @State private var showAlbum = false
    @State private var editing: PHAsset?
    @State private var showDate = false
    @State private var showLocation = false
    @State private var showMeta = false
    @State private var slideshow = false
    @State private var working = false

    private var index: Int { min(max(currentID ?? context.start, 0), max(context.list.count - 1, 0)) }
    private var asset: PHAsset { refreshed[context.list[index].localIdentifier] ?? context.list[index] }

    var body: some View {
        ZStack {
            (chrome ? pal.bg : Color.black).ignoresSafeArea()
            pager
            if chrome { topBar.transition(.opacity); bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
            if working { ProgressView().controlSize(.large).padding(24).glass(RoundedRectangle(cornerRadius: 18)) }
        }
        .navigationTransition(.zoom(sourceID: context.prefix + context.list[index].localIdentifier, in: ns))
        .statusBarHidden(!chrome)
        .sheet(isPresented: $showInfo) { InfoSheet(asset: asset).presentationDetents([.medium, .large]) }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
        .sheet(isPresented: $showAlbum) { AlbumPickerSheet(assets: [asset]) { app.showToast("Ajouté à « \($0) »") } }
        .sheet(isPresented: $showDate) { DateEditSheet(asset: asset) { refresh() } .presentationDetents([.medium]) }
        .sheet(isPresented: $showLocation) { LocationEditSheet(asset: asset) { refresh() } }
        .sheet(isPresented: $showMeta) { MetaEditSheet(asset: asset).presentationDetents([.medium, .large]) }
        .fullScreenCover(item: $editing) { a in
            if a.isVideo { VideoEditorView(asset: a) { refresh() } } else { PhotoEditorView(asset: a) { refresh() } }
        }
        .fullScreenCover(isPresented: $slideshow) { SlideshowView(list: context.list, start: index) }
        .confirmationDialog("Supprimer ce média de la photothèque ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                Task { if await MediaActions.delete([asset]) { dismiss() } }
            }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Il ira dans « Supprimés récemment » de l’app Photos d’iOS. iOS demandera aussi sa propre confirmation.") }
        .onAppear { currentID = context.start }
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<context.list.count, id: \.self) { i in
                    let a = context.list[i]
                    Group {
                        if a.isVideo { VideoPage(asset: a, active: i == index) }
                        else { PhotoPage(asset: a, active: i == index, onTap: { settings.animate { chrome.toggle() } }, onZoom: { z in if i == index { zoomed = z } }) }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollDisabled(zoomed)
        .ignoresSafeArea()
        .onChange(of: currentID) { _, _ in Haptics.shared.selection(); zoomed = false }
    }

    private var topBar: some View {
        VStack {
            HStack {
                GlassIconButton(system: "chevron.down", label: "Fermer") { dismiss() }
                Spacer()
                VStack(spacing: 1) {
                    if let d = asset.creationDate {
                        Text(d.formatted(.dateTime.day().month(.wide).year())).gFont(.headline)
                        Text(d.formatted(date: .omitted, time: .shortened)).gFont(.caption).foregroundStyle(pal.textSecondary)
                    }
                }
                Spacer()
                actionsMenu
            }.padding(.horizontal, 14).padding(.top, 6)
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                bar("square.and.arrow.up", "Partager") { Task { await shareCurrent() } }
                bar(asset.isFavorite ? "heart.fill" : "heart", asset.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", tint: asset.isFavorite ? .pink : nil) { toggleFavorite() }
                bar("slider.horizontal.3", "Modifier") { editing = asset }
                bar("info.circle", "Informations") { showInfo = true }
                bar("trash", "Supprimer") { Haptics.shared.warning(); confirmDelete = true }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glass(Capsule()).padding(.horizontal, 20).padding(.bottom, 6)
        }
    }

    private func bar(_ icon: String, _ label: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.shared.light(); action() } label: {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint ?? pal.icon)
                .frame(maxWidth: .infinity, minHeight: 46)
        }.buttonStyle(PressableStyle()).accessibilityLabel(label)
    }

    private var actionsMenu: some View {
        Menu {
            if !asset.isVideo { Button { Task { let ok = await MediaActions.copyToPasteboard(asset); app.showToast(ok ? "Copié" : "Copie impossible") } } label: { Label("Copier", systemImage: "doc.on.doc") } }
            Button { Task { working = true; let ok = await MediaActions.duplicate(asset); working = false; app.showToast(ok ? "Copie enregistrée dans la photothèque" : "Duplication impossible") } } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button { Task { await shareCurrent() } } label: { Label("Partager", systemImage: "square.and.arrow.up") }
            Button { toggleFavorite() } label: { Label(asset.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: asset.isFavorite ? "heart.slash" : "heart") }
            Button { showAlbum = true } label: { Label("Ajouter à un album", systemImage: "rectangle.stack.badge.plus") }
            Divider()
            Button { showDate = true } label: { Label("Modifier la date et l’heure", systemImage: "calendar.badge.clock") }
            Button { showLocation = true } label: { Label("Modifier la localisation", systemImage: "mappin.and.ellipse") }
            Button { showMeta = true } label: { Label("Légende, mots-clés, note", systemImage: "text.badge.plus") }
            Button { slideshow = true } label: { Label("Diaporama", systemImage: "play.rectangle") }
            Button { showInfo = true } label: { Label("Informations", systemImage: "info.circle") }
            if asset.isLive { Button { Task { working = true; let ok = await MediaActions.saveLiveAsVideo(asset); working = false; app.showToast(ok ? "Vidéo enregistrée" : "Échec de l’enregistrement") } } label: { Label("Enregistrer comme vidéo", systemImage: "video") } }
            if asset.canPerform(.revert) { Button { Task { let ok = await MediaActions.revert(asset); if ok { refresh() }; app.showToast(ok ? "Original rétabli" : "Impossible de rétablir") } } label: { Label("Rétablir l’original", systemImage: "arrow.uturn.backward") } }
            Divider()
            Button { Task { if await MediaActions.setHidden([asset], true) { dismiss() } } } label: { Label("Masquer", systemImage: "eye.slash") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(pal.icon)
                .frame(width: 44, height: 44).glass(Circle(), interactive: true)
        }.accessibilityLabel("Actions")
    }

    private func toggleFavorite() {
        let a = asset, v = !a.isFavorite
        Task { if await MediaActions.setFavorite([a], v) { refresh(a.localIdentifier) } }
    }
    private func refresh(_ id: String? = nil) {
        let key = id ?? asset.localIdentifier
        if let n = PHAsset.fetchAssets(withLocalIdentifiers: [key], options: nil).firstObject { refreshed[key] = n }
    }
    private func shareCurrent() async {
        working = true
        let u = await MediaActions.shareItems([asset])
        working = false
        if u.isEmpty { app.showToast("Préparation impossible (iCloud ?)") } else { share = ShareItems(urls: u) }
    }
}

extension PHAsset: @retroactive Identifiable { public var id: String { localIdentifier } }

// MARK: - Diaporama
struct SlideshowView: View {
    let list: AssetList
    let start: Int
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var i = 0
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea().transition(.opacity) }
            VStack { Spacer(); Text("Touche pour quitter").font(.caption).foregroundStyle(.white.opacity(0.5)).padding() }
        }
        .contentShape(Rectangle()).onTapGesture { dismiss() }
        .task {
            i = start
            while !Task.isCancelled && list.count > 0 {
                await loadCurrent()
                try? await Task.sleep(nanoseconds: UInt64(settings.prefs.slideshowSeconds * 1_000_000_000))
                i = (i + 1) % list.count
                // saute les vidéos : le diaporama ne montre que des images fixes
                var guardCount = 0
                while list[i].isVideo && guardCount < list.count { i = (i + 1) % list.count; guardCount += 1 }
            }
        }
        .statusBarHidden()
    }
    private func loadCurrent() async {
        let a = list[i]
        let img: UIImage? = await withCheckedContinuation { c in
            let o = PHImageRequestOptions(); o.deliveryMode = .highQualityFormat; o.isNetworkAccessAllowed = true; o.isSynchronous = false
            var done = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 2000, height: 2000), contentMode: .aspectFit, options: o) { im, _ in
                if !done { done = true; c.resume(returning: im) }
            }
        }
        withAnimation(.easeInOut(duration: 0.6)) { image = img }
    }
}
