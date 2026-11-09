import AppKit
import SwiftUI
import TilesCore

/// The pop-up behind ⌃⌥/: the handful of shortcuts you use every day, read from the
/// current config so it stays right after you remap something. Click away or press Esc to close.
final class CheatSheet {
    private var panel: NSPanel?

    /// Everyday commands, in the order they're shown.
    static let rows: [(command: Command, label: String)] = [
        (.focus(.left), "Move between windows (any arrow)"),
        (.swap(.left), "Move the window itself (any arrow)"),
        (.nextLayout, "Next layout"),
        (.toggleZoom, "Fill the screen / put it back"),
        (.promote, "Make it the main window"),
        (.toggleFloat, "Float or tile this window"),
        (.workspace(1), "Go to desktop 1 (any number)"),
        (.moveToWorkspace(1), "Send the window to desktop 1"),
        (.toggleTiling, "Turn tiling on or off"),
        (.showShortcuts, "Show or hide this list"),
    ]

    func toggle(config: Config) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let rows = Self.rows.map { row -> (String, String) in
            // Prefer the arrow-key binding so "any arrow" reads naturally.
            let shortcuts = config.shortcuts(for: row.command)
            let shortcut = shortcuts.first { ["left", "right", "up", "down"].contains($0.key) } ?? shortcuts.first
            return (NSLocalizedString(row.label, comment: "Cheat sheet"), shortcut?.description ?? "—")
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: CheatSheetView(rows: rows))
        panel.setContentSize(panel.contentViewController!.view.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .hudWindow, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = NSLocalizedString("Tiles shortcuts", comment: "Cheat sheet title")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true // click anywhere else and it goes away
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

private struct CheatSheetView: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hold ⌃ Control + ⌥ Option, then press:")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text(rows[i].1).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(rows[i].0)
                    }
                }
            }
            Text("Change any of these in Tiles → Shortcuts.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 420)
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) } // Esc
    }
}
