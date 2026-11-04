import AppKit
import TilesCore

/// A click-through coloured border drawn around the focused tiled window.
final class FocusOutline {
    private let window: NSWindow
    private let border = NSView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        border.wantsLayer = true
        border.layer?.borderWidth = 3
        border.layer?.cornerRadius = 12
        window.contentView = border
    }

    /// `frame` is in top-left-origin coordinates; `hex` like `#E8643C`, empty to hide.
    func show(around frame: Rect?, hex: String) {
        guard let frame, let color = NSColor(hex: hex),
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            window.orderOut(nil)
            return
        }
        let rect = NSRect(x: frame.x, y: Double(primaryHeight) - frame.maxY, width: frame.width, height: frame.height)
        border.layer?.borderColor = color.cgColor
        window.setFrame(rect.insetBy(dx: -2, dy: -2), display: true)
        window.orderFrontRegardless()
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
