import Foundation

/// The saved arrangement of one display: its layout and which apps sit in
/// which tile. Stores app bundle identifiers only, never window titles.
public struct SceneDisplay: Codable, Equatable {
    public var layout: LayoutKind
    public var masterRatio: Double
    public var masterCount: Int
    /// Bundle identifiers in tiling order. An app appears once per window.
    public var apps: [String]

    public init(layout: LayoutKind, masterRatio: Double, masterCount: Int, apps: [String]) {
        self.layout = layout
        self.masterRatio = masterRatio
        self.masterCount = masterCount
        self.apps = apps
    }
}

/// The arrangement across a whole set of connected displays.
public struct Scene: Codable, Equatable {
    /// Keyed by stable display identifier (the display's UUID).
    public var displays: [String: SceneDisplay]
    public var savedAt: Date

    public init(displays: [String: SceneDisplay], savedAt: Date = Date()) {
        self.displays = displays
        self.savedAt = savedAt
    }
}

/// All saved scenes, one per distinct combination of displays.
public struct SceneStore: Codable, Equatable {
    public var scenes: [String: Scene]

    public init(scenes: [String: Scene] = [:]) {
        self.scenes = scenes
    }

    /// A key that identifies a set of displays regardless of arrangement order.
    public static func fingerprint(displayIDs: [String]) -> String {
        displayIDs.sorted().joined(separator: "|")
    }

    public func scene(for displayIDs: [String]) -> Scene? {
        scenes[SceneStore.fingerprint(displayIDs: displayIDs)]
    }

    public mutating func save(_ scene: Scene, for displayIDs: [String]) {
        scenes[SceneStore.fingerprint(displayIDs: displayIDs)] = scene
    }

    public static func load(from url: URL) -> SceneStore {
        guard let data = try? Data(contentsOf: url) else { return SceneStore() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SceneStore.self, from: data)) ?? SceneStore()
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// A window as the scene matcher sees it.
public struct SceneWindow<ID: Hashable>: Equatable {
    public var id: ID
    public var bundleID: String
    public var display: String

    public init(id: ID, bundleID: String, display: String) {
        self.id = id
        self.bundleID = bundleID
        self.display = display
    }
}

public enum SceneMatcher {
    /// Assigns current windows to displays and tile order according to `scene`.
    ///
    /// For each display, each saved app slot takes a matching window, preferring
    /// one already on that display. Windows the scene doesn't mention stay on
    /// their current display, after the restored ones.
    public static func assign<ID: Hashable>(
        scene: Scene,
        windows: [SceneWindow<ID>],
        displays: [String]
    ) -> [String: [ID]] {
        var result: [String: [ID]] = [:]
        for d in displays { result[d] = [] }
        var taken = Set<ID>()
        let ordered = displays.sorted()

        // slots[display][i] is the window picked for the i-th saved app.
        var slots: [String: [ID?]] = [:]
        for display in ordered {
            if let saved = scene.displays[display] {
                slots[display] = Array(repeating: nil, count: saved.apps.count)
            }
        }

        // Pass 1: windows already on the right display. Pass 2: anything left.
        for sameDisplayOnly in [true, false] {
            for display in ordered {
                guard let saved = scene.displays[display], var filled = slots[display] else { continue }
                for (i, app) in saved.apps.enumerated() where filled[i] == nil {
                    let pick = windows.first {
                        $0.bundleID == app && !taken.contains($0.id) && (!sameDisplayOnly || $0.display == display)
                    }
                    guard let pick else { continue }
                    taken.insert(pick.id)
                    filled[i] = pick.id
                }
                slots[display] = filled
            }
        }
        for display in ordered {
            result[display, default: []].append(contentsOf: (slots[display] ?? []).compactMap { $0 })
        }

        for w in windows where !taken.contains(w.id) {
            let target = result[w.display] != nil ? w.display : (displays.first ?? w.display)
            result[target, default: []].append(w.id)
        }
        return result
    }
}
