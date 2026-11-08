import AppKit
import TilesCore

/// A small "3" badge on every tile that holds more than one window. Click it to flip through them.
final class StackBadges: NSObject {
    private var panels: [NSPanel] = []
    private var stackIDs: [Int: [WindowID]] = [:]
    var onClick: (([WindowID]) -> Void)?

    /// `stacks`: each stacked tile's frame (top-left coordinates) and the windows in it.
    func show(_ stacks: [(frame: Rect, ids: [WindowID])], hex: String) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        while panels.count < stacks.count { panels.append(makePanel()) }
        for (i, panel) in panels.enumerated() {
            guard i < stacks.count else { panel.orderOut(nil); continue }
            let (frame, ids) = stacks[i]
            let button = panel.contentView as! NSButton
            button.attributedTitle = NSAttributedString(string: "\(ids.count)", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 12),
            ])
            button.layer?.backgroundColor = (NSColor(hex: hex) ?? .controlAccentColor).cgColor
            button.toolTip = "\(ids.count) windows stacked here. Click to flip through them."
            button.tag = i
            stackIDs[i] = ids
            let size = NSSize(width: 30, height: 22)
            // Top-right corner of the tile, in the title bar.
            panel.setFrame(NSRect(x: frame.maxX - size.width - 10, y: Double(primaryHeight) - frame.minY - size.height - 6,
                                  width: size.width, height: size.height), display: true)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        let button = NSButton(title: "", target: self, action: #selector(clicked(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 11
        panel.contentView = button
        return panel
    }

    @objc private func clicked(_ sender: NSButton) {
        if let ids = stackIDs[sender.tag] { onClick?(ids) }
    }
}
