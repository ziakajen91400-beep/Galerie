import SwiftUI
import Photos
import MapKit
import AVFoundation
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

struct InfoSection: Identifiable { let id = UUID(); let title: String; var rows: [(String, String)] }

@MainActor
final class InfoModel: ObservableObject {
    @Published var sections: [InfoSection] = []
    @Published var loading = true
    @Published var needsNetwork = false
    @Published var placeName: String?
    let asset: PHAsset
    init(_ a: PHAsset) { asset = a }

    func load(network: Bool, geocode: Bool) async {
        loading = true
        var s: [InfoSection] = []
        var general: [(String, String)] = []
        if let d = asset.creationDate { general.append(("Prise de vue", d.formatted(date: .complete, time: .standard))) }
        if let m = asset.modificationDate, asset.hasAdjustments { general.append(("Modifié le", m.formatted(date: .abbreviated, time: .shortened))) }
        general.append(("Type", kind))
        if let r = asset.primaryResource {
            general.append(("Nom du fichier", r.originalFilename))
            if let t = UTType(r.uniformTypeIdentifier) { general.append(("Format", t.preferredFilenameExtension?.uppercased() ?? t.identifier)) }
        }
        general.append(("Dimensions", "\(asset.pixelWidth) × \(asset.pixelHeight) px" + (asset.isVideo ? "" : String(format: " (%.1f Mpx)", Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000))))
        if asset.isHDRPhoto { general.append(("HDR", "Oui")) }
        if asset.isFavorite { general.append(("Favori", "Oui")) }
        s.append(InfoSection(title: "Général", rows: general))

        if asset.isVideo { await loadVideo(&s, network: network) } else { await loadPhoto(&s, network: network) }

        if asset.hasValidLocation, let l = asset.location {
            var rows = [("Coordonnées", String(format: "%.5f°, %.5f°", l.coordinate.latitude, l.coordinate.longitude))]
            if l.verticalAccuracy >= 0 { rows.append(("Altitude", String(format: "%.0f m", l.altitude))) }
            if geocode, let p = try? await CLGeocoder().reverseGeocodeLocation(l).first {
                let name = [p.name, p.locality, p.administrativeArea, p.country].compactMap { $0 }.joined(separator: ", ")
                if !name.isEmpty { rows.insert(("Lieu", name), at: 0); placeName = name }
            }
            s.append(InfoSection(title: "Localisation", rows: rows))
        }
        let meta = MetadataStore.shared.get(asset.localIdentifier)
        if !meta.isEmpty {
            var r: [(String, String)] = []
            if !meta.caption.isEmpty { r.append(("Légende", meta.caption)) }
            if !meta.keywords.isEmpty { r.append(("Mots-clés", meta.keywords.joined(separator: ", "))) }
            if !meta.note.isEmpty { r.append(("Note", meta.note)) }
            s.append(InfoSection(title: "Dans Galerie", rows: r))
        }
        sections = s
        loading = false
    }

    private var kind: String {
        if asset.isVideo { return asset.mediaSubtypes.contains(.videoHighFrameRate) ? "Vidéo ralenti" : "Vidéo" }
        var t = [String]()
        if asset.isLive { t.append("Live Photo") }
        if asset.isPanorama { t.append("Panorama") }
        if asset.isScreenshot { t.append("Capture d’écran") }
        if asset.mediaSubtypes.contains(.photoDepthEffect) { t.append("Portrait") }
        return t.isEmpty ? "Photo" : t.joined(separator: ", ")
    }

    private func loadPhoto(_ s: inout [InfoSection], network: Bool) async {
        let url: URL? = await withCheckedContinuation { c in
            let o = PHContentEditingInputRequestOptions(); o.isNetworkAccessAllowed = network
            asset.requestContentEditingInput(with: o) { input, _ in c.resume(returning: input?.fullSizeImageURL) }
        }
        guard let url else { needsNetwork = !network; return }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            s[0].rows.append(("Taille du fichier", Fmt.bytes(Int64(size))))
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return }
        let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        var cam: [(String, String)] = []
        let make = tiff[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff[kCGImagePropertyTIFFModel as String] as? String
        if let model { cam.append(("Appareil", [make, model].compactMap { $0 }.filter { !model.hasPrefix($0) || $0 == model }.joined(separator: " "))) }
        if let lens = exif[kCGImagePropertyExifLensModel as String] as? String {
            cam.append(("Objectif", lens))
            let l = lens.lowercased()
            if l.contains("front") || l.contains("avant") { cam.append(("Caméra", "Avant")) } else if l.contains("back") || l.contains("arrière") { cam.append(("Caméra", "Arrière")) }
        }
        if let f = exif[kCGImagePropertyExifFocalLength as String] as? Double {
            var v = String(format: "%.1f mm", f)
            if let f35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double { v += String(format: " (équiv. %.0f mm)", f35) }
            cam.append(("Focale", v))
        }
        if let a = exif[kCGImagePropertyExifFNumber as String] as? Double { cam.append(("Ouverture", String(format: "ƒ/%.1f", a))) }
        if let t = exif[kCGImagePropertyExifExposureTime as String] as? Double, t > 0 { cam.append(("Vitesse d’obturation", Fmt.shutter(t))) }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first { cam.append(("ISO", "\(iso)")) }
        if let b = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double { cam.append(("Correction d’exposition", String(format: "%+.1f IL", b))) }
        if let sw = tiff[kCGImagePropertyTIFFSoftware as String] as? String { cam.append(("Logiciel", sw)) }
        if let cs = p[kCGImagePropertyProfileName as String] as? String { cam.append(("Profil colorimétrique", cs)) }
        if !cam.isEmpty { s.append(InfoSection(title: "Appareil et exposition", rows: cam)) }
    }

    private func loadVideo(_ s: inout [InfoSection], network: Bool) async {
        let av: AVAsset? = await withCheckedContinuation { c in
            let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = network
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { a, _, _ in c.resume(returning: a) }
        }
        guard let av else { needsNetwork = !network; return }
        var rows: [(String, String)] = [("Durée", Fmt.duration(asset.duration))]
        if let u = (av as? AVURLAsset)?.url, let size = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize { s[0].rows.append(("Taille du fichier", Fmt.bytes(Int64(size)))) }
        if let t = try? await av.loadTracks(withMediaType: .video).first {
            if let fps = try? await t.load(.nominalFrameRate), fps > 0 { rows.append(("Images par seconde", String(format: "%.0f i/s", fps))) }
            if let fds = try? await t.load(.formatDescriptions), let fd = fds.first {
                rows.append(("Codec vidéo", Self.codecName(CMFormatDescriptionGetMediaSubType(fd))))
            }
            if let ch = try? await t.load(.mediaCharacteristics), ch.contains(.containsHDRVideo) { rows.append(("HDR", "Oui (contenu HDR détecté)")) }
            if let br = try? await t.load(.estimatedDataRate), br > 0 { rows.append(("Débit", String(format: "%.1f Mb/s", br / 1_000_000))) }
        }
        if let a = try? await av.loadTracks(withMediaType: .audio), a.isEmpty { rows.append(("Audio", "Aucune piste audio")) }
        s.append(InfoSection(title: "Vidéo", rows: rows))
    }

    static func codecName(_ f: FourCharCode) -> String {
        switch f {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC (H.265)"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes422HQ: return "Apple ProRes"
        default:
            let b = [UInt8((f >> 24) & 255), UInt8((f >> 16) & 255), UInt8((f >> 8) & 255), UInt8(f & 255)]
            return String(bytes: b, encoding: .ascii) ?? "Inconnu"
        }
    }
}

struct InfoSheet: View {
    let asset: PHAsset
    @StateObject private var model: InfoModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var showMap = false

    init(asset: PHAsset) { self.asset = asset; _model = StateObject(wrappedValue: InfoModel(asset)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.loading { ProgressView().padding() }
                    if asset.hasValidLocation, let l = asset.location {
                        Button { showMap = true } label: {
                            Map(initialPosition: .region(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)), interactionModes: []) {
                                Marker("", coordinate: l.coordinate)
                            }
                            .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).allowsHitTesting(false)
                        }.accessibilityLabel("Ouvrir la carte")
                        if !settings.prefs.allowGeocoding {
                            Text("Le nom du lieu n’est pas affiché : active « Noms de lieux » dans Réglages › Confidentialité (les coordonnées sont alors envoyées à Apple pour être converties).").gFont(.small).foregroundStyle(pal.textSecondary)
                        }
                    }
                    ForEach(model.sections) { sec in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: sec.title)
                            GCard {
                                VStack(spacing: 10) {
                                    ForEach(Array(sec.rows.enumerated()), id: \.offset) { i, r in
                                        InfoRow(title: r.0, value: r.1)
                                        if i < sec.rows.count - 1 { Divider2() }
                                    }
                                }
                            }
                        }
                    }
                    if model.needsNetwork {
                        GCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("L’original n’est pas sur l’iPhone : les détails (EXIF, taille) nécessitent de le télécharger depuis iCloud.").gFont(.caption)
                                Button("Télécharger les détails") { Task { await model.load(network: true, geocode: settings.prefs.allowGeocoding) } }
                            }
                        }
                    }
                    Text("Les informations absentes ne sont pas affichées : Galerie n’en invente aucune.").gFont(.small).foregroundStyle(pal.textSecondary)
                }.padding()
            }
            .background(pal.bg)
            .navigationTitle("Informations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(isPresented: $showMap) { LocationDetailView(asset: asset) }
        }
        .task { await model.load(network: false, geocode: settings.prefs.allowGeocoding) }
    }
}

// MARK: - Carte d’un média
struct LocationDetailView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    @State private var googleAvailable = false

    var body: some View {
        NavigationStack {
            if let l = asset.location, asset.hasValidLocation {
                ZStack(alignment: .bottom) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                        Annotation("", coordinate: l.coordinate) {
                            AssetThumb(asset: asset, size: CGSize(width: 56, height: 56)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2)).shadow(radius: 4)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { openInMaps(l) } label: { Label("Plans", systemImage: "map").frame(maxWidth: .infinity).padding(.vertical, 12) }
                        if googleAvailable { Button { openGoogle(l) } label: { Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity).padding(.vertical, 12) } }
                    }
                    .gFont(.headline).glass(Capsule(), interactive: true).padding()
                }
            } else {
                EmptyState(icon: "mappin.slash", title: "Pas de localisation", message: "Ce média ne contient pas de coordonnées GPS.")
            }
        }
        .overlay(alignment: .topTrailing) { GlassIconButton(system: "xmark", label: "Fermer") { dismiss() }.padding() }
        .onAppear { if let u = URL(string: "comgooglemaps://") { googleAvailable = UIApplication.shared.canOpenURL(u) } }
    }
    private func openInMaps(_ l: CLLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: l.coordinate))
        item.name = "Lieu de prise de vue"
        item.openInMaps()
    }
    private func openGoogle(_ l: CLLocation) {
        if let u = URL(string: "comgooglemaps://?q=\(l.coordinate.latitude),\(l.coordinate.longitude)") { UIApplication.shared.open(u) }
    }
}

// MARK: - Édition date / lieu / légende
struct DateEditSheet: View {
    let asset: PHAsset
    var onDone: () -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    @EnvironmentObject private var app: AppState
    init(asset: PHAsset, onDone: @escaping () -> Void) { self.asset = asset; self.onDone = onDone; _date = State(initialValue: asset.creationDate ?? Date()) }
    var body: some View {
        NavigationStack {
            VStack { DatePicker("Date et heure", selection: $date, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical); Spacer() }
                .padding().background(pal.bg)
                .navigationTitle("Date et heure").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                        Task { let ok = await MediaActions.setDate(asset, date); app.showToast(ok ? "Date modifiée" : "Modification refusée"); if ok { onDone() }; dismiss() }
                    } }
                }
        }
    }
}

struct LocationEditSheet: View {
    let asset: PHAsset
    var onDone: () -> Void
    @State private var coord: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    init(asset: PHAsset, onDone: @escaping () -> Void) { self.asset = asset; self.onDone = onDone; _coord = State(initialValue: asset.hasValidLocation ? asset.location?.coordinate : nil) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(initialPosition: coord.map { .region(MKCoordinateRegion(center: $0, latitudinalMeters: 3000, longitudinalMeters: 3000)) } ?? .automatic) {
                        if let coord { Marker("Nouveau lieu", coordinate: coord) }
                    }
                    .onTapGesture { p in if let c = proxy.convert(p, from: .local) { Haptics.shared.light(); coord = c } }
                }
                Text(coord == nil ? "Touche la carte pour choisir un lieu" : "Touche ailleurs pour déplacer le repère").gFont(.caption)
                    .padding(10).glass(Capsule()).padding()
            }
            .navigationTitle("Localisation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    if asset.hasValidLocation { Button("Retirer", role: .destructive) { save(nil) } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { if let c = coord { save(CLLocation(latitude: c.latitude, longitude: c.longitude)) } }.disabled(coord == nil) }
            }
        }
    }
    private func save(_ l: CLLocation?) {
        Task { let ok = await MediaActions.setLocation(asset, l); app.showToast(ok ? "Localisation modifiée" : "Modification refusée"); if ok { onDone() }; dismiss() }
    }
}

struct MetaEditSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    @State private var caption = ""
    @State private var keywords = ""
    @State private var note = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Légende"); field(TextField("Ajouter une légende", text: $caption, axis: .vertical))
                    SectionTitle(text: "Mots-clés (séparés par des virgules)"); field(TextField("vacances, famille…", text: $keywords))
                    SectionTitle(text: "Note personnelle"); field(TextField("Note", text: $note, axis: .vertical).lineLimit(3...8))
                    Text("Ces informations sont conservées dans Galerie sur cet iPhone (PhotoKit ne permet pas de les écrire dans Photos) et servent à la recherche.").gFont(.small).foregroundStyle(pal.textSecondary)
                }.padding()
            }
            .background(pal.bg)
            .navigationTitle("Légende et mots-clés").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                    let kws = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    MetadataStore.shared.set(asset.localIdentifier, LocalMeta(caption: caption, keywords: kws, note: note))
                    Haptics.shared.success(); dismiss()
                } }
            }
        }
        .onAppear { let m = MetadataStore.shared.get(asset.localIdentifier); caption = m.caption; keywords = m.keywords.joined(separator: ", "); note = m.note }
    }
    private func field<V: View>(_ v: V) -> some View { v.gFont(.body).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(pal.card)) }
}
