import SwiftUI
import Photos

struct LibraryView: View {
    @EnvironmentObject var library: PhotoLibraryModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.pal) private var pal
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            Group {
                switch library.status {
                case .notDetermined:
                    EmptyState(icon: "photo.on.rectangle.angled", title: "Bienvenue dans Galerie", message: "Autorise l’accès à ta photothèque pour afficher tes photos et vidéos. Tout reste sur ton iPhone.", actionTitle: "Autoriser l’accès") { Task { await library.requestAccess() } }
                case .denied, .restricted:
                    EmptyState(icon: "lock.shield", title: "Accès à la photothèque refusé", message: "Galerie a besoin d’accéder à tes photos. Tu peux l’autoriser dans les Réglages d’iOS.", actionTitle: "Ouvrir les Réglages") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                default:
                    VStack(spacing: 0) {
                        if library.isLimited { limitedBanner }
                        filterBar
                        MediaGridView(list: library.list, token: "\(library.filter.rawValue)-\(library.version)-\(settings.prefs.libraryKey)",
                                      emptyIcon: "photo", emptyTitle: library.isLoading ? "Chargement…" : "Aucun média",
                                      emptyMessage: library.isLoading ? "" : "Aucun élément ne correspond à ce filtre.",
                                      isLibrary: true)
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Photothèque")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Haptics.shared.light(); showProfile = true } label: { AvatarView(size: 30) }.accessibilityLabel("Profil")
                }
            }
            .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() }.presentationDetents([.large]) }
        }
    }

    private var limitedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(pal.accent)
            Text("Accès limité : seules certaines photos sont visibles.").gFont(.caption)
            Spacer()
            Button("Gérer") { library.presentLimitedPicker() }.gFont(.caption).fontWeight(.semibold)
        }.padding(10).glass(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 10).padding(.top, 4)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MediaFilter.allCases) { f in
                    Chip(title: f.label, icon: f.icon, selected: library.filter == f) { settings.animate { library.filter = f } }
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}
