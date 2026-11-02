import AppKit
import Carbon

struct HotKeyCombo: Equatable, Identifiable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    var id: String { label }

    static let presets: [HotKeyCombo] = [
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), label: "⇧⌘V"),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), label: "⌥⌘V"),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey), label: "⌃⌘V"),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧V"),
        HotKeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), label: "⇧⌘C"),
        HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Space"),
    ]
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    static let defaultExcluded = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    @Published var maxItems: Int { didSet { d.set(maxItems, forKey: "maxItems") } }
    @Published var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var ignoreConcealed: Bool { didSet { d.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    @Published var autoPaste: Bool { didSet { d.set(autoPaste, forKey: "autoPaste") } }
    @Published var ocrImages: Bool { didSet { d.set(ocrImages, forKey: "ocrImages") } }
    @Published var excludedBundleIDs: [String] { didSet { d.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    @Published var hotKeyLabel: String { didSet { d.set(hotKeyLabel, forKey: "hotKeyLabel") } }

    var hotKey: HotKeyCombo {
        HotKeyCombo.presets.first { $0.label == hotKeyLabel } ?? HotKeyCombo.presets[0]
    }

    private init() {
        d.register(defaults: [
            "maxItems": 500,
            "retentionDays": 30,
            "paused": false,
            "ignoreConcealed": true,
            "autoPaste": true,
            "ocrImages": true,
            "excludedBundleIDs": AppSettings.defaultExcluded,
            "hotKeyLabel": HotKeyCombo.presets[0].label,
        ])
        maxItems = d.integer(forKey: "maxItems")
        retentionDays = d.integer(forKey: "retentionDays")
        paused = d.bool(forKey: "paused")
        ignoreConcealed = d.bool(forKey: "ignoreConcealed")
        autoPaste = d.bool(forKey: "autoPaste")
        ocrImages = d.bool(forKey: "ocrImages")
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? AppSettings.defaultExcluded
        hotKeyLabel = d.string(forKey: "hotKeyLabel") ?? HotKeyCombo.presets[0].label
    }
}
