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
    private var started = false
    private let outline = FocusOutline()
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?

    static let repoURL = URL(string: "https://github.com/vannaenae/tiles")!

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
        manager.onStateChange = { [weak self] in self?.updateIcon() }
        manager.onMessage = { [weak self] text in self?.flash(text) }
        manager.onFocusFrame = { [weak self] frame in
            guard let self else { return }
            self.outline.show(around: frame, hex: self.configStore.config.outlineColor)
        }
        registerHotKeys()
        NotificationCenter.default.addObserver(forName: .tilesShortcutRecording, object: nil, queue: .main) { [weak self] note in
            if note.object as? Bool == true { self?.hotKeys.unregisterAll() } else { self?.registerHotKeys() }
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

    private var lastTrusted: Bool?

    private func checkPermission() {
        let trusted = AccessibilityPermission.isTrusted
        guard trusted != lastTrusted else { return }
        lastTrusted = trusted
        if trusted { startTiling() }
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if started, configStore.config.restoreWindowsOnQuit { manager.restoreOriginalFrames() }
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
        guard !started else { return }
        started = true
        manager.start()
        updateIcon()
        // First run: show Settings so people see what Tiles can do.
        if !UserDefaults.standard.bool(forKey: "didShowSettings") {
            UserDefaults.standard.set(true, forKey: "didShowSettings")
            openSettings()
        }
    }

    // MARK: - Config & hotkeys

    private func configChanged(_ config: Config) {
        let old = lastConfig
        lastConfig = config
        applyAppearance()
        applyIconPlacement()
        registerHotKeys()
        if started { manager.configDidChange(from: old, to: config) }
        // Keep an open Settings window current, so it never writes back a stale copy.
        if let model = settingsModel, model.config != config { model.config = config }
        if let error = configStore.lastError {
            flash("Config error")
            NSLog("Tiles config error: \(error)")
        }
        updateIcon()
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
        if !AccessibilityPermission.isTrusted {
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

        if !AccessibilityPermission.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(item("Already Allowed? Reset Permission…", #selector(resetAccess)))
            menu.addItem(.separator())
        }

        if manager.undoSnapshot != nil {
            menu.addItem(item("Undo Scene Restore", #selector(undoRestore)))
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
        }

        let gaps = NSMenuItem(title: "Gaps", action: nil, keyEquivalent: "")
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
        menu.addItem(item("Save Scene for This Setup", #selector(saveScene)))
        let restore = item("Restore Scene", #selector(restoreScene))
        restore.isEnabled = manager.hasSceneForCurrentDisplays
        menu.addItem(restore)

        menu.addItem(.separator())
        let options = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        optionsMenu.addItem(check("Drag Window onto Another to Swap", config.dragToSwap, #selector(toggleDragToSwap)))
        optionsMenu.addItem(check("Resize with Mouse Adjusts Layout", config.resizeToAdjustRatio, #selector(toggleResizeRatio)))
        optionsMenu.addItem(check("Restore Scenes When Displays Change", config.autoRestoreScenes, #selector(toggleAutoScenes)))
        optionsMenu.addItem(check("Mouse Follows Keyboard Focus", config.mouseFollowsFocus, #selector(toggleMouseFollows)))
        let placement = NSMenuItem(title: "New Windows Open", action: nil, keyEquivalent: "")
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

        menu.addItem(shortcutsMenu())
        menu.addItem(item("Open Tiles…", #selector(openSettings), key: ","))
        menu.addItem(item("Edit Config File…", #selector(openConfig)))
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
        let parent = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
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
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func check(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = on ? .on : .off
        return entry
    }

    // MARK: - Actions

    @objc private func grantAccess() { AccessibilityPermission.request() }
    @objc private func resetAccess() { AccessibilityPermission.reset() }
    @objc private func restart() { AccessibilityPermission.relaunch() }
    @objc private func toggleTiling() { manager.perform(.toggleTiling); updateIcon() }
    @objc private func retile() { manager.perform(.retile) }
    @objc private func toggleFloat() { manager.perform(.toggleFloat) }
    @objc private func saveScene() { manager.perform(.saveScene) }
    @objc private func restoreScene() { manager.perform(.restoreScene) }
    @objc private func undoRestore() { manager.perform(.undoRestore) }

    @objc private func pickLayout(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String], info.count == 2,
              let kind = LayoutKind(rawValue: info[1]) else { return }
        manager.setLayout(kind, for: info[0])
    }

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
                setLayout: { [weak self] kind, display in self?.manager.setLayout(kind, for: display) },
                status: { [weak self] in self?.manager.status() ?? [] }
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

    @objc private func openConfig() {
        configStore.ensureFileExists()
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    @objc private func openRepo() { NSWorkspace.shared.open(Self.repoURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
