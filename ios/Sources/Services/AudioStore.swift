// Recordings live in the store, as external binary data, so they sync and
// survive the app; this directory is where they are while being made and
// a cache of them for playback, which needs a file.

import Foundation

enum AudioStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    static func newFileName() -> String {
        "\(UUID().uuidString).m4a"
    }

    static func exists(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: file).path)
    }

    static func delete(_ file: String) {
        try? FileManager.default.removeItem(at: url(for: file))
    }

    /// Brings an outside file (a share, a Files pick) into the store under
    /// a fresh name; the caller owns the security scope.
    static func adopt(_ source: URL) throws -> String {
        let name = "\(UUID().uuidString).\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)"
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    /// A file to play: the cached one if it is here, else the entry's
    /// data written out under its name. Nil when there is no recording.
    static func playbackURL(file: String?, data: Data?) -> URL? {
        if let file, exists(file) { return url(for: file) }
        guard let data else { return nil }
        let name = file ?? "\(UUID().uuidString).m4a"
        let target = url(for: name)
        try? data.write(to: target)
        return target
    }

    /// The bytes behind a file name, for putting into the store.
    static func data(for file: String) -> Data? {
        try? Data(contentsOf: url(for: file))
    }
}
