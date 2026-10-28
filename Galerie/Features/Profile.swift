import SwiftUI
import Photos
import PhotosUI
import AuthenticationServices

@MainActor
final class ProfileStore: ObservableObject {
    @Published var avatar: UIImage?
    private var url: URL { appSupportURL().appendingPathComponent("avatar.jpg") }
    init() { if let d = try? Data(contentsOf: url) { avatar = UIImage(data: d) } }
    func setAvatar(_ data: Data) {
        guard let img = UIImage(data: data) else { return }
        let side: CGFloat = 400
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let out = r.image { _ in
            let s = max(side / img.size.width, side / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        avatar = out
        try? out.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
    }
    func removeAvatar() { avatar = nil; try? FileManager.default.removeItem(at: url) }
}

struct AvatarView: View {
    var size: CGFloat
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pal) private var pal
    var body: some View {
        Group {
            if let a = profile.avatar { Image(uiImage: a).resizable().scaledToFill() }
            else {
                ZStack {
                    Circle().fill(LinearGradient(colors: [pal.accent, pal.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    let n = displayName
                    if n.isEmpty { Image(systemName: "person.fill").foregroundStyle(.white).font(.system(size: size * 0.45)) }
                    else { Text(String(n.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white) }
                }
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
    private var displayName: String { settings.prefs.profileName.isEmpty ? settings.prefs.appleName : settings.prefs.profileName }
}

struct ProfileView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var app: AppState
    @Environment(\.pal) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var favorites = 0
    @State private var albumCount = 0
    @State private var recent: [PHAsset] = []
    @State private var appleMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        AvatarView(size: 96).overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill").font(.system(size: 28)).foregroundStyle(.white, pal.accent)
                        }
                    }.accessibilityLabel("Changer la photo de profil")
                    TextField("Ton nom", text: $settings.prefs.profileName).multilineTextAlignment(.center).gFont(.title)
                    if profile.avatar != nil { Button("Retirer la photo") { profile.removeAvatar() }.gFont(.caption) }
                }.padding(.top, 8)

                GCard {
                    VStack(spacing: 10) {
                        InfoRow(title: "Photos", value: "\(library.photoCount)")
                        Divider2(); InfoRow(title: "Vidéos", value: "\(library.videoCount)")
                        Divider2(); InfoRow(title: "Favoris", value: "\(favorites)")
                        Divider2(); InfoRow(title: "Albums", value: "\(albumCount)")
                        Divider2(); InfoRow(title: "Accès à la photothèque", value: library.statusLabel)
                    }
                }
                if library.isLimited { Button("Gérer les photos autorisées") { library.presentLimitedPicker() }.gFont(.body) }
                if library.status == .denied { Button("Ouvrir les Réglages iOS") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } }

                appleSection

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Ajoutés récemment")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(recent.enumerated()), id: \.element.localIdentifier) { i, a in
                                    AssetThumb(asset: a, size: CGSize(width: 84, height: 84)).clipShape(RoundedRectangle(cornerRadius: 10))
                                        .onTapGesture { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { app.open(AssetList(recent), at: i, prefix: "pro") } }
                                }
                            }
                        }
                    }
                }
                Button { dismiss(); app.select(.settings) } label: {
                    HStack { Image(systemName: "gearshape"); Text("Préférences de l’app").gFont(.body); Spacer(); Image(systemName: "chevron.right") }
                        .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(pal.card))
                }.buttonStyle(PressableStyle())
                Text("Le profil est stocké uniquement sur cet iPhone. Il est distinct de ton compte iCloud : Galerie accède à la photothèque via l’autorisation Photos, pas via ton identifiant Apple.").gFont(.small).foregroundStyle(pal.textSecondary)
            }.padding(16)
        }
        .themedScreen().navigationTitle("Profil").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        .onChange(of: pickerItem) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { profile.setAvatar(d); Haptics.shared.success() } }
        }
        .task { await loadStats() }
    }

    @ViewBuilder private var appleSection: some View {
        #if APPLE_SIGN_IN
        GCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compte Apple").gFont(.headline)
                if settings.prefs.appleUserID.isEmpty {
                    SignInWithAppleButton(.signIn, onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: handleApple)
                        .frame(height: 46).signInWithAppleButtonStyle(.whiteOutline)
                    Text("Apple ne transmet que ton nom et ton e-mail (si tu les autorises), jamais ton mot de passe ni ta photothèque.").gFont(.small).foregroundStyle(pal.textSecondary)
                } else {
                    if !settings.prefs.appleName.isEmpty { InfoRow(title: "Nom", value: settings.prefs.appleName) }
                    if !settings.prefs.appleEmail.isEmpty { InfoRow(title: "E-mail", value: settings.prefs.appleEmail) }
                    Button("Se déconnecter", role: .destructive) { settings.prefs.appleUserID = ""; settings.prefs.appleEmail = ""; settings.prefs.appleName = "" }
                }
                if let m = appleMessage { Text(m).gFont(.small).foregroundStyle(.red) }
            }
        }
        #else
        GCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Connexion avec Apple", systemImage: "applelogo").gFont(.headline)
                Text("Non incluse dans ce build : elle exige un compte développeur Apple payant (capacité « Sign in with Apple »). Le code est prêt : suis les instructions du README pour l’activer.").gFont(.caption).foregroundStyle(pal.textSecondary)
            }
        }
        #endif
    }

    #if APPLE_SIGN_IN
    private func handleApple(_ r: Result<ASAuthorization, Error>) {
        switch r {
        case .success(let a):
            if let c = a.credential as? ASAuthorizationAppleIDCredential {
                settings.prefs.appleUserID = c.user
                if let n = c.fullName { let s = PersonNameComponentsFormatter().string(from: n); if !s.isEmpty { settings.prefs.appleName = s } }
                if let e = c.email { settings.prefs.appleEmail = e }
                Haptics.shared.success()
            }
        case .failure(let e): appleMessage = e.localizedDescription; Haptics.shared.error()
        }
    }
    #endif

    private func loadStats() async {
        guard library.isAuthorized else { return }
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "favorite == YES")
        favorites = PHAsset.fetchAssets(with: o).count
        albumCount = Albums.userAlbums().count
        let ro = PHFetchOptions(); ro.fetchLimit = 12; ro.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var a: [PHAsset] = []; PHAsset.fetchAssets(with: ro).enumerateObjects { x, _, _ in a.append(x) }
        recent = a
    }
}
