// Where recordings live: one flat directory under Documents, so iOS
// device backup carries them and export can copy the folder wholesale.

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
}
