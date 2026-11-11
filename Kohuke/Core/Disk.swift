import Foundation

/// What the phone keeps between launches.
///
/// The last shelf the site answered, and every deck, lesson, song and
/// conversation that has been opened, each as the bytes that came back, in
/// Application Support. A launch on a plane still has a shelf, and a deck
/// opened once can be read there. The one file compiled into the build is
/// `Seed/app-strings.json`, the few strings only an app needs.
enum Disk {
    private static var folder: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("content", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func read(_ name: String) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func write(_ data: Data, _ name: String) {
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    /// Everything kept, gone: what the phone held of somebody's shelf goes
    /// when they sign out.
    static func forget() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A file compiled into the app. Xcode's synchronised folder copies the
    /// resources flat into the bundle, but this also looks under `Seed/` in
    /// case a future project setting keeps the folder.
    static func bundled(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Seed")
    }

    static func seed(_ name: String) -> Data? {
        guard let url = bundled(name, "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}
