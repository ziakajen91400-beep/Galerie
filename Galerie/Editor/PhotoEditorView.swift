import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class PhotoEditorModel: ObservableObject {
    let asset: PHAsset
    let session = EditorSession()
    @Published var preview: UIImage?
    @Published var geometrySize: CGSize = .zero
    @Published var thumbs: [String: UIImage] = [:]
    @Published var loading = true
    @Published var error: String?
    @Published var saving = false
    var tab: EditorTab = .adjust
    private var source: CIImage?
    private var previewSrc: CIImage?
    private var input: PHContentEditingInput?
    private var props: [String: Any] = [:]
    private var uti = "public.jpeg"
    private var gen = 0

    init(asset: PHAsset) { self.asset = asset }

    func load() async {
        let result: (PHContentEditingInput?, [AnyHashable: Any]?) = await withCheckedContinuation { c in
            let o = PHContentEditingInputRequestOptions(); o.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: o) { i, info in c.resume(returning: (i, info)) }
        }
        guard let input = result.0, let url = input.fullSizeImageURL,
              let ci = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            error = "Impossible de charger la photo (disponible seulement dans iCloud, ou format non pris en charge)."
            loading = false; return
        }
        self.input = input
        uti = input.uniformTypeIdentifier ?? "public.jpeg"
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] { props = p }
        source = ci
        let prev = ImagePipeline.scaled(ImagePipeline.normalized(ci), maxSide: 1600)
        previewSrc = prev
        loading = false
        session.onChange = { [weak self] in self?.requestRender() }
        requestRender()
        let small = ImagePipeline.scaled(prev, maxSide: 160)
        let t = await Task.detached(priority: .utility) { () -> [String: UIImage] in
            var out: [String: UIImage] = [:]
            for f in ImagePipeline.filters {
                var s = EditState(); s.filterID = f.id
                if let cg = ImagePipeline.cgImage(ImagePipeline.applyFilter(small, s)) { out[f.id] = UIImage(cgImage: cg) }
            }
            return out
        }.value
        thumbs = t
    }

    func requestRender() {
        guard let src = previewSrc else { return }
        gen += 1; let g = gen
        let s = session.showOriginal ? EditState() : session.state
        let tab = self.tab
        Task.detached(priority: .userInitiated) {
            let geo = ImagePipeline.geometry(src, s)
            let out = tab == .crop ? geo : ImagePipeline.applyFilter(ImagePipeline.adjust(ImagePipeline.applyCrop(geo, s), s), s)
            let cg = ImagePipeline.cgImage(out)
            let gs = geo.extent.size
            await MainActor.run {
                guard g == self.gen, let cg else { return }
                self.preview = UIImage(cgImage: cg); self.geometrySize = gs
            }
        }
    }

    func export(forceJPEG: Bool) async throws -> URL {
        guard let source else { throw MediaError.message("Photo non chargée.") }
        let s = session.state, props = self.props
        let uti = forceJPEG ? "public.jpeg" : self.uti
        return try await Task.detached(priority: .userInitiated) { () -> URL in
            let ci = ImagePipeline.render(source, s)
            let cs = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
            guard var cg = ImagePipeline.cgImage(ci, colorSpace: cs) else { throw MediaError.message("Rendu impossible.") }
            cg = AnnotationRenderer.compose(cg, annotations: s.annotations)
            var type = (uti == "public.heic" || uti == "public.png") ? uti : "public.jpeg"
            func ext(_ t: String) -> String { t == "public.heic" ? "heic" : (t == "public.png" ? "png" : "jpg") }
            var url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext(type))
            var dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
            if dest == nil { type = "public.jpeg"; url = url.deletingPathExtension().appendingPathExtension("jpg"); dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) }
            guard let d = dest else { throw MediaError.message("Format d’export indisponible.") }
            var p = props
            for k in [kCGImagePropertyOrientation, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyMakerAppleDictionary] { p.removeValue(forKey: k as String) }
            if var tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] { tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation as String); p[kCGImagePropertyTIFFDictionary as String] = tiff }
            p[kCGImageDestinationLossyCompressionQuality as String] = 0.95
            CGImageDestinationAddImage(d, cg, p as CFDictionary)
            guard CGImageDestinationFinalize(d) else { throw MediaError.message("Écriture du fichier impossible.") }
            return url
        }.value
    }

    func saveCopy() async throws {
        let url = try await export(forceJPEG: false)
        let a = asset
        try await PHPhotoLibrary.shared().performChanges {
            let r = PHAssetCreationRequest.forAsset()
            r.addResource(with: .photo, fileURL: url, options: nil)
            r.creationDate = a.creationDate; r.location = a.location
        }
    }

    func saveReplacing() async throws {
        guard let input else { throw MediaError.message("Entrée d’édition indisponible.") }
        let url = try await export(forceJPEG: true)
        let out = PHContentEditingOutput(contentEditingInput: input)
        let data = try JSONEncoder().encode(session.state)
        out.adjustmentData = PHAdjustmentData(formatIdentifier: "com.perso.galerie.photo", formatVersion: "1.0", data: data)
        try? FileManager.default.removeItem(at: out.renderedContentURL)
        try FileManager.default.copyItem(at: url, to: out.renderedContentURL)
        let a = asset
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest(for: a).contentEditingOutput = out }
    }
}

struct PhotoEditorView: View {
    let asset: PHAsset
    var onSaved: () -> Void
    @StateObject private var model: PhotoEditorModel
    @StateObject private var annotate = AnnotateSettings()
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var tab: EditorTab = .adjust
    @State private var textPoint: CGPoint?
    @State private var textInput = ""
    @State private var confirmClose = false
    @State private var message: String?

    init(asset: PHAsset, onSaved: @escaping () -> Void) {
        self.asset = asset; self.onSaved = onSaved
        _model = StateObject(wrappedValue: PhotoEditorModel(asset: asset))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Color.black
                if let e = model.error { Text(e).gFont(.body).foregroundStyle(.white).multilineTextAlignment(.center).padding() }
                else { EditorCanvas(image: model.preview, session: model.session, tool: annotate, tab: tab, geometrySize: model.geometrySize) { p in textPoint = p; textInput = "" } }
                if model.saving { ProgressView("Enregistrement…").tint(.white).foregroundStyle(.white).padding().glass(RoundedRectangle(cornerRadius: 16)) }
            }.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.horizontal, 8)
            VStack(spacing: 8) {
                panel.frame(minHeight: 120, alignment: .top)
                tabBar
            }.padding(.top, 10)
        }
        .background(pal.bg.ignoresSafeArea())
        .task { await model.load() }
        .onChange(of: tab) { _, t in model.tab = t; model.requestRender() }
        .alert("Texte", isPresented: Binding(get: { textPoint != nil }, set: { if !$0 { textPoint = nil } })) {
            TextField("Ton texte", text: $textInput)
            Button("Ajouter") {
                if let p = textPoint, !textInput.isEmpty {
                    model.session.state.annotations.append(Annotation(kind: .text, points: [p], colorHex: annotate.colorHex, width: annotate.width, text: textInput))
                    model.session.commit(); Haptics.shared.light()
                }
                textPoint = nil
            }
            Button("Annuler", role: .cancel) { textPoint = nil }
        }
        .confirmationDialog("Abandonner les modifications ?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer l’édition", role: .cancel) {}
        }
        .alert("Édition", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }

    @ViewBuilder private var panel: some View {
        switch tab {
        case .adjust: AdjustPanel(session: model.session)
        case .filters: FiltersPanel(session: model.session, thumbs: model.thumbs)
        case .crop: CropPanel(session: model.session, geometrySize: model.geometrySize)
        case .annotate: AnnotatePanel(session: model.session, tool: annotate)
        default: EmptyView()
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach([EditorTab.adjust, .filters, .crop, .annotate]) { t in
                Button { Haptics.shared.selection(); tab = t } label: {
                    VStack(spacing: 2) { Image(systemName: t.icon).font(.system(size: 19)); Text(t.title).font(.system(size: 10, weight: .medium)) }
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(tab == t ? pal.accent : pal.textSecondary)
                }.accessibilityLabel(t.title)
            }
        }.padding(.horizontal, 10).padding(.vertical, 4).glass(Capsule()).padding(.horizontal, 14).padding(.bottom, 4)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassIconButton(system: "xmark", label: "Fermer", size: 40) { model.session.state.isDefault ? dismiss() : (confirmClose = true) }
            Spacer()
            GlassIconButton(system: "arrow.uturn.backward", label: "Annuler", size: 40) { model.session.undo() }.disabled(!model.session.canUndo).opacity(model.session.canUndo ? 1 : 0.4)
            GlassIconButton(system: "arrow.uturn.forward", label: "Rétablir", size: 40) { model.session.redo() }.disabled(!model.session.canRedo).opacity(model.session.canRedo ? 1 : 0.4)
            Image(systemName: "square.split.2x1").font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.icon).frame(width: 40, height: 40).glass(Circle())
                .onLongPressGesture(minimumDuration: 0, maximumDistance: 40, pressing: { p in model.session.showOriginal = p; model.requestRender() }, perform: {})
                .accessibilityLabel("Maintenir pour voir l’original")
            Menu {
                Button { save(replace: true) } label: { Label("Enregistrer (modifie la photo)", systemImage: "square.and.arrow.down") }.disabled(asset.isLive)
                Button { save(replace: false) } label: { Label("Enregistrer une copie", systemImage: "plus.square.on.square") }
            } label: {
                Text("Enregistrer").gFont(.headline).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 40).background(Capsule().fill(pal.accent))
            }.disabled(model.session.state.isDefault || model.saving || model.error != nil)
        }.padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func save(replace: Bool) {
        model.saving = true
        Task {
            do {
                if replace { try await model.saveReplacing() } else { try await model.saveCopy() }
                Haptics.shared.success(); onSaved()
                app.showToast(replace ? "Modifications enregistrées (réversibles dans Photos)" : "Copie enregistrée dans la photothèque")
                model.saving = false; dismiss()
            } catch {
                model.saving = false; Haptics.shared.error()
                message = "Enregistrement impossible : \(error.localizedDescription)"
            }
        }
    }
}
