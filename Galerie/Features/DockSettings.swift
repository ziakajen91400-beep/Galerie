import SwiftUI

/// Personnalisation de la barre de navigation : ajouter, retirer, réordonner, prévisualiser, restaurer.
/// Enregistrement automatique (les réglages sont persistés à chaque modification).
/// Les écrans proposés sont de vrais écrans de l’app ; Photothèque et Réglages restent toujours dans la barre.
struct DockSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal

    private var current: [AppTab] { settings.dock }
    private var available: [AppTab] { AppTab.allCases.filter { !current.contains($0) } }
    private let maxTabs = 8

    var body: some View {
        List {
            Section {
                DockPreview(tabs: current)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } header: { Text("Aperçu") } footer: {
                Text(current.count > 5 ? "Plus de 5 onglets : la barre défile horizontalement." : "Jusqu’à 5 onglets : la barre reste fixe et se parcourt aussi en glissant le doigt dessus.")
            }

            Section {
                ForEach(current) { t in
                    row(t).deleteDisabled(t.isEssential)
                }
                .onMove { from, to in
                    var arr = current; arr.move(fromOffsets: from, toOffset: to); save(arr); Haptics.shared.selection()
                }
                .onDelete { offsets in
                    var arr = current
                    for i in offsets.sorted(by: >) where !arr[i].isEssential { arr.remove(at: i) }
                    save(arr); Haptics.shared.light()
                }
            } header: { Text("Dans la barre (\(current.count)/\(maxTabs))") } footer: {
                Text("Maintiens et fais glisser les poignées pour changer l’ordre. Photothèque et Réglages ne peuvent pas être retirés.")
            }

            if !available.isEmpty {
                Section {
                    ForEach(available) { t in
                        HStack {
                            row(t)
                            Button {
                                guard current.count < maxTabs else { app.showToast("8 onglets au maximum"); Haptics.shared.warning(); return }
                                save(current + [t]); Haptics.shared.light()
                            } label: { Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(pal.accent).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.plain).accessibilityLabel("Ajouter \(t.title)")
                        }
                    }
                } header: { Text("Disponibles") } footer: {
                    Text("Une section hors de la barre reste accessible depuis ici avec « Ouvrir ».")
                }
                Section("Ouvrir une section hors de la barre") {
                    ForEach(available) { t in
                        Button { app.select(t) } label: { HStack { Image(systemName: t.icon).frame(width: 26).foregroundStyle(pal.accent); Text("Ouvrir \(t.title)").gFont(.body); Spacer() } }
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { settings.prefs.dockSwipe }, set: { settings.prefs.dockSwipe = $0; Haptics.shared.selection() })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Naviguer en glissant sur la barre").gFont(.body)
                        Text("Un glissement horizontal fait suivre l’indicateur sous le doigt ; la section s’ouvre au relâchement. Un simple appui fonctionne toujours.").gFont(.small).foregroundStyle(pal.textSecondary)
                    }
                }.tint(pal.accent)
                Button("Restaurer la disposition par défaut", role: .destructive) {
                    settings.prefs.dockTabs = DockDefaults.tabs; Haptics.shared.warning()
                }.gFont(.body)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .themedScreen()
        .navigationTitle("Barre de navigation").navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ t: AppTab) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(pal.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).gFont(.body)
                Text(t.subtitle).gFont(.small).foregroundStyle(pal.textSecondary)
            }
            Spacer(minLength: 0)
            if t.isEssential && current.contains(t) { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(pal.textSecondary) }
        }
    }

    private func save(_ tabs: [AppTab]) {
        settings.prefs.dockTabs = AppSettings.sanitizeDock(tabs.map(\.rawValue)).map(\.rawValue)
    }
}

/// Maquette de la barre (mêmes icônes et même ordre que la vraie).
struct DockPreview: View {
    let tabs: [AppTab]
    @Environment(\.pal) private var pal
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { t in
                    VStack(spacing: 2) {
                        if t == .library {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [pal.accent.opacity(0.95), pal.accent.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "photo.fill.on.rectangle.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            }.frame(width: 30, height: 30)
                        } else {
                            Image(systemName: t.icon).font(.system(size: 19, weight: .semibold)).frame(height: 30)
                        }
                        Text(t.title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(t == .library ? pal.accent : pal.textSecondary)
                    .frame(width: tabs.count > 5 ? 66 : max(60, (UIScreen.main.bounds.width - 100) / CGFloat(max(tabs.count, 1))), height: 54)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
    }
}
