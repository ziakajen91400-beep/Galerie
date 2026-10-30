import SwiftUI
import Photos

private struct SettingItem: Identifiable {
    let id: String
    let section: String
    let title: String
    let keywords: String
    let content: AnyView
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var themes: ThemeStore
    @EnvironmentObject private var fonts: FontStore
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var intelligence: IntelligenceIndex
    @EnvironmentObject private var memories: MemoriesEngine
    @EnvironmentObject private var geo: GeoIndex
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var privateStore: PrivateStore
    @Environment(\.pal) private var pal
    @State private var search = ""
    @State private var confirmReset = false
    @State private var confirmClearIndex = false
    @State private var showProfile = false

    private var p: Binding<Prefs> { $settings.prefs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if search.isEmpty { profileHeader }
                    let groups = grouped
                    if groups.isEmpty { EmptyState(icon: "magnifyingglass", title: "Aucun réglage trouvé", message: "Essaie un autre mot : thème, haptique, carte…").frame(height: 260) }
                    ForEach(groups, id: \.0) { name, items in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: name)
                            GCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                                        it.content.padding(.horizontal, 14).padding(.vertical, 11)
                                        if i < items.count - 1 { Divider2().padding(.leading, 14) }
                                    }
                                }
                            }
                        }
                    }
                }.padding(14)
            }
            .themedScreen().navigationTitle("Réglages")
            // Le champ de recherche reste replié (tirer l’écran vers le bas pour l’afficher) et le clavier
            // se ferme au défilement : aucun clavier ne s’ouvre de lui-même dans les réglages.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Rechercher un réglage")
            .scrollDismissesKeyboard(.interactively)
            .onDisappear { Keyboard.dismiss() }
            .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() }.presentationDetents([.large]) }
            .confirmationDialog("Réinitialiser tous les réglages ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Réinitialiser", role: .destructive) { settings.resetAll(); Haptics.shared.warning(); app.showToast("Réglages réinitialisés") }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Thème, polices, affichage et souvenirs reviennent à leurs valeurs d’origine. Tes photos, albums et thèmes personnalisés ne sont pas touchés.") }
            .confirmationDialog("Effacer l’analyse locale ?", isPresented: $confirmClearIndex, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { intelligence.clear() }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private var grouped: [(String, [SettingItem])] {
        let q = search.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let all = items.filter { q.isEmpty || ($0.title + " " + $0.keywords + " " + $0.section).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) }
        var order: [String] = []
        var map: [String: [SettingItem]] = [:]
        for i in all { if map[i.section] == nil { order.append(i.section) }; map[i.section, default: []].append(i) }
        return order.map { ($0, map[$0]!) }
    }

    /// Profil en haut de la page : photo, prénom, nom, compte associé réel (jamais inventé) et accès à la modification.
    private var profileHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(size: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.prefs.displayFullName.isEmpty ? "Mon profil" : settings.prefs.displayFullName).gFont(.title).lineLimit(2)
                    Text(settings.prefs.accountLine).gFont(.caption).foregroundStyle(pal.textSecondary).lineLimit(1)
                    Text("\(library.photoCount) photos · \(library.videoCount) vidéos").gFont(.small).foregroundStyle(pal.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Button { Haptics.shared.light(); showProfile = true } label: {
                HStack { Image(systemName: "pencil"); Text("Modifier le profil").gFont(.body) }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(pal.accent.opacity(0.14)))
                    .foregroundStyle(pal.accent)
                    .contentShape(Capsule())
            }.buttonStyle(PressableStyle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 0.5))
    }

    // MARK: Réglages
    private func item(_ id: String, _ section: String, _ title: String, _ kw: String = "", @ViewBuilder _ v: () -> some View) -> SettingItem {
        SettingItem(id: id, section: section, title: title, keywords: kw, content: AnyView(v()))
    }
    private func link<D: View>(_ title: String, _ icon: String, value: String = "", @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack { Image(systemName: icon).foregroundStyle(pal.accent).frame(width: 26); Text(title).gFont(.body); Spacer()
                if !value.isEmpty { Text(value).gFont(.caption).foregroundStyle(pal.textSecondary) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.textSecondary) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var items: [SettingItem] {
        let ap = "Apparence", li = "Photothèque", le = "Lecture", ha = "Retour haptique", pr = "Confidentialité et autorisations"
        let bi = "Bibliothèque", so = "Souvenirs et suggestions", ga = "Gestion de l’application"
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        var list: [SettingItem] = []

        // Apparence
        list.append(item("mode", ap, "Mode d’affichage", "clair sombre automatique") {
            VStack(alignment: .leading, spacing: 8) { Text("Mode").gFont(.body)
                Picker("Mode", selection: p.appearance) { ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: settings.prefs.appearance) { _, _ in Haptics.shared.selection() } }
        })
        list.append(item("theme", ap, "Thème", "couleur rose bleu violet palette éditeur") {
            link("Thème", "paintpalette", value: themes.theme(settings.prefs.themeID).name) { ThemePickerView() }
        })
        list.append(item("accent", ap, "Couleur d’accentuation", "accent couleur personnalisée") {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: "Accent personnalisé", subtitle: "Remplace l’accent du thème", isOn: p.customAccent)
                if settings.prefs.customAccent {
                    ColorPicker("Couleur", selection: Binding(get: { Color(hex: settings.prefs.accentHex) }, set: { settings.prefs.accentHex = $0.hexString }), supportsOpacity: false).gFont(.body)
                }
            }
        })
        list.append(item("fonts", ap, "Polices", "police typographie taille texte importer ttf otf") {
            link("Polices et texte", "textformat", value: fonts.choice(settings.prefs.fontBody).label.components(separatedBy: " (").first ?? "") { FontSettingsView() }
        })
        list.append(item("anim", ap, "Réduire les animations", "mouvement animations") {
            ToggleRow(title: "Réduire les animations", subtitle: "Suit aussi le réglage d’accessibilité d’iOS", isOn: p.reduceAnimations)
        })
        list.append(item("panel", ap, "Style des panneaux", "verre liquid glass translucide opaque flou") {
            VStack(alignment: .leading, spacing: 8) { Text("Style des panneaux").gFont(.body)
                Picker("Style", selection: p.panelStyle) { ForEach(PanelStyle.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Text("Liquid Glass natif sur iOS 26 ; matériau translucide sur les versions précédentes.").gFont(.small).foregroundStyle(pal.textSecondary) }
        })
        list.append(item("glass", ap, "Intensité du Liquid Glass", "verre transparence reflets teinte faible moyen élevé") {
            VStack(alignment: .leading, spacing: 8) { Text("Intensité du Liquid Glass").gFont(.body)
                Picker("Intensité", selection: p.glassLevel) { ForEach(GlassLevel.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: settings.prefs.glassLevel) { _, _ in Haptics.shared.selection() }
                Text("Faible : très transparent et discret. Moyen : équilibré. Élevé : teinte et reflets plus marqués. Ne change pas la navigation.").gFont(.small).foregroundStyle(pal.textSecondary) }
        })
        list.append(item("dock", ap, "Barre de navigation", "dock onglets boutons ordre personnaliser glisser") {
            link("Barre de navigation", "dock.rectangle", value: "\(settings.dock.count) onglets") { DockSettingsView() }
        })
        list.append(item("density", ap, "Densité de la grille", "colonnes zoom vignettes") {
            HStack { Text("Colonnes").gFont(.body); Spacer()
                Picker("Colonnes", selection: p.gridColumns) { ForEach([2, 3, 4, 5, 6, 8, 10], id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.menu) }
        })
        list.append(item("aspect", ap, "Format des vignettes", "ratio carré portrait paysage recadrer") {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Format").gFont(.body); Spacer(); Picker("Format", selection: p.thumbAspect) { ForEach(ThumbAspect.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu) }
                ToggleRow(title: "Recadrer les vignettes", subtitle: "Désactivé : image entière", isOn: p.thumbFill)
            }
        })
        list.append(item("spacing", ap, "Espacement de la grille", "espace marge") {
            HStack { Text("Espacement").gFont(.body); Slider(value: p.gridSpacing, in: 0...8, step: 1); Text("\(Int(settings.prefs.gridSpacing)) pt").gFont(.caption).frame(width: 44) }
        })
        list.append(item("badges", ap, "Badges sur les vignettes", "vidéo live favori durée") {
            ToggleRow(title: "Afficher les badges", subtitle: "Durée, Live Photo, favori, capture d’écran", isOn: p.showBadges)
        })
        list.append(item("icon", ap, "Icône de l’app", "icône icone application") {
            link("Icône de l’app", "app.badge") { IconPickerView() }
        })

        // Photothèque
        list.append(item("group", li, "Regroupement chronologique", "jours mois années") {
            HStack { Text("Regrouper par").gFont(.body); Spacer(); Picker("Regrouper", selection: p.groupMode) { ForEach(GroupMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu) }
        })
        list.append(item("sort", li, "Ordre de tri", "plus ancien récent inverser") {
            ToggleRow(title: "Plus anciens d’abord", subtitle: "Désactivé : du plus récent au plus ancien", isOn: p.sortAscending)
        })
        list.append(item("shots", li, "Afficher les captures d’écran", "screenshots") { ToggleRow(title: "Afficher les captures d’écran", subtitle: "Dans la grille principale", isOn: p.showScreenshots) })
        list.append(item("vids", li, "Afficher les vidéos", "vidéos") { ToggleRow(title: "Afficher les vidéos", subtitle: "Dans la grille principale", isOn: p.showVideos) })
        list.append(item("cats", li, "Catégories des collections", "collections catégories albums") { link("Catégories visibles", "square.stack", value: "") { CategoriesVisibilityView() } })
        list.append(item("albumlist", li, "Albums en liste", "albums préférences") { ToggleRow(title: "Albums en liste", subtitle: "Au lieu de la grille de pochettes", isOn: p.albumsAsList) })

        // Lecture
        list.append(item("live", le, "Lecture automatique des Live Photos", "live photo animation") { ToggleRow(title: "Lire les Live Photos automatiquement", subtitle: "Sinon : appui prolongé sur la photo", isOn: p.autoPlayLive) })
        list.append(item("loop", le, "Lecture en boucle des vidéos", "vidéo boucle répéter") { ToggleRow(title: "Lire les vidéos en boucle", isOn: p.loopVideos) })
        list.append(item("slide", le, "Durée du diaporama", "diaporama secondes") {
            Stepper(value: p.slideshowSeconds, in: 1...10, step: 1) { Text("Diaporama : \(Int(settings.prefs.slideshowSeconds)) s par photo").gFont(.body) }
        })
        list.append(item("hdr", le, "HDR", "hdr dolby vision") {
            VStack(alignment: .leading, spacing: 2) { Text("HDR").gFont(.body); Text("Les photos et vidéos HDR sont affichées en HDR automatiquement par iOS lorsque l’écran le permet. Aucun réglage n’est nécessaire.").gFont(.small).foregroundStyle(pal.textSecondary) }
        })

        // Haptique
        list.append(item("haptics", ha, "Retour haptique", "vibration taptic haptique intensité force") {
            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "Retour haptique", subtitle: "Navigation, sélection, favoris, menus, succès et erreurs", isOn: Binding(get: { settings.prefs.hapticsEnabled }, set: { v in
                    settings.prefs.hapticsEnabled = v
                    if v { Haptics.shared.preview() }
                }))
                if settings.prefs.hapticsEnabled {
                    Text("Intensité").gFont(.body)
                    Picker("Intensité", selection: Binding(get: { settings.prefs.hapticsIntensity }, set: { v in
                        settings.prefs.hapticsIntensity = v; Haptics.shared.preview()
                    })) { ForEach(HapticIntensity.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    Button("Tester la vibration") { Haptics.shared.preview() }.gFont(.body)
                    Text("Chaque niveau change le style et la force réels de la vibration (léger, moyen, rigide). Les retours de succès et d’erreur sont des motifs système fixes. Les iPad et certains appareils sans moteur Taptic ne vibrent pas.").gFont(.small).foregroundStyle(pal.textSecondary)
                }
            }
        })

        // Confidentialité
        list.append(item("auth", pr, "Accès à la photothèque", "autorisation accès limité photos") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "Accès à la photothèque", value: library.statusLabel)
                if library.isLimited { Button("Gérer les photos autorisées") { library.presentLimitedPicker() }.gFont(.body) }
                Button("Ouvrir les Réglages d’iOS") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.gFont(.body)
                Text("Galerie lit ta photothèque système via PhotoKit et n’en fait aucune copie. Elle n’utilise pas ta position GPS : seules les coordonnées déjà présentes dans tes photos sont lues, localement.").gFont(.small).foregroundStyle(pal.textSecondary)
            }
        })
        list.append(item("geocode", pr, "Noms de lieux", "géocodage localisation ville adresse") {
            ToggleRow(title: "Noms de lieux (service Apple)", subtitle: "Convertit les coordonnées d’une photo en nom de lieu. Les coordonnées sont alors envoyées à Apple. Désactivé par défaut.", isOn: p.allowGeocoding)
        })
        list.append(item("intel", pr, "Analyse locale des images", "vision texte ocr qr objets documents recherche") {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: "Analyse locale (Vision)", subtitle: "Détecte texte, QR codes et objets sur l’iPhone pour la recherche et les collections. Aucune image n’est envoyée.", isOn: p.intelligenceEnabled)
                if settings.prefs.intelligenceEnabled {
                    Stepper(value: p.intelligenceLimit, in: 500...20000, step: 500) { Text("Analyser les \(settings.prefs.intelligenceLimit) plus récentes").gFont(.caption) }
                    if intelligence.running {
                        ProgressView(value: Double(intelligence.processed), total: Double(max(intelligence.target, 1)))
                        Text("\(intelligence.processed) / \(intelligence.target)").gFont(.small)
                        Button("Arrêter") { intelligence.stop() }.gFont(.body)
                    } else {
                        Button("Lancer l’analyse") { intelligence.start(limit: settings.prefs.intelligenceLimit); Haptics.shared.medium() }.gFont(.body)
                    }
                    Text("\(intelligence.entries.count) image(s) analysée(s). Les originaux stockés uniquement dans iCloud sont ignorés.").gFont(.small).foregroundStyle(pal.textSecondary)
                    Button("Effacer l’analyse", role: .destructive) { confirmClearIndex = true }.gFont(.body)
                }
            }
        })
        list.append(item("hist", pr, "Historique de recherche", "recherche historique effacer") {
            VStack(alignment: .leading, spacing: 6) {
                ToggleRow(title: "Historique de recherche", isOn: p.searchHistoryEnabled)
                if !settings.prefs.searchHistory.isEmpty { Button("Effacer l’historique", role: .destructive) { settings.prefs.searchHistory = [] }.gFont(.body) }
            }
        })
        list.append(item("localmeta", pr, "Légendes et mots-clés locaux", "légendes mots-clés notes effacer") {
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(title: "Médias annotés", value: "\(MetadataStore.shared.items.count)")
                if !MetadataStore.shared.items.isEmpty { Button("Effacer toutes les annotations", role: .destructive) { MetadataStore.shared.clear(); Haptics.shared.warning() }.gFont(.body) }
            }
        })

        // Verrouillage et galerie distincte
        let lk = "Verrouillage"
        list.append(item("lock", lk, "Verrouiller avec Face ID", "face id touch id code verrouillage sécurité masqués supprimés sensibles") {
            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "Verrouiller avec \(AppLock.methodName)", subtitle: "Demande l’authentification à l’ouverture de l’app et à son retour au premier plan. Le code de l’iPhone sert de secours.", isOn: p.lockApp)
                if settings.prefs.lockApp {
                    HStack { Text("Verrouiller après").gFont(.body); Spacer()
                        Picker("Délai", selection: p.lockDelay) { Text("Immédiatement").tag(0); Text("1 minute").tag(60); Text("5 minutes").tag(300); Text("15 minutes").tag(900) }.pickerStyle(.menu) }
                }
                if !AppLock.canAuthenticate { Text("Aucun code ni Face ID n’est configuré sur cet iPhone : le verrouillage ne pourra pas s’appliquer.").gFont(.small).foregroundStyle(.red) }
            }
        })
        list.append(item("lockzones", lk, "Zones protégées", "masqués privée suppression face id") {
            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "Photos masquées", subtitle: "Demande l’authentification pour ouvrir l’album « Masqués ».", isOn: p.lockHidden)
                ToggleRow(title: "Galerie distincte", subtitle: "Demande l’authentification pour ouvrir la galerie distincte.", isOn: p.lockPrivate)
                ToggleRow(title: "Suppressions", subtitle: "Demande l’authentification avant de supprimer des photos ou vidéos.", isOn: p.lockDelete)
                Text("« Supprimés récemment » est une section de l’app Photos d’iOS, que les apps tierces ne peuvent pas ouvrir : elle se protège dans Réglages › Photos (Face ID pour les albums masqués et supprimés).").gFont(.small).foregroundStyle(pal.textSecondary)
            }
        })
        let pg = "Galerie distincte"
        list.append(item("vault", pg, "Galerie distincte", "photos autre stockage iphone partager facebook fichiers enregistrer hors icloud") {
            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "Activer la galerie distincte", subtitle: "Médias gardés dans le stockage de l’iPhone, séparés de ta photothèque et de iCloud.", isOn: p.privateEnabled)
                if settings.prefs.privateEnabled {
                    Button { app.select(.vault) } label: { HStack { Image(systemName: "lock.rectangle.stack.fill").foregroundStyle(pal.accent).frame(width: 26); Text("Ouvrir la galerie distincte").gFont(.body); Spacer(); Text("\(privateStore.items.count)").gFont(.caption).foregroundStyle(pal.textSecondary) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                    Text("Pour y ajouter une photo depuis une autre app : Partager › « Galerie distincte », ou « Enregistrer dans Fichiers » › Sur mon iPhone › Galerie › Dépôt. Le partage direct demande que l’iPhone accorde un groupe d’apps à l’installation ; sinon, utilise Fichiers.").gFont(.small).foregroundStyle(pal.textSecondary)
                }
            }
        })

        // Bibliothèque
        list.append(item("libstate", bi, "État de la bibliothèque", "synchronisation actualiser icloud nombre photos vidéos") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "Photos accessibles", value: "\(library.photoCount)")
                InfoRow(title: "Vidéos accessibles", value: "\(library.videoCount)")
                InfoRow(title: "État", value: library.isLoading ? "Chargement…" : (library.isAuthorized ? "Chargée" : "Accès indisponible"))
                InfoRow(title: "Dernière lecture réussie", value: library.lastRefresh.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                InfoRow(title: "Médias géolocalisés", value: geo.loaded ? "\(geo.points.count)" : "…")
                Button("Actualiser la bibliothèque") { Haptics.shared.medium(); library.reload(); geo.invalidate() }.gFont(.body)
                Text("Galerie lit directement la photothèque d’iOS et se met à jour dès qu’iOS signale un changement. La synchronisation iCloud est gérée par l’app Photos d’Apple ; Galerie n’en affiche pas l’état (non exposé aux apps tierces).").gFont(.small).foregroundStyle(pal.textSecondary)
            }
        })

        // Souvenirs
        list.append(item("mem", so, "Souvenirs", "souvenirs suggestions à cette date") {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(title: "Souvenirs", subtitle: "Calculés sur ton iPhone à partir de tes vrais médias", isOn: p.memoriesEnabled)
                if settings.prefs.memoriesEnabled {
                    ToggleRow(title: "À cette date", subtitle: "Médias du même jour, il y a 1 an ou plus", isOn: p.memOnThisDay)
                    ToggleRow(title: "Voyages", subtitle: "Séries de photos géolocalisées loin de chez toi", isOn: p.memTrips)
                    ToggleRow(title: "Sélection de favoris", isOn: p.memFavorites)
                    ToggleRow(title: "Meilleurs mois", isOn: p.memPeriods)
                }
                Button("Réinitialiser les suggestions") {
                    settings.prefs.dismissedMemories = []; Haptics.shared.success()
                    Task { await memories.refresh(prefs: settings.prefs, geo: geo, force: true) }
                }.gFont(.body)
            }
        })

        list.append(item("assistant", so, "Assistant", "assistant suggestions albums fonds d’écran") {
            Button { app.select(.assistant) } label: {
                HStack { Image(systemName: "sparkles").foregroundStyle(pal.accent).frame(width: 26); Text("Ouvrir l’assistant").gFont(.body); Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(pal.textSecondary) }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        })

        // Application
        list.append(item("about", ga, "Informations sur l’app", "version build à propos") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "Version", value: ver)
                InfoRow(title: "iOS", value: UIDevice.current.systemVersion)
                InfoRow(title: "Appareil", value: UIDevice.current.model)
                InfoRow(title: "Liquid Glass natif", value: { if #available(iOS 26.0, *) { return "Disponible" } else { return "Non (repli translucide)" } }())
                InfoRow(title: "Icônes alternatives", value: "\(AppIconManager.configuredAlternates().count) déclarées")
            }
        })
        list.append(item("help", ga, "Aide et limites", "aide limites impossible ios photos") { link("Aide et limites des fonctions", "questionmark.circle") { HelpView() } })
        list.append(item("reset", ga, "Réinitialiser les réglages", "reset réinitialisation") {
            Button("Réinitialiser les réglages…", role: .destructive) { Haptics.shared.warning(); confirmReset = true }.gFont(.body)
        })
        return list
    }
}

struct CategoriesVisibilityView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    var body: some View {
        ScrollView {
            GCard {
                VStack(spacing: 12) {
                    ForEach(CollectionDef.all) { d in
                        ToggleRow(title: d.title, isOn: Binding(get: { !settings.prefs.hiddenCollections.contains(d.id) }, set: { on in
                            if on { settings.prefs.hiddenCollections.removeAll { $0 == d.id } } else { settings.prefs.hiddenCollections.append(d.id) }
                        }))
                    }
                }
            }.padding(14)
        }.themedScreen().navigationTitle("Catégories visibles").navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpView: View {
    @Environment(\.pal) private var pal
    private let sections: [(String, String)] = [
        ("Photothèque et iCloud", "Galerie lit la photothèque d’iOS (PhotoKit) et reflète les changements faits dans Photos. Elle ne crée aucune copie et n’expose pas l’état de la synchronisation iCloud. Les originaux absents de l’iPhone sont téléchargés à la demande."),
        ("Supprimés récemment, personnes, animaux, album partagé en famille", "iOS ne donne pas accès à ces collections aux apps tierces. Les albums partagés iCloud classiques sont listés en lecture."),
        ("Légendes et mots-clés", "PhotoKit ne permet pas d’écrire ces champs dans Photos : Galerie les garde localement et s’en sert pour la recherche."),
        ("Recherche", "Texte visible, QR codes et objets sont détectés par Vision après l’analyse locale. Ce n’est pas la recherche sémantique d’Apple Photos."),
        ("Édition", "L’éditeur utilise Core Image : ses réglages (brillance, définition…) sont des approximations, pas les algorithmes privés d’Apple. « Enregistrer » conserve l’original et reste réversible depuis Photos. Les gain maps HDR et la partie animée des Live Photos ne sont pas conservées lors d’une édition."),
        ("Vidéo", "Découpage, réglages d’image, filtres, recadrage, rotation et volume sont disponibles. Les mixages audio « Studio », « Cinématique », etc. d’Apple ne sont pas reproductibles : ils ne sont pas proposés."),
        ("Date d’ajout", "PhotoKit n’expose pas la date d’ajout à la bibliothèque : elle n’est pas affichée."),
        ("Connexion Apple", "Nécessite un compte développeur payant ; voir le README. Elle n’ouvre pas l’accès à ta photothèque iCloud."),
        ("Icône de l’app", "iOS affiche une confirmation système lors du changement d’icône."),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(sections, id: \.0) { s in
                    GCard { VStack(alignment: .leading, spacing: 4) { Text(s.0).gFont(.headline); Text(s.1).gFont(.caption).foregroundStyle(pal.textSecondary) } }
                }
            }.padding(14)
        }.themedScreen().navigationTitle("Aide et limites").navigationBarTitleDisplayMode(.inline)
    }
}
