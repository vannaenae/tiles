import AppKit
import ApplicationServices

/// What happened, as far as the tiling manager cares.
enum WindowEvent {
    /// Windows appeared, disappeared, or changed visibility. Re-tile.
    case structureChanged
    /// A window moved or resized. Might be the user dragging it.
    case frameChanged(AXUIElement)
    /// Focus moved to another window.
    case focusChanged
}

/// Subscribes to Accessibility notifications for one app.
final class AppObserver {
    let pid: pid_t
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var observedWindows = Set<WindowID>()
    fileprivate let handler: (WindowEvent) -> Void

    private static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    init?(pid: pid_t, handler: @escaping (WindowEvent) -> Void) {
        self.pid = pid
        self.handler = handler
        self.appElement = AXUIElementCreateApplication(pid)
        // Never let a frozen app freeze Tiles.
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let created else { return nil }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(created, appElement, name as CFString, refcon)
        }
        observeWindows()
    }

    deinit {
        guard let observer else { return }
        for name in Self.appNotifications {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Subscribes to per-window notifications for any window not yet observed.
    func observeWindows() {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in appElement.elements(kAXWindowsAttribute) {
            guard let id = window.windowID, !observedWindows.contains(id) else { continue }
            observedWindows.insert(id)
            for name in Self.windowNotifications {
                AXObserverAddNotification(observer, window, name as CFString, refcon)
            }
        }
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String) {
        switch notification {
        case kAXWindowCreatedNotification:
            observeWindows()
            handler(.structureChanged)
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            handler(.structureChanged)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            handler(.frameChanged(element))
        case kAXFocusedWindowChangedNotification:
            handler(.focusChanged)
        default:
            break
        }
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let appObserver = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
    appObserver.handle(element, notification as String)
}

/// Watches app launches/quits, Space switches and display changes, and keeps
/// an `AppObserver` for every regular app.
final class WorkspaceObserver {
    private var apps: [pid_t: AppObserver] = [:]
    private let handler: (WindowEvent) -> Void
    private let onDisplaysChanged: () -> Void
    private var tokens: [NSObjectProtocol] = []

    init(handler: @escaping (WindowEvent) -> Void, onDisplaysChanged: @escaping () -> Void) {
        self.handler = handler
        self.onDisplaysChanged = onDisplaysChanged
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let structural: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in structural {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.apps[app.processIdentifier] = nil
                }
                self.syncApps()
                self.handler(.structureChanged)
                // Some apps create their first window a moment after launching, and after a
                // desktop (Space) switch macOS still reports the old desktop's windows until the
                // slide animation ends. Look again once things have settled.
                // (Found on a real Mac: other desktops never got tiled.)
                if name == NSWorkspace.didLaunchApplicationNotification || name == NSWorkspace.activeSpaceDidChangeNotification {
                    for delay in [0.4, 1.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.syncApps()
                            self?.handler(.structureChanged)
                        }
                    }
                }
            })
        }
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler(.focusChanged)
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onDisplaysChanged()
        })
        syncApps()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens {
            center.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
        apps.removeAll()
    }

    /// Apps whose windows Tiles manages: regular, visible, not Tiles itself.
    static func managedApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }
    }

    func syncApps() {
        let running = Self.managedApps()
        let pids = Set(running.map(\.processIdentifier))
        for pid in apps.keys where !pids.contains(pid) {
            apps[pid] = nil
        }
        for app in running {
            if let existing = apps[app.processIdentifier] {
                existing.observeWindows()
            } else if let observer = AppObserver(pid: app.processIdentifier, handler: handler) {
                apps[app.processIdentifier] = observer
            }
        }
    }
}
