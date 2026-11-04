import SwiftUI
import TilesCore

/// Edits a copy of the config and writes it back shortly after each change.
final class SettingsModel: ObservableObject {
    @Published var config: Config { didSet { scheduleSave() } }
    @Published var preset = Preset.laptop
    @Published var windowCount = 4
    private let store: ConfigStore
    private var saveWork: DispatchWorkItem?
    static let outlineColors = ["#E8643C", "#3F8F5F", "#3478F6", "#D4A017", "#8E8E93", ""]

    init(store: ConfigStore) {
        self.store = store
        self.config = store.config
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.config != self.store.config else { return }
            let config = self.config
            self.store.update { $0 = config }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Typical usable areas, in points, for the preview.
    enum Preset: String, CaseIterable {
        case laptop = "MacBook 14″", studio = "27″", ultrawide = "34″ ultrawide", superUltrawide = "49″"

        var area: Rect {
            switch self {
            case .laptop: return Rect(x: 0, y: 0, width: 1512, height: 945)
            case .studio: return Rect(x: 0, y: 0, width: 2560, height: 1415)
            case .ultrawide: return Rect(x: 0, y: 0, width: 3440, height: 1415)
            case .superUltrawide: return Rect(x: 0, y: 0, width: 5120, height: 1415)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    private var area: Rect { model.preset.area }
    private var kind: LayoutKind {
        model.config.layoutKind(forDisplayNamed: model.preset.rawValue, aspectRatio: area.width / area.height)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 14) {
                Picker("Display", selection: $model.preset) {
                    ForEach(SettingsModel.Preset.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                preview

                HStack {
                    Text("\(kind.displayName) on this display").foregroundStyle(.secondary)
                    Spacer()
                    Stepper("\(model.windowCount) windows", value: $model.windowCount, in: 1...12)
                }
                .font(.callout)
            }
            .padding(20)
            .frame(width: 460)

            Form {
                Section("Layout") {
                    layoutPicker("Default", $model.config.defaultLayout)
                    layoutPicker("Ultrawide", $model.config.ultrawideLayout)
                    Picker("New windows", selection: $model.config.newWindowPlacement) {
                        Text("At the end").tag(NewWindowPlacement.end)
                        Text("As master").tag(NewWindowPlacement.master)
                        Text("Next to focused").tag(NewWindowPlacement.afterFocused)
                    }
                }
                Section("Appearance") {
                    LabeledContent("Focus outline") {
                        HStack(spacing: 8) {
                            ForEach(SettingsModel.outlineColors, id: \.self) { hex in
                                swatch(hex)
                            }
                        }
                    }
                }
                Section("Spacing") {
                    LabeledContent("Gaps: \(Int(model.config.layout.innerGap)) pt") {
                        Slider(value: gaps, in: 0...32, step: 2)
                    }
                    LabeledContent("Master: \(Int(model.config.layout.masterRatio * 100))%") {
                        Slider(value: $model.config.layout.masterRatio, in: 0.2...0.8, step: 0.05)
                    }
                    LabeledContent("Width cap: \(widthCapLabel)") {
                        Slider(value: $model.config.layout.maxTileWidth, in: 0...4000, step: 100)
                    }
                    Stepper("Max tiles: \(model.config.layout.maxTiles == 0 ? "Auto" : "\(model.config.layout.maxTiles)")",
                            value: $model.config.layout.maxTiles, in: 0...24)
                }
                Section("Behaviour") {
                    Toggle("Drag a window onto another to swap", isOn: $model.config.dragToSwap)
                    Toggle("Resizing with the mouse moves the split", isOn: $model.config.resizeToAdjustRatio)
                    Toggle("Restore scenes when displays change", isOn: $model.config.autoRestoreScenes)
                    Toggle("Mouse follows keyboard focus", isOn: $model.config.mouseFollowsFocus)
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)
        }
        .frame(height: 520)
    }

    private var preview: some View {
        let frames = LayoutEngine.frames(count: model.windowCount, in: area, kind: kind, parameters: model.config.layout)
        return GeometryReader { geo in
            let scale = min(geo.size.width / area.width, geo.size.height / area.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: area.width * scale, height: area.height * scale)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(index == 0 ? 0.9 : 0.4))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                        .frame(width: frame.width * scale, height: frame.height * scale)
                        .offset(x: frame.x * scale, y: frame.y * scale)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: frames)
        }
        .aspectRatio(area.width / area.height, contentMode: .fit)
        .frame(height: 240)
    }

    /// One slider sets both gaps, matching the menu.
    private var gaps: Binding<Double> {
        Binding(
            get: { model.config.layout.innerGap },
            set: {
                model.config.layout.innerGap = $0
                model.config.layout.outerGap = $0
            }
        )
    }

    private var widthCapLabel: String {
        model.config.layout.maxTileWidth == 0 ? "Off" : "\(Int(model.config.layout.maxTileWidth)) pt"
    }

    private func swatch(_ hex: String) -> some View {
        let selected = model.config.outlineColor.uppercased() == hex
        return Button {
            model.config.outlineColor = hex
        } label: {
            Circle()
                .fill(hex.isEmpty ? Color.clear : Color(nsColor: NSColor(hex: hex) ?? .gray))
                .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.9 : 0.2), lineWidth: selected ? 2.5 : 1))
                .overlay(hex.isEmpty ? Image(systemName: "nosign").foregroundStyle(.secondary) : nil)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(hex.isEmpty ? "No outline" : hex)
    }

    private func layoutPicker(_ title: String, _ selection: Binding<LayoutKind>) -> some View {
        Picker(title, selection: selection) {
            ForEach(LayoutKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
    }
}
