import UIKit
import UniformTypeIdentifiers

/// Extension de partage « Galerie distincte » : reçoit les images et vidéos du menu Partager d’autres apps
/// (Facebook, Safari, Messages…) et les dépose dans le stockage de l’app, sans toucher à la photothèque iCloud.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Enregistrement dans la galerie distincte…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner); view.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        Task { await run() }
    }

    private func finish(_ message: String, success: Bool) {
        spinner.stopAnimating()
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.9 : 2.6)) {
            if success { self.extensionContext?.completeRequest(returningItems: nil) }
            else { self.extensionContext?.cancelRequest(withError: NSError(domain: "Galerie", code: 1)) }
        }
    }

    private func run() async {
        guard let inbox = SharedGroup.inboxURL() else {
            finish("Indisponible : l’iPhone n’a pas accordé le groupe d’apps à cette installation. Utilise « Enregistrer dans Fichiers › Galerie › Dépôt » à la place.", success: false)
            return
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        for p in providers {
            if await save(p, to: inbox) { saved += 1 }
        }
        if saved > 0 { finish(saved == 1 ? "Enregistré dans la galerie distincte ✓" : "\(saved) éléments enregistrés ✓", success: true) }
        else { finish("Aucune image ni vidéo exploitable dans ce partage.", success: false) }
    }

    private func save(_ p: NSItemProvider, to inbox: URL) async -> Bool {
        for type in [UTType.movie, UTType.image] where p.hasItemConformingToTypeIdentifier(type.identifier) {
            let url: URL? = await withCheckedContinuation { cont in
                p.loadFileRepresentation(forTypeIdentifier: type.identifier) { tmp, _ in
                    guard let tmp else { cont.resume(returning: nil); return }
                    // Le fichier temporaire n’existe que pendant ce rappel : on le copie tout de suite.
                    cont.resume(returning: try? SharedGroup.deposit(tmp, in: inbox))
                }
            }
            if url != nil { return true }
        }
        // Repli : image fournie comme objet (UIImage) plutôt que comme fichier.
        if p.canLoadObject(ofClass: UIImage.self) {
            let img: UIImage? = await withCheckedContinuation { cont in
                _ = p.loadObject(ofClass: UIImage.self) { obj, _ in cont.resume(returning: obj as? UIImage) }
            }
            if let data = img?.jpegData(compressionQuality: 0.95) {
                let dst = inbox.appendingPathComponent(UUID().uuidString + ".jpg")
                if (try? data.write(to: dst)) != nil { return true }
            }
        }
        return false
    }
}
