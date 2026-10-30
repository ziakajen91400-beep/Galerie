import Foundation

/// Code partagé entre l’app et l’extension de partage (API compatibles extensions uniquement).
enum SharedGroup {
    /// Identifiant de l’app principale, même depuis l’extension (« …galerie.share » → « …galerie »).
    static func mainBundleID() -> String {
        let id = Bundle.main.bundleIdentifier ?? "com.perso.galerie"
        return id.hasSuffix(".share") ? String(id.dropLast(6)) : id
    }

    /// Conteneur d’App Group, s’il est réellement disponible avec la signature utilisée pour installer l’app.
    static func containerURL() -> URL? {
        let fm = FileManager.default
        var tried = Set<String>()
        for g in ["group." + mainBundleID(), "group.com.perso.galerie"] where tried.insert(g).inserted {
            if let u = fm.containerURL(forSecurityApplicationGroupIdentifier: g) { return u }
        }
        return nil
    }

    /// Dossier où l’extension dépose les fichiers reçus ; l’app les déplace dans la galerie distincte.
    static func inboxURL() -> URL? {
        guard let base = containerURL() else { return nil }
        let u = base.appendingPathComponent("InboxGalerieDistincte", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Copie un fichier dans le dossier de dépôt, avec un nom unique.
    @discardableResult
    static func deposit(_ src: URL, in dir: URL) throws -> URL {
        let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension.lowercased()
        let dst = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "3gp", "avi"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]
    static func isSupported(_ url: URL) -> Bool {
        let e = url.pathExtension.lowercased()
        return videoExtensions.contains(e) || imageExtensions.contains(e)
    }
}
