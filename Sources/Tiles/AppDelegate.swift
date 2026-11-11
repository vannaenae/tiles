import AppKit
import SwiftUI
import ServiceManagement
import TilesCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let configStore = ConfigStore()
    private lazy var manager = TilingManager(configStore: configStore)
    private let hotKeys = HotKeyCenter()
    private var statusItem: NSStatusItem!
    private var lastConfig: Config = .default
    private var hotkeyErrors: [String] = []
    private var permissionTimer: Timer?
    private var messageWork: DispatchWorkItem?
    /// Permission and lifecycle, one value. Transitions live in TilesCore (AppPhase.next).
    private var phase = AppPhase.launching
    /// True while the shortcut recorder is listening, so a config reload can't re-arm global shortcuts under it.
    private var hotkeysPaused = false
    private var statusWork: DispatchWorkItem?
    private var lastStatus: Data?
    private let outline = FocusOutline()
    private let badges = StackBadges()
    private let tabBars = TabBars()
    private let cheatSheet = CheatSheet()
    private let finder = WindowFinder()
    private let tour = Tour()
    private let snapPreview = FocusOutline(filled: true)
    let updater = Updater()
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?

    static let repoURL = URL(string: "https://github.com/vannaenae/tiles")!
    static let howItWorksURL = URL(string: "https://i-tilesapp.vercel.app/how-it-works.html")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        lastConfig = configStore.config
        applyAppearance()
        applyIconPlacement()
        configStore.onChange = { [weak self] config in self?.configChanged(config) }
        manager.onStateChange = { [weak self] in self?.updateIcon(); self?.scheduleStatusWrite() }
        manager.onMessage = { [weak self] text in self?.flash(text) }
        manager.onStacks = { [weak self] stacks in
            guard let self else { return }
            let hex = self.configStore.config.theme.hex
            self.tabBars.show(stacks.filter { $0.tabs != nil }, hex: hex)
            self.badges.show(stacks.filter { $0.tabs == nil }.map { (frame: $0.frame, ids: $0.ids) }, hex: hex)
        }
        tabBars.onSelect = { [weak self] id in self?.manager.selectTab(id) }
        badges.onClick = { [weak self] ids in self?.manager.cycleStack(ids) }
        manager.onShowShortcuts = { [weak self] in
            guard let self else { return }
            self.cheatSheet.toggle(config: self.configStore.config)
        }
        manager.onFindWindow = { [weak self] in
            guard let self else { return }
            self.finder.toggle(items: self.manager.windowList())
        }
        finder.onChoose = { [weak self] id in self?.manager.jump(to: id) }
        manager.onShowTour = { [weak self] in self?.showTour() }
        manager.onSnapPreview = { [weak self] frame in
            guard let self else { return }
            self.snapPreview.show(around: frame, hex: self.configStore.config.theme.hex)
        }
        updater.onChange = { [weak self] in
            self?.settingsModel?.objectWillChange.send()
            self?.scheduleStatusWrite()
        }
        updater.setAutomatic(configStore.config.checkForUpdates)
        manager.onFocusFrame = { [weak self] frame in
            guard let self else { return }
            self.outline.show(around: frame, hex: self.configStore.config.outlineColor)
        }
        registerHotKeys()
        NotificationCenter.default.addObserver(forName: .tilesShortcutRecording, object: nil, queue: .main) { [weak self] note in
            self?.hotkeysPaused = note.object as? Bool == true
            self?.registerHotKeys()
        }

        // One watcher owns the permission state: it starts tiling the moment access is
        // granted and keeps the menu bar icon and dashboard banner in step, both ways.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        checkPermission()
        if !AccessibilityPermission.isTrusted {
            // No blocking alert: it hid behind other windows and froze every Tiles window.
            AccessibilityPermission.request()
            openSettings()
        }
    }

    private func checkPermission() {
        let (next, effect) = phase.next(trusted: AccessibilityPermission.isTrusted)
        guard next != phase || effect != .none else { return }
        phase = next
        switch effect {
        case .none: break
        case .start: startTiling()
        case .resume: manager.refresh()
        case .pause:
            outline.show(around: nil, hex: "")
            badges.show([], hex: "")
        }
        updateIcon()
        scheduleStatusWrite()
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: Self.statusURL)
        guard phase.hasStarted else { return }
        // Windows on hidden workspaces always come back, whatever the setting.
        if configStore.config.restoreWindowsOnQuit { manager.restoreOriginalFrames() } else { manager.unparkAll() }
    }

    /// `tiles://<command>` — lets Raycast, Alfred, Shortcuts or a shell script drive Tiles.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "tiles" {
            let name = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let command = Command(name: name) {
                manager.perform(command)
            } else {
                flash("Unknown command: \(name)")
            }
        }
    }

    // MARK: - Permission

    private func startTiling() {
        manager.start()
        updateIcon()
        // First run (and once for people updating): a short tour of how Tiles works.
        if !UserDefaults.standard.bool(forKey: "didShowTour") {
            UserDefaults.standard.set(true, forKey: "didShowTour")
            showTour()
        }
    }

    // MARK: - Config & hotkeys

    private func configChanged(_ config: Config) {
        let old = lastConfig
        lastConfig = config
        applyAppearance()
        applyIconPlacement()
        registerHotKeys()
        if old.checkForUpdates != config.checkForUpdates { updater.setAutomatic(config.checkForUpdates) }
        if phase.hasStarted { manager.configDidChange(from: old, to: config) }
        // Keep an open Settings window current, so it never writes back a stale copy.
        if let model = settingsModel, model.config != config { model.config = config }
        if let error = configStore.lastError {
            flash("Config error")
            NSLog("Tiles config error: \(error)")
        }
        updateIcon()
        scheduleStatusWrite()
    }

    // MARK: - Status file (`tiles status`)

    static let statusURL: URL = TilingManager.scenesURL.deletingLastPathComponent().appendingPathComponent("status.json")

    /// Coalesces bursts of changes into one small write, and skips writes that change nothing.
    private func scheduleStatusWrite() {
        guard statusWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusWork = nil
            let snapshot = StatusSnapshot(
                version: self.updater.current,
                pid: ProcessInfo.processInfo.processIdentifier,
                phase: self.phase,
                tilingEnabled: self.manager.isEnabled,
                mode: self.configStore.config.mode,
                update: self.updater.phase,
                configError: self.configStore.lastError,
                displays: self.manager.status().map {
                    .init(name: $0.name, layout: $0.layout, workspace: $0.workspace, workspaces: $0.workspaces, windows: $0.tiles.count)
                })
            var withPinch = snapshot
            withPinch.pinch = self.manager.pinchDiagnostics.summary
            guard let data = try? withPinch.encoded(), data != self.lastStatus else { return }
            self.lastStatus = data
            try? FileManager.default.createDirectory(at: Self.statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.statusURL, options: .atomic)
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func applyAppearance() {
        switch configStore.config.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        guard !hotkeysPaused else { return }
        let (bindings, errors) = configStore.config.resolvedHotkeys()
        hotkeyErrors = errors
        for binding in bindings {
            let command = binding.command
            if !hotKeys.register(binding.shortcut, action: { [weak self] in self?.manager.perform(command) }) {
                hotkeyErrors.append("\(binding.shortcut) is taken by another app")
            }
        }
    }

    // MARK: - Status item

    private func updateIcon() {
        let symbol: String
        if phase != .running {
            symbol = "exclamationmark.triangle"
        } else if manager.isEnabled {
            symbol = "rectangle.split.2x2"
        } else {
            symbol = "rectangle.dashed"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tiles")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func flash(_ text: String) {
        messageWork?.cancel()
        statusItem.button?.title = " " + text
        let work = DispatchWorkItem { [weak self] in self?.statusItem.button?.title = "" }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (text.count > 24 ? 5 : 1.6), execute: work)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = configStore.config

        if phase != .running {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(item("Already Allowed? Reset Permission…", #selector(resetAccess)))
            menu.addItem(.separator())
        }

        if manager.undoSnapshot != nil {
            menu.addItem(item("Undo Scene Restore", #selector(undoRestore)))
            menu.addItem(.separator())
        }

        if let version = updater.available {
            menu.addItem(item("Update to Tiles \(version)…", #selector(installUpdate)))
            menu.addItem(.separator())
        }

        let toggle = item(manager.isEnabled ? "Tiling On" : "Tiling Off", #selector(toggleTiling))
        toggle.state = manager.isEnabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        let displays = manager.displays.isEmpty ? Display.current() : manager.displays
        for display in displays {
            let title = displays.count > 1 ? "Layout — \(display.name)" : "Layout"
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let current = manager.layout(for: display.id)
            for kind in LayoutKind.allCases {
                let entry = item(kind.displayName, #selector(pickLayout(_:)))
                entry.representedObject = [display.id, kind.rawValue]
                entry.state = kind == current ? .on : .off
                sub.addItem(entry)
            }
            parent.submenu = sub
            menu.addItem(parent)

            // Workspaces 1–5 always, plus any higher one with windows in it.
            let active = manager.activeWorkspace(on: display.id)
            let used = manager.occupiedWorkspaces(on: display.id)
            let spaces = NSMenuItem(title: (displays.count > 1 ? "Workspace — \(display.name)" : "Workspace") + " (\(active))",
                                    action: nil, keyEquivalent: "")
            let spaceMenu = NSMenu()
            for n in Workspaces.numbers where n <= 5 || used.contains(n) {
                let name = config.workspaceName(n)
                let title = name == "Workspace \(n)" ? name : "\(n) · \(name)"
                let entry = item(title + (used.contains(n) && n != active ? "  •" : ""), #selector(pickWorkspace(_:)))
                entry.representedObject = [display.id, String(n)]
                entry.state = n == active ? .on : .off
                spaceMenu.addItem(entry)
            }
            spaces.submenu = spaceMenu
            menu.addItem(spaces)
        }

        let gaps = NSMenuItem(title: NSLocalizedString("Gaps", comment: "Menu"), action: nil, keyEquivalent: "")
        let gapMenu = NSMenu()
        for (name, size) in [("None", 0.0), ("Small", 4.0), ("Medium", 8.0), ("Large", 16.0), ("Extra Large", 24.0)] {
            let entry = item(name, #selector(pickGap(_:)))
            entry.representedObject = size
            entry.state = config.layout.innerGap == size ? .on : .off
            gapMenu.addItem(entry)
        }
        gaps.submenu = gapMenu
        menu.addItem(gaps)

        menu.addItem(.separator())
        menu.addItem(item("Retile Now", #selector(retile)))
        menu.addItem(item("Float / Tile Focused Window", #selector(toggleFloat)))
        menu.addItem(item("Save Scene for This Setup…", #selector(saveScene)))
        let current = manager.sceneForCurrentDisplays
        let restore = item("Restore Scene", #selector(restoreScene))
        if let name = current?.name {
            restore.title = String(format: NSLocalizedString("Restore “%@”", comment: "Menu item"), name)
        }
        restore.isEnabled = current != nil
        menu.addItem(restore)

        menu.addItem(.separator())
        let options = NSMenuItem(title: NSLocalizedString("Options", comment: "Menu"), action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        optionsMenu.addItem(check("Drag Window onto Another to Swap", config.dragToSwap, #selector(toggleDragToSwap)))
        optionsMenu.addItem(check("Resize with Mouse Adjusts Layout", config.resizeToAdjustRatio, #selector(toggleResizeRatio)))
        optionsMenu.addItem(check("Restore Scenes When Displays Change", config.autoRestoreScenes, #selector(toggleAutoScenes)))
        optionsMenu.addItem(check("Mouse Follows Keyboard Focus", config.mouseFollowsFocus, #selector(toggleMouseFollows)))
        optionsMenu.addItem(check("Animate Windows", config.animateWindows, #selector(toggleAnimate)))
        optionsMenu.addItem(check("Tabs on Windows Sharing a Tile", config.stackTabs, #selector(toggleStackTabs)))
        optionsMenu.addItem(check("⌥-Pinch to Zoom", config.pinchToZoom, #selector(togglePinchToZoom)))
        optionsMenu.addItem(check("Snap Mode (No Automatic Tiling)", config.mode == .snap, #selector(toggleSnapMode)))
        let placement = NSMenuItem(title: NSLocalizedString("New Windows Open", comment: "Menu"), action: nil, keyEquivalent: "")
        let placementMenu = NSMenu()
        let placements: [(String, NewWindowPlacement)] = [("At the End", .end), ("As Master", .master), ("Next to Focused", .afterFocused)]
        for (name, value) in placements {
            let entry = item(name, #selector(pickPlacement(_:)))
            entry.representedObject = value.rawValue
            entry.state = config.newWindowPlacement == value ? .on : .off
            placementMenu.addItem(entry)
        }
        placement.submenu = placementMenu
        optionsMenu.addItem(placement)
        optionsMenu.addItem(.separator())
        optionsMenu.addItem(check("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        options.submenu = optionsMenu
        menu.addItem(options)

        menu.addItem(item("Find Window…", #selector(findWindow)))
        menu.addItem(item("Show Shortcuts", #selector(showShortcuts)))
        menu.addItem(item("Welcome Tour…", #selector(showTour)))
        menu.addItem(item("How Tiles Works…", #selector(openHowItWorks)))
        menu.addItem(shortcutsMenu())
        menu.addItem(item("Open Tiles…", #selector(openSettings), key: ","))
        if let error = configStore.lastError {
            let warn = NSMenuItem(title: "⚠︎ Config: \(error)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        for error in hotkeyErrors.prefix(3) {
            let warn = NSMenuItem(title: "⚠︎ \(error)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        menu.addItem(item("About Tiles", #selector(openRepo)))
        menu.addItem(item("Restart Tiles", #selector(restart)))
        menu.addItem(item("Quit Tiles", #selector(quit), key: "q"))
    }

    private func shortcutsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: NSLocalizedString("Keyboard Shortcuts", comment: "Menu"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let bindings = configStore.config.resolvedHotkeys().bindings
            .sorted { Command.allNames.firstIndex(of: $0.command.name) ?? 0 < Command.allNames.firstIndex(of: $1.command.name) ?? 0 }
        for binding in bindings {
            let entry = NSMenuItem(title: "\(binding.shortcut)\t\(binding.command.name)", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            sub.addItem(entry)
        }
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: "Menu item"), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func check(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = on ? .on : .off
        return entry
    }

    // MARK: - Actions

    @objc private func showShortcuts() { cheatSheet.toggle(config: configStore.config) }
    @objc private func findWindow() { manager.perform(.findWindow) }
    @objc private func toggleSnapMode() { configStore.update { $0.mode = $0.mode == .snap ? .automatic : .snap } }
    @objc private func showTour() {
        tour.show(accentHex: configStore.config.theme.hex) { [weak self] command in self?.manager.perform(command) }
    }
    @objc private func grantAccess() { AccessibilityPermission.request() }
    @objc private func resetAccess() { AccessibilityPermission.reset() }
    @objc private func restart() { AccessibilityPermission.relaunch() }
    @objc private func installUpdate() { updater.install() }
    @objc private func toggleTiling() { manager.perform(.toggleTiling); updateIcon() }
    @objc private func retile() { manager.perform(.retile) }
    @objc private func toggleFloat() { manager.perform(.toggleFloat) }
    /// Asks for a name, prefilled with the current one, then saves.
    @objc private func saveScene() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = manager.sceneForCurrentDisplays?.name ?? ""
        field.placeholderString = NSLocalizedString("e.g. Desk, Laptop, Studio", comment: "Scene name placeholder")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Save Scene for This Setup", comment: "Alert title")
        alert.informativeText = NSLocalizedString("Give it a name so you can tell your setups apart. Tiles brings it back whenever these displays are connected.", comment: "Alert text")
        alert.accessoryView = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.saveScene(named: field.stringValue)
        settingsModel?.reloadScenes()
        let name = manager.sceneForCurrentDisplays?.name
        flash(name.map { String(format: NSLocalizedString("Saved “%@”", comment: "Menu bar message"), $0) }
              ?? NSLocalizedString("Scene saved", comment: "Menu bar message"))
    }
    @objc private func restoreScene() { manager.perform(.restoreScene) }
    @objc private func undoRestore() { manager.perform(.undoRestore) }

    @objc private func pickLayout(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2,
              let kind = LayoutKind(rawValue: info[1]) else { return }
        manager.setLayout(kind, for: info[0])
    }

    @objc private func pickWorkspace(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2, let n = Int(info[1]) else { return }
        manager.showWorkspace(n, on: info[0])
    }

    @objc private func toggleAnimate() { configStore.update { $0.animateWindows.toggle() } }

    @objc private func pickGap(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        manager.setGaps(size)
    }

    @objc private func pickPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = NewWindowPlacement(rawValue: raw) else { return }
        configStore.update { $0.newWindowPlacement = value }
    }

    @objc private func toggleDragToSwap() { configStore.update { $0.dragToSwap.toggle() } }
    @objc private func toggleResizeRatio() { configStore.update { $0.resizeToAdjustRatio.toggle() } }
    @objc private func toggleAutoScenes() { configStore.update { $0.autoRestoreScenes.toggle() } }
    @objc private func toggleMouseFollows() { configStore.update { $0.mouseFollowsFocus.toggle() } }
    @objc private func toggleStackTabs() { configStore.update { $0.stackTabs.toggle() } }
    @objc private func togglePinchToZoom() { configStore.update { $0.pinchToZoom.toggle() } }

    @objc private func toggleLogin() {
        do {
            let login = SMAppService.mainApp
            try login.status == .enabled ? login.unregister() : login.register()
        } catch {
            flash("Couldn't change login item")
            NSLog("Tiles login item error: \(error)")
        }
    }

    @objc private func openSettings() {
        if settingsWindow?.isVisible != true {
            // Fresh model each time so it picks up edits made to the file meanwhile.
            let model = SettingsModel(
                store: configStore,
                perform: { [weak self] in self?.manager.perform($0) },
                saveScene: { [weak self] in self?.manager.saveScene(named: $0) },
                setLayout: { [weak self] kind, display in self?.manager.setLayout(kind, for: display) },
                showWorkspace: { [weak self] n, display in self?.manager.showWorkspace(n, on: display) },
                status: { [weak self] in self?.manager.status() ?? [] },
                updater: updater
            )
            settingsModel = model
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Tiles"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 900, height: 640))
            window.center()
            window.setFrameAutosaveName("TilesSettings")
            settingsWindow = window
        }
        // A real app while Settings is open: Dock icon and ⌘-Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        DispatchQueue.main.async { self.applyIconPlacement() }
    }

    /// Menu bar icon and/or Dock icon. The Dock icon also shows while the window is open.
    private func applyIconPlacement() {
        let placement = configStore.config.iconPlacement
        statusItem.isVisible = placement != .dock
        let windowOpen = settingsWindow?.isVisible == true
        NSApp.setActivationPolicy(placement != .menuBar || windowOpen ? .regular : .accessory)
    }

    /// Right-clicking the Dock icon shows the same menu as the menu bar icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu
    }

    /// Opening Tiles again from Finder, Spotlight or the Dock shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func openRepo() { NSWorkspace.shared.open(Self.repoURL) }
    @objc private func openHowItWorks() { NSWorkspace.shared.open(Self.howItWorksURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
