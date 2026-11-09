import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import TilesCore

// MARK: - Model

/// Edits a copy of the config and writes it back shortly after each change.
final class SettingsModel: ObservableObject {
    @Published var config: Config { didSet { scheduleSave() } }
    @Published var section: SettingsSection? = .dashboard
    @Published var preset = Preset.laptop
    @Published var windowCount = 4
    /// Size for the "Custom" preview, in points.
    @Published var customWidth: Double = 2560
    @Published var customHeight: Double = 1440

    var previewArea: Rect {
        preset == .custom
            ? Rect(x: 0, y: 0, width: max(400, customWidth), height: max(300, customHeight))
            : preset.area
    }

    /// Fills the custom size from this Mac's main display.
    func useMainScreenSize() {
        guard let screen = NSScreen.main else { return }
        customWidth = Double(screen.visibleFrame.width).rounded()
        customHeight = Double(screen.visibleFrame.height).rounded()
    }
    @Published var scenes: [SavedScene] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var trusted = AccessibilityPermission.isTrusted
    @Published var live: [TilingManager.DisplayStatus] = []
    @Published var lastSaved: Date?
    @Published var profiles: [String] = []

    let perform: (Command) -> Void
    let setLayout: (LayoutKind, String) -> Void
    let showWorkspace: (Int, String) -> Void
    let updater: Updater
    private let status: () -> [TilingManager.DisplayStatus]
    private let store: ConfigStore
    private var saveWork: DispatchWorkItem?
    private var liveTimer: Timer?

    init(store: ConfigStore,
         perform: @escaping (Command) -> Void,
         setLayout: @escaping (LayoutKind, String) -> Void,
         showWorkspace: @escaping (Int, String) -> Void,
         status: @escaping () -> [TilingManager.DisplayStatus],
         updater: Updater) {
        self.store = store
        self.updater = updater
        self.showWorkspace = showWorkspace
        self.perform = perform
        self.setLayout = setLayout
        self.status = status
        self.config = store.config
        reloadScenes()
        reloadProfiles()
        live = status()
        // The dashboard follows windows as they open, close and move.
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let live = self.status(), trusted = AccessibilityPermission.isTrusted
            if live != self.live { self.live = live }
            if trusted != self.trusted { self.trusted = trusted }
        }
    }

    deinit { liveTimer?.invalidate() }

    // MARK: Profiles: named copies of the whole config in ~/.config/tiles/profiles

    static let profilesDirectory = ConfigStore.directory.appendingPathComponent("profiles", isDirectory: true)

    private static func profileURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        return profilesDirectory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func reloadProfiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.profilesDirectory, includingPropertiesForKeys: nil)) ?? []
        profiles = files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    func saveProfile(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let data = try? config.encoded() else { return }
        try? FileManager.default.createDirectory(at: Self.profilesDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.profileURL(name), options: .atomic)
        reloadProfiles()
    }

    func applyProfile(_ name: String) {
        guard let data = try? Data(contentsOf: Self.profileURL(name)), let loaded = try? Config.decode(data) else { return }
        config = loaded
    }

    func deleteProfile(_ name: String) {
        try? FileManager.default.removeItem(at: Self.profileURL(name))
        reloadProfiles()
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tiles Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? config.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let loaded = try? Config.decode(data) else { return }
        config = loaded
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.config != self.store.config else { return }
            let config = self.config
            self.store.update { $0 = config }
            self.lastSaved = Date()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    var accent: Color { Color(nsColor: NSColor(hex: config.theme.hex) ?? .controlAccentColor) }

    /// Switching theme recolours the focus outline too, unless it's off.
    func setTheme(_ theme: Theme) {
        config.theme = theme
        if !config.outlineColor.isEmpty { config.outlineColor = theme.hex }
    }

    func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        try? on ? service.register() : service.unregister()
        launchAtLogin = service.status == .enabled
    }

    struct SavedScene: Identifiable {
        let id: String
        let scene: TilesCore.Scene
        var windowCount: Int { scene.displays.values.reduce(0) { $0 + $1.apps.count } }
    }

    func reloadScenes() {
        scenes = SceneStore.load(from: TilingManager.scenesURL).scenes
            .map { SavedScene(id: $0.key, scene: $0.value) }
            .sorted { $0.scene.savedAt > $1.scene.savedAt }
    }

    func deleteScene(_ id: String) {
        var store = SceneStore.load(from: TilingManager.scenesURL)
        store.scenes[id] = nil
        try? store.write(to: TilingManager.scenesURL)
        reloadScenes()
    }

    /// Typical usable areas, in points, for the preview.
    enum Preset: String, CaseIterable {
        case laptop = "MacBook 14″", studio = "27″", ultrawide = "34″ ultrawide", superUltrawide = "49″", custom = "Custom"

        var area: Rect {
            switch self {
            case .custom: return Rect(x: 0, y: 0, width: 2560, height: 1440)
            case .laptop: return Rect(x: 0, y: 0, width: 1512, height: 945)
            case .studio: return Rect(x: 0, y: 0, width: 2560, height: 1415)
            case .ultrawide: return Rect(x: 0, y: 0, width: 3440, height: 1415)
            case .superUltrawide: return Rect(x: 0, y: 0, width: 5120, height: 1415)
            }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard, general, layouts, spacing, appearance, mouse, scenes, shortcuts, rules, profiles, about
    var id: String { rawValue }

    var title: String { NSLocalizedString(englishTitle, comment: "Sidebar section") }

    private var englishTitle: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .profiles: return "Profiles"
        case .general: return "General"
        case .layouts: return "Layouts"
        case .spacing: return "Gaps & Sizing"
        case .appearance: return "Appearance"
        case .mouse: return "Mouse"
        case .scenes: return "Scenes"
        case .shortcuts: return "Shortcuts"
        case .rules: return "App Rules"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .profiles: return "tray.full"
        case .general: return "gearshape"
        case .layouts: return "rectangle.split.3x1"
        case .spacing: return "square.dashed"
        case .appearance: return "paintpalette"
        case .mouse: return "cursorarrow.motionlines"
        case .scenes: return "display.2"
        case .shortcuts: return "keyboard"
        case .rules: return "macwindow.on.rectangle"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $model.section) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch model.section ?? .dashboard {
                case .dashboard: DashboardPane(model: model)
                case .profiles: ProfilesPane(model: model)
                case .general: GeneralPane(model: model)
                case .layouts: LayoutsPane(model: model)
                case .spacing: SpacingPane(model: model)
                case .appearance: AppearancePane(model: model)
                case .mouse: MousePane(model: model)
                case .scenes: ScenesPane(model: model)
                case .shortcuts: ShortcutsPane(model: model)
                case .rules: RulesPane(model: model)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((model.section ?? .general).title)
            .navigationSubtitle(model.lastSaved == nil ? "" : "All changes saved")
        }
        .frame(minWidth: 820, minHeight: 580)
        .tint(model.accent)
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tiles").font(.title2.bold())
                        Text("Tiling for every display").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Tile windows automatically", isOn: $model.config.enabled)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Accessibility access") {
                    if model.trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { AccessibilityPermission.request() }
                    }
                }
            }
            Section {
                Picker("Show Tiles in", selection: $model.config.iconPlacement) {
                    Text("Menu bar").tag(IconPlacement.menuBar)
                    Text("Dock").tag(IconPlacement.dock)
                    Text("Both").tag(IconPlacement.both)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("You can also open Tiles any time from Spotlight or Finder.")
            }
            Section("Windows") {
                Picker("New windows open", selection: $model.config.newWindowPlacement) {
                    Text("At the end").tag(NewWindowPlacement.end)
                    Text("As the main window").tag(NewWindowPlacement.master)
                    Text("Next to the focused window").tag(NewWindowPlacement.afterFocused)
                }
                Toggle("Mouse follows keyboard focus", isOn: $model.config.mouseFollowsFocus)
                Toggle("Put windows back where they were when Tiles quits", isOn: $model.config.restoreWindowsOnQuit)
                Toggle("Focus follows mouse", isOn: $model.config.focusFollowsMouse)
                    .help("Hovering over a tiled window focuses it")
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $model.config.checkForUpdates)
                HStack {
                    Text("Version \(model.updater.current)")
                    if !model.updater.status.isEmpty {
                        Text("· \(model.updater.status)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let version = model.updater.available {
                        Button("Install Tiles \(version)") { model.updater.install() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Check Now") { model.updater.check() }
                    }
                }
            }
            Section {
                Button("Restore All Defaults…", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Your settings save automatically the moment you change them.")
            }
        }
        .confirmationDialog("Restore all settings to their defaults?", isPresented: $confirmReset) {
            Button("Restore Defaults", role: .destructive) { model.config = .default }
        }
        .onAppear { model.trusted = AccessibilityPermission.isTrusted }
    }
}

private struct LayoutsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                PreviewPanel(model: model)
            }
            Section("Default layout") {
                LayoutGrid(selection: $model.config.defaultLayout, model: model)
            }
            Section {
                Picker("Ultrawide layout", selection: $model.config.ultrawideLayout) {
                    ForEach(LayoutKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Used automatically on displays at least \(String(format: "%.1f", model.config.layout.ultrawideAspectRatio))× wider than tall.")
            }
            Section("Connected displays") {
                ForEach(Display.current(), id: \.id) { display in
                    Picker(display.name, selection: Binding<LayoutKind?>(
                        get: { model.config.displays[display.name] },
                        set: { model.config.displays[display.name] = $0 }
                    )) {
                        Text("Automatic").tag(LayoutKind?.none)
                        Divider()
                        ForEach(LayoutKind.allCases, id: \.self) { Text($0.displayName).tag(LayoutKind?.some($0)) }
                    }
                }
            }
        }
    }
}

private struct SpacingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section { PreviewPanel(model: model) }
            Section("Gaps") {
                slider("Between windows", $model.config.layout.innerGap, 0...40, 2) { "\(Int($0)) pt" }
                slider("Screen edges", $model.config.layout.outerGap, 0...40, 2) { "\(Int($0)) pt" }
            }
            Section("Main window") {
                slider("Size", $model.config.layout.masterRatio, 0.2...0.8, 0.05) { "\(Int($0 * 100))%" }
                Stepper("Windows in main area: \(model.config.layout.masterCount)", value: $model.config.layout.masterCount, in: 1...6)
            }
            Section {
                slider("Width cap", $model.config.layout.maxTileWidth, 0...4000, 100) { $0 == 0 ? "Off" : "\(Int($0)) pt" }
                slider("New window width (Scrolling)", $model.config.layout.scrollWidth, 0.2...1, 0.05) { "\(Int($0 * 100))% of the screen" }
                slider("Lone window on ultrawide", $model.config.layout.ultrawideSingleWindowRatio, 0.3...1, 0.05) { "\(Int($0 * 100))% wide" }
                Stepper("Tiles per display: \(model.config.layout.maxTiles == 0 ? "Automatic" : "\(model.config.layout.maxTiles)")",
                        value: $model.config.layout.maxTiles, in: 0...24)
            } header: {
                Text("Big and small screens")
            } footer: {
                Text("When a display is full, new windows stack on the last tile. Press ⌃⌥N to flip through a stack.")
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double,
                        format: @escaping (Double) -> String) -> some View {
        LabeledContent {
            HStack {
                Slider(value: value, in: range, step: step)
                Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Appearance", selection: $model.config.appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                    Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                    Label("Dark", systemImage: "moon").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
            }
            Section("Theme") {
                HStack(spacing: 14) {
                    ForEach(Theme.allCases, id: \.self) { theme in themeCard(theme) }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Outline the focused window", isOn: Binding(
                    get: { !model.config.outlineColor.isEmpty },
                    set: { model.config.outlineColor = $0 ? model.config.theme.hex : "" }
                ))
                if !model.config.outlineColor.isEmpty {
                    ColorPicker("Outline colour", selection: outlineColor, supportsOpacity: false)
                }
            } footer: {
                Text("A border around the focused tiled window, so you always know where your keystrokes go. It follows the theme unless you pick a colour.")
            }
            Section { PreviewPanel(model: model) }
        }
    }

    private func themeCard(_ theme: Theme) -> some View {
        let color = Color(nsColor: NSColor(hex: theme.hex) ?? .gray)
        let selected = model.config.theme == theme
        return Button { model.setTheme(theme) } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 44)
                    .overlay(selected ? Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) : nil)
                Text(theme.displayName).font(.callout)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? color.opacity(0.15) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? color : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var outlineColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: model.config.outlineColor) ?? .gray) },
            set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                model.config.outlineColor = String(format: "#%02X%02X%02X",
                    Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            }
        )
    }
}

private struct MousePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Drag a window onto another to swap them", isOn: $model.config.dragToSwap)
                Toggle("Resizing a window moves the split", isOn: $model.config.resizeToAdjustRatio)
                Toggle("Animate windows into place", isOn: $model.config.animateWindows)
            } footer: {
                Text("Drag a window to another display to move it there. Hold ⌥ (Option) while dropping to stack it with the window underneath; drag it out again to unstack. Other resizes snap back to the grid.")
            }
            Section {
                Text("Hold ⌃⌥ and scroll, or swipe sideways on the trackpad, to slide the strip.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scrolling layout")
            }
        }
    }
}

private struct ScenesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Restore scenes when displays change", isOn: $model.config.autoRestoreScenes)
                HStack {
                    Button("Save Current Scene") { model.perform(.saveScene); model.reloadScenes() }
                    Button("Restore Now") { model.perform(.restoreScene) }
                }
            } footer: {
                Text("A scene is the layout and app order for one combination of displays. Tiles saves it as you work and brings it back when you dock. It stores app identifiers only, never window titles.")
            }
            Section("Saved scenes") {
                if model.scenes.isEmpty {
                    Text("None yet. Arrange some windows and Tiles saves the scene a few seconds later.").foregroundStyle(.secondary)
                }
                ForEach(model.scenes) { saved in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(saved.scene.displays.count) display\(saved.scene.displays.count == 1 ? "" : "s") · \(saved.windowCount) windows")
                            Text(saved.scene.displays.values.map(\.layout.displayName).joined(separator: " + "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(saved.scene.savedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.deleteScene(saved.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .onAppear { model.reloadScenes() }
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(Command.all, id: \.name) { command in
                    LabeledContent(title(command)) {
                        ShortcutRecorder(shortcuts: model.config.shortcuts(for: command)) { model.config.bind($0, to: command) }
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the new keys. Esc cancels. Every command also works as a tiles:// link.")
            }
            Section {
                Button("Reset All Shortcuts") { model.config.hotkeys = [:] }
            }
        }
    }

    private func title(_ command: Command) -> String {
        if case .setLayout(let kind) = command { return "Layout: \(kind.displayName)" }
        let words = command.name.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

private struct RulesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                if model.config.rules.isEmpty {
                    Text("No rules yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.config.rules.enumerated()), id: \.offset) { index, rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("App or bundle ID", text: text(index, \.app))
                            TextField("Title contains (optional)", text: text(index, \.titleContains))
                            Button(role: .destructive) { model.config.rules.remove(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                        HStack(spacing: 16) {
                            Toggle("Float", isOn: Binding(
                                get: { rule.float ?? false },
                                set: { model.config.rules[index].float = $0 }
                            ))
                            Picker("Open on", selection: Binding<String>(
                                get: { rule.display ?? "" },
                                set: { model.config.rules[index].display = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Any display").tag("")
                                ForEach(displayNames(including: rule.display), id: \.self) { Text($0).tag($0) }
                            }
                            .fixedSize()
                            .disabled(rule.float == true)
                            Toggle("Main tile", isOn: Binding(
                                get: { rule.master ?? false },
                                // An explicit false, so a later rule can override an earlier "main tile" one.
                                set: { model.config.rules[index].master = $0 }
                            ))
                            .disabled(rule.float == true)
                        }
                        .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("App rules")
            } footer: {
                Text("Float keeps an app's windows out of the tiles. Otherwise, new windows of that app open on the display you pick, optionally in the main tile. The last matching rule wins. ⌃⌥F floats or tiles any single window.")
            }
            Section {
                HStack {
                    Menu("Float an App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                model.config.rules.append(WindowRule(app: app.bundleIdentifier, float: true))
                            }
                        }
                    }
                    Menu("Place an App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                model.config.rules.append(WindowRule(app: app.bundleIdentifier, display: Display.current().first?.name))
                            }
                        }
                    }
                    Button("Add Empty Rule") { model.config.rules.append(WindowRule(app: "")) }
                }
                .fixedSize()
            }
        }
    }

    /// Connected displays, plus a saved name that isn't connected right now.
    private func displayNames(including saved: String?) -> [String] {
        var names = Display.current().map(\.name)
        if let saved, !saved.isEmpty, !names.contains(saved) { names.append(saved) }
        return names
    }

    private var runningApps: [NSRunningApplication] {
        WorkspaceObserver.managedApps()
            .filter { $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func text(_ index: Int, _ field: WritableKeyPath<WindowRule, String?>) -> Binding<String> {
        Binding(
            get: { model.config.rules.indices.contains(index) ? model.config.rules[index][keyPath: field] ?? "" : "" },
            set: { model.config.rules[index][keyPath: field] = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Tiles").font(.largeTitle.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Free and open source under the MIT License.")
            HStack {
                Link("GitHub", destination: AppDelegate.repoURL)
                Text("·").foregroundStyle(.secondary)
                Link("Report an Issue", destination: AppDelegate.repoURL.appendingPathComponent("issues"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardPane: View {
    @ObservedObject var model: SettingsModel

    private var windowCount: Int { model.live.reduce(0) { $0 + $1.tiles.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !model.trusted { permissionBanner }
                ForEach(model.live) { display in displayCard(display) }
                actions
                tips
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tiles").font(.title.bold())
                HStack(spacing: 6) {
                    Circle().fill(model.config.enabled ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(model.config.enabled
                         ? "Tiling \(windowCount) window\(windowCount == 1 ? "" : "s") on \(model.live.count) display\(model.live.count == 1 ? "" : "s")"
                         : "Tiling is paused")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Tiling", isOn: $model.config.enabled).toggleStyle(.switch).labelsHidden().controlSize(.large)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tiles needs Accessibility access to move windows.")
                Text("Already switched on in Settings? Click Reset, then switch Tiles on again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset") { AccessibilityPermission.reset() }
            Button("Grant Access…") { AccessibilityPermission.request() }
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func displayCard(_ display: TilingManager.DisplayStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "display")
                Text(display.name).font(.headline)
                Text("\(display.tiles.count) window\(display.tiles.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                if display.workspaces.count > 1 {
                    Picker("Workspace", selection: Binding(
                        get: { display.workspace },
                        set: { model.showWorkspace($0, display.id) }
                    )) {
                        ForEach(display.workspaces, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("Workspaces on this display")
                }
                Menu(display.layout.displayName) {
                    ForEach(LayoutKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { model.setLayout(kind, display.id) }
                    }
                }
                .fixedSize()
            }
            if display.tiles.isEmpty {
                Text(display.layout == .float ? "Tiles leaves this display alone." : "No windows on this display.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                TilesCanvas(area: display.size, frames: display.tiles.map(\.frame),
                            labels: display.tiles.map(\.app), accent: model.accent)
                    .frame(maxHeight: 220)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            action("Retile", "arrow.triangle.2.circlepath", .retile)
            action("Save Scene", "square.and.arrow.down", .saveScene)
            action("Restore Scene", "clock.arrow.circlepath", .restoreScene)
            action("Next Layout", "rectangle.split.3x1", .nextLayout)
        }
    }

    private func action(_ title: String, _ icon: String, _ command: Command) -> some View {
        Button { model.perform(command) } label: {
            Label(LocalizedStringKey(title), systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .controlSize(.large)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Handy shortcuts").font(.headline)
            Group {
                Text("⌃⌥ + arrows  focus a window   ·   ⌃⌥⇧ + arrows  swap")
                Text("⌃⌥Space  next layout   ·   ⌃⌥M  fill the screen   ·   ⌃⌥F  float")
                Text("⌃⌥1–9  switch desktop   ·   ⌃⌥⇧1–9  send the window there   ·   ⌃⌥/  all shortcuts")
                Text("Drag a window onto another to swap them; hold ⌥ to stack them instead.")
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ProfilesPane: View {
    @ObservedObject var model: SettingsModel
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Profile name, e.g. Desk or Travel", text: $name)
                    Button("Save Current Settings") {
                        model.saveProfile(name)
                        name = ""
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Save your settings")
            } footer: {
                Text("A profile is a snapshot of every setting: layouts, gaps, colours, shortcuts and rules. Your current settings already save automatically.")
            }
            Section("Saved profiles") {
                if model.profiles.isEmpty {
                    Text("No profiles yet.").foregroundStyle(.secondary)
                }
                ForEach(model.profiles, id: \.self) { profile in
                    HStack {
                        Image(systemName: "tray.full")
                        Text(profile)
                        Spacer()
                        Button("Apply") { model.applyProfile(profile) }
                        Button(role: .destructive) { model.deleteProfile(profile) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Section("Move settings between Macs") {
                HStack {
                    Button("Export Settings…") { model.exportSettings() }
                    Button("Import Settings…") { model.importSettings() }
                }
            }
        }
        .onAppear { model.reloadProfiles() }
    }
}

// MARK: - Shared pieces

/// Live preview of the current settings on a chosen display size.
private struct PreviewPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let area = model.previewArea
        let kind = model.config.layoutKind(forDisplayNamed: model.preset.rawValue, aspectRatio: area.width / area.height)
        VStack(spacing: 10) {
            Picker("Display", selection: $model.preset) {
                ForEach(SettingsModel.Preset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.preset == .custom {
                HStack(spacing: 8) {
                    TextField("Width", value: $model.customWidth, format: .number).frame(width: 80)
                    Text("×").foregroundStyle(.secondary)
                    TextField("Height", value: $model.customHeight, format: .number).frame(width: 80)
                    Text("points").foregroundStyle(.secondary)
                    Spacer()
                    Button("Use This Mac's Screen") { model.useMainScreenSize() }
                }
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            }
            LayoutPreview(kind: kind, area: area, count: model.windowCount, parameters: model.config.layout, accent: model.accent)
                .frame(height: 200)
            HStack {
                Text("\(kind.displayName) on this display").foregroundStyle(.secondary)
                Spacer()
                Stepper("\(model.windowCount) windows", value: $model.windowCount, in: 1...12)
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

/// Clickable cards, each a small preview of one layout.
private struct LayoutGrid: View {
    @Binding var selection: LayoutKind
    @ObservedObject var model: SettingsModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(LayoutKind.allCases, id: \.self) { kind in
                Button { selection = kind } label: {
                    VStack(spacing: 6) {
                        LayoutPreview(kind: kind, area: Rect(x: 0, y: 0, width: 1600, height: 1000), count: 4,
                                      parameters: LayoutParameters(innerGap: 24, outerGap: 24, maxTiles: 12), accent: model.accent)
                            .frame(height: 64)
                        Text(kind.displayName).font(.caption).lineLimit(1)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selection == kind ? model.accent.opacity(0.15) : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selection == kind ? model.accent : Color.secondary.opacity(0.25),
                                                                       lineWidth: selection == kind ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LayoutPreview: View {
    let kind: LayoutKind
    let area: Rect
    let count: Int
    let parameters: LayoutParameters
    let accent: Color

    var body: some View {
        TilesCanvas(area: area, frames: LayoutEngine.frames(count: count, in: area, kind: kind, parameters: parameters),
                    labels: [], accent: accent)
    }
}

/// Draws tiles scaled into the available space, optionally labelled with app names.
struct TilesCanvas: View {
    let area: Rect
    let frames: [Rect]
    let labels: [String]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / area.width, geo.size.height / area.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: area.width * scale, height: area.height * scale)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(accent.opacity(index == 0 ? 0.85 : 0.35))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                        .overlay(alignment: .topLeading) {
                            if index < labels.count, !labels[index].isEmpty {
                                Text(labels[index])
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(index == 0 ? Color.white : Color.primary)
                                    .lineLimit(1)
                                    .padding(6)
                            }
                        }
                        .frame(width: frame.width * scale, height: frame.height * scale)
                        .offset(x: frame.x * scale, y: frame.y * scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped() // Scrolling windows waiting off screen stay inside the card
            .animation(.easeInOut(duration: 0.25), value: frames)
        }
        .aspectRatio(area.width / max(1, area.height), contentMode: .fit)
    }
}

/// Click, press keys, done. Esc cancels.
private struct ShortcutRecorder: View {
    let shortcuts: [Shortcut]
    let onChange: (Shortcut?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press keys…" : (shortcuts.isEmpty ? "Record" : shortcuts.map(\.description).joined(separator: "  "))) {
                recording ? stop() : start()
            }
            .frame(minWidth: 120)
            if !shortcuts.isEmpty {
                Button { onChange(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        // Tiles' own global shortcuts would swallow the keys before this window sees them.
        NotificationCenter.default.post(name: .tilesShortcutRecording, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let shortcut = Shortcut(event: event) {
                onChange(shortcut)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .tilesShortcutRecording, object: false)
    }
}

extension Notification.Name {
    /// Posted with `true` when the shortcut recorder starts listening and `false` when it stops.
    static let tilesShortcutRecording = Notification.Name("TilesShortcutRecording")
}

extension Shortcut {
    init?(event: NSEvent) {
        guard let key = KeyCodes.name(for: Int(event.keyCode)) else { return nil }
        var mods: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        guard !mods.isEmpty else { return nil }
        self.init(modifiers: mods, key: key)
    }
}
