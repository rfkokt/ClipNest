import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let panel = PanelController()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        AppSettings.shared.$paused
            .sink { [weak self] paused in self?.updateIcon(paused: paused) }
            .store(in: &cancellables)

        HotKeyManager.shared.onPress = { [weak self] in self?.panel.toggle() }
        HotKeyManager.shared.register(AppSettings.shared.hotKey)
        ClipboardMonitor.shared.start()

        // Expire old items periodically, not only when something new is copied.
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in ClipStore.shared.prune() }

        if !Paster.hasAccessibility { Paster.requestAccessibility() }
    }

    private func updateIcon(paused: Bool) {
        let name = paused ? "pause.circle" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "ClipNest")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = AppSettings.shared

        menu.addItem(item("Buka ClipNest (\(s.hotKey.label))", #selector(openPanel)))
        menu.addItem(.separator())

        let recent = ClipStore.shared.items.prefix(10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Riwayat masih kosong", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (i, clip) in recent.enumerated() {
            var title = clip.title
            if title.count > 50 { title = String(title.prefix(50)) + "…" }
            let mi = item(title, #selector(pasteRecent(_:)), key: i < 9 ? "\(i + 1)" : "")
            mi.representedObject = clip.id
            switch clip.kind {
            case .text: mi.image = NSImage(systemSymbolName: clip.pinned ? "pin" : "text.alignleft", accessibilityDescription: nil)
            case .image:
                if let img = ClipStore.shared.image(clip) {
                    let thumb = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                        img.draw(in: rect); return true
                    }
                    mi.image = thumb
                }
            case .file: mi.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            }
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let pause = item(s.paused ? "Lanjutkan perekaman" : "Jeda perekaman", #selector(togglePause))
        menu.addItem(pause)
        menu.addItem(item("Hapus riwayat (kecuali pin)", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Pengaturan…", #selector(openSettings), key: ","))
        menu.addItem(item("Keluar ClipNest", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func openPanel() {
        // Let the menu finish closing first, so the panel keeps focus.
        DispatchQueue.main.async { self.panel.show() }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
        Paster.write(clip)
        Paster.pasteIntoFrontApp(kind: clip.kind)
    }

    @objc private func togglePause() {
        AppSettings.shared.paused.toggle()
    }

    @objc private func clearHistory() {
        ClipStore.shared.clearUnpinned()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Pengaturan ClipNest"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
