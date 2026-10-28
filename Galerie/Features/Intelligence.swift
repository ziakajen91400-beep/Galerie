import SwiftUI
import Photos
import Vision

struct IndexEntry: Codable, Equatable {
    var text: String = ""
    var qr = false
    var labels: [String] = []
    var isDocument: Bool { text.count >= 80 }
}

/// Analyse 100 % locale (Vision) : texte, QR codes et objets. Aucune image ne quitte l’appareil.
@MainActor
final class IntelligenceIndex: ObservableObject {
    @Published private(set) var entries: [String: IndexEntry] = [:]
    @Published private(set) var running = false
    @Published private(set) var processed = 0
    @Published private(set) var target = 0
    private var task: Task<Void, Never>?
    private var url: URL { appSupportURL().appendingPathComponent("vision-index.json") }

    init() { if let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([String: IndexEntry].self, from: d) { entries = e } }

    static let fr2en: [String: [String]] = [
        "chat": ["cat"], "chien": ["dog"], "plage": ["beach"], "voiture": ["car", "vehicle"], "fleur": ["flower"], "fleurs": ["flower"],
        "montagne": ["mountain"], "ciel": ["sky"], "mer": ["sea", "water", "ocean"], "océan": ["ocean", "water"], "arbre": ["tree"],
        "neige": ["snow"], "nourriture": ["food"], "repas": ["food"], "bâtiment": ["building", "structure"], "personne": ["people", "person"],
        "oiseau": ["bird"], "bateau": ["boat", "watercraft"], "vélo": ["bicycle"], "forêt": ["forest", "tree"], "lac": ["lake", "water"],
        "soleil": ["sun", "sunset"], "coucher": ["sunset"], "ville": ["city", "building"], "livre": ["book"], "écran": ["screen"], "document": ["document"]
    ]

    func match(_ query: String) -> Set<String> {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard q.count >= 2 else { return [] }
        let terms = Self.fr2en[query.lowercased()] ?? []
        var out = Set<String>()
        for (id, e) in entries {
            if e.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) { out.insert(id); continue }
            if e.labels.contains(where: { l in l.contains(q) || terms.contains(where: { l.contains($0) }) }) { out.insert(id) }
        }
        return out
    }
    var documentIDs: [String] { entries.filter { $0.value.isDocument }.map(\.key) }
    var qrIDs: [String] { entries.filter { $0.value.qr }.map(\.key) }

    func start(limit: Int) {
        guard !running else { return }
        running = true; processed = 0
        let existing = entries
        task = Task.detached(priority: .background) { [weak self] in
            let o = PHFetchOptions()
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            o.fetchLimit = limit
            let r = PHAsset.fetchAssets(with: o)
            var todo: [PHAsset] = []
            r.enumerateObjects { a, _, _ in if existing[a.localIdentifier] == nil { todo.append(a) } }
            await MainActor.run { self?.target = todo.count }
            var batch: [String: IndexEntry] = [:]
            let mgr = PHImageManager.default()
            for (n, a) in todo.enumerated() {
                if Task.isCancelled { break }
                let ro = PHImageRequestOptions(); ro.isSynchronous = true; ro.deliveryMode = .highQualityFormat
                ro.isNetworkAccessAllowed = false   // jamais de téléchargement iCloud pour l’analyse
                var cg: CGImage?
                mgr.requestImage(for: a, targetSize: CGSize(width: 800, height: 800), contentMode: .aspectFit, options: ro) { img, _ in cg = img?.cgImage }
                if let cg {
                    batch[a.localIdentifier] = IntelligenceIndex.analyze(cg)
                }
                if batch.count >= 25 || n == todo.count - 1 {
                    let b = batch; batch = [:]
                    await MainActor.run { self?.merge(b, processed: n + 1) }
                }
            }
            await MainActor.run { self?.finish() }
        }
    }
    func stop() { task?.cancel() }
    func clear() { stop(); entries = [:]; try? FileManager.default.removeItem(at: url); processed = 0; target = 0 }

    private func merge(_ b: [String: IndexEntry], processed p: Int) {
        entries.merge(b) { _, n in n }; processed = p; save()
    }
    private func finish() { running = false; save() }
    private func save() { if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url, options: .atomic) } }

    nonisolated static func analyze(_ cg: CGImage) -> IndexEntry {
        var e = IndexEntry()
        let text = VNRecognizeTextRequest(); text.recognitionLevel = .fast; text.recognitionLanguages = ["fr-FR", "en-US"]
        let codes = VNDetectBarcodesRequest()
        let cls = VNClassifyImageRequest()
        let h = VNImageRequestHandler(cgImage: cg, options: [:])
        try? h.perform([text, codes, cls])
        e.text = String((text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").prefix(1500))
        e.qr = (codes.results ?? []).contains { $0.symbology == .qr }
        e.labels = (cls.results ?? []).filter { $0.confidence > 0.55 }.prefix(6).map { $0.identifier.lowercased() }
        return e
    }
}
