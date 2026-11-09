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
    /// ⌃⌥F choices that beat the app rules (TilesCore.FloatOverride).
    private var floatOverrides: [WindowID: FloatOverride] = [:]

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
    /// Arrangement from just before the last scene restore, for one-step undo.
    private(set) var undoSnapshot: (orders: [String: [WindowID]], layouts: [String: LayoutKind], parameters: [String: LayoutParameters])?

    /// Read from disk on use, so the Settings window and the manager never disagree.
    static let scenesURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tiles/scenes.json")
    }()

    /// Called after every re-tile so the menu can update.
    var onStateChange: (() -> Void)?
    /// Short status text to flash in the menu bar ("Scene saved").
    var onMessage: ((String) -> Void)?
    /// Frame of the focused tiled window for the outline, or nil to hide it.
    var onFocusFrame: ((Rect?) -> Void)?
    /// ⌃⌥/ : show the shortcut cheat sheet (drawn by the app, not the manager).
    var onShowShortcuts: (() -> Void)?
    /// Tiles holding more than one window, for the stack badges.
    var onStacks: (([(frame: Rect, ids: [WindowID])]) -> Void)?
    private var mouseMonitor: Any?
    private var hovered: WindowID?
    /// Window temporarily filling its display (Focus).
    private var zoomed: WindowID?
    /// Scrolling layout: each window's width (share of the screen) and each display's scroll position.
    private var scrollWidths: [WindowID: Double] = [:]
    private var scrollOffsets: [String: Double] = [:]
    /// Where each window was when Tiles first saw it, to put it back on quit.
    private var originalFrames: [WindowID: Rect] = [:]
    /// Which workspace each display shows, and where each window lives.
    private var workspaces = Workspaces()
    /// Windows on a hidden workspace, parked just off screen, with the frame to bring them back to.
    private var parked: [WindowID: Rect] = [:]
    private var lastWorkspaceSwitch = Date.distantPast
    /// Focused window at the last focus event: only a newly focused hidden window switches workspace.
    private var lastFocused: WindowID?
    /// Option-drag: window → the window whose tile it shares.
    private var stackedOn: [WindowID: WindowID] = [:]
    /// Displays being panned with ⌃⌥ + scroll, so the strip doesn't snap back to the focused window.
    private var panning = Set<String>()
    private var panWork: DispatchWorkItem?
    private var panEndWork: DispatchWorkItem?
    private var scrollTap: CFMachPort?
    private var animation: (start: Date, moves: [WindowID: (from: Rect, to: Rect)])?
    private var animationTimer: Timer?

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.isEnabled = configStore.config.enabled
    }

    // MARK: - Lifecycle

    func start() {
        guard observer == nil else { return }
        isEnabled = config.enabled
        let observer = WorkspaceObserver(
            handler: { [weak self] event in self?.handle(event) },
            onDisplaysChanged: { [weak self] in self?.displaysChanged() }
        )
        self.observer = observer
        observer.start()
        // Focus follows mouse: global mouse moves, only acted on when the option is on.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.mouseMoved() }
        startScrollTap()
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
            unparkAll()
            targetFrames = [:]
            onFocusFrame?(nil)
            onStacks?([])
        }
        onMessage?(enabled ? "Tiling on" : "Tiling off")
        onStateChange?()
    }

    func configDidChange(from old: Config, to new: Config) {
        if old.enabled != new.enabled { setEnabled(new.enabled) }
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
        case .focusChanged:
            followFocusToWorkspace()
            updateOutline()
            // Scrolling follows focus: clicking a sliver or ⌘-Tabbing to a window brings it into view.
            if layouts.values.contains(.scrolling) { scheduleRefresh() }
        case .frameChanged(let element):
            guard isEnabled, Date() > ignoreMovesUntil, trackedWindow == nil,
                  // Only a mouse drag or resize counts as the user rearranging.
                  NSEvent.pressedMouseButtons & 1 == 1,
                  let id = element.windowID, targetFrames[id] != nil else { return }
            onFocusFrame?(nil)
            trackMouse(for: id)
        }
    }

    private func displaysChanged() {
        // macOS also reports a "screen change" when the Dock, menu bar or resolution shifts, or
        // even when Tiles opens its window. Only a different set of displays means docking.
        guard Set(Display.current().map(\.id)) != Set(displays.map(\.id)) else {
            scheduleRefresh()
            return
        }
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

    func scheduleRefresh(after delay: TimeInterval = 0.03) {
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
                if originalFrames[window.id] == nil { originalFrames[window.id] = frame }
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
        var newMasters: [WindowID] = []
        for (id, frame) in frames {
            if let d = knownDisplay[id] {
                present[d, default: []].append(id)
            } else if nowVisible.contains(id), let window = found[id] {
                // A new window: a placement rule can send it to a display or the main tile.
                let rule = config.placement(bundleID: window.bundleID, appName: window.appName,
                                            title: config.rules.contains { $0.titleContains != nil } ? window.title : nil)
                let ruled = rule.display.flatMap { name in displays.first { $0.name.localizedCaseInsensitiveContains(name) } }
                guard let d = ruled ?? Display.best(for: frame, in: displays) else { continue }
                present[d.id, default: []].append(id)
                if rule.master { newMasters.append(id) }
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
        for id in newMasters {
            for (d, ids) in newOrders where ids.contains(id) { newOrders[d] = TilingOrder.promote(ids, id) }
        }
        for (d, ids) in newOrders { for id in ids { workspaces.adopt(id, on: d) } }
        workspaces.keep(only: Set(found.keys))
        parked = parked.filter { found[$0.key] != nil }
        stackedOn = stackedOn.filter { found[$0.key] != nil && found[$0.value] != nil }
        let structureChanged = newOrders != orders
        orders = newOrders
        apply(currentFrames: frames)
        if structureChanged { scheduleAutosave() }
        onStateChange?()
    }

    /// Windows on screen on the workspace this display shows, in tiling order.
    private func visibleOrder(_ displayID: String) -> [WindowID] {
        (orders[displayID] ?? []).filter { visible.contains($0) && workspaces.isShown($0, on: displayID) }
    }

    /// Windows on this display's other workspaces.
    private func hiddenOrder(_ displayID: String) -> [WindowID] {
        (orders[displayID] ?? []).filter { visible.contains($0) && !workspaces.isShown($0, on: displayID) }
    }

    private func apply(currentFrames: [WindowID: Rect]) {
        var targets: [WindowID: Rect] = [:]
        let focusedID = focusedWindow()?.id
        for display in displays {
            let kind = layouts[display.id] ?? config.defaultLayout
            guard kind != .float else { continue }
            let all = visibleOrder(display.id)
            // Option-dragged windows share their host's tile instead of taking one.
            let ids = all.filter { id in stackedOn[id].map { !all.contains($0) } ?? true }
            let p = parameters[display.id] ?? config.layout
            let rects: [Rect]
            if kind == .scrolling {
                let result = ScrollingLayout.layout(
                    widths: ids.map { scrollWidths[$0] ?? p.scrollWidth }, in: display.area, parameters: p,
                    focused: panning.contains(display.id) ? nil : focusedID.flatMap { ids.firstIndex(of: $0) },
                    offset: scrollOffsets[display.id] ?? 0,
                    hideLeft: hasNeighbor(display, left: true), hideRight: hasNeighbor(display, left: false))
                scrollOffsets[display.id] = result.offset
                rects = result.frames
            } else {
                rects = LayoutEngine.frames(count: ids.count, in: display.area, kind: kind, parameters: p)
            }
            for (id, rect) in zip(ids, rects) { targets[id] = rect }
            for id in all where targets[id] == nil { targets[id] = stackedOn[id].flatMap { targets[$0] } }
        }
        if let z = zoomed, targets[z] != nil, let d = displayID(of: z), let display = displays.first(where: { $0.id == d }) {
            targets[z] = display.area.inset(by: (parameters[d] ?? config.layout).outerGap).integral
        } else {
            zoomed = nil
        }
        targetFrames = targets
        reportStacks()

        // Hidden workspaces: park each window in the display's bottom corner, one point on screen.
        var moves = targets
        for display in displays {
            let a = display.area
            for id in hiddenOrder(display.id) {
                guard let current = currentFrames[id] else { continue }
                if parked[id] == nil { parked[id] = current }
                let x = hasNeighbor(display, left: false) ? a.minX - current.width + 1 : a.maxX - 1
                moves[id] = Rect(x: x, y: a.maxY - 1, width: current.width, height: current.height)
            }
        }
        // Windows coming back from a hidden workspace are tiled again.
        for id in parked.keys where targets[id] != nil { parked[id] = nil }

        var pending: [WindowID: (from: Rect, to: Rect)] = [:]
        for (id, target) in moves {
            let current = animatedFrame(id) ?? currentFrames[id]
            if let current, current.isClose(to: target) { continue }
            pending[id] = (current ?? target, target)
        }
        if !pending.isEmpty {
            ignoreMovesUntil = Date().addingTimeInterval(0.5)
            // Animate small, tiled rearrangements; jump for big ones and for parking.
            let animatable = pending.filter { targets[$0.key] != nil && currentFrames[$0.key] != nil }
            if config.animateWindows, panning.isEmpty, animatable.count == pending.count, pending.count <= 8 {
                animate(pending)
            } else {
                stopAnimation()
                setFrames(pending.mapValues(\.to))
            }
        }

        // In monocle or Focus, keep the focused window on top.
        if let focused = focusedWindow(), let d = displayID(of: focused.id), layouts[d] == .monocle || zoomed == focused.id {
            AXUIElementPerformAction(focused.element, kAXRaiseAction as CFString)
        }
        updateOutline()
    }

    /// Tiles that hold several windows: Monocle, or more windows than a display has tiles.
    /// Scrolling's off-screen windows share an edge frame but aren't a stack, so only
    /// frames fully on a display count.
    private func reportStacks() {
        var stacks: [(frame: Rect, ids: [WindowID])] = []
        for display in displays {
            let a = display.area
            let ids = visibleOrder(display.id).filter { id in
                guard let f = targetFrames[id] else { return false }
                return f.minX >= a.minX - 1 && f.maxX <= a.maxX + 1
            }
            for (_, group) in Dictionary(grouping: ids, by: { "\(targetFrames[$0]!)" }) where group.count > 1 {
                stacks.append((targetFrames[group[0]]!, group))
            }
        }
        onStacks?(stacks)
    }

    private func setFrames(_ frames: [WindowID: Rect], positionOnly: Bool = false) {
        let byApp = Dictionary(grouping: frames.keys.compactMap { windows[$0] }, by: \.pid)
        for (pid, appWindows) in byApp {
            let move = {
                for window in appWindows {
                    guard let f = frames[window.id] else { continue }
                    positionOnly ? window.setPositionAndSize(CGRect(f)) : window.setFrame(CGRect(f))
                }
            }
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.withEnhancedUIDisabled(move)
            } else {
                move()
            }
        }
    }

    // MARK: - Animation

    private static let animationDuration = 0.18

    private func animatedFrame(_ id: WindowID) -> Rect? {
        guard let animation, let move = animation.moves[id] else { return nil }
        return Self.interpolate(move.from, move.to, progress(of: animation.start))
    }

    private func progress(of start: Date) -> Double {
        let t = min(1, Date().timeIntervalSince(start) / Self.animationDuration)
        return 1 - pow(1 - t, 3) // ease out
    }

    private static func interpolate(_ a: Rect, _ b: Rect, _ t: Double) -> Rect {
        Rect(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
             width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t).integral
    }

    private func animate(_ moves: [WindowID: (from: Rect, to: Rect)]) {
        stopAnimation()
        animation = (Date(), moves)
        ignoreMovesUntil = Date().addingTimeInterval(Self.animationDuration + 0.5)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, let animation = self.animation else { return }
            let t = self.progress(of: animation.start)
            if t >= 1 {
                self.stopAnimation()
                // Last step uses the careful size → position → size move.
                self.setFrames(animation.moves.mapValues(\.to))
            } else {
                self.setFrames(animation.moves.mapValues { Self.interpolate($0.from, $0.to, t) }, positionOnly: true)
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animation = nil
    }

    // MARK: - Workspaces

    func activeWorkspace(on displayID: String) -> Int { workspaces.active(on: displayID) }

    /// Workspaces in use on a display (always including the one showing).
    func occupiedWorkspaces(on displayID: String) -> [Int] {
        workspaces.occupied(by: (orders[displayID] ?? []).filter { visible.contains($0) }, on: displayID)
    }

    func showWorkspace(_ number: Int, on displayID: String?) {
        guard let d = displayID else { return }
        guard workspaces.active(on: d) != number else {
            onMessage?("Workspace \(number)")
            return
        }
        workspaces.show(number, on: d)
        lastWorkspaceSwitch = Date()
        refresh()
        if let first = visibleOrder(d).first { focus(first) }
        onMessage?("Workspace \(number)")
    }

    /// ⌘-Tab or a Dock click to a window on a hidden workspace shows that workspace.
    /// (Found on a real Mac: a window sent away keeps focus for a moment, and its own focus
    /// event used to pull the display over to the workspace it was just sent to.)
    private func followFocusToWorkspace() {
        let focused = focusedWindow()?.id
        defer { lastFocused = focused }
        guard isEnabled, Date().timeIntervalSince(lastWorkspaceSwitch) > 0.6, let id = focused, id != lastFocused,
              let d = displayID(of: id), !workspaces.isShown(id, on: d) else { return }
        workspaces.show(workspaces.workspace(of: id, on: d), on: d)
        lastWorkspaceSwitch = Date()
        scheduleRefresh()
        onMessage?("Workspace \(workspaces.active(on: d))")
    }

    /// Puts every parked window back on screen, e.g. when tiling is turned off or Tiles quits.
    func unparkAll() {
        stopAnimation()
        for (id, frame) in parked { windows[id]?.setFrame(CGRect(frame)) }
        parked = [:]
        workspaces = Workspaces()
    }

    // MARK: - Scroll to pan

    /// ⌃⌥ + trackpad or mouse wheel slides the Scrolling strip under the pointer.
    /// An event tap rather than a monitor, so the app under the pointer doesn't scroll too.
    private func startScrollTap() {
        guard scrollTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<TilingManager>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.scrollTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return manager.handleScroll(event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        scrollTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Returns true when the scroll was used to pan, so it isn't passed on.
    private func handleScroll(_ event: CGEvent) -> Bool {
        let flags = event.flags
        guard isEnabled, flags.contains(.maskControl), flags.contains(.maskAlternate),
              !flags.contains(.maskCommand) else { return false }
        let p = Display.mouseLocation()
        guard let display = Display.display(atX: p.x, y: p.y, in: displays), layouts[display.id] == .scrolling else { return false }
        let precise = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        // Sideways swipes pan directly; an ordinary wheel pans with its up/down motion.
        let delta = (abs(dx) > abs(dy) ? -dx : -dy) * (precise ? 1 : 8)
        guard delta != 0 else { return true }
        scrollOffsets[display.id, default: 0] += delta
        panning.insert(display.id)
        if panWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.panWork = nil
                self.apply(currentFrames: self.targetFrames)
            }
            panWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60, execute: work)
        }
        panEndWork?.cancel()
        let end = DispatchWorkItem { [weak self] in self?.finishPan(display.id) }
        panEndWork = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: end)
        return true
    }

    /// When the scrolling stops, focus the window nearest the middle so the strip stays put.
    private func finishPan(_ displayID: String) {
        panning.remove(displayID)
        guard let display = displays.first(where: { $0.id == displayID }) else { return }
        let mid = display.area.midX
        let nearest = visibleOrder(displayID).min { a, b in
            abs((targetFrames[a]?.midX ?? .infinity) - mid) < abs((targetFrames[b]?.midX ?? .infinity) - mid)
        }
        if let nearest, focusedWindow()?.id != nearest { focus(nearest) }
    }

    /// Badge click: bring forward the window after the one on top of the stack.
    /// (Found on a real Mac: going by the focused window, which is usually outside the stack,
    /// picked the window already on top, so clicking did nothing visible.)
    func cycleStack(_ ids: [WindowID]) {
        let top = onScreenWindowOrder().first { ids.contains($0) }
        if let next = TilingOrder.cycle(ids, from: top ?? ids.last, forward: true) { focus(next) }
    }

    private func mouseMoved() {
        guard config.focusFollowsMouse, isEnabled, NSEvent.pressedMouseButtons == 0 else { return }
        let p = Display.mouseLocation()
        // Only the window actually on top counts, so hovering a floating window
        // (Calculator, a dialog) never raises the tile behind it.
        guard let id = topWindow(atX: p.x, y: p.y), targetFrames[id] != nil else { hovered = nil; return }
        guard id != hovered else { return }
        hovered = id
        if focusedWindow()?.id != id { windows[id]?.focus() }
    }

    /// Whether another display touches this one's left or right edge.
    private func hasNeighbor(_ display: Display, left: Bool) -> Bool {
        let f = display.fullFrame
        return displays.contains { other in
            let o = other.fullFrame
            let touches = left ? abs(o.maxX - f.minX) < 2 : abs(o.minX - f.maxX) < 2
            return other.id != display.id && touches && o.minY < f.maxY && o.maxY > f.minY
        }
    }

    /// Puts every window back where Tiles first found it.
    func restoreOriginalFrames() {
        for (id, window) in windows {
            if let frame = originalFrames[id] { window.setFrame(CGRect(frame)) }
        }
    }

    private func updateOutline() {
        onFocusFrame?(isEnabled ? focusedWindow().flatMap { targetFrames[$0.id] } : nil)
    }

    private func isFloating(_ window: Window) -> Bool {
        if let override = floatOverrides[window.id] { return override == .float }
        return ruleFloats(window)
    }

    private func ruleFloats(_ window: Window) -> Bool {
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
        let other = ids.first { $0 != id && targetFrames[$0]?.contains(x: mouse.x, y: mouse.y) == true }
        if NSEvent.modifierFlags.contains(.option), let other {
            // Option-drag onto a window: share its tile, as a stack.
            stack(id, onto: other, from: from, to: destination.id)
            return
        }
        // A plain drag takes a window out of its stack. Dropped on its old tile, it just gets its own.
        let formerHost = stackedOn.removeValue(forKey: id)
        if let other, other != formerHost {
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
        let area = display.area.inset(by: p.outerGap)
        let gap = p.innerGap
        if kind == .scrolling {
            // A window in the strip keeps the width you dragged it to.
            scrollWidths[id] = ScrollingLayout.share(forWidth: f.width, in: display.area, parameters: p)
            return
        }
        guard let index = ids.firstIndex(of: id), ids.count > 1 else { return }
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

    private func stackHost(of id: WindowID) -> WindowID { stackedOn[id] ?? id }

    private func stack(_ id: WindowID, onto other: WindowID, from: String, to: String) {
        let host = stackHost(of: other)
        guard host != id else { return }
        // Windows stacked on the dragged one follow it to the new host.
        for (w, h) in stackedOn where h == id { stackedOn[w] = host }
        stackedOn[id] = host
        if from != to { move(id, from: from, to: to) }
        // Sit right after the host, so unstacking puts it next door.
        if var order = orders[to], let at = order.firstIndex(of: host) {
            order.removeAll { $0 == id }
            order.insert(id, at: min(at + 1, order.count))
            orders[to] = order
        }
        onMessage?("Stacked · click the badge to flip")
    }

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
        // Its workspace follows on the next refresh: Workspaces.adopt sees the new display.
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
        if command == .showShortcuts {
            onShowShortcuts?()
            return
        }
        if command == .toggleTiling {
            // Saved like any other setting, so the menu, dashboard and next launch agree.
            configStore.update { $0.enabled = !isEnabled }
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
            if let id = focusedID, let d = displayID(of: id), layouts[d] == .scrolling {
                let current = scrollWidths[id] ?? (parameters[d] ?? config.layout).scrollWidth
                scrollWidths[id] = min(1, max(0.1, current + (command == .growMaster ? 0.05 : -0.05)))
                refresh()
                return
            }
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

        case .cycleWidth:
            guard let id = focusedID, let d = displayID(of: id), layouts[d] == .scrolling else {
                onMessage?("Widths work in the Scrolling layout")
                return
            }
            let current = scrollWidths[id] ?? (parameters[d] ?? config.layout).scrollWidth
            let next = ScrollingLayout.nextPreset(after: current)
            scrollWidths[id] = next
            refresh()
            onMessage?(["⅓", "½", "⅔", "Full"][ScrollingLayout.widthPresets.firstIndex(of: next) ?? 0] + " width")

        case .centerWindow:
            if let id = focusedID, let d = displayID(of: id), layouts[d] == .scrolling,
               let display = displays.first(where: { $0.id == d }) {
                let ids = visibleOrder(d)
                let p = parameters[d] ?? config.layout
                if let index = ids.firstIndex(of: id) {
                    scrollOffsets[d] = ScrollingLayout.centeredOffset(
                        widths: ids.map { scrollWidths[$0] ?? p.scrollWidth }, index: index, in: display.area, parameters: p)
                    refresh()
                }
            } else if let window = focused, targetFrames[window.id] == nil,
                      let frame = window.frame?.tilesRect, let display = Display.best(for: frame, in: displays) {
                // A floating window: keep its size, move it to the middle of its display.
                let a = display.area
                window.setFrame(CGRect(x: a.midX - frame.width / 2, y: a.midY - frame.height / 2,
                                       width: frame.width, height: frame.height))
            } else {
                onMessage?("Centre works on floating windows and in Scrolling")
            }

        case .toggleZoom:
            guard let id = focusedID else { return }
            zoomed = zoomed == id ? nil : id
            refresh()

        case .undoRestore:
            guard let snapshot = undoSnapshot else {
                onMessage?("Nothing to undo")
                return
            }
            undoSnapshot = nil
            orders = snapshot.orders
            layouts = snapshot.layouts
            parameters = snapshot.parameters
            refresh()
            scheduleAutosave()
            onMessage?("Undone")

        case .workspace(let number):
            showWorkspace(number, on: activeDisplayID())

        case .moveToWorkspace(let number):
            guard let id = focusedID, let d = displayID(of: id) else { return }
            guard workspaces.workspace(of: id, on: d) != number else { return }
            let neighbour = TilingOrder.cycle(visibleOrder(d), from: id, forward: true)
            workspaces.move(id, to: number)
            lastWorkspaceSwitch = Date()
            stackedOn[id] = nil
            for (w, h) in stackedOn where h == id { stackedOn[w] = nil }
            refresh()
            if let neighbour, neighbour != id { focus(neighbour) }
            onMessage?("Sent to workspace \(number)")

        case .toggleTiling, .showShortcuts:
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

    /// What the dashboard shows: each display with its tiles, relative to the display's corner.
    struct DisplayStatus: Identifiable, Equatable {
        struct Tile: Equatable { let frame: Rect; let app: String }
        let id: String
        let name: String
        let size: Rect
        let layout: LayoutKind
        let tiles: [Tile]
        var workspace = 1
        var workspaces: [Int] = [1]
    }

    func status() -> [DisplayStatus] {
        let current = displays.isEmpty ? Display.current() : displays
        return current.map { display in
            let a = display.area
            let tiles = visibleOrder(display.id).compactMap { id -> DisplayStatus.Tile? in
                guard let f = targetFrames[id] else { return nil }
                return .init(frame: Rect(x: f.x - a.x, y: f.y - a.y, width: f.width, height: f.height),
                             app: windows[id]?.appName ?? "")
            }
            return DisplayStatus(id: display.id, name: display.name,
                                 size: Rect(x: 0, y: 0, width: a.width, height: a.height),
                                 layout: layout(for: display.id), tiles: tiles,
                                 workspace: workspaces.active(on: display.id),
                                 workspaces: occupiedWorkspaces(on: display.id))
        }
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
        floatOverrides[window.id] = FloatOverride.toggled(isTiled: tiled, ruleSaysFloat: ruleFloats(window))
        if tiled {
            refresh()
            // Make it obvious the window is floating: centre it at a comfortable size.
            if let frame = window.frame?.tilesRect, let display = Display.best(for: frame, in: displays) {
                let a = display.area
                let w = (a.width * 0.6).rounded(), h = (a.height * 0.7).rounded()
                window.setFrame(CGRect(x: a.x + (a.width - w) / 2, y: a.y + (a.height - h) / 2, width: w, height: h))
            }
            onMessage?("Floating")
        } else {
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
        var store = SceneStore.load(from: Self.scenesURL)
        store.save(captureScene(), for: displays.map(\.id))
        try? store.write(to: Self.scenesURL)
    }

    var hasSceneForCurrentDisplays: Bool {
        SceneStore.load(from: Self.scenesURL).scene(for: Display.current().map(\.id)) != nil
    }

    func restoreScene(silently: Bool) {
        refresh()
        guard let scene = SceneStore.load(from: Self.scenesURL).scene(for: displays.map(\.id)) else {
            if !silently { onMessage?("No scene saved for these displays") }
            return
        }
        let sceneWindows = displays.flatMap { display in
            visibleOrder(display.id).map { id in
                SceneWindow(id: id, bundleID: windows[id]?.bundleID ?? "", display: display.id)
            }
        }
        let assignment = SceneMatcher.assign(scene: scene, windows: sceneWindows, displays: displays.map(\.id))
        undoSnapshot = (orders, layouts, parameters)
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
        // e.g. "Restored LG UltraFine · 3 windows". Undo sits at the top of the menu.
        let external = displays.map(\.name).filter { !$0.contains("Built-in") }
        let name = external.isEmpty ? "laptop" : external.joined(separator: " + ")
        onMessage?("Restored \(name) · \(sceneWindows.count) windows · ⌃⌥Z to undo")
    }
}
