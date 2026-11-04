import Foundation
import TilesCore

/// Loads `~/.config/tiles/config.json`, creates it on first run, and reloads it
/// whenever it changes on disk.
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tiles", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("config.json")

    private(set) var config: Config = .default
    private(set) var lastError: String?
    var onChange: ((Config) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var lastModified: Date?
    private var reloadWork: DispatchWorkItem?

    init() {
        ensureFileExists()
        load()
        watch()
    }

    deinit { source?.cancel() }

    func ensureFileExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: Self.fileURL.path) else { return }
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if let data = try? Config.default.encoded() {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    @discardableResult
    func load() -> Bool {
        lastModified = modificationDate()
        do {
            let data = try Data(contentsOf: Self.fileURL)
            config = try Config.decode(data)
            lastError = nil
            return true
        } catch let error as DecodingError {
            lastError = Self.describe(error)
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// Changes a setting from the menu and writes it back to the file.
    func update(_ change: (inout Config) -> Void) {
        var updated = config
        change(&updated)
        config = updated
        if let data = try? updated.encoded() {
            try? data.write(to: Self.fileURL, options: .atomic)
            lastModified = modificationDate()
        }
        onChange?(updated)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path))?[.modificationDate] as? Date
    }

    /// Watches the directory, because editors save by replacing the file.
    private func watch() {
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let modified = self.modificationDate()
            guard modified != self.lastModified else { return }
            self.load()
            self.onChange?(self.config)
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let p = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
            return p.isEmpty ? "" : " at \(p)"
        }
        switch error {
        case .dataCorrupted(let c): return "Invalid JSON\(path(c)): \(c.debugDescription)"
        case .keyNotFound(let key, let c): return "Missing \(key.stringValue)\(path(c))"
        case .typeMismatch(_, let c): return "Wrong type\(path(c)): \(c.debugDescription)"
        case .valueNotFound(_, let c): return "Missing value\(path(c))"
        @unknown default: return error.localizedDescription
        }
    }
}
