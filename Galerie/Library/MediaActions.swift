import SwiftUI
import Photos
import CoreLocation
import AVFoundation

enum MediaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

extension PHAsset {
    var isLive: Bool { mediaSubtypes.contains(.photoLive) }
    var isScreenshot: Bool { mediaSubtypes.contains(.photoScreenshot) }
    var isPanorama: Bool { mediaSubtypes.contains(.photoPanorama) }
    var isHDRPhoto: Bool { mediaSubtypes.contains(.photoHDR) }
    var isVideo: Bool { mediaType == .video }
    var primaryResource: PHAssetResource? {
        let r = PHAssetResource.assetResources(for: self)
        let wanted: [PHAssetResourceType] = isVideo ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        for t in wanted { if let x = r.first(where: { $0.type == t }) { return x } }
        return r.first
    }
    var originalFilename: String { primaryResource?.originalFilename ?? "Média" }
    var hasValidLocation: Bool {
        guard let l = location else { return false }
        return CLLocationCoordinate2DIsValid(l.coordinate) && !(l.coordinate.latitude == 0 && l.coordinate.longitude == 0)
    }
}

enum MediaActions {
    // MARK: Modifications de la photothèque
    static func perform(_ changes: @escaping () -> Void) async throws {
        try await PHPhotoLibrary.shared().performChanges(changes)
    }

    static func setFavorite(_ assets: [PHAsset], _ value: Bool) async -> Bool {
        do {
            try await perform { for a in assets { PHAssetChangeRequest(for: a).isFavorite = value } }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
    static func setHidden(_ assets: [PHAsset], _ value: Bool) async -> Bool {
        do { try await perform { for a in assets { PHAssetChangeRequest(for: a).isHidden = value } }; await Haptics.shared.success(); return true }
        catch { await Haptics.shared.error(); return false }
    }
    /// Suppression : iOS affiche sa propre confirmation et place les éléments dans « Supprimés récemment ».
    static func delete(_ assets: [PHAsset]) async -> Bool {
        do { try await perform { PHAssetChangeRequest.deleteAssets(assets as NSArray) }; await Haptics.shared.success(); return true }
        catch { await Haptics.shared.warning(); return false }
    }
    static func add(_ assets: [PHAsset], to album: PHAssetCollection) async -> Bool {
        do {
            try await perform { PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray) }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
    static func remove(_ assets: [PHAsset], from album: PHAssetCollection) async -> Bool {
        do {
            try await perform { PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets as NSArray) }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
    static func createAlbum(named name: String, with assets: [PHAsset] = []) async -> Bool {
        do {
            try await perform {
                let r = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                if !assets.isEmpty { r.addAssets(assets as NSArray) }
            }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
    static func rename(_ album: PHAssetCollection, to name: String) async -> Bool {
        do { try await perform { PHAssetCollectionChangeRequest(for: album)?.title = name }; return true } catch { return false }
    }
    static func deleteAlbum(_ album: PHAssetCollection) async -> Bool {
        do { try await perform { PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray) }; return true } catch { return false }
    }
    static func setDate(_ asset: PHAsset, _ date: Date) async -> Bool {
        do { try await perform { PHAssetChangeRequest(for: asset).creationDate = date }; await Haptics.shared.success(); return true }
        catch { await Haptics.shared.error(); return false }
    }
    static func setLocation(_ asset: PHAsset, _ loc: CLLocation?) async -> Bool {
        do { try await perform { PHAssetChangeRequest(for: asset).location = loc }; await Haptics.shared.success(); return true }
        catch { await Haptics.shared.error(); return false }
    }
    static func revert(_ asset: PHAsset) async -> Bool {
        guard asset.hasAdjustments else { return false }
        do { try await perform { PHAssetChangeRequest(for: asset).revertAssetContentToOriginal() }; await Haptics.shared.success(); return true }
        catch { await Haptics.shared.error(); return false }
    }

    // MARK: Export de fichiers originaux (partage, copie, duplication)
    static func exportOriginal(_ asset: PHAsset, resource: PHAssetResource? = nil) async throws -> URL {
        guard let res = resource ?? asset.primaryResource else { throw MediaError.message("Ressource introuvable.") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("galerie-export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + res.originalFilename)
        let o = PHAssetResourceRequestOptions(); o.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: res, toFile: url, options: o)
        return url
    }
    static func shareItems(_ assets: [PHAsset]) async -> [URL] {
        var urls: [URL] = []
        for a in assets { if let u = try? await exportOriginal(a) { urls.append(u) } }
        return urls
    }
    static func copyToPasteboard(_ asset: PHAsset) async -> Bool {
        guard !asset.isVideo, let u = try? await exportOriginal(asset), let img = UIImage(contentsOfFile: u.path) else { return false }
        UIPasteboard.general.image = img; await Haptics.shared.success(); return true
    }
    static func duplicate(_ asset: PHAsset) async -> Bool {
        guard let res = asset.primaryResource, let u = try? await exportOriginal(asset, resource: res) else { return false }
        do {
            try await perform {
                let r = PHAssetCreationRequest.forAsset()
                r.addResource(with: asset.isVideo ? .video : .photo, fileURL: u, options: nil)
                r.creationDate = asset.creationDate; r.location = asset.location
            }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
    /// Enregistre la partie vidéo d’une Live Photo comme vidéo indépendante.
    static func saveLiveAsVideo(_ asset: PHAsset) async -> Bool {
        guard let res = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }),
              let u = try? await exportOriginal(asset, resource: res) else { return false }
        let mov = u.deletingPathExtension().appendingPathExtension("mov")
        try? FileManager.default.moveItem(at: u, to: mov)
        do {
            try await perform {
                let r = PHAssetCreationRequest.forAsset()
                r.addResource(with: .video, fileURL: mov, options: nil)
                r.creationDate = asset.creationDate; r.location = asset.location
            }
            await Haptics.shared.success(); return true
        } catch { await Haptics.shared.error(); return false }
    }
}

// MARK: - Albums
enum Albums {
    static func userAlbums() -> [PHAssetCollection] {
        var out: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in out.append(c) }
        return out
    }
    static func sharedAlbums() -> [PHAssetCollection] {
        var out: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil).enumerateObjects { c, _, _ in out.append(c) }
        return out
    }
    static func count(_ c: PHAssetCollection) -> Int {
        let n = c.estimatedAssetCount
        return n == NSNotFound ? PHAsset.fetchAssets(in: c, options: nil).count : n
    }
}
