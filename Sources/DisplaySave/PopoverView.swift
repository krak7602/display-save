import AppKit
import DisplayCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var isNaming = false
    @State private var name = ""
    @State private var deleteCandidate: DisplayPreset?
    @State private var contentHeight: CGFloat = 200
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        currentLayout
                        if let error = model.persistenceError {
                            messageCard(
                                "Saved layouts couldn’t be read",
                                message: error,
                                symbol: "externaldrive.badge.exclamationmark"
                            )
                        }
                        if let notice = model.notice {
                            VStack(alignment: .leading, spacing: 8) {
                                messageCard(notice.title, message: notice.message, symbol: "exclamationmark.circle")
                                Button("Dismiss") { model.dismissNotice() }
                                    .font(.caption)
                            }
                        }
                        if let confirmation = model.confirmation {
                            confirmationCard(confirmation)
                                .id("confirmation")
                        } else if model.isBusy {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text(model.activity).font(.callout)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityElement(children: .combine)
                        }
                        savedLayouts
                    }
                    .padding(12)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ContentHeightPreference.self, value: geometry.size.height)
                        }
                    }
                }
                .frame(height: min(contentHeight, maximumContentHeight))
                .onPreferenceChange(ContentHeightPreference.self) { contentHeight = $0 }
                .onChange(of: model.confirmation != nil) { _, pending in
                    if pending { scroll.scrollTo("confirmation", anchor: .top) }
                }
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .onChange(of: model.hasUnconfirmedChanges) { _, active in
            if active { isNaming = false; name = ""; deleteCandidate = nil }
        }
        .onChange(of: deleteCandidate?.id) { _, candidate in
            if candidate != nil { cancelNaming() }
        }
        .onExitCommand {
            if deleteCandidate != nil { deleteCandidate = nil }
            else if isNaming { cancelNaming() }
            else if model.confirmation != nil { model.revert() }
            else { NSApp.keyWindow?.close() }
        }
    }

    private var maximumContentHeight: CGFloat {
        min(460, max(160, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
    }


    private var currentLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.captureError {
                messageCard("Couldn’t read displays", message: error, symbol: "display.trianglebadge.exclamationmark")
                Button("Try Again") { model.refreshCurrent() }
                    .disabled(model.isBusy)
            } else if model.current.isEmpty {
                Text("No displays connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ArrangementView(displays: model.current.map(\.state), compact: false)
                        .frame(height: 104)
                        .help(model.current.map { $0.state.name }.joined(separator: " · "))
                        .overlay(alignment: .bottom) {
                            HStack {
                                Text("\(model.current.count) \(model.current.count == 1 ? "display" : "displays")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !isNaming {
                                    saveControls
                                }
                            }
                            .padding(10)
                        }
                    if isNaming {
                        Divider()
                        saveControls
                            .frame(minHeight: 30)
                            .padding(10)
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var saveControls: some View {
        if isNaming {
            HStack(spacing: 8) {
                TextField("Layout name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .accessibilityLabel("Layout name")
                    .onSubmit { save() }
                Button("Cancel") { cancelNaming() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canSave)
            }
            .controlSize(.large)
            .onAppear { nameFocused = true }
        } else {
            Button("Save…") {
                deleteCandidate = nil
                name = ""
                isNaming = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.canSave)
            .accessibilityLabel("Save current layout")
        }
    }

    private var savedLayouts: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.presets.isEmpty {
                Text(model.persistenceError == nil ? "No saved layouts" : "Layouts unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Layouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(model.presets, id: \.id) { preset in
                        presetRow(preset)
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: DisplayPreset) -> some View {
        let availability = model.availability(of: preset)
        let isCurrent = model.isCurrent(preset)
        return HStack(spacing: 8) {
            ArrangementView(displays: preset.displays, compact: true)
                .frame(width: 44, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .help(preset.name)
                if availability.matched < availability.total {
                    Text("\(availability.matched)/\(availability.total) connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if deleteCandidate?.id == preset.id {
                HStack(spacing: 6) {
                    Button("Cancel") { deleteCandidate = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Delete", role: .destructive) {
                        model.delete(preset)
                        deleteCandidate = nil
                    }
                    .disabled(!model.canEditPresets)
                    .accessibilityLabel("Confirm deleting \(preset.name)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .labelStyle(.iconOnly)
                        .help("Matches your current display arrangement")
                        .accessibilityLabel("Current layout")
                } else {
                    Button("Switch") { model.apply(preset) }
                        .controlSize(.small)
                        .disabled(!availability.canApply || model.hasUnconfirmedChanges)
                        .accessibilityLabel("Switch to \(preset.name)")
                        .help(availability.canApply ? "Apply this saved arrangement" : "None of this layout’s displays are connected")
                }
                Button {
                    deleteCandidate = preset
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canEditPresets)
                .accessibilityLabel("Delete \(preset.name)")
                .help("Delete layout")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete “\(preset.name)”", role: .destructive) { deleteCandidate = preset }
                .disabled(!model.canEditPresets)
        }
    }

    private func confirmationCard(_ confirmation: AppModel.Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keep “\(confirmation.layoutName)”?")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text("Reverts in \(model.secondsRemaining)s")
                    .font(.caption.monospacedDigit())
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reverts in \(model.secondsRemaining) seconds")
            }
            if !confirmation.warnings.isEmpty {
                DisclosureGroup("Adjustments") {
                    Text(confirmation.warnings.joined(separator: "\n"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
            HStack {
                Spacer()
                Button("Revert") { model.revert() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityHint("Restore the previous arrangement")
                Button("Keep") { model.keep() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Button("Display Settings…") { model.openDisplaySettings() }
                .accessibilityHint("Arrange your displays in System Settings")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func messageCard(_ title: String, message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    private func save() {
        if model.saveCurrent(named: name) { cancelNaming() }
    }

    private func cancelNaming() {
        isNaming = false
        name = ""
        nameFocused = false
    }
}

private struct ContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ArrangementView: View {
    let displays: [DisplayState]
    let compact: Bool

    var body: some View {
        Canvas { context, size in
            let identities = Set(displays.map(\.id))
            let independent = displays.filter { display in
                guard let source = display.mirrorSourceUUID else { return true }
                return !identities.contains(source)
            }
            let visible = independent.isEmpty ? displays : independent
            let rectangles = visible.map { display -> CGRect in
                // CoreGraphics mode dimensions already include the display’s rotation.
                CGRect(x: display.x, y: display.y,
                       width: max(1, display.mode.width), height: max(1, display.mode.height))
            }
            guard let first = rectangles.first else { return }
            let bounds = rectangles.dropFirst().reduce(first) { $0.union($1) }
            let inset: CGFloat = compact ? 3 : 13
            let scale = min((size.width - inset * 2) / max(1, bounds.width),
                            (size.height - inset * 2) / max(1, bounds.height))
            let offsetX = (size.width - bounds.width * scale) / 2
            let offsetY = (size.height - bounds.height * scale) / 2
            for (index, display) in visible.enumerated() {
                let original = rectangles[index]
                let rect = CGRect(
                    x: (original.minX - bounds.minX) * scale + offsetX,
                    y: (original.minY - bounds.minY) * scale + offsetY,
                    width: original.width * scale,
                    height: original.height * scale
                ).insetBy(dx: 1.5, dy: 1.5)
                let path = Path(roundedRect: rect, cornerRadius: compact ? 2 : 4)
                context.fill(path, with: .color(display.isMain ? .accentColor.opacity(0.24) : .secondary.opacity(0.13)))
                context.stroke(path, with: .color(display.isMain ? .accentColor : .secondary.opacity(0.65)), lineWidth: compact ? 1 : 1.5)
                if display.isMain, rect.width > 8, rect.height > 8 {
                    let bar = CGRect(x: rect.minX + 3, y: rect.minY + 3, width: max(1, rect.width - 6), height: compact ? 2 : 3)
                    context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(.accentColor.opacity(0.7)))
                }
                if !compact, rect.width > 46, rect.height > 28 {
                    let mirrored = displays.contains { $0.mirrorSourceUUID == display.id }
                    let title = mirrored ? "\(index + 1) · Mirrored" : "\(index + 1)"
                    context.draw(Text(title).font(.system(size: rect.width > 90 ? 11 : 9, weight: .medium)).foregroundStyle(.primary),
                                 at: CGPoint(x: rect.midX, y: rect.midY + 2))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Display arrangement")
        .accessibilityValue(displays.map { display in
            let primary = display.isMain ? ", main display" : ""
            let mirror = display.mirrorSourceUUID == nil ? "" : ", mirrored"
            return "\(display.name), \(display.mode.width) by \(display.mode.height), position \(display.x), \(display.y), rotation \(display.rotation) degrees\(primary)\(mirror)"
        }.joined(separator: "; "))
    }
}
