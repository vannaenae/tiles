import AppKit
import TilesCore

/// Checks GitHub Releases for a newer Tiles and installs it in place.
final class Updater {
    /// Every release is signed by this Apple developer team; anything else is refused.
    static let teamID = "GQ638955FB"
    private static let repo = "vannaenae/tiles"

    /// The one source of truth; see UpdatePhase for the rules.
    private(set) var phase: UpdatePhase = .idle {
        didSet { if phase != oldValue { onChange?() } }
    }
    var available: String? { phase.installable }
    var status: String { phase.message }
    var onChange: (() -> Void)?
    private var timer: Timer?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Checks now and then once a day, or stops checking.
    func setAutomatic(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        // Never interrupt a check or a download that's already running.
        guard phase.canCheck else { return }
        phase = .checking
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let latest = (json?["tag_name"] as? String).map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
            DispatchQueue.main.async {
                guard let self, self.phase == .checking else { return }
                self.phase = .checked(latest: latest, current: self.current)
            }
        }.resume()
    }

    /// Downloads the release, checks its signature, then swaps the app and reopens it.
    func install() {
        // Only from "available" or "failed": a second click while downloading does nothing.
        guard let version = phase.installable,
              let url = URL(string: "https://github.com/\(Self.repo)/releases/download/v\(version)/Tiles.zip") else { return }
        phase = .downloading(version: version)
        URLSession.shared.downloadTask(with: url) { [weak self] file, _, _ in
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("tiles-update-\(UUID().uuidString)")
            let zip = dir.appendingPathComponent("Tiles.zip")
            let newApp = dir.appendingPathComponent("Tiles.app")
            let ok = file != nil
                && (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
                && (try? fm.moveItem(at: file!, to: zip)) != nil
                && Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
                && Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict",
                                                  "-R", "=anchor apple generic and certificate leaf[subject.OU] = \"\(Self.teamID)\"",
                                                  newApp.path])
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else {
                    self.phase = .failed(version: version)
                    return
                }
                self.phase = .installing(version: version)
                // Swap the app once this copy has quit, then reopen it.
                let swap = Process()
                swap.executableURL = URL(fileURLWithPath: "/bin/sh")
                swap.arguments = ["-c",
                    "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; rm -rf \"$2\" && mv \"$3\" \"$2\" && xattr -dr com.apple.quarantine \"$2\"; open \"$2\"",
                    "sh", "\(getpid())", Bundle.main.bundlePath, newApp.path]
                try? swap.run()
                NSApp.terminate(nil)
            }
        }.resume()
    }

    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
