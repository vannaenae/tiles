import AppKit
import TilesCore

/// A strip of tabs above every tile that holds more than one window: one tab per window,
/// whatever app it belongs to. Click a tab to bring that window to the front of the tile.
final class TabBars: NSObject {
    private var panels: [NSPanel] = []
    private var tabIDs: [[WindowID]] = []
    private var last: [TilingManager.StackInfo] = []
    private var lastHex = ""
    var onSelect: ((WindowID) -> Void)?

    /// `stacks`: each strip's frame (top-left coordinates) and its tabs.
    func show(_ stacks: [TilingManager.StackInfo], hex: String) {
        // Called on every retile; only redraw when something a tab shows has changed.
        guard stacks != last || hex != lastHex else { return }
        last = stacks
        lastHex = hex
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let accent = NSColor(hex: hex) ?? .controlAccentColor
        while panels.count < stacks.count { panels.append(makePanel()) }
        tabIDs = stacks.map { ($0.tabs ?? []).map(\.id) }

        for (i, panel) in panels.enumerated() {
            guard i < stacks.count, let bar = panel.contentView, let tabs = stacks[i].tabs, !tabs.isEmpty else {
                panel.orderOut(nil)
                continue
            }
            let frame = stacks[i].frame
            panel.setFrame(NSRect(x: frame.x, y: Double(primaryHeight) - frame.maxY, width: frame.width, height: frame.height),
                           display: false)
            bar.subviews.forEach { $0.removeFromSuperview() }
            let gap = 4.0
            let width = max(20, (frame.width - gap * Double(tabs.count + 1)) / Double(tabs.count))
            for (t, tab) in tabs.enumerated() {
                let button = makeTab(tab, active: tab.id == stacks[i].active, accent: accent)
                button.tag = i * 1000 + t
                button.frame = NSRect(x: gap + Double(t) * (width + gap), y: 3, width: width, height: frame.height - 6)
                bar.addSubview(button)
            }
            panel.orderFrontRegardless()
        }
    }

    private func makeTab(_ tab: TilingManager.StackInfo.Tab, active: Bool, accent: NSColor) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(clicked(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = (active ? accent : NSColor.white.withAlphaComponent(0.1)).cgColor
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = .center
        button.attributedTitle = NSAttributedString(string: " " + tab.title, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(active ? 1 : 0.75),
            .font: NSFont.systemFont(ofSize: 12, weight: active ? .semibold : .regular),
            .paragraphStyle: style,
        ])
        if let icon = NSRunningApplication(processIdentifier: tab.pid)?.icon?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            button.image = icon
            button.imagePosition = .imageLeading
        }
        button.toolTip = tab.title
        return button
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 8
        bar.layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.94).cgColor
        panel.contentView = bar
        return panel
    }

    @objc private func clicked(_ sender: NSButton) {
        let (stack, tab) = (sender.tag / 1000, sender.tag % 1000)
        guard stack < tabIDs.count, tab < tabIDs[stack].count else { return }
        onSelect?(tabIDs[stack][tab])
    }
}
