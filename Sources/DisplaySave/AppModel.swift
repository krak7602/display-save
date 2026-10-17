import AppKit
import Combine
import DisplayCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    struct Notice {
        let title: String
        let message: String
    }

    struct Confirmation {
        let layoutName: String
        let previous: DisplayPreset
        let warnings: [String]
        let availability: Availability
        let deadline: Date
    }

    struct Availability {
        let matched: Int
        let total: Int
        var canApply: Bool { matched > 0 }
        var text: String {
            if matched == total { return "All \(total) connected" }
            return "\(matched) of \(total) connected"
        }
    }

    @Published private(set) var presets: [DisplayPreset] = []
    @Published private(set) var current: [ConnectedDisplay] = []
    @Published private(set) var isBusy = false
    @Published private(set) var activity = ""
    @Published private(set) var confirmation: Confirmation?
    @Published private(set) var secondsRemaining = 20
    @Published private(set) var notice: Notice?
    @Published private(set) var persistenceError: String?
    @Published private(set) var captureError: String?

    private let service = DisplayService()
    private var store: PresetStore?
    private var screenObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var countdown: Timer?
    private var terminationReply: ((Bool) -> Void)?

    var canEditPresets: Bool { store != nil && persistenceError == nil && !isBusy && confirmation == nil }
    var canSave: Bool { canEditPresets && !current.isEmpty && captureError == nil }
    var hasUnconfirmedChanges: Bool { isBusy || confirmation != nil }

    init() {
        do {
            let loadedStore = try PresetStore()
            let loaded = try loadedStore.load()
            store = loadedStore
            presets = loaded
        } catch {
            persistenceError = error.localizedDescription
        }
        refreshCurrent()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        refreshTask?.cancel()
        countdown?.invalidate()
    }

    func refreshCurrent() {
        guard !isBusy else { return }
        captureCurrent()
    }

    private func captureCurrent() {
        do {
            current = try service.capture()
            captureError = nil
        } catch {
            current = []
            captureError = error.localizedDescription
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refreshCurrent()
        }
    }

    func availability(of preset: DisplayPreset) -> Availability {
        guard let plan = try? RestorePlanner.plan(saved: preset.displays, connected: current) else {
            return Availability(matched: 0, total: preset.displays.count)
        }
        let identities = Set(preset.displays.map(\.id))
        let matched = plan.displays.filter { identities.contains($0.saved.id) }.count
        return Availability(matched: matched, total: preset.displays.count)
    }

    func isCurrent(_ preset: DisplayPreset) -> Bool {
        guard captureError == nil, !isBusy,
              current.count == preset.displays.count,
              let plan = try? RestorePlanner.plan(saved: preset.displays, connected: current),
              plan.displays.count == preset.displays.count,
              Set(plan.displays.map { $0.saved.id }) == Set(preset.displays.map(\.id)) else { return false }
        let liveByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.state) })
        for planned in plan.displays {
            guard let live = liveByID[planned.displayID],
                  live.mode.matches(planned.saved.mode),
                  live.x == planned.x, live.y == planned.y,
                  live.rotation == planned.saved.rotation,
                  live.isMain == planned.saved.isMain else { return false }
            let expectedMirror = planned.mirrorSourceID.flatMap { liveByID[$0]?.id }
            guard live.mirrorSourceUUID == expectedMirror else { return false }
        }
        return true
    }

    func saveCurrent(named proposedName: String) -> Bool {
        guard canEditPresets, let store else { return false }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            notice = Notice(title: "Give this layout a name", message: "Enter a name before saving.")
            return false
        }
        guard !presets.contains(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) else {
            notice = Notice(title: "That name is already used", message: "Choose another name for this layout.")
            return false
        }
        do {
            let snapshot = try service.capture()
            guard !snapshot.isEmpty else {
                notice = Notice(title: "No displays found", message: "Connect a display, then try saving again.")
                return false
            }
            let preset = DisplayPreset(name: name, displays: snapshot.map(\.state))
            let updated = presets + [preset]
            try store.save(updated)
            presets = updated
            current = snapshot
            captureError = nil
            notice = nil
            return true
        } catch {
            notice = Notice(title: "Couldn’t save layout", message: "Your saved layouts have not changed. \(error.localizedDescription)")
            return false
        }
    }

    func delete(_ preset: DisplayPreset) {
        guard canEditPresets, let store else { return }
        let updated = presets.filter { $0.id != preset.id }
        do {
            try store.save(updated)
            presets = updated
            notice = nil
        } catch {
            notice = Notice(title: "Couldn’t delete layout", message: "Your saved layouts have not changed. \(error.localizedDescription)")
        }
    }

    func apply(_ preset: DisplayPreset) {
        guard !hasUnconfirmedChanges else { return }
        let previous: DisplayPreset
        do {
            let snapshot = try service.capture()
            guard !snapshot.isEmpty else {
                notice = Notice(title: "No displays found", message: "Connect a display and try again.")
                return
            }
            previous = DisplayPreset(name: "Previous arrangement", displays: snapshot.map(\.state))
        } catch {
            notice = Notice(title: "Couldn’t read your current layout", message: "Nothing was changed. \(error.localizedDescription)")
            return
        }
        notice = nil
        isBusy = true
        activity = "Applying \(preset.name)…"
        refreshTask?.cancel()
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.service.restore(preset)
                if self.terminationReply != nil {
                    await self.rollback(previous, reason: nil)
                    return
                }
                self.isBusy = false
                self.captureCurrent()
                self.confirmation = Confirmation(
                    layoutName: preset.name,
                    previous: previous,
                    warnings: outcome.warnings,
                    availability: self.availability(of: preset),
                    deadline: Date().addingTimeInterval(20)
                )
                self.secondsRemaining = 20
                self.startCountdown()
            } catch {
                await self.rollback(previous, reason: "Couldn’t apply “\(preset.name)”. \(error.localizedDescription)")
            }
        }
    }

    private func startCountdown() {
        countdown?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        countdown = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let confirmation else { return }
        secondsRemaining = max(0, Int(ceil(confirmation.deadline.timeIntervalSinceNow)))
        if secondsRemaining == 0 { revert(timedOut: true) }
    }

    func keep() {
        guard let pending = confirmation, !isBusy else { return }
        // A delayed click must not extend the safety window.
        guard pending.deadline > Date() else { revert(timedOut: true); return }
        countdown?.invalidate()
        countdown = nil
        do {
            try service.keep()
            confirmation = nil
            captureCurrent()
            notice = pending.warnings.isEmpty ? nil : Notice(
                title: "Layout kept with adjustments",
                message: pending.warnings.joined(separator: "\n")
            )
        } catch {
            confirmation = nil
            isBusy = true
            activity = "Restoring previous layout…"
            operationTask = Task { @MainActor [weak self] in
                await self?.rollback(pending.previous, reason: "Couldn’t keep this layout. \(error.localizedDescription)")
            }
        }
    }

    func revert(timedOut: Bool = false) {
        guard let pending = confirmation, !isBusy else { return }
        countdown?.invalidate()
        countdown = nil
        confirmation = nil
        isBusy = true
        activity = "Restoring previous layout…"
        operationTask = Task { @MainActor [weak self] in
            await self?.rollback(
                pending.previous,
                reason: timedOut ? "The layout was not confirmed within 20 seconds." : nil
            )
        }
    }

    func prepareForTermination(_ completion: @escaping (Bool) -> Void) {
        guard hasUnconfirmedChanges else { completion(true); return }
        terminationReply = completion
        if confirmation != nil { revert() }
        // An in-flight apply or rollback finishes through rollback before replying.
    }

    private func rollback(_ previous: DisplayPreset, reason: String?) async {
        isBusy = true
        activity = "Restoring previous layout…"
        confirmation = nil
        countdown?.invalidate()
        countdown = nil
        var restored = false
        do {
            let outcome = try await service.restore(previous)
            // Restore applies for this session. Persist the rollback, not the rejected layout.
            try service.keep()
            var detail = [reason, "Your previous layout was restored."].compactMap { $0 }
            detail.append(contentsOf: outcome.warnings)
            notice = Notice(title: "Layout reverted", message: detail.joined(separator: "\n"))
            restored = true
        } catch {
            let prefix = reason.map { "\($0)\n\n" } ?? ""
            notice = Notice(
                title: "Couldn’t fully restore the previous layout",
                message: prefix + "Rollback failed: \(error.localizedDescription)\nOpen Display Settings to check and recover your arrangement."
            )
        }
        isBusy = false
        captureCurrent()
        let reply = terminationReply
        terminationReply = nil
        reply?(restored)
    }

    func dismissNotice() { notice = nil }

    func openDisplaySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            notice = Notice(title: "Couldn’t open Display Settings", message: "Open System Settings and choose Displays to adjust your arrangement.")
        }
    }
}
