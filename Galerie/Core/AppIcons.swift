import SwiftUI

struct AppIconOption: Identifiable, Hashable {
    let id: String          // nom du jeu d’icônes ("" = icône par défaut)
    let title: String
    let preview: String     // nom de l’imageset d’aperçu
    var altName: String? { id.isEmpty ? nil : id }
    static let all: [AppIconOption] = [
        .init(id: "", title: "Premium", preview: "IconPreview-default"),
        .init(id: "Icon-Lens", title: "Objectif", preview: "IconPreview-lens"),
        .init(id: "Icon-Gradient", title: "Dégradé", preview: "IconPreview-gradient"),
        .init(id: "Icon-Glass", title: "Verre", preview: "IconPreview-glass"),
        .init(id: "Icon-Mono", title: "Noir et blanc", preview: "IconPreview-mono"),
        .init(id: "Icon-Rose", title: "Rose", preview: "IconPreview-rose"),
        .init(id: "Icon-Violet", title: "Violet", preview: "IconPreview-violet"),
        .init(id: "Icon-Blue", title: "Bleu", preview: "IconPreview-blue"),
        .init(id: "Icon-Dark", title: "Sombre", preview: "IconPreview-dark"),
        .init(id: "Icon-Light", title: "Clair", preview: "IconPreview-light"),
        .init(id: "Icon-Multi", title: "Multicolore", preview: "IconPreview-multi"),
        .init(id: "Icon-Photo", title: "Photo", preview: "IconPreview-photo"),
    ]
}

@MainActor
final class AppIconManager: ObservableObject {
    @Published var current: String = UIApplication.shared.alternateIconName ?? ""
    var supported: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Noms d’icônes alternatives réellement déclarés dans l’Info.plist généré à la compilation.
    static func configuredAlternates() -> Set<String> {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alts = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return Set(alts?.keys.map { $0 } ?? [])
    }
    /// N’affiche que les icônes dont la configuration ET l’aperçu existent.
    var available: [AppIconOption] {
        let alts = Self.configuredAlternates()
        return AppIconOption.all.filter { o in
            UIImage(named: o.preview) != nil && (o.id.isEmpty || alts.contains(o.id))
        }
    }
    func apply(_ o: AppIconOption) async throws {
        try await UIApplication.shared.setAlternateIconName(o.altName)
        current = UIApplication.shared.alternateIconName ?? ""
    }
}

struct IconPickerView: View {
    @StateObject private var manager = AppIconManager()
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @State private var pending = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !manager.supported {
                    GCard { Text("iOS n’autorise pas le changement d’icône dans ce contexte (appareil ou installation non compatible).").gFont(.caption) }
                }
                let opts = manager.available
                if opts.count < AppIconOption.all.count {
                    GCard { Text("\(AppIconOption.all.count - opts.count) icône(s) masquée(s) : ressource ou configuration manquante dans ce build.").gFont(.caption).foregroundStyle(pal.textSecondary) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 18) {
                    ForEach(opts) { o in
                        Button { Haptics.shared.selection(); pending = o.id } label: {
                            VStack(spacing: 6) {
                                Image(o.preview).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(pending == o.id ? pal.accent : pal.border, lineWidth: pending == o.id ? 3.5 : 0.5))
                                    .overlay(alignment: .bottomTrailing) {
                                        if manager.current == o.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, pal.accent).font(.system(size: 22)).padding(4) }
                                    }
                                Text(o.title).gFont(.caption)
                                if manager.current == o.id { Text("Actuelle").gFont(.small).foregroundStyle(pal.accent) }
                            }
                        }.buttonStyle(PressableStyle()).accessibilityLabel("Icône \(o.title)").accessibilityAddTraits(pending == o.id ? .isSelected : [])
                    }
                }
                Button {
                    guard let o = opts.first(where: { $0.id == pending }) else { return }
                    busy = true
                    Task {
                        do { try await manager.apply(o); Haptics.shared.success(); app.showToast("Icône « \(o.title) » appliquée") }
                        catch { Haptics.shared.error(); app.showToast("iOS a refusé le changement : \(error.localizedDescription)") }
                        busy = false
                    }
                } label: {
                    Text(pending == manager.current ? "Icône déjà active" : "Appliquer l’icône").gFont(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).background(Capsule().fill(pending == manager.current || !manager.supported ? Color.gray : pal.accent))
                }.disabled(pending == manager.current || busy || !manager.supported)
                Button("Revenir à l’icône par défaut") {
                    if let d = opts.first(where: { $0.id.isEmpty }) { pending = ""; Task { try? await manager.apply(d); Haptics.shared.success() } }
                }.gFont(.caption).disabled(manager.current.isEmpty)
                Text("iOS affiche lui-même une confirmation lors du changement d’icône.").gFont(.small).foregroundStyle(pal.textSecondary)
            }.padding(16)
        }
        .themedScreen().navigationTitle("Icône de l’app").navigationBarTitleDisplayMode(.inline)
        .onAppear { pending = manager.current }
    }
}
