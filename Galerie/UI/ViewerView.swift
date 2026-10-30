import SwiftUI
import Photos
import PhotosUI
import AVKit
import AVFoundation

// MARK: - Média zoomable (photo ou Live Photo) dans une UIScrollView
/// Corrige le « zoom excessif » : la vue zoomée (`host`) est dimensionnée à la taille exactement ajustée
/// (aspect fit) du média, calculée depuis les dimensions réelles de l’image reçue (orientation EXIF déjà appliquée
/// par PhotoKit) ; le centrage passe par `contentInset`, et le zoom est remis à 1 à chaque changement de page,
/// de média ou de taille d’écran. L’ancienne version fixait le cadre sur l’écran entier et s’appuyait sur
/// le `contentMode` de l’image, ce qui laissait un décalage de zoom et d’insets d’une photo à l’autre.
final class ZoomScrollView: UIScrollView {
    let host = UIView()
    let imageView = UIImageView()
    let liveView = PHLivePhotoView()
    var mediaSize: CGSize = .zero
    private var laidOutSize: CGSize = .zero
    private var inRelayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        host.backgroundColor = .clear
        for v in [imageView, liveView] as [UIView] {
            v.contentMode = .scaleAspectFit
            v.isUserInteractionEnabled = false
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(v)
        }
        liveView.isHidden = true
        // La lecture est pilotée par notre propre geste (voir Coordinator) : on retire celui de PhotoKit pour éviter tout conflit.
        liveView.playbackGestureRecognizer.isEnabled = false
        addSubview(host)
        minimumZoomScale = 1; maximumZoomScale = 6
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        decelerationRate = .fast
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    private func fittedSize() -> CGSize {
        let b = bounds.size
        guard mediaSize.width > 0, mediaSize.height > 0, b.width > 0, b.height > 0 else { return b }
        let s = min(b.width / mediaSize.width, b.height / mediaSize.height)
        return CGSize(width: mediaSize.width * s, height: mediaSize.height * s)
    }

    /// Recalcule la mise en page à zoom 1 (rotation, nouveau média, première mise en page).
    func relayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        inRelayout = true
        defer { inRelayout = false }
        if zoomScale != 1 { zoomScale = 1 }
        let fit = fittedSize()
        host.frame = CGRect(origin: .zero, size: fit)
        contentSize = fit
        centerContent()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    /// Centre le média quand il est plus petit que l’écran (en zoom 1 comme pendant un pincement).
    func centerContent() {
        let x = max(0, (bounds.width - host.frame.width) / 2)
        let y = max(0, (bounds.height - host.frame.height) / 2)
        let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != inset { contentInset = inset }
    }

    func apply(image: UIImage?, live: PHLivePhoto?, pixel: CGSize) {
        var size = pixel
        if let image, image.size.width > 0, image.size.height > 0 { size = image.size }
        if imageView.image !== image { imageView.image = image }
        if liveView.livePhoto !== live { liveView.livePhoto = live }
        liveView.isHidden = (live == nil)
        guard size.width > 0, size.height > 0 else { return }
        let oldRatio = mediaSize.height > 0 ? mediaSize.width / mediaSize.height : 0
        let newRatio = size.width / size.height
        mediaSize = size
        if abs(oldRatio - newRatio) > 0.001 { relayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if inRelayout { return }
        if laidOutSize != bounds.size { laidOutSize = bounds.size; relayout() }
    }
}

struct ZoomableMedia: UIViewRepresentable {
    let image: UIImage?
    let livePhoto: PHLivePhoto?
    let pixelSize: CGSize
    let active: Bool
    let autoplayLive: Bool
    var onSingleTap: () -> Void
    var onZoom: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let sv = ZoomScrollView()
        sv.delegate = context.coordinator
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        let one = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        one.require(toFail: dbl)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 30
        hold.delegate = context.coordinator
        sv.addGestureRecognizer(dbl); sv.addGestureRecognizer(one); sv.addGestureRecognizer(hold)
        context.coordinator.hold = hold
        return sv
    }

    func updateUIView(_ sv: ZoomScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        sv.apply(image: image, live: livePhoto, pixel: pixelSize)
        // Le maintien prolongé ne concerne que les vraies Live Photos : une photo ordinaire ne déclenche rien.
        c.hold?.isEnabled = (livePhoto != nil)
        if !active {
            // Page quittée : zoom réinitialisé (pas de zoom « mémorisé » d’une photo à l’autre) et lecture stoppée.
            if sv.zoomScale != 1 { sv.setZoomScale(1, animated: false); sv.centerContent() }
            if c.autoPlayed != nil { sv.liveView.stopPlayback() }
            c.autoPlayed = nil
        } else if autoplayLive, let lp = livePhoto, c.autoPlayed !== lp {
            c.autoPlayed = lp
            sv.liveView.startPlayback(with: .full)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableMedia
        var hold: UILongPressGestureRecognizer?
        var autoPlayed: PHLivePhoto?
        init(_ p: ZoomableMedia) { parent = p }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomScrollView)?.host }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
            parent.onZoom(scrollView.zoomScale > 1.01)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func singleTap() { parent.onSingleTap() }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? ZoomScrollView else { return }
            if sv.zoomScale > 1.01 { sv.setZoomScale(1, animated: true) }
            else {
                let p = g.location(in: sv.host)
                let w = sv.bounds.width / 2.5, h = sv.bounds.height / 2.5
                sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
            }
        }
        /// Maintien prolongé : lecture de la Live Photo tant que le doigt reste posé (arrêt au relâchement).
        @objc func hold(_ g: UILongPressGestureRecognizer) {
            guard let sv = g.view as? ZoomScrollView, sv.liveView.livePhoto != nil else { return }
            switch g.state {
            case .began:
                guard sv.zoomScale <= 1.01 else { return }
                Haptics.shared.medium()
                sv.liveView.startPlayback(with: .full)
            case .ended, .cancelled, .failed:
                sv.liveView.stopPlayback()
            default: break
            }
        }
    }
}

// MARK: - Lecteur vidéo (une seule série de commandes : les nôtres)
final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.backgroundColor = .clear
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: PlayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// Lecteur piloté par l’app. Remplace `AVPlayerViewController`, qui dessinait ses propres commandes
/// (fermeture, menu « … », barre de lecture) par-dessus celles de la visionneuse : c’est l’origine des boutons
/// en double sur les vidéos, et il absorbait aussi les appuis (donc pas de mode immersif).
final class VideoController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var failed = false
    var scrubbing = false
    var loop = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rateObserver: NSKeyValueObservation?
    private var wantsPlay = false

    func load(asset: PHAsset, loop: Bool, autoplay: Bool) {
        self.loop = loop
        guard player == nil else { return }
        wantsPlay = autoplay
        let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: o) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let item else { self.failed = true; return }
                let p = AVPlayer(playerItem: item)
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    guard let self, let p = self.player else { return }
                    if self.loop { p.seek(to: .zero); p.play() } else { self.isPlaying = false }
                }
                self.timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
                    guard let self else { return }
                    if !self.scrubbing, t.seconds.isFinite { self.current = t.seconds }
                    if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
                }
                self.rateObserver = p.observe(\.rate, options: [.new]) { [weak self] pl, _ in
                    DispatchQueue.main.async { self?.isPlaying = pl.rate > 0 }
                }
                self.player = p
                if self.wantsPlay { p.play() }
            }
        }
    }
    func play() { wantsPlay = true; player?.play() }
    func pause() { wantsPlay = false; player?.pause() }
    func toggle() {
        guard let p = player else { return }
        if p.rate > 0 { pause() } else {
            if duration > 0, current >= duration - 0.3 { p.seek(to: .zero) }
            play()
        }
    }
    func seek(to t: Double) {
        current = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func teardown() {
        player?.pause()
        if let t = timeObserver, let p = player { p.removeTimeObserver(t) }
        timeObserver = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        rateObserver = nil
    }
    deinit { teardown() }
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
    @State private var liveReq: PHImageRequestID?
    @State private var failed = false
    @State private var progress: Double?

    var body: some View {
        ZStack {
            if image != nil || live != nil {
                ZoomableMedia(image: image, livePhoto: asset.isLive ? live : nil,
                              pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                              active: active, autoplayLive: settings.prefs.autoPlayLive,
                              onSingleTap: onTap, onZoom: onZoom)
            } else if failed {
                VStack(spacing: 8) { Image(systemName: "exclamationmark.icloud").font(.largeTitle); Text("Impossible de charger ce média.").gFont(.caption) }.foregroundStyle(pal.text)
            } else {
                VStack(spacing: 8) { ProgressView(); if let p = progress { Text("iCloud \(Int(p * 100)) %").gFont(.caption) } }.foregroundStyle(pal.textSecondary)
                    .contentShape(Rectangle()).onTapGesture { onTap() }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: load)
        .onDisappear {
            if let r = req { PHImageManager.default().cancelImageRequest(r) }
            if let r = liveReq { PHImageManager.default().cancelImageRequest(r) }
            req = nil; liveReq = nil
        }
    }

    private func load() {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let screen = UIScreen.main.bounds.size
        let side = max(screen.width, screen.height) * scale * 2
        let target = CGSize(width: min(side, 4096), height: min(side, 4096))
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic; o.isNetworkAccessAllowed = true; o.resizeMode = .fast
        o.progressHandler = { p, _, _, _ in DispatchQueue.main.async { progress = p } }
        req = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: o) { img, info in
            DispatchQueue.main.async {
                if let img { image = img } else if (info?[PHImageErrorKey] as? NSError) != nil, live == nil { failed = true }
            }
        }
        if asset.isLive {
            // Taille « écran » : c’est la taille attendue par PHLivePhotoView ; une taille démesurée faisait échouer la requête.
            let liveTarget = CGSize(width: screen.width * scale, height: screen.height * scale)
            let lo = PHLivePhotoRequestOptions(); lo.deliveryMode = .highQualityFormat; lo.isNetworkAccessAllowed = true
            liveReq = PHImageManager.default().requestLivePhoto(for: asset, targetSize: liveTarget, contentMode: .aspectFit, options: lo) { lp, _ in
                DispatchQueue.main.async { if let lp { live = lp } }
            }
        }
    }
}

struct VideoPage: View {
    let asset: PHAsset
    let active: Bool
    let chrome: Bool
    var onTap: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pal) private var pal
    @StateObject private var ctl = VideoController()

    var body: some View {
        ZStack {
            if let p = ctl.player {
                PlayerLayerView(player: p).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture { onTap() }
            } else if ctl.failed {
                Text("Vidéo indisponible (iCloud ou erreur de lecture).").gFont(.caption).foregroundStyle(pal.textSecondary)
                    .contentShape(Rectangle()).onTapGesture { onTap() }
            } else { ProgressView().tint(pal.textSecondary) }
            if active && chrome && ctl.player != nil {
                VStack { Spacer(); controls.padding(.horizontal, 20).padding(.bottom, 96) }
                    .transition(.opacity)
            }
        }
        .onAppear { ctl.load(asset: asset, loop: settings.prefs.loopVideos, autoplay: active) }
        .onChange(of: settings.prefs.loopVideos) { _, v in ctl.loop = v }
        .onChange(of: active) { _, a in if a { ctl.play() } else { ctl.pause() } }
        .onChange(of: scenePhase) { _, p in if p != .active { ctl.pause() } }
        .onDisappear { ctl.teardown() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { Haptics.shared.light(); ctl.toggle() } label: {
                Image(systemName: ctl.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(pal.icon).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(PressableStyle()).accessibilityLabel(ctl.isPlaying ? "Pause" : "Lecture")
            Text(Fmt.duration(ctl.current)).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(pal.textSecondary)
            Slider(value: Binding(get: { min(ctl.current, max(ctl.duration, 0.1)) }, set: { ctl.seek(to: $0) }),
                   in: 0...max(ctl.duration, 0.1), onEditingChanged: { editing in ctl.scrubbing = editing })
                .tint(pal.accent)
            Text(Fmt.duration(ctl.duration)).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(pal.textSecondary)
        }
        .padding(.horizontal, 8)
        .glass(Capsule())
    }
}

// MARK: - Date et heure (Liquid Glass)
struct DateTimeBadge: View {
    let date: Date
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 10, weight: .semibold)).textCase(.uppercase).tracking(1.4).foregroundStyle(pal.accent)
            Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(pal.text)
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 9, weight: .bold))
                Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12, weight: .medium).monospacedDigit())
            }.foregroundStyle(pal.textSecondary)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04), .white.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .shortened))
    }
}

// MARK: - Visionneuse
struct ViewerView: View {
    let context: ViewerContext
    let ns: Namespace.ID
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLock
    @Environment(\.pal) private var pal

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
        // Une seule instance de chaque commande : la barre du haut et celle du bas sont définies ici et nulle part ailleurs
        // (le lecteur vidéo n’affiche plus ses propres commandes).
        ZStack {
            (chrome ? pal.bg : Color.black).ignoresSafeArea()
            pager
        }
        .overlay(alignment: .top) { if chrome { topBar.transition(.opacity) } }
        .overlay(alignment: .bottom) { if chrome { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .overlay { if working { ProgressView().controlSize(.large).padding(24).glass(RoundedRectangle(cornerRadius: 18)) } }
        .navigationTransition(.zoom(sourceID: context.prefix + context.list[index].localIdentifier, in: ns))
        .statusBarHidden(!chrome)
        .persistentSystemOverlays(chrome ? .automatic : .hidden)
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
                Task { if await lock.authorize(.delete, prefs: settings.prefs), await MediaActions.delete([asset]) { close() } }
            }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Il ira dans « Supprimés récemment » de l’app Photos d’iOS. iOS demandera aussi sa propre confirmation.") }
        .onAppear { currentID = context.start }
    }

    /// Fermeture explicite par l’état de l’app (et non `dismiss()`), donc fiable même avec des feuilles imbriquées.
    private func close() { Haptics.shared.light(); app.closeViewer() }

    private func toggleChrome() { settings.animate { chrome.toggle() } }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<context.list.count, id: \.self) { i in
                    let a = context.list[i]
                    Group {
                        if a.isVideo { VideoPage(asset: a, active: i == index, chrome: chrome, onTap: toggleChrome) }
                        else { PhotoPage(asset: a, active: i == index, onTap: toggleChrome, onZoom: { z in if i == index { zoomed = z } }) }
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
        HStack(alignment: .center) {
            Button { close() } label: {
                Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(pal.icon)
                    .frame(width: 48, height: 48).glass(Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Fermer")
            Spacer(minLength: 8)
            if let d = asset.creationDate { DateTimeBadge(date: d) }
            Spacer(minLength: 8)
            actionsMenu
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    private var bottomBar: some View {
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

    private func bar(_ icon: String, _ label: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.shared.light(); action() } label: {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint ?? pal.icon)
                .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
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
            if asset.hasAdjustments { Button { Task { let ok = await MediaActions.revert(asset); if ok { refresh() }; app.showToast(ok ? "Original rétabli" : "Impossible de rétablir") } } label: { Label("Rétablir l’original", systemImage: "arrow.uturn.backward") } }
            Divider()
            Button { Task { if await MediaActions.setHidden([asset], true) { close() } } } label: { Label("Masquer", systemImage: "eye.slash") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(pal.icon)
                .frame(width: 48, height: 48).glass(Circle(), interactive: true).contentShape(Circle())
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
