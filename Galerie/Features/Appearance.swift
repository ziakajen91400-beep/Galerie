import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Aperçu de thème (maquette d’interface colorée avec la vraie palette)
struct ThemePreviewCard: View {
    let pal: Pal
    var backdrop: BackdropSpec? = nil
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text("Photothèque").font(.system(size: 15, weight: .bold)).foregroundStyle(pal.text); Spacer()
                Image(systemName: "ellipsis.circle").foregroundStyle(pal.icon) }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in Text(["Tout", "Photos", "Vidéos", "Favoris"][i]).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5).foregroundStyle(i == 0 ? Color.white : pal.text)
                    .background(Capsule().fill(i == 0 ? pal.accent : pal.card)).overlay(Capsule().stroke(pal.border, lineWidth: i == 0 ? 0 : 0.5)) }
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(i % 3 == 0 ? pal.accent.opacity(0.55) : (i % 3 == 1 ? pal.surface : pal.elevated)).aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(pal.border, lineWidth: 0.5))
                }
            }
            Rectangle().fill(pal.separator).frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(["square.stack", "magnifyingglass", "photo.fill", "map", "gearshape"], id: \.self) { n in
                    Image(systemName: n).frame(maxWidth: .infinity).foregroundStyle(n == "photo.fill" ? pal.accent : pal.textSecondary)
                }
            }.padding(.vertical, 8).background(Capsule().fill(pal.nav)).overlay(Capsule().stroke(pal.border, lineWidth: 0.5))
            Text("Texte secondaire").font(.system(size: 11)).foregroundStyle(pal.textSecondary)
        }
        .padding(14)
        .background {
            ZStack {
                pal.bg
                if let b = backdrop { BackdropView(spec: b, pal: pal, dark: b.dark) }
            }.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(pal.border, lineWidth: 0.8))
        .shadow(color: pal.shadow.opacity(0.18), radius: 10, y: 4)
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack(spacing: 0) { Color(hex: theme.light.background); Color(hex: theme.dark.background) }
                if let ch = theme.character, UIImage(named: "CharFace-" + ch) != nil {
                    Image("CharFace-" + ch).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: theme.light.accent), lineWidth: 2))
                } else {
                    Circle().fill(Color(hex: theme.light.accent)).frame(width: 22).offset(x: -12)
                    Circle().fill(Color(hex: theme.dark.accent)).frame(width: 22).offset(x: 12)
                }
            }
            .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? pal.accent : pal.border, lineWidth: selected ? 3 : 0.5))
            .overlay(alignment: .topTrailing) {
                if theme.art != nil { Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(4).shadow(radius: 2) }
            }
            Text(theme.name).gFont(.small).lineLimit(2).multilineTextAlignment(.center)
        }
    }
}

struct ThemePickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var themes: ThemeStore
    @EnvironmentObject private var backdrops: BackdropStore
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @Environment(\.colorScheme) private var scheme
    @State private var pending = ""
    @State private var previewMode: AppearanceMode = .system
    @State private var editing: Theme?
    @State private var editingIsNew = false
    @State private var pickerItem: PhotosPickerItem?
    @StateObject private var icons = AppIconManager()

    private var previewDark: Bool { previewMode == .dark || (previewMode == .system && scheme == .dark) }
    private var previewPal: Pal {
        themes.palette(id: pending, dark: previewDark, accent: settings.prefs.customAccent ? settings.prefs.accentHex : nil)
    }
    private var previewBackdrop: BackdropSpec? {
        let t = themes.theme(pending), img = backdrops.image(pending)
        guard t.art != nil || img != nil else { return nil }
        return BackdropSpec(art: t.art, image: img, opacity: settings.prefs.backdropOpacity, dark: previewDark, character: t.character)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Aperçu", selection: $previewMode) {
                    Text("Auto").tag(AppearanceMode.system); Text("Clair").tag(AppearanceMode.light); Text("Sombre").tag(AppearanceMode.dark)
                }.pickerStyle(.segmented)
                ThemePreviewCard(pal: previewPal, backdrop: previewBackdrop)
                Button {
                    settings.prefs.themeID = pending; Haptics.shared.success(); app.showToast("Thème « \(themes.theme(pending).name) » appliqué")
                } label: {
                    Text(pending == settings.prefs.themeID ? "Thème actuel" : "Appliquer ce thème").gFont(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).background(Capsule().fill(pending == settings.prefs.themeID ? Color.gray : pal.accent))
                        .contentShape(Capsule())
                }.disabled(pending == settings.prefs.themeID)
                if settings.prefs.themeID != "galerie" {
                    Button {
                        settings.prefs.themeID = "galerie"; pending = "galerie"; Haptics.shared.success(); app.showToast("Thème d’origine rétabli")
                    } label: { Label("Revenir au thème d’origine", systemImage: "arrow.uturn.backward").gFont(.body) }
                }

                HStack { SectionTitle(text: "Thèmes"); Spacer()
                    Button { editing = themes.newTheme(); editingIsNew = true } label: { Label("Nouveau", systemImage: "plus").gFont(.caption) } }
                grid(themes.all.filter { $0.art == nil })

                SectionTitle(text: "Personnages fictifs · créations originales")
                Text("Neuf personnages féminins inventés pour l’app, chacun avec sa palette, son motif et son icône d’app assortie. Aucun personnage existant n’est reproduit. Tu peux aussi ajouter ta propre image ci-dessous.").gFont(.small).foregroundStyle(pal.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                grid(themes.all.filter { $0.art != nil })
                matchingIconButton

                backdropControls
                Text("Maintiens un thème pour le dupliquer. Les thèmes personnalisés peuvent être modifiés et supprimés.").gFont(.small).foregroundStyle(pal.textSecondary)
            }.padding(16)
        }
        .themedScreen().navigationTitle("Thèmes").navigationBarTitleDisplayMode(.inline)
        .onAppear { pending = settings.prefs.themeID }
        .sheet(item: $editing) { t in ThemeEditorView(theme: t, isNew: editingIsNew) { saved in pending = saved.id } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            let target = pending
            Task {
                if let d = try? await item.loadTransferable(type: Data.self) { backdrops.set(d, for: target); Haptics.shared.success() }
                pickerItem = nil
            }
        }
    }

    /// Icône d’écran d’accueil assortie au personnage du thème sélectionné (mécanisme d’icônes alternatives d’iOS).
    @ViewBuilder private var matchingIconButton: some View {
        if let ch = themes.theme(pending).character, let opt = AppIconOption.matching(character: ch), UIImage(named: opt.preview) != nil {
            Button {
                Task {
                    do { try await icons.apply(opt); Haptics.shared.success(); app.showToast("Icône « \(opt.title) » appliquée") }
                    catch { Haptics.shared.error(); app.showToast("iOS a refusé le changement : \(error.localizedDescription)") }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(opt.preview).resizable().scaledToFit().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) { Text("Appliquer l’icône assortie").gFont(.body); Text("Icône de l’écran d’accueil · \(opt.title)").gFont(.small).foregroundStyle(pal.textSecondary) }
                    Spacer()
                }.padding(10).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.card)).contentShape(Rectangle())
            }.buttonStyle(PressableStyle()).disabled(!icons.supported)
        }
    }

    private func grid(_ list: [Theme]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(list) { t in
                Button { Haptics.shared.selection(); pending = t.id } label: { ThemeSwatch(theme: t, selected: pending == t.id) }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        if t.isCustom { Button { editing = t; editingIsNew = false } label: { Label("Modifier", systemImage: "pencil") } }
                        Button { pending = themes.duplicate(t).id } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                        if t.isCustom { Button(role: .destructive) { if settings.prefs.themeID == t.id { settings.prefs.themeID = "galerie" }; if pending == t.id { pending = "galerie" }; themes.delete(t) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
            }
        }
    }

    /// Image personnelle facultative : fond du thème sélectionné (reste sur l’iPhone).
    private var backdropControls: some View {
        GCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Illustration personnelle").gFont(.headline)
                Text("Choisis une image dont tu détiens les droits : elle devient le fond du thème « \(themes.theme(pending).name) ». Elle est copiée dans l’app (réduite), sans connexion, et l’original de ta photothèque n’est pas modifié.").gFont(.small).foregroundStyle(pal.textSecondary)
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(backdrops.image(pending) == nil ? "Choisir une image" : "Changer l’image", systemImage: "photo").gFont(.body)
                    }
                    Spacer()
                    if backdrops.image(pending) != nil { Button("Retirer", role: .destructive) { backdrops.remove(for: pending); Haptics.shared.warning() }.gFont(.body) }
                }
                if backdrops.image(pending) != nil {
                    HStack { Text("Opacité").gFont(.caption); Slider(value: $settings.prefs.backdropOpacity, in: 0.1...0.9) }
                }
            }
        }
    }
}

struct ThemeEditorView: View {
    @State var draft: Theme
    let original: Theme
    let isNew: Bool
    var onSaved: (Theme) -> Void
    @EnvironmentObject private var themes: ThemeStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    @State private var editDark = false

    init(theme: Theme, isNew: Bool, onSaved: @escaping (Theme) -> Void) {
        _draft = State(initialValue: theme); original = theme; self.isNew = isNew; self.onSaved = onSaved
    }

    private var current: ThemePalette { editDark ? draft.dark : draft.light }
    private func binding(_ kp: WritableKeyPath<ThemePalette, String>) -> Binding<Color> {
        Binding(get: { Color(hex: (editDark ? draft.dark : draft.light)[keyPath: kp]) },
                set: { c in if editDark { draft.dark[keyPath: kp] = c.hexString } else { draft.light[keyPath: kp] = c.hexString } })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Nom du thème", text: $draft.name).gFont(.title).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(pal.card))
                    Picker("Mode", selection: $editDark) { Text("Clair").tag(false); Text("Sombre").tag(true) }.pickerStyle(.segmented)
                    ThemePreviewCard(pal: Pal(current))
                    GCard {
                        VStack(spacing: 8) {
                            row("Fond général", \.background); row("Surfaces", \.surface); row("Surfaces élevées", \.elevated)
                            row("Barre de navigation", \.navBar); row("Menus", \.menu); row("Cartes", \.card)
                            row("Texte", \.text); row("Texte secondaire", \.textSecondary); row("Icônes", \.icon)
                            row("Bordures", \.border); row("Séparateurs", \.separator); row("Ombres", \.shadow)
                            row("Accent du thème", \.accent); row("Teinte du verre", \.glassTint)
                            HStack { Text("Opacité du verre").gFont(.body); Slider(value: Binding(get: { current.glassOpacity }, set: { v in if editDark { draft.dark.glassOpacity = v } else { draft.light.glassOpacity = v } }), in: 0...0.8) }
                        }
                    }
                    Button("Réinitialiser les modifications") { Haptics.shared.warning(); draft = original }.gFont(.body)
                    if !isNew && original.isCustom {
                        Button("Supprimer ce thème", role: .destructive) { if settings.prefs.themeID == original.id { settings.prefs.themeID = "galerie" }; themes.delete(original); dismiss() }
                    }
                }.padding(16)
            }
            .background(pal.bg)
            .navigationTitle(isNew ? "Nouveau thème" : "Modifier le thème").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                    if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = "Mon thème" }
                    themes.save(draft); Haptics.shared.success(); onSaved(draft); dismiss()
                } }
            }
        }
    }
    private func row(_ title: String, _ kp: WritableKeyPath<ThemePalette, String>) -> some View {
        ColorPicker(selection: binding(kp), supportsOpacity: false) { Text(title).gFont(.body) }
    }
}

// MARK: - Polices
extension FontStore {
    func preview(_ c: FontChoice, size: CGFloat) -> Font {
        if let fam = c.family { return Font.custom(fam, fixedSize: size) }
        return Font.system(size: size, design: c.design ?? .default)
    }
}

struct FontSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fonts: FontStore
    @Environment(\.pal) private var pal
    @State private var importing = false
    @State private var confirmDelete: ImportedFont?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aperçu").gFont(.small).foregroundStyle(pal.textSecondary)
                        Text("Un week-end à la mer").gFont(.largeTitle)
                        Text("Titre de section").gFont(.headline)
                        Text("Le renard brun saute par-dessus le chien paresseux. 0123456789").gFont(.body)
                        Text("Légende · 27 octobre 2026 · 14:32").gFont(.caption).foregroundStyle(pal.textSecondary)
                    }
                }
                picker("Police générale", $settings.prefs.fontBody)
                picker("Titres et en-têtes", $settings.prefs.fontTitle)
                picker("Légendes et informations", $settings.prefs.fontCaption)
                GCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Graisse", selection: $settings.prefs.fontWeight) { ForEach(FontWeightPref.allCases) { Text($0.label).tag($0) } }
                        HStack { Text("Taille").gFont(.body); Slider(value: $settings.prefs.textScale, in: 0.8...1.5, step: 0.05); Text("\(Int(settings.prefs.textScale * 100)) %").gFont(.caption).frame(width: 46) }
                        Text("S’ajoute à la taille de texte dynamique d’iOS (Réglages › Accessibilité).").gFont(.small).foregroundStyle(pal.textSecondary)
                    }
                }
                Button("Rétablir la police par défaut") {
                    Haptics.shared.warning()
                    settings.prefs.fontBody = "system"; settings.prefs.fontTitle = "system"; settings.prefs.fontCaption = "system"
                    settings.prefs.fontWeight = .regular; settings.prefs.textScale = 1
                }.gFont(.body)

                SectionTitle(text: "Polices importées")
                GCard {
                    VStack(alignment: .leading, spacing: 10) {
                        if fonts.imported.isEmpty { Text("Aucune police importée.").gFont(.caption).foregroundStyle(pal.textSecondary) }
                        ForEach(fonts.imported) { f in
                            HStack {
                                VStack(alignment: .leading) { Text(f.family).font(.custom(f.postScriptName, fixedSize: 20)); Text(f.postScriptName).gFont(.small).foregroundStyle(pal.textSecondary) }
                                Spacer()
                                Button(role: .destructive) { confirmDelete = f } label: { Image(systemName: "trash") }.accessibilityLabel("Supprimer \(f.family)")
                            }
                        }
                        Button { importing = true } label: { Label("Importer une police (TTF / OTF)", systemImage: "square.and.arrow.down") }
                        if let e = fonts.importError { Text(e).gFont(.caption).foregroundStyle(.red) }
                        Text("Importe uniquement des polices dont la licence autorise cet usage. Les fichiers sont copiés dans l’app, validés par iOS, et ne sont jamais envoyés ailleurs. Les polices importées ne sont pas partagées avec les autres apps.").gFont(.small).foregroundStyle(pal.textSecondary)
                    }
                }
            }.padding(16)
        }
        .themedScreen().navigationTitle("Polices").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.font, UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf")].compactMap { $0 }) { r in
            switch r { case .success(let u): fonts.importFont(from: u); case .failure(let e): fonts.importError = e.localizedDescription }
        }
        .confirmationDialog("Supprimer cette police ?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let f = confirmDelete {
                    let id = "custom:" + f.postScriptName
                    if settings.prefs.fontBody == id { settings.prefs.fontBody = "system" }
                    if settings.prefs.fontTitle == id { settings.prefs.fontTitle = "system" }
                    if settings.prefs.fontCaption == id { settings.prefs.fontCaption = "system" }
                    fonts.delete(f)
                }
                confirmDelete = nil
            }
            Button("Annuler", role: .cancel) { confirmDelete = nil }
        }
    }

    private func picker(_ title: String, _ sel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: title)
            GCard(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(fonts.choices) { c in
                        Button { Haptics.shared.selection(); sel.wrappedValue = c.id } label: {
                            HStack {
                                Text(c.label).font(fonts.preview(c, size: 17)).foregroundStyle(pal.text)
                                Spacer()
                                if sel.wrappedValue == c.id { Image(systemName: "checkmark").foregroundStyle(pal.accent) }
                            }.padding(.vertical, 9).padding(.horizontal, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
