import AppKit
import TilesCore

/// Owns the tiling state and keeps windows where they belong.
final class TilingManager {
    private let configStore: ConfigStore
    private var config: Config { configStore.config }
    private var observer: WorkspaceObserver?

    private(set) var isEnabled: Bool
    private(set) var displays: [Display] = []

    /// Tiling order per display. Includes minimised windows so they get their slot back.
    private var orders: [String: [WindowID]] = [:]
    private var layouts: [String: LayoutKind] = [:]
    private var parameters: [String: LayoutParameters] = [:]
    /// Windows the user floated by hand.
    private var userFloating = Set<WindowID>()
    /// Windows the user tiled by hand even though a rule says float.
    private var userTiled = Set<WindowID>()

    private var windows: [WindowID: Window] = [:]
    private var visible = Set<WindowID>()
    private var targetFrames: [WindowID: Rect] = [:]

    private var ignoreMovesUntil = Date.distantPast
    private var autosaveBlockedUntil = Date.distantPast
    private var refreshWork: DispatchWorkItem?
    private var autosaveWork: DispatchWorkItem?
    private var displayWork: DispatchWorkItem?
    private var mouseTimer: Timer?
    private var trackedWindow: WindowID?

    private var sceneStore = SceneStore()
    private let scenesURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tiles/scenes.json")
    }()

    /// Called after every re-tile so the menu can update.
    var onStateChange: (() -> Void)?
    /// Short status text to flash in the menu bar ("Scene saved").
    var onMessage: ((String) -> Void)?

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.isEnabled = configStore.config.enabled
    }

    // MARK: - Lifecycle

    func start() {
        guard observer == nil else { return }
        sceneStore = SceneStore.load(from: scenesURL)
        let observer = WorkspaceObserver(
            handler: { [weak self] event in self?.handle(event) },
            onDisplaysChanged: { [weak self] in self?.displaysChanged() }
        )
        self.observer = observer
        observer.start()
        refresh()
        if config.autoRestoreScenes { restoreScene(silently: true) }
        // Apps keep opening windows for a while after login; don't save half a scene.
        autosaveBlockedUntil = Date().addingTimeInterval(20)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            refresh()
        } else {
            targetFrames = [:]
        }
        onMessage?(enabled ? "Tiling on" : "Tiling off")
        onStateChange?()
    }

    func configDidChange(from old: Config, to new: Config) {
        if old.enabled != new.enabled { isEnabled = new.enabled }
        // Re-derive layouts only if the layout settings themselves changed,
        // so editing gaps doesn't undo a layout picked from the menu.
        if old.defaultLayout != new.defaultLayout || old.ultrawideLayout != new.ultrawideLayout || old.displays != new.displays {
            layouts = [:]
        }
        for (id, p) in parameters {
            var updated = new.layout
            if old.layout.masterRatio == new.layout.masterRatio { updated.masterRatio = p.masterRatio }
            if old.layout.masterCount == new.layout.masterCount { updated.masterCount = p.masterCount }
            parameters[id] = updated
        }
        refresh()
    }

    // MARK: - Events

    private func handle(_ event: WindowEvent) {
        switch event {
        case .structureChanged:
            scheduleRefresh()
        case .frameChanged(let element):
            guard isEnabled, Date() > ignoreMovesUntil, trackedWindow == nil,
                  // Only a mouse drag or resize counts as the user rearranging.
                  NSEvent.pressedMouseButtons & 1 == 1,
                  let id = element.windowID, targetFrames[id] != nil else { return }
            trackMouse(for: id)
        }
    }

    private func displaysChanged() {
        autosaveWork?.cancel()
        autosaveBlockedUntil = Date().addingTimeInterval(8)
        displayWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.config.autoRestoreScenes { self.restoreScene(silently: true) }
        }
        displayWork = work
        // Displays take a moment to settle after docking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func scheduleRefresh(after delay: TimeInterval = 0.08) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func flushPendingRefresh() {
        if let work = refreshWork, !work.isCancelled {
            work.cancel()
            refresh()
        }
    }

    // MARK: - Core loop

    /// Re-reads every window, updates the tiling order and moves windows into place.
    func refresh() {
        refreshWork = nil
        guard isEnabled, AccessibilityPermission.isTrusted else { return }
        displays = Display.current()
        guard !displays.isEmpty else { return }
        observer?.syncApps()

        let onScreen = onScreenWindowIDs()
        let focusedID = focusedWindow()?.id
        var found: [WindowID: Window] = [:]
        var frames: [WindowID: Rect] = [:]
        var nowVisible = Set<WindowID>()

        for app in WorkspaceObserver.managedApps() {
            let appElement = app.axElement
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            for element in appElement.elements(kAXWindowsAttribute) {
                guard let window = Window(element: element, app: app),
                      window.isStandard, !isFloating(window),
                      window.isMovable, window.isResizable,
                      let frame = window.frame?.tilesRect else { continue }
                found[window.id] = window
                frames[window.id] = frame
                if !app.isHidden, onScreen.contains(window.id), !window.isMinimized, !window.isFullscreen {
                    nowVisible.insert(window.id)
                }
            }
        }
        windows = found
        visible = nowVisible

        // Windows keep the display they were tiled on; new ones go where they opened.
        let displayIDs = Set(displays.map(\.id))
        var knownDisplay: [WindowID: String] = [:]
        for (displayID, ids) in orders where displayIDs.contains(displayID) {
            for id in ids { knownDisplay[id] = displayID }
        }
        var present: [String: [WindowID]] = [:]
        for (id, frame) in frames {
            if let d = knownDisplay[id] {
                present[d, default: []].append(id)
            } else if nowVisible.contains(id), let d = Display.best(for: frame, in: displays) {
                present[d.id, default: []].append(id)
            }
        }

        var newOrders: [String: [WindowID]] = [:]
        for display in displays {
            // New windows enter left-to-right, top-to-bottom.
            let ids = (present[display.id] ?? []).sorted { a, b in
                let fa = frames[a]!, fb = frames[b]!
                return (fa.minX, fa.minY, a) < (fb.minX, fb.minY, b)
            }
            newOrders[display.id] = TilingOrder.sync(
                orders[display.id] ?? [], present: ids,
                placement: config.newWindowPlacement, focused: focusedID
            )
            if layouts[display.id] == nil {
                layouts[display.id] = config.layoutKind(forDisplayNamed: display.name, aspectRatio: display.aspectRatio)
            }
            if parameters[display.id] == nil {
                parameters[display.id] = config.layout
            }
        }
        let structureChanged = newOrders != orders
        orders = newOrders
        apply(currentFrames: frames)
        if structureChanged { scheduleAutosave() }
        onStateChange?()
    }

    private func visibleOrder(_ displayID: String) -> [WindowID] {
        (orders[displayID] ?? []).filter { visible.contains($0) }
    }

    private func apply(currentFrames: [WindowID: Rect]) {
        var targets: [WindowID: Rect] = [:]
        for display in displays {
            let kind = layouts[display.id] ?? config.defaultLayout
            guard kind != .float else { continue }
            let ids = visibleOrder(display.id)
            let rects = LayoutEngine.frames(count: ids.count, in: display.area, kind: kind,
                                            parameters: parameters[display.id] ?? config.layout)
            for (id, rect) in zip(ids, rects) { targets[id] = rect }
        }
        targetFrames = targets

        let byApp = Dictionary(grouping: targets.keys.compactMap { windows[$0] }, by: \.pid)
        for (pid, appWindows) in byApp {
            let pending = appWindows.filter { window in
                guard let current = currentFrames[window.id], let target = targets[window.id] else { return true }
                return !current.isClose(to: target)
            }
            guard !pending.isEmpty else { continue }
            ignoreMovesUntil = Date().addingTimeInterval(0.5)
            let move = {
                for window in pending {
                    if let target = targets[window.id] { window.setFrame(CGRect(target)) }
                }
            }
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.withEnhancedUIDisabled(move)
            } else {
                move()
            }
        }

        // In monocle, keep the focused window on top.
        if let focused = focusedWindow(), let d = displayID(of: focused.id), layouts[d] == .monocle {
            AXUIElementPerformAction(focused.element, kAXRaiseAction as CFString)
        }
    }

    private func isFloating(_ window: Window) -> Bool {
        if userFloating.contains(window.id) { return true }
        if userTiled.contains(window.id) { return false }
        let needsTitle = config.rules.contains { $0.titleContains != nil }
        return config.shouldFloat(bundleID: window.bundleID, appName: window.appName, title: needsTitle ? window.title : nil)
    }

    // MARK: - Mouse drag & resize

    private func trackMouse(for id: WindowID) {
        trackedWindow = id
        mouseTimer?.invalidate()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            self?.finishUserChange()
        }
    }

    private func finishUserChange() {
        mouseTimer = nil
        guard let id = trackedWindow else { return }
        trackedWindow = nil
        defer { refresh() }
        guard let window = windows[id], let frame = window.frame?.tilesRect,
              let target = targetFrames[id], let from = displayID(of: id) else { return }

        let resized = abs(frame.width - target.width) > 2 || abs(frame.height - target.height) > 2
        if resized {
            if config.resizeToAdjustRatio { adjustRatio(for: id, newFrame: frame, displayID: from) }
            return
        }
        guard config.dragToSwap else { return }
        let mouse = Display.mouseLocation()
        guard let destination = Display.display(atX: mouse.x, y: mouse.y, in: displays) else { return }
        let ids = visibleOrder(destination.id)
        if let other = ids.first(where: { targetFrames[$0]?.contains(x: mouse.x, y: mouse.y) == true }), other != id {
            swapWindows(id, other)
        } else if destination.id != from {
            move(id, from: from, to: destination.id)
        }
        scheduleAutosave()
    }

    /// Turns a mouse resize of a master or stack window into a new master ratio.
    private func adjustRatio(for id: WindowID, newFrame f: Rect, displayID d: String) {
        guard let display = displays.first(where: { $0.id == d }),
              var p = parameters[d], let kind = layouts[d] else { return }
        let ids = visibleOrder(d)
        guard let index = ids.firstIndex(of: id), ids.count > 1 else { return }
        let area = display.area.inset(by: p.outerGap)
        let gap = p.innerGap
        let masterCount = max(1, p.masterCount)
        let isMaster = index < masterCount
        var ratio: Double?

        switch kind {
        case .masterStack:
            guard ids.count > masterCount else { return }
            let w = f.width / max(1, area.width - gap)
            ratio = isMaster ? w : 1 - w
        case .wideMaster:
            guard ids.count > masterCount else { return }
            let h = f.height / max(1, area.height - gap)
            ratio = isMaster ? h : 1 - h
        case .dwindle:
            guard index <= 1 else { return }
            let landscape = area.width >= area.height
            let share = landscape ? f.width / max(1, area.width - gap) : f.height / max(1, area.height - gap)
            if index == 0 {
                ratio = share
            } else if ids.count == 2 {
                ratio = 1 - share
            }
        case .centeredMaster:
            guard ids.count > masterCount else { return }
            if ids.count - masterCount == 1 {
                let w = f.width / max(1, area.width - gap)
                ratio = isMaster ? w : 1 - w
            } else {
                let usable = max(1, area.width - 2 * gap)
                ratio = isMaster ? f.width / usable : (usable - 2 * f.width) / usable
            }
        default:
            return
        }
        guard let ratio else { return }
        p.masterRatio = min(0.9, max(0.1, ratio))
        parameters[d] = p
        scheduleAutosave()
    }

    // MARK: - Order helpers

    private func displayID(of id: WindowID) -> String? {
        orders.first { $0.value.contains(id) }?.key
    }

    private func swapWindows(_ a: WindowID, _ b: WindowID) {
        guard let da = displayID(of: a), let db = displayID(of: b),
              let ia = orders[da]?.firstIndex(of: a), let ib = orders[db]?.firstIndex(of: b) else { return }
        if da == db {
            orders[da]?.swapAt(ia, ib)
        } else {
            orders[da]?[ia] = b
            orders[db]?[ib] = a
        }
    }

    private func move(_ id: WindowID, from: String, to: String) {
        orders[from]?.removeAll { $0 == id }
        orders[to, default: []].append(id)
    }

    // MARK: - Focus

    private func focusedWindow() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let element = app.axElement.element(kAXFocusedWindowAttribute) else { return nil }
        return Window(element: element, app: app)
    }

    /// The display holding the focused window, or else the one under the mouse.
    func activeDisplayID() -> String? {
        if let id = focusedWindow()?.id, let d = displayID(of: id) { return d }
        let mouse = Display.mouseLocation()
        return Display.display(atX: mouse.x, y: mouse.y, in: displays)?.id ?? displays.first?.id
    }

    private func focus(_ id: WindowID) {
        guard let window = windows[id] else { return }
        window.focus()
        if config.mouseFollowsFocus, let frame = targetFrames[id] {
            CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    // MARK: - Commands

    func perform(_ command: Command) {
        if command == .toggleTiling {
            setEnabled(!isEnabled)
            return
        }
        guard isEnabled else {
            onMessage?("Tiling is off")
            return
        }
        flushPendingRefresh()
        let focused = focusedWindow()
        let focusedID = focused.flatMap { targetFrames[$0.id] != nil ? $0.id : nil }

        switch command {
        case .focus(let direction):
            if let id = focusedID, let d = displayID(of: id), layouts[d] == .monocle {
                if let next = TilingOrder.cycle(visibleOrder(d), from: id, forward: direction == .right || direction == .down) {
                    focus(next)
                }
            } else if let target = neighbor(of: focusedID, direction: direction) {
                focus(target)
            }

        case .swap(let direction):
            guard let id = focusedID, let other = neighbor(of: id, direction: direction) else { return }
            swapWindows(id, other)
            refresh()
            scheduleAutosave()

        case .promote:
            guard let id = focusedID, let d = displayID(of: id) else { return }
            let ids = visibleOrder(d)
            if ids.first == id, ids.count > 1 {
                swapWindows(id, ids[1])
            } else if let first = ids.first, var order = orders[d], let at = order.firstIndex(of: first) {
                order.removeAll { $0 == id }
                order.insert(id, at: min(at, order.count))
                orders[d] = order
            }
            refresh()
            scheduleAutosave()

        case .setLayout(let kind):
            setLayout(kind, for: activeDisplayID())

        case .nextLayout, .previousLayout:
            guard let d = activeDisplayID() else { return }
            let all = LayoutKind.allCases.filter { $0 != .float }
            let current = layouts[d] ?? config.defaultLayout
            let index = all.firstIndex(of: current) ?? 0
            let step = command == .nextLayout ? 1 : all.count - 1
            setLayout(all[(index + step) % all.count], for: d)

        case .growMaster, .shrinkMaster:
            adjustParameters { $0.masterRatio = min(0.9, max(0.1, $0.masterRatio + (command == .growMaster ? 0.05 : -0.05))) }

        case .increaseMasterCount, .decreaseMasterCount:
            adjustParameters { $0.masterCount = min(10, max(1, $0.masterCount + (command == .increaseMasterCount ? 1 : -1))) }

        case .increaseGaps, .decreaseGaps:
            let delta: Double = command == .increaseGaps ? 4 : -4
            setGaps(min(64, max(0, config.layout.innerGap + delta)))

        case .toggleFloat:
            guard let window = focused else { return }
            toggleFloat(window)

        case .retile:
            targetFrames = [:]
            refresh()
            onMessage?("Retiled")

        case .focusNextWindow, .focusPreviousWindow:
            let d = focusedID.flatMap { displayID(of: $0) } ?? activeDisplayID()
            guard let d, let next = TilingOrder.cycle(visibleOrder(d), from: focusedID, forward: command == .focusNextWindow) else { return }
            focus(next)

        case .moveToNextDisplay, .moveToPreviousDisplay:
            guard displays.count > 1, let id = focusedID, let from = displayID(of: id),
                  let index = displays.firstIndex(where: { $0.id == from }) else { return }
            let step = command == .moveToNextDisplay ? 1 : displays.count - 1
            let to = displays[(index + step) % displays.count].id
            move(id, from: from, to: to)
            refresh()
            focus(id)
            scheduleAutosave()

        case .saveScene:
            saveScene()
            onMessage?("Scene saved")

        case .restoreScene:
            restoreScene(silently: false)

        case .toggleTiling:
            break
        }
    }

    private func neighbor(of id: WindowID?, direction: Direction) -> WindowID? {
        let ids = Array(targetFrames.keys).sorted()
        let rects = ids.map { targetFrames[$0]! }
        guard let id, let index = ids.firstIndex(of: id) else {
            // Nothing tiled is focused: start from the first window on the active display.
            return activeDisplayID().flatMap { visibleOrder($0).first }
        }
        return Geometry.neighbor(of: index, in: rects, direction: direction).map { ids[$0] }
    }

    private func adjustParameters(_ change: (inout LayoutParameters) -> Void) {
        guard let d = activeDisplayID() else { return }
        var p = parameters[d] ?? config.layout
        change(&p)
        parameters[d] = p
        refresh()
        scheduleAutosave()
    }

    func setLayout(_ kind: LayoutKind, for displayID: String?) {
        guard let d = displayID else { return }
        layouts[d] = kind
        refresh()
        onMessage?(kind.displayName)
        scheduleAutosave()
    }

    func layout(for displayID: String) -> LayoutKind {
        layouts[displayID] ?? config.defaultLayout
    }

    func setGaps(_ gap: Double) {
        configStore.update {
            $0.layout.innerGap = gap
            $0.layout.outerGap = gap
        }
    }

    private func toggleFloat(_ window: Window) {
        let tiled = targetFrames[window.id] != nil
        if tiled {
            userFloating.insert(window.id)
            userTiled.remove(window.id)
            refresh()
            // Make it obvious the window is floating: centre it at a comfortable size.
            if let frame = window.frame?.tilesRect, let display = Display.best(for: frame, in: displays) {
                let a = display.area
                let w = (a.width * 0.6).rounded(), h = (a.height * 0.7).rounded()
                window.setFrame(CGRect(x: a.x + (a.width - w) / 2, y: a.y + (a.height - h) / 2, width: w, height: h))
            }
            onMessage?("Floating")
        } else {
            userFloating.remove(window.id)
            if config.shouldFloat(bundleID: window.bundleID, appName: window.appName, title: window.title) {
                userTiled.insert(window.id)
            }
            refresh()
            onMessage?("Tiled")
        }
    }

    // MARK: - Scenes

    private func scheduleAutosave() {
        guard config.autoRestoreScenes else { return }
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, Date() > self.autosaveBlockedUntil, !self.visible.isEmpty else { return }
            self.saveScene()
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func captureScene() -> Scene {
        var saved: [String: SceneDisplay] = [:]
        for display in displays {
            let p = parameters[display.id] ?? config.layout
            saved[display.id] = SceneDisplay(
                layout: layouts[display.id] ?? config.defaultLayout,
                masterRatio: p.masterRatio,
                masterCount: p.masterCount,
                apps: visibleOrder(display.id).compactMap { windows[$0]?.bundleID }
            )
        }
        return Scene(displays: saved)
    }

    func saveScene() {
        guard !displays.isEmpty else { return }
        sceneStore.save(captureScene(), for: displays.map(\.id))
        try? sceneStore.write(to: scenesURL)
    }

    var hasSceneForCurrentDisplays: Bool {
        sceneStore.scene(for: Display.current().map(\.id)) != nil
    }

    func restoreScene(silently: Bool) {
        refresh()
        guard let scene = sceneStore.scene(for: displays.map(\.id)) else {
            if !silently { onMessage?("No scene saved for these displays") }
            return
        }
        let sceneWindows = displays.flatMap { display in
            visibleOrder(display.id).map { id in
                SceneWindow(id: id, bundleID: windows[id]?.bundleID ?? "", display: display.id)
            }
        }
        let assignment = SceneMatcher.assign(scene: scene, windows: sceneWindows, displays: displays.map(\.id))
        for display in displays {
            // Keep minimised windows' slots after the restored ones.
            let hidden = (orders[display.id] ?? []).filter { !visible.contains($0) }
            orders[display.id] = (assignment[display.id] ?? []) + hidden
            if let saved = scene.displays[display.id] {
                layouts[display.id] = saved.layout
                var p = parameters[display.id] ?? config.layout
                p.masterRatio = saved.masterRatio
                p.masterCount = saved.masterCount
                parameters[display.id] = p
            }
        }
        refresh()
        onMessage?("Scene restored")
    }
}
