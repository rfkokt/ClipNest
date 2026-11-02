import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating ClipNest,
/// so the app the user was typing in stays frontmost for pasting.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    private let panel: ClipPanel
    private let model = PanelModel()
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    override init() {
        panel = ClipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false)
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(
            model: model,
            onPaste: { [weak self] entry, plain, transform in self?.paste(entry, plain: plain, transform: transform) },
            onClose: { [weak self] in self?.hide() }))
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        model.query = ""
        model.selection = 0
        model.focusToken += 1

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.08))
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func paste(_ entry: Entry, plain: Bool, transform: TextTransform?) {
        var kind = ClipKind.text
        switch entry {
        case .clip(let item):
            Paster.write(item, plain: plain, transform: transform)
            kind = item.kind
        case .snippet(let s):
            Paster.write(text: transform?.apply(s.text) ?? s.text)
        }
        hide()
        if let app = previousApp, !app.isActive { app.activate() }
        Paster.pasteIntoFrontApp(kind: kind, target: previousApp)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Returns true when the key was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let entries = model.entries()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let selected = entries.indices.contains(model.selection) ? entries[model.selection] : nil

        switch event.keyCode {
        case 53: // esc
            hide()
        case 125: // down
            model.selection = min(model.selection + 1, max(entries.count - 1, 0))
        case 126: // up
            model.selection = max(model.selection - 1, 0)
        case 36, 76: // return
            if let selected { paste(selected, plain: flags.contains(.shift), transform: nil) }
        case 48: // tab
            model.cycleCategory(forward: !flags.contains(.shift))
        case 35 where cmd: // ⌘P
            if case .clip(let item) = selected { ClipStore.shared.togglePin(item.id) }
        case 51 where cmd: // ⌘⌫
            if case .clip(let item) = selected {
                ClipStore.shared.remove(item.id)
                model.selection = min(model.selection, max(entries.count - 2, 0))
            }
        default:
            if cmd, let i = Self.digitKeyCodes.firstIndex(of: event.keyCode) {
                if entries.indices.contains(i) { paste(entries[i], plain: false, transform: nil) }
                return true
            }
            return false
        }
        return true
    }
}
