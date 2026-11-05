import Foundation

/// Installs an immutable version of bundled media into a writable per-user directory.
/// Call before loading a preset that refers to ManagedMedia/v1.
enum ManagedMediaInstaller {
    enum Error: Swift.Error { case missingResource(String), invalidOwner }
    private static let assets = [
        "CPU-Memory/chart.applescript", "CPU-Memory/icon.applescript", "CPU-Memory/toggle.applescript",
        "CPU-Memory/cpu.png", "CPU-Memory/memory.png",
        "SpotifyArtwork/artwork.applescript", "SpotifyArtwork/artwork-placeholder.png",
        "SpotifyArtwork/play-state.applescript", "SpotifyArtwork/toggle.applescript",
        "SpotifyArtwork/previous.applescript", "SpotifyArtwork/next.applescript",
        "SpotifyArtwork/play.png", "SpotifyArtwork/pause.png", "SpotifyArtwork/unavailable.png",
        "SpotifyArtwork/previous.png", "SpotifyArtwork/next.png"
    ]
    private static let helpers = ["graph": "CPU-Memory/graph", "artwork-worker": "SpotifyArtwork/artwork-worker"]

    @discardableResult
    static func install(resources: URL, helpers: URL, support: URL, ownerID: String) throws -> URL {
        guard !ownerID.isEmpty, ownerID.rangeOfCharacter(from: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).inverted) == nil else { throw Error.invalidOwner }
        let fm = FileManager.default
        let base = support.appendingPathComponent("MTMR/ManagedMedia", isDirectory: true)
        let destination = base.appendingPathComponent("v1", isDirectory: true)
        let source = resources.appendingPathComponent("ManagedMedia/v1", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        for relative in assets where !fm.fileExists(atPath: source.appendingPathComponent(relative).path) { throw Error.missingResource(relative) }
        for name in Self.helpers.keys where !fm.fileExists(atPath: helpers.appendingPathComponent(name).path) { throw Error.missingResource(name) }
        if !fm.fileExists(atPath: destination.path) {
            let temporary = base.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: temporary) }
            try fm.copyItem(at: source, to: temporary)
            for (name, relative) in Self.helpers { try fm.copyItem(at: helpers.appendingPathComponent(name), to: temporary.appendingPathComponent(relative)) }
            try fm.copyItem(at: temporary.appendingPathComponent("SpotifyArtwork/artwork-placeholder.png"), to: temporary.appendingPathComponent("SpotifyArtwork/artwork.png"))
            try "cpu\n".write(to: temporary.appendingPathComponent("CPU-Memory/mode.txt"), atomically: true, encoding: .utf8)
            do { try fm.moveItem(at: temporary, to: destination) }
            catch { if !fm.fileExists(atPath: destination.path) { throw error } }
        }
        // An existing managed version is left intact; fail explicitly if incomplete.
        for relative in assets + Array(Self.helpers.values) + ["SpotifyArtwork/artwork.png"] where !fm.fileExists(atPath: destination.appendingPathComponent(relative).path) { throw Error.missingResource(relative) }
        try (ownerID + "\n").write(to: destination.appendingPathComponent("SpotifyArtwork/owner-bundle-id"), atomically: true, encoding: .utf8)
        return destination
    }
}
