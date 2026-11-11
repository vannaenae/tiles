import AppKit
import SwiftUI
import TilesCore

/// The welcome tour: six short pages shown on first launch, and any time from the menu.
final class Tour {
    private var window: NSWindow?

    func show(accentHex: String, perform: @escaping (Command) -> Void) {
        let view = TourView(accent: Color(nsColor: NSColor(hex: accentHex) ?? .controlAccentColor), perform: perform,
                            close: { [weak self] in self?.window?.close() })
        let window = self.window ?? {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.level = .floating // stays above the windows it's teaching you to arrange
            return w
        }()
        self.window = window
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 520, height: 430))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct TourPage {
    let symbol: String
    let title: String
    let text: String
    var tryLabel: String?
    var tryCommand: Command?
}

private struct TourView: View {
    let accent: Color
    let perform: (Command) -> Void
    let close: () -> Void
    @State private var index = 0

    private let pages = [
        TourPage(symbol: "rectangle.split.2x2.fill", title: "Welcome to Tiles",
                 text: "Tiles arranges your windows for you. Open a few apps and they snap into a tidy grid, with nothing overlapping. Close one and the rest fill the gap."),
        TourPage(symbol: "rectangle.split.3x1.fill", title: "Change the layout",
                 text: "Hold ⌃ Control and ⌥ Option, then press Space to flip between layouts: side by side, a grid, one big window in the middle, and more.",
                 tryLabel: "Try the next layout", tryCommand: .nextLayout),
        TourPage(symbol: "arrow.left.arrow.right", title: "Move around",
                 text: "⌃⌥ + an arrow key jumps to the window on that side. Add ⇧ Shift to move the window itself. Or drag one window onto another and they swap."),
        TourPage(symbol: "square.stack.3d.up.fill", title: "More room with desktops",
                 text: "⌃⌥2 gives you a second, empty desktop for other work, and ⌃⌥1 brings you back. ⌃⌥⇧2 sends the window you're in over there."),
        TourPage(symbol: "rectangle.stack.fill", title: "Tabs and zoom",
                 text: "Hold ⌥ Option and drop one window onto another: they share a tile, with a tab each. ⌃⌥O zooms out to show every window, and ⌃⌥I zooms back in."),
        TourPage(symbol: "checkmark.seal.fill", title: "You're all set",
                 text: "Forgot a shortcut? Press ⌃⌥/ any time for the list. Would rather place windows yourself? Choose Snap mode in Tiles → General.",
                 tryLabel: "Show the shortcuts", tryCommand: .showShortcuts),
    ]

    var body: some View {
        let page = pages[index]
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: page.symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 24))
            Text(LocalizedStringKey(page.title)).font(.title.bold())
            Text(LocalizedStringKey(page.text))
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            if let label = page.tryLabel, let command = page.tryCommand {
                Button(LocalizedStringKey(label)) { perform(command) }.controlSize(.large)
            }
            Spacer(minLength: 0)
            HStack {
                Button("Back") { index -= 1 }.opacity(index == 0 ? 0 : 1).disabled(index == 0)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle().fill(i == index ? accent : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if index < pages.count - 1 {
                    Button("Next") { index += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { close() }.keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 520, height: 430)
        .tint(accent)
        .animation(.easeInOut(duration: 0.2), value: index)
    }
}
