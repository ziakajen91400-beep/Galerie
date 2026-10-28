import SwiftUI
import Photos
import AVFoundation
import AVKit

struct PlainPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController(); c.player = player; c.showsPlaybackControls = false; c.videoGravity = .resizeAspect; return c
    }
    func updateUIViewController(_ c: AVPlayerViewController, context: Context) {}
}

@MainActor
final class VideoEditorModel: ObservableObject {
    let asset: PHAsset
    let session = EditorSession()
    @Published var loading = true
    @Published var error: String?
    @Published var duration: Double = 0
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var current: Double = 0
    @Published var isPlaying = false
    @Published var strip: [UIImage] = []
    @Published var preview: UIImage?
    @Published var geometrySize: CGSize = .zero
    @Published var thumbs: [String: UIImage] = [:]
    @Published var volume: Double = 1
    @Published var muted = false
    @Published var exporting = false
    @Published var progress: Double = 0
    @Published var canvasTab: EditorTab = .trim
    let player = AVPlayer()
    private(set) var avAsset: AVAsset?
    private var natural = CGSize(width: 1920, height: 1080)
    private var posterCI: CIImage?
    private var timeObs: Any?
    private var compTask: Task<Void, Never>?
    private var exportSession: AVAssetExportSession?
    private var gen = 0

    init(asset: PHAsset) { self.asset = asset }

    func load() async {
        let av: AVAsset? = await withCheckedContinuation { c in
            let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { a, _, _ in c.resume(returning: a) }
        }
        guard let av, let dur = try? await av.load(.duration), dur.seconds > 0 else { error = "Vidéo indisponible (iCloud ou format non pris en charge)."; loading = false; return }
        avAsset = av; duration = dur.seconds; end = duration
        if let t = try? await av.loadTracks(withMediaType: .video).first, let size = try? await t.load(.naturalSize), let tr = try? await t.load(.preferredTransform) {
            let s = size.applying(tr); natural = CGSize(width: abs(s.width), height: abs(s.height))
        }
        let item = AVPlayerItem(asset: av)
        player.replaceCurrentItem(with: item)
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                self.current = t.seconds
                if self.isPlaying && t.seconds >= self.end - 0.03 { self.player.pause(); self.isPlaying = false; await self.seek(self.start) }
            }
        }
        // image d’aperçu (première image) pour le recadrage et les filtres
        let gen = AVAssetImageGenerator(asset: av); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 1600, height: 1600)
        if let r = try? await gen.image(at: .zero) {
            let ci = ImagePipeline.normalized(CIImage(cgImage: r.image)); posterCI = ci
            session.onChange = { [weak self] in self?.stateChanged() }
            requestRender()
            let small = ImagePipeline.scaled(ci, maxSide: 160)
            thumbs = await Task.detached(priority: .utility) { () -> [String: UIImage] in
                var out: [String: UIImage] = [:]
                for f in ImagePipeline.filters { var s = EditState(); s.filterID = f.id; if let cg = ImagePipeline.cgImage(ImagePipeline.applyFilter(small, s)) { out[f.id] = UIImage(cgImage: cg) } }
                return out
            }.value
        }
        loading = false
        await makeStrip(av)
    }

    private func makeStrip(_ av: AVAsset) async {
        let g = AVAssetImageGenerator(asset: av); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 160, height: 160)
        var imgs: [UIImage] = []
        for i in 0..<8 {
            let t = CMTime(seconds: duration * (Double(i) + 0.5) / 8, preferredTimescale: 600)
            if let r = try? await g.image(at: t) { imgs.append(UIImage(cgImage: r.image)) }
        }
        strip = imgs
    }

    func seek(_ t: Double) async { await player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); current = t }
    func togglePlay() {
        if isPlaying { player.pause(); isPlaying = false }
        else { if current >= end - 0.05 || current < start { Task { await seek(start); player.play() } } else { player.play() }; isPlaying = true; applyVolume() }
    }
    func stop() { player.pause(); isPlaying = false; exportSession?.cancelExport(); if let t = timeObs { player.removeTimeObserver(t); timeObs = nil } }

    func stateChanged() { requestRender(); scheduleComposition() }

    func requestRender() {
        guard let src = posterCI else { return }
        gen += 1; let g = gen
        let s = session.showOriginal ? EditState() : session.state
        let tab = canvasTab
        Task.detached(priority: .userInitiated) {
            let geo = ImagePipeline.geometry(src, s)
            let out = tab == .crop ? geo : ImagePipeline.applyFilter(ImagePipeline.adjust(ImagePipeline.applyCrop(geo, s), s), s)
            let cg = ImagePipeline.cgImage(out); let gs = geo.extent.size
            await MainActor.run { guard g == self.gen, let cg else { return }; self.preview = UIImage(cgImage: cg); self.geometrySize = gs }
        }
    }

    func makeComposition(_ av: AVAsset, _ s: EditState) -> AVVideoComposition? {
        guard s.hasVisualEdits else { return nil }
        let size = s.outputSize(for: natural)
        let comp = AVMutableVideoComposition(asset: av, applyingCIFiltersWithHandler: { req in
            let out = ImagePipeline.render(ImagePipeline.normalized(req.sourceImage), s).cropped(to: CGRect(origin: .zero, size: size))
            req.finish(with: out, context: nil)
        })
        comp.renderSize = size
        return comp
    }

    func scheduleComposition() {
        compTask?.cancel()
        compTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let av = avAsset else { return }
            player.currentItem?.videoComposition = makeComposition(av, session.state)
        }
    }

    func applyVolume() { player.volume = muted ? 0 : Float(min(volume, 1)) }

    private func audioMix(for av: AVAsset) async -> AVAudioMix? {
        guard muted || volume != 1, let tracks = try? await av.loadTracks(withMediaType: .audio), !tracks.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { t in
            let p = AVMutableAudioMixInputParameters(track: t); p.setVolume(muted ? 0 : Float(volume), at: .zero); return p
        }
        return mix
    }

    /// Exporte la séquence (découpage + réglages + audio) vers `url`.
    func export(to url: URL) async throws {
        guard let av = avAsset else { throw MediaError.message("Vidéo non chargée.") }
        try? FileManager.default.removeItem(at: url)
        guard let es = AVAssetExportSession(asset: av, presetName: AVAssetExportPresetHighestQuality) else { throw MediaError.message("Export non disponible pour cette vidéo.") }
        es.outputURL = url; es.outputFileType = .mov
        es.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        es.videoComposition = makeComposition(av, session.state)
        es.audioMix = await audioMix(for: av)
        exportSession = es; exporting = true; progress = 0
        let poll = Task { while !Task.isCancelled { progress = Double(es.progress); try? await Task.sleep(nanoseconds: 200_000_000) } }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in es.exportAsynchronously { c.resume() } }
        poll.cancel(); exporting = false
        switch es.status {
        case .completed: return
        case .cancelled: throw MediaError.message("Export annulé.")
        default: throw MediaError.message(es.error?.localizedDescription ?? "Échec de l’export (espace disque insuffisant ou vidéo non compatible).")
        }
    }

    func saveCopy() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try await export(to: url)
        let a = asset
        try await PHPhotoLibrary.shared().performChanges {
            let r = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            r?.creationDate = a.creationDate; r?.location = a.location
        }
    }

    func saveReplacing() async throws {
        let input: PHContentEditingInput? = await withCheckedContinuation { c in
            let o = PHContentEditingInputRequestOptions(); o.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: o) { i, _ in c.resume(returning: i) }
        }
        guard let input else { throw MediaError.message("Entrée d’édition indisponible.") }
        let out = PHContentEditingOutput(contentEditingInput: input)
        try await export(to: out.renderedContentURL)
        out.adjustmentData = PHAdjustmentData(formatIdentifier: "com.perso.galerie.video", formatVersion: "1.0", data: (try? JSONEncoder().encode(session.state)) ?? Data())
        let a = asset
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest(for: a).contentEditingOutput = out }
    }
    func cancelExport() { exportSession?.cancelExport() }
}

struct TrimBar: View {
    @ObservedObject var model: VideoEditorModel
    @Environment(\.pal) private var pal
    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let x0 = W * model.start / max(model.duration, 0.1), x1 = W * model.end / max(model.duration, 0.1)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) { ForEach(Array(model.strip.enumerated()), id: \.offset) { _, i in Image(uiImage: i).resizable().scaledToFill().frame(width: W / CGFloat(max(model.strip.count, 1)), height: 52).clipped() } }
                    .frame(width: W, height: 52, alignment: .leading).background(pal.card).clipShape(RoundedRectangle(cornerRadius: 8))
                Rectangle().fill(Color.black.opacity(0.55)).frame(width: x0, height: 52)
                Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(0, W - x1), height: 52).offset(x: x1)
                RoundedRectangle(cornerRadius: 8).stroke(pal.accent, lineWidth: 3).frame(width: max(x1 - x0, 6), height: 52).offset(x: x0)
                Rectangle().fill(Color.white).frame(width: 2, height: 60).offset(x: min(max(W * model.current / max(model.duration, 0.1), 0), W))
                handle.offset(x: x0 - 8).gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    model.start = min(max(0, v.location.x / W * model.duration + 0), model.end - 0.5); Task { await model.seek(model.start) }
                }.onEnded { _ in Haptics.shared.light() })
                handle.offset(x: x1 - 8).gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    model.end = max(min(model.duration, v.location.x / W * model.duration), model.start + 0.5); Task { await model.seek(model.end) }
                }.onEnded { _ in Haptics.shared.light() })
            }
        }.frame(height: 64)
    }
    private var handle: some View { RoundedRectangle(cornerRadius: 4).fill(pal.accent).frame(width: 16, height: 64).overlay(Image(systemName: "line.3.horizontal").font(.system(size: 8)).rotationEffect(.degrees(90)).foregroundStyle(.white)) }
}

struct VideoEditorView: View {
    let asset: PHAsset
    var onSaved: () -> Void
    @StateObject private var model: VideoEditorModel
    @StateObject private var dummy = AnnotateSettings()
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: EditorTab = .trim
    @State private var message: String?
    @State private var confirmClose = false

    init(asset: PHAsset, onSaved: @escaping () -> Void) { self.asset = asset; self.onSaved = onSaved; _model = StateObject(wrappedValue: VideoEditorModel(asset: asset)) }

    private var edited: Bool { !model.session.state.isDefault || model.start > 0.01 || model.end < model.duration - 0.01 || model.muted || model.volume != 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Color.black
                if let e = model.error { Text(e).foregroundStyle(.white).multilineTextAlignment(.center).padding() }
                else if model.loading { ProgressView().tint(.white) }
                else if tab == .crop { EditorCanvas(image: model.preview, session: model.session, tool: dummy, tab: .crop, geometrySize: model.geometrySize) { _ in } }
                else { PlainPlayer(player: model.player) }
                if model.exporting {
                    VStack(spacing: 10) { ProgressView(value: model.progress).tint(.white); Text("Export \(Int(model.progress * 100)) %").gFont(.caption).foregroundStyle(.white)
                        Button("Annuler l’export") { model.cancelExport() }.foregroundStyle(.white) }.padding(20).glass(RoundedRectangle(cornerRadius: 18)).frame(maxWidth: 260)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.horizontal, 8)
            transport
            VStack(spacing: 8) { panel.frame(minHeight: 110, alignment: .top); tabBar }.padding(.top, 6)
        }
        .background(pal.bg.ignoresSafeArea())
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, p in if p != .active, model.isPlaying { model.togglePlay() } }
        .onChange(of: tab) { _, t in model.canvasTab = t; model.requestRender() }
        .onChange(of: model.volume) { _, _ in model.applyVolume() }
        .onChange(of: model.muted) { _, _ in model.applyVolume() }
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }; Button("Continuer", role: .cancel) {}
        }
        .alert("Édition vidéo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { Haptics.shared.light(); model.togglePlay() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)).frame(width: 44, height: 44).glass(Circle(), interactive: true) }
                .accessibilityLabel(model.isPlaying ? "Pause" : "Lecture")
            Slider(value: Binding(get: { min(max(model.current, model.start), model.end) }, set: { v in Task { await model.seek(v) } }), in: model.start...max(model.end, model.start + 0.1))
            Text("\(Fmt.duration(max(0, model.current - model.start))) / \(Fmt.duration(model.end - model.start))").gFont(.small).monospacedDigit()
        }.padding(.horizontal, 14).padding(.top, 8)
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .trim:
            VStack(spacing: 6) {
                TrimBar(model: model).padding(.horizontal, 22)
                Text("Début \(Fmt.duration(model.start)) · Fin \(Fmt.duration(model.end)) · Durée \(Fmt.duration(model.end - model.start))").gFont(.small).foregroundStyle(pal.textSecondary)
            }
        case .adjust: AdjustPanel(session: model.session)
        case .filters: FiltersPanel(session: model.session, thumbs: model.thumbs)
        case .crop: CropPanel(session: model.session, geometrySize: model.geometrySize)
        case .audio:
            VStack(spacing: 10) {
                ToggleRow(title: "Couper le son", isOn: $model.muted).padding(.horizontal, 14)
                HStack { Image(systemName: "speaker.fill"); Slider(value: $model.volume, in: 0...2); Image(systemName: "speaker.wave.3.fill"); Text("\(Int(model.volume * 100)) %").gFont(.small).frame(width: 46) }.padding(.horizontal, 14).disabled(model.muted)
                Text("Le volume au-delà de 100 % s’applique à l’export. Les mixages audio d’Apple (Studio, Cinématique…) ne sont pas reproduits.").gFont(.small).foregroundStyle(pal.textSecondary).padding(.horizontal, 14)
            }
        default: EmptyView()
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach([EditorTab.trim, .adjust, .filters, .crop, .audio]) { t in
                Button { Haptics.shared.selection(); if model.isPlaying { model.togglePlay() }; tab = t } label: {
                    VStack(spacing: 2) { Image(systemName: t.icon).font(.system(size: 18)); Text(t.title).font(.system(size: 10, weight: .medium)) }
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(tab == t ? pal.accent : pal.textSecondary)
                }
            }
        }.padding(.horizontal, 10).padding(.vertical, 4).glass(Capsule()).padding(.horizontal, 14).padding(.bottom, 4)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(system: "xmark", label: "Fermer", size: 40) { if model.exporting { return }; edited ? (confirmClose = true) : dismiss() }
            Spacer()
            GlassIconButton(system: "arrow.uturn.backward", label: "Annuler", size: 40) { model.session.undo() }.disabled(!model.session.canUndo).opacity(model.session.canUndo ? 1 : 0.4)
            GlassIconButton(system: "arrow.uturn.forward", label: "Rétablir", size: 40) { model.session.redo() }.disabled(!model.session.canRedo).opacity(model.session.canRedo ? 1 : 0.4)
            Menu {
                Button { save(replace: true) } label: { Label("Enregistrer (modifie la vidéo)", systemImage: "square.and.arrow.down") }
                Button { save(replace: false) } label: { Label("Enregistrer une copie", systemImage: "plus.square.on.square") }
            } label: { Text("Enregistrer").gFont(.headline).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 40).background(Capsule().fill(pal.accent)) }
                .disabled(!edited || model.exporting || model.error != nil)
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func save(replace: Bool) {
        if model.isPlaying { model.togglePlay() }
        Task {
            do {
                if replace { try await model.saveReplacing() } else { try await model.saveCopy() }
                Haptics.shared.success(); onSaved()
                app.showToast(replace ? "Vidéo modifiée (réversible dans Photos)" : "Copie enregistrée dans la photothèque")
                dismiss()
            } catch { Haptics.shared.error(); message = error.localizedDescription }
        }
    }
}
