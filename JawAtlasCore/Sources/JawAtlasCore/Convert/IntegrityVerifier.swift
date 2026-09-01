import Foundation

public enum IntegrityVerifier {
    public static func loadManifest(in directory: URL) throws -> BundleManifest {
        let url = BundleLayout.manifestURL(in: directory)
        guard let data = try? Data(contentsOf: url) else {
            throw VolumeError.caseMissing(directory.lastPathComponent)
        }
        do {
            let manifest = try BundleManifest.decoder().decode(BundleManifest.self, from: data)
            return try manifest.validated()
        } catch let error as VolumeError {
            throw error
        } catch {
            throw VolumeError.bundleCorrupt("manifest")
        }
    }

    public static func quickCheck(manifest: BundleManifest, directory: URL) throws {
        let volume = BundleLayout.volumeURL(in: directory)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: volume.path),
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            throw VolumeError.bundleCorrupt("missing volume")
        }
        guard size == manifest.volumeByteCount else {
            throw VolumeError.bundleCorrupt("size mismatch")
        }
    }

    public static func deepVerify(manifest: BundleManifest, directory: URL) throws {
        try quickCheck(manifest: manifest, directory: directory)
        let hash = try StreamingHasher.hexOfFile(at: BundleLayout.volumeURL(in: directory))
        guard hash == manifest.volumeSHA256 else { throw VolumeError.hashMismatch }
    }

    public static func denyListHit(in manifestData: Data, denyValues: [String]) -> String? {
        guard let text = String(data: manifestData, encoding: .utf8)?.lowercased() else { return nil }
        for value in denyValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            if text.contains(trimmed.lowercased()) { return trimmed }
        }
        if text.contains("dicm") { return "DICM" }
        return nil
    }
}
