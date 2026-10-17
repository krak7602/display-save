import AppKit
import SwiftUI

@main
enum DisplaySaveApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var model: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let content = NSHostingController(rootView: PopoverView(model: model))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // The app embeds its SwiftPM resource bundle in Contents/Resources.
            guard let bundleURL = Bundle.main.url(forResource: "DisplaySave_DisplaySave", withExtension: "bundle"),
                  let resources = Bundle(url: bundleURL),
                  let iconURL = resources.url(forResource: "StatusIcon", withExtension: "pdf"),
                  let image = NSImage(contentsOf: iconURL) else {
                fatalError("Display Save's packaged status icon is missing.")
            }
            image.size = NSSize(width: 22, height: 18)
            image.isTemplate = true
            button.image = image
            button.toolTip = "Display Save"
            button.setAccessibilityLabel("Display Save")
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let firstLaunch = !UserDefaults.standard.bool(forKey: "HasOpenedDisplaySave")
        if firstLaunch || ProcessInfo.processInfo.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPopover()
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover else { return }
        if popover.isShown { popover.performClose(sender) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        model?.refreshCurrent()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        UserDefaults.standard.set(true, forKey: "HasOpenedDisplaySave")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.hasUnconfirmedChanges else { return .terminateNow }
        model.prepareForTermination { [weak self] restored in
            NSApp.reply(toApplicationShouldTerminate: restored)
            if !restored { self?.showPopover() }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
