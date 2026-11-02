import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Umum", systemImage: "gearshape") }
            PrivacySettings().tabItem { Label("Privasi", systemImage: "hand.raised") }
            SnippetSettings().tabItem { Label("Snippet", systemImage: "text.badge.star") }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var s = AppSettings.shared
    @StateObject private var ui = GeneralUI()

    var body: some View {
        Form {
            Picker("Shortcut buka riwayat", selection: $s.hotKeyLabel) {
                ForEach(HotKeyCombo.presets) { Text($0.label).tag($0.label) }
            }
            .onChange(of: s.hotKeyLabel) { _ in HotKeyManager.shared.register(s.hotKey) }

            Stepper("Simpan maksimal \(s.maxItems) item", value: $s.maxItems, in: 50...5000, step: 50)
                .onChange(of: s.maxItems) { _ in ClipStore.shared.prune() }

            Picker("Hapus otomatis item lebih lama dari", selection: $s.retentionDays) {
                Text("1 hari").tag(1)
                Text("7 hari").tag(7)
                Text("30 hari").tag(30)
                Text("90 hari").tag(90)
                Text("Jangan pernah").tag(0)
            }
            .onChange(of: s.retentionDays) { _ in ClipStore.shared.prune() }
            Text("Item yang di-pin tidak pernah dihapus otomatis.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Langsung paste ke app aktif setelah memilih", isOn: $s.autoPaste)
            Toggle("Kenali teks di gambar (OCR) agar bisa dicari", isOn: $s.ocrImages)

            Toggle("Jalankan saat login", isOn: $ui.launchAtLogin)
                .onChange(of: ui.launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        ui.launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            HStack {
                Image(systemName: ui.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ui.hasAccessibility ? .green : .orange)
                Text(ui.hasAccessibility ? "Izin Aksesibilitas aktif (auto-paste bisa jalan)"
                                      : "Auto-paste butuh izin Aksesibilitas")
                Spacer()
                if !ui.hasAccessibility {
                    Button("Beri izin…") {
                        Paster.requestAccessibility()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                ui.hasAccessibility = Paster.hasAccessibility
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @ObservedObject var s = AppSettings.shared
    @StateObject private var ui = PrivacyUI()

    var body: some View {
        Form {
            Toggle("Jeda perekaman clipboard", isOn: $s.paused)
            Toggle("Abaikan data rahasia (password manager, data sementara)", isOn: $s.ignoreConcealed)

            Section("Jangan rekam dari aplikasi ini") {
                List(s.excludedBundleIDs, id: \.self, selection: $ui.selection) { bid in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            Text(FileManager.default.displayName(atPath: url.path))
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18)
                            Text(bid).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 140)
                HStack {
                    Button("Tambah aplikasi…", action: addApp)
                    Button("Hapus") {
                        if let sel = ui.selection { s.excludedBundleIDs.removeAll { $0 == sel } }
                    }
                    .disabled(ui.selection == nil)
                }
            }

            Button("Hapus semua riwayat (kecuali pin)…", role: .destructive) { ui.confirmClear = true }
                .confirmationDialog("Hapus semua riwayat yang tidak di-pin?", isPresented: $ui.confirmClear) {
                    Button("Hapus", role: .destructive) { ClipStore.shared.clearUnpinned() }
                }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bid = Bundle(url: url)?.bundleIdentifier, !s.excludedBundleIDs.contains(bid) {
                s.excludedBundleIDs.append(bid)
            }
        }
    }
}

private struct SnippetSettings: View {
    @ObservedObject var store = ClipStore.shared
    @StateObject private var ui = SnippetUI()

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                List(store.snippets, selection: $ui.selection) { s in
                    Text(s.name.isEmpty ? "(tanpa nama)" : s.name).tag(s.id)
                }
                HStack {
                    Button {
                        let s = Snippet(name: "Snippet baru", text: "")
                        store.snippets.append(s)
                        ui.selection = s.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        store.snippets.removeAll { $0.id == ui.selection }
                        ui.selection = nil
                    } label: { Image(systemName: "minus") }
                    .disabled(ui.selection == nil)
                    Spacer()
                }
            }
            .frame(width: 180)

            if let idx = store.snippets.firstIndex(where: { $0.id == ui.selection }) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nama", text: $store.snippets[idx].name)
                    TextEditor(text: $store.snippets[idx].text)
                        .font(.system(.body, design: .monospaced))
                        .border(Color.secondary.opacity(0.3))
                    Text("Snippet muncul di tab \"Snippet\" pada popup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Pilih atau tambah snippet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private final class GeneralUI: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var hasAccessibility = Paster.hasAccessibility
}

private final class PrivacyUI: ObservableObject {
    @Published var selection: String?
    @Published var confirmClear = false
}

private final class SnippetUI: ObservableObject {
    @Published var selection: UUID?
}
