import SwiftUI
import UniformTypeIdentifiers
import CoreText

enum FontRole { case largeTitle, title, headline, body, caption, small }

struct FontChoice: Identifiable, Hashable {
    let id: String          // "system", "rounded", "serif", "mono" ou "name:<PostScript/famille>" ou "custom:<ps>"
    let label: String
    let family: String?     // nom pour Font.custom
    let design: Font.Design?
    var isImported = false
}

struct ImportedFont: Codable, Identifiable, Equatable {
    var id: String { postScriptName }
    var postScriptName: String
    var family: String
    var fileName: String
}

@MainActor
final class FontStore: ObservableObject {
    private static let key = "galerie.importedFonts.v1"
    @Published private(set) var imported: [ImportedFont] = []
    @Published var importError: String?

    static let builtInFamilies = ["Avenir Next", "Avenir", "Helvetica Neue", "Futura", "Gill Sans", "Optima", "Trebuchet MS", "Verdana",
        "Georgia", "Palatino", "Baskerville", "Didot", "Hoefler Text", "Cochin", "Iowan Old Style", "Charter", "Times New Roman",
        "American Typewriter", "Courier New", "Menlo", "Copperplate", "Marker Felt", "Noteworthy", "Chalkboard SE", "Snell Roundhand", "Bradley Hand", "Papyrus", "Zapfino"]

    private var fontsDir: URL { appSupportURL("Fonts") }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let l = try? JSONDecoder().decode([ImportedFont].self, from: d) {
            imported = l
            for f in l { register(fontsDir.appendingPathComponent(f.fileName)) }
        }
    }

    var choices: [FontChoice] {
        var c: [FontChoice] = [
            FontChoice(id: "system", label: "Système (SF Pro)", family: nil, design: .default),
            FontChoice(id: "rounded", label: "Arrondie (SF Rounded)", family: nil, design: .rounded),
            FontChoice(id: "serif", label: "Serif (New York)", family: nil, design: .serif),
            FontChoice(id: "mono", label: "Monospace (SF Mono)", family: nil, design: .monospaced),
        ]
        let available = Set(UIFont.familyNames)
        for f in Self.builtInFamilies where available.contains(f) {
            c.append(FontChoice(id: "name:" + f, label: f, family: f, design: nil))
        }
        for f in imported { c.append(FontChoice(id: "custom:" + f.postScriptName, label: f.family + " (importée)", family: f.postScriptName, design: nil, isImported: true)) }
        return c
    }
    func choice(_ id: String) -> FontChoice { choices.first { $0.id == id } ?? choices[0] }

    func font(_ role: FontRole, prefs: Prefs, scale: CGFloat) -> Font {
        let (fid, base, w): (String, CGFloat, Font.Weight) = {
            switch role {
            case .largeTitle: return (prefs.fontTitle, 30, .bold)
            case .title: return (prefs.fontTitle, 21, .semibold)
            case .headline: return (prefs.fontTitle, 17, .semibold)
            case .body: return (prefs.fontBody, 16, prefs.fontWeight.weight)
            case .caption: return (prefs.fontCaption, 12.5, prefs.fontWeight.weight)
            case .small: return (prefs.fontCaption, 11, prefs.fontWeight.weight)
            }
        }()
        let size = base * scale * prefs.textScale
        let c = choice(fid)
        if let fam = c.family { return Font.custom(fam, fixedSize: size).weight(w) }
        return Font.system(size: size, weight: w, design: c.design ?? .default)
    }

    // MARK: Import
    func importFont(from url: URL) {
        importError = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["ttf", "otf"].contains(ext) else { importError = "Format non pris en charge (TTF ou OTF uniquement)."; return }
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size < 20_000_000 else { importError = "Fichier vide ou trop volumineux (max 20 Mo)."; return }
            let data = try Data(contentsOf: url)
            guard let provider = CGDataProvider(data: data as CFData), let cg = CGFont(provider),
                  let ps = cg.postScriptName as String? else { importError = "Fichier de police invalide ou corrompu."; return }
            if imported.contains(where: { $0.postScriptName == ps }) { importError = "Cette police est déjà importée."; return }
            if UIFont(name: ps, size: 12) != nil, !imported.contains(where: { $0.postScriptName == ps }) {
                importError = "Une police du système porte déjà ce nom."; return
            }
            let name = UUID().uuidString + "." + ext
            let dest = fontsDir.appendingPathComponent(name)
            try data.write(to: dest, options: .atomic)
            guard register(dest), UIFont(name: ps, size: 12) != nil else {
                try? FileManager.default.removeItem(at: dest)
                importError = "iOS a refusé d’enregistrer cette police."; return
            }
            let fam = (UIFont(name: ps, size: 12)?.familyName) ?? ps
            imported.append(ImportedFont(postScriptName: ps, family: fam, fileName: name))
            persist()
            Haptics.shared.success()
        } catch {
            importError = "Lecture impossible : \(error.localizedDescription)"
            Haptics.shared.error()
        }
    }

    func delete(_ f: ImportedFont) {
        let u = fontsDir.appendingPathComponent(f.fileName)
        CTFontManagerUnregisterFontsForURL(u as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: u)
        imported.removeAll { $0.id == f.id }
        persist()
    }

    @discardableResult
    private func register(_ url: URL) -> Bool {
        var err: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        return ok
    }
    private func persist() { if let d = try? JSONEncoder().encode(imported) { UserDefaults.standard.set(d, forKey: Self.key) } }
}

/// Applique la police de l’utilisateur avec Dynamic Type : `.gFont(.body)`.
struct GFont: ViewModifier {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var fonts: FontStore
    @ScaledMetric(relativeTo: .body) private var dyn: CGFloat = 1
    let role: FontRole
    func body(content: Content) -> some View {
        content.font(fonts.font(role, prefs: settings.prefs, scale: dyn))
    }
}
extension View { func gFont(_ r: FontRole) -> some View { modifier(GFont(role: r)) } }
