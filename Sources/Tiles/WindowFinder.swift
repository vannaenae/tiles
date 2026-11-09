import AppKit
import SwiftUI
import TilesCore

/// ⌃⌥G: type a few letters, press Return, and you're in that window, wherever it is.
final class WindowFinder {
    private var panel: NSPanel?
    private let model = WindowFinderModel()
    private var monitor: Any?
    var onChoose: ((WindowID) -> Void)?

    func toggle(items: [WindowSearch.Item]) {
        if let panel, panel.isVisible {
            close()
            return
        }
        stopListening()
        model.items = items
        model.query = ""
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: WindowFinderView(model: model, choose: { [weak self] id in self?.choose(id) }))
        panel.setContentSize(NSSize(width: 520, height: 340))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Arrow keys, Return and Esc drive the list while the text field keeps the typing.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            let results = self.model.results
            switch event.keyCode {
            case 125: self.model.selection = min(self.model.selection + 1, max(0, results.count - 1))
            case 126: self.model.selection = max(self.model.selection - 1, 0)
            case 36, 76: if results.indices.contains(self.model.selection) { self.choose(results[self.model.selection].id) }
            case 53: self.close()
            default: return event
            }
            return nil
        }
    }

    private func choose(_ id: WindowID) {
        close()
        onChoose?(id)
    }

    private func close() {
        stopListening()
        panel?.orderOut(nil)
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true // click anywhere else and it goes away
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        return panel
    }
}

final class WindowFinderModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    var items: [WindowSearch.Item] = []

    var results: [WindowSearch.Item] { WindowSearch.rank(query, in: items) }
}

private struct WindowFinderView: View {
    @ObservedObject var model: WindowFinderModel
    let choose: (WindowID) -> Void
    @FocusState private var typing: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Type an app or window name", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($typing)
            }
            .padding(16)
            Divider()
            if results.isEmpty {
                Text("No matching windows")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == model.selection)
                                    .id(index)
                                    .onTapGesture { choose(item.id) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selection) { index in proxy.scrollTo(index) }
                }
            }
        }
        .frame(width: 520, height: 340)
        .onAppear { typing = true }
    }

    private func row(_ item: WindowSearch.Item, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(item.app).fontWeight(.semibold)
            Text(item.title)
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
