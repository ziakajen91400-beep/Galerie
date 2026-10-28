import SwiftUI
import Photos

struct ShareItems: Identifiable { let id = UUID(); let urls: [URL] }

private struct SectionKey: Equatable { var token: String; var mode: GroupMode; var count: Int }

struct GridCell: View {
    let asset: PHAsset
    let size: CGSize
    let fill: Bool
    let selecting: Bool
    let isSelected: Bool
    let showBadges: Bool
    @Environment(\.pal) private var pal

    var body: some View {
        ZStack {
            AssetThumb(asset: asset, size: size, fill: fill)
            if showBadges {
                VStack {
                    HStack {
                        if asset.isLive { badge("livephoto") }
                        Spacer()
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        if asset.isScreenshot { badge("camera.viewfinder") }
                        if asset.isFavorite { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.white).shadow(radius: 2) }
                        Spacer()
                        if asset.isVideo { Text(Fmt.duration(asset.duration)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).shadow(radius: 2) }
                    }
                }
                .padding(5)
            }
            if selecting {
                ZStack(alignment: .bottomTrailing) {
                    if isSelected { Color.black.opacity(0.25) }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(isSelected ? pal.accent : .white)
                        .background(Circle().fill(isSelected ? .white : .clear).padding(3))
                        .shadow(radius: 2).padding(6)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
    private var label: String {
        var s = asset.isVideo ? "Vidéo" : (asset.isLive ? "Live Photo" : "Photo")
        if let d = asset.creationDate { s += ", " + d.formatted(date: .long, time: .shortened) }
        if asset.isFavorite { s += ", favori" }
        return s
    }
    private func badge(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).shadow(radius: 2)
    }
}

struct MediaGridView: View {
    let list: AssetList
    let token: String
    var album: PHAssetCollection? = nil
    var prefix = "lib"
    var emptyIcon = "photo.on.rectangle"
    var emptyTitle = "Aucun média"
    var emptyMessage = ""
    var isLibrary = false

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @Environment(\.zoomNS) private var zoomNS

    @State private var sections: [MediaSection] = []
    @State private var selecting = false
    @State private var selected: [String: PHAsset] = [:]
    @State private var share: ShareItems?
    @State private var showJump = false
    @State private var confirmDelete = false
    @State private var showAlbumPicker = false
    @State private var scrubbing: MediaSection?
    @State private var working = false
    @State private var lastScrubIndex = -1

    private let allColumns = [2, 3, 4, 5, 6, 8, 10]
    private var prefs: Prefs { settings.prefs }

    private func columns(for width: CGFloat) -> [Int] { allColumns.filter { width / CGFloat($0) >= 34 } }
    private func effective(_ width: CGFloat) -> Int {
        let opts = columns(for: width)
        return opts.min(by: { abs($0 - prefs.gridColumns) < abs($1 - prefs.gridColumns) }) ?? 3
    }

    var body: some View {
        GeometryReader { geo in
            let cols = effective(geo.size.width)
            let sp = CGFloat(prefs.gridSpacing)
            let cw = floor((geo.size.width - sp * CGFloat(cols - 1)) / CGFloat(cols))
            let ch = cw / prefs.thumbAspect.ratio
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    if list.isEmpty {
                        EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: sp, pinnedViews: [.sectionHeaders]) {
                                ForEach(sections) { sec in
                                    Section {
                                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cw), spacing: sp), count: cols), spacing: sp) {
                                            ForEach(sec.start..<(sec.start + sec.count), id: \.self) { i in
                                                cell(i, size: CGSize(width: cw, height: ch))
                                            }
                                        }
                                    } header: { header(sec) }
                                    .id(sec.id)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .simultaneousGesture(MagnifyGesture().onEnded { v in pinch(v.magnification, width: geo.size.width) })
                        scrubber(proxy: proxy, height: geo.size.height)
                    }
                }
                .onChange(of: app.scrollToLatestTick) { _, _ in
                    guard isLibrary, let first = prefs.sortAscending ? sections.last : sections.first else { return }
                    settings.animate { proxy.scrollTo(first.id, anchor: .top) }
                    Haptics.shared.light()
                }
                .sheet(isPresented: $showJump) {
                    JumpToDateSheet(sections: sections, mode: prefs.groupMode) { sec in
                        showJump = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(sec.id, anchor: .top) }
                    }.presentationDetents([.medium])
                }
            }
        }
        .task(id: SectionKey(token: token, mode: prefs.groupMode, count: list.count)) {
            let l = list, m = prefs.groupMode
            let s = await Task.detached(priority: .userInitiated) { MediaSection.compute(list: l, mode: m) }.value
            sections = s
        }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .toolbar { gridToolbar }
        .onChange(of: selecting) { _, v in app.tabBarHidden = v }
        .onChange(of: prefs.gridColumns) { _, _ in Haptics.shared.selection() }
        .onDisappear { if selecting { app.tabBarHidden = false } }
        .confirmationDialog("Supprimer \(selected.count) élément(s) de la photothèque ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { deleteSelected() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Ils iront dans « Supprimés récemment » de l’app Photos d’iOS pendant 30 jours. iOS demandera aussi sa propre confirmation.") }
        .sheet(item: $share) { s in ShareSheet(items: s.urls) }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerSheet(assets: Array(selected.values)) { name in
                app.showToast("Ajouté à « \(name) »"); exitSelection()
            }
        }
        .overlay { if working { ProgressView().controlSize(.large).padding(24).glass(RoundedRectangle(cornerRadius: 18)) } }
    }

    // MARK: Cellules
    private func cell(_ i: Int, size: CGSize) -> some View {
        let a = list[i]
        let isSel = selected[a.localIdentifier] != nil
        return GridCell(asset: a, size: size, fill: prefs.thumbFill, selecting: selecting, isSelected: isSel, showBadges: prefs.showBadges)
            .modifier(ZoomSource(id: prefix + a.localIdentifier, ns: zoomNS))
            .onTapGesture {
                if selecting {
                    Haptics.shared.selection()
                    if isSel { selected.removeValue(forKey: a.localIdentifier) } else { selected[a.localIdentifier] = a }
                } else {
                    Haptics.shared.light(); app.open(list, at: i, prefix: prefix)
                }
            }
            .contextMenu {
                Button { Task { _ = await MediaActions.setFavorite([a], !a.isFavorite) } } label: { Label(a.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: a.isFavorite ? "heart.slash" : "heart") }
                Button { selecting = true; selected[a.localIdentifier] = a } label: { Label("Sélectionner", systemImage: "checkmark.circle") }
            }
    }

    private func header(_ sec: MediaSection) -> some View {
        HStack {
            Text(sec.title(prefs.groupMode)).gFont(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6).glass(Capsule())
            Spacer()
            if selecting {
                Button {
                    Haptics.shared.selection()
                    for i in sec.start..<(sec.start + sec.count) { let a = list[i]; selected[a.localIdentifier] = a }
                } label: { Text("Tout").gFont(.caption).padding(.horizontal, 12).padding(.vertical, 6).glass(Capsule(), interactive: true) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: Défilement rapide
    private func scrubber(proxy: ScrollViewProxy, height: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Capsule().fill(pal.textSecondary.opacity(0.25)).frame(width: 4, height: height * 0.5).padding(.trailing, 3)
            Color.clear.frame(width: 34, height: height * 0.6)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let frac = min(max(v.location.y / (height * 0.6), 0), 1)
                    let idx = min(list.count - 1, Int(frac * Double(list.count)))
                    guard let sec = sections.last(where: { $0.start <= idx }) ?? sections.first else { return }
                    if scrubbing?.id != sec.id { Haptics.shared.selection() }
                    scrubbing = sec
                    proxy.scrollTo(sec.id, anchor: .top)
                }.onEnded { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scrubbing = nil } })
            if let s = scrubbing {
                Text(s.title(prefs.groupMode)).gFont(.caption).padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(Capsule()).padding(.trailing, 44).transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func pinch(_ m: CGFloat, width: CGFloat) {
        let opts = columns(for: width)
        guard let idx = opts.firstIndex(of: effective(width)) else { return }
        var n = idx
        if m > 1.18 { n = max(0, idx - 1) } else if m < 0.85 { n = min(opts.count - 1, idx + 1) }
        if n != idx { Haptics.shared.light(); settings.animate { settings.prefs.gridColumns = opts[n] } }
    }

    // MARK: Barre d’outils
    @ToolbarContentBuilder private var gridToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if selecting {
                Button("Terminer") { Haptics.shared.light(); exitSelection() }
            } else {
                Menu {
                    Section("Densité") {
                        ForEach(allColumns, id: \.self) { n in
                            Button { settings.prefs.gridColumns = n } label: {
                                Label("\(n) colonnes", systemImage: prefs.gridColumns == n ? "checkmark" : "")
                            }
                        }
                    }
                    Picker("Regrouper par", selection: $settings.prefs.groupMode) { ForEach(GroupMode.allCases) { Text($0.label).tag($0) } }
                    Picker("Ordre", selection: $settings.prefs.sortAscending) { Text("Plus récent d’abord").tag(false); Text("Plus ancien d’abord").tag(true) }
                    Picker("Format", selection: $settings.prefs.thumbAspect) { ForEach(ThumbAspect.allCases) { Text($0.label).tag($0) } }
                    Toggle("Recadrer les vignettes", isOn: $settings.prefs.thumbFill)
                    Toggle("Afficher les badges", isOn: $settings.prefs.showBadges)
                } label: { Image(systemName: "square.grid.2x2") }
                .accessibilityLabel("Options d’affichage")
                Menu {
                    Button { Haptics.shared.light(); showJump = true } label: { Label("Aller à une date…", systemImage: "calendar") }
                    Button { selecting = true; Haptics.shared.light() } label: { Label("Sélectionner", systemImage: "checkmark.circle") }
                    if isLibrary { Button { app.scrollToLatestTick += 1 } label: { Label("Retour aux plus récents", systemImage: "arrow.up.to.line") } }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Plus d’actions")
            }
        }
    }

    private var selectionBar: some View {
        let items = Array(selected.values)
        return HStack {
            Text("\(items.count)").gFont(.headline).frame(minWidth: 28)
            Spacer()
            barButton("square.and.arrow.up", "Partager") { Task { await shareSelected() } }
            barButton(items.allSatisfy { $0.isFavorite } && !items.isEmpty ? "heart.slash" : "heart", "Favori") {
                let all = items.allSatisfy { $0.isFavorite }
                Task { _ = await MediaActions.setFavorite(items, !all); exitSelection() }
            }
            barButton("rectangle.stack.badge.plus", "Ajouter à un album") { showAlbumPicker = true }
            if let album {
                barButton("rectangle.stack.badge.minus", "Retirer de l’album") {
                    Task { _ = await MediaActions.remove(items, from: album); exitSelection() }
                }
            }
            barButton("eye.slash", "Masquer") { Task { _ = await MediaActions.setHidden(items, true); exitSelection() } }
            barButton("trash", "Supprimer") { Haptics.shared.warning(); confirmDelete = true }
        }
        .disabled(items.isEmpty)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func barButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.shared.light(); action() } label: {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
        }.accessibilityLabel(label)
    }

    private func exitSelection() { selecting = false; selected = [:] }
    private func shareSelected() async {
        working = true
        let urls = await MediaActions.shareItems(Array(selected.values))
        working = false
        if urls.isEmpty { app.showToast("Impossible de préparer les fichiers (iCloud ?)"); Haptics.shared.error() }
        else { share = ShareItems(urls: urls) }
    }
    private func deleteSelected() {
        let items = Array(selected.values)
        Task {
            let ok = await MediaActions.delete(items)
            if ok { exitSelection() }
        }
    }
}

struct ZoomSource: ViewModifier {
    let id: String
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns { content.matchedTransitionSource(id: id, in: ns) } else { content }
    }
}

struct JumpToDateSheet: View {
    let sections: [MediaSection]
    let mode: GroupMode
    let onPick: (MediaSection) -> Void
    @State private var date = Date()
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 12) {
            Text("Aller à une date").gFont(.title)
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            Button {
                Haptics.shared.medium()
                if let s = nearest() { onPick(s) }
            } label: {
                Text("Aller").gFont(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Capsule().fill(pal.accent))
            }.disabled(sections.isEmpty)
        }.padding().background(pal.bg)
    }
    private func nearest() -> MediaSection? {
        sections.min { dist($0) < dist($1) }
    }
    private func dist(_ s: MediaSection) -> TimeInterval {
        if date >= s.minDate && date <= s.maxDate { return 0 }
        return min(abs(date.timeIntervalSince(s.minDate)), abs(date.timeIntervalSince(s.maxDate)))
    }
}

struct AlbumPickerSheet: View {
    let assets: [PHAsset]
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    @State private var albums: [PHAssetCollection] = []
    @State private var showNew = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Button { showNew = true } label: {
                        HStack { Image(systemName: "plus.circle.fill"); Text("Nouvel album").gFont(.body); Spacer() }
                            .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(pal.card))
                    }
                    ForEach(albums, id: \.localIdentifier) { c in
                        Button {
                            Task { if await MediaActions.add(assets, to: c) { onDone(c.localizedTitle ?? "Album"); dismiss() } }
                        } label: {
                            HStack { Text(c.localizedTitle ?? "Sans titre").gFont(.body); Spacer(); Text("\(Albums.count(c))").foregroundStyle(pal.textSecondary) }
                                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(pal.card))
                        }
                    }
                }.padding()
            }
            .background(pal.bg)
            .navigationTitle("Ajouter à un album").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .alert("Nouvel album", isPresented: $showNew) {
                TextField("Nom", text: $name)
                Button("Créer") {
                    let n = name.trimmingCharacters(in: .whitespaces); name = ""
                    guard !n.isEmpty else { return }
                    Task { if await MediaActions.createAlbum(named: n, with: assets) { onDone(n); dismiss() } }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        .onAppear { albums = Albums.userAlbums() }
        .presentationDetents([.medium, .large])
    }
}
