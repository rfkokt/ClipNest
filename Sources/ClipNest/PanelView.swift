import AppKit
import SwiftUI

enum Entry: Identifiable {
    case clip(ClipItem)
    case snippet(Snippet)

    var id: UUID {
        switch self {
        case .clip(let c): return c.id
        case .snippet(let s): return s.id
        }
    }
}

final class PanelModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var category: Category = .all { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var focusToken = 0

    func entries(_ store: ClipStore = .shared) -> [Entry] {
        if category == .snippets {
            let list = store.snippets
            if query.isEmpty { return list.map(Entry.snippet) }
            return list
                .compactMap { s in fuzzyScore(query, in: s.name + " " + s.text).map { (s, $0) } }
                .sorted { $0.1 > $1.1 }
                .map { Entry.snippet($0.0) }
        }

        let filtered = store.items.filter { item in
            switch category {
            case .all: return true
            case .text: return item.kind == .text
            case .image: return item.kind == .image
            case .file: return item.kind == .file
            case .pinned: return item.pinned
            case .snippets: return false
            }
        }
        if query.isEmpty { return filtered.map(Entry.clip) }
        return filtered
            .compactMap { item in fuzzyScore(query, in: item.searchText).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map { Entry.clip($0.0) }
    }

    func count(_ c: Category, _ store: ClipStore) -> Int {
        switch c {
        case .all: return store.items.count
        case .text: return store.items.filter { $0.kind == .text }.count
        case .image: return store.items.filter { $0.kind == .image }.count
        case .file: return store.items.filter { $0.kind == .file }.count
        case .pinned: return store.items.filter(\.pinned).count
        case .snippets: return store.snippets.count
        }
    }

    func cycleCategory(forward: Bool) {
        let all = Category.allCases
        let i = all.firstIndex(of: category)!
        category = all[(i + (forward ? 1 : all.count - 1)) % all.count]
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store = ClipStore.shared
    @ObservedObject var settings = AppSettings.shared
    @FocusState private var searchFocused: Bool

    var onPaste: (Entry, Bool, TextTransform?) -> Void
    var onClose: () -> Void

    var body: some View {
        let entries = model.entries(store)
        let selected = entries.indices.contains(model.selection) ? entries[model.selection] : nil

        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list(entries).frame(width: 330)
                Divider()
                preview(selected).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(VisualEffect().ignoresSafeArea())
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _ in searchFocused = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cari riwayat, teks di gambar, nama file…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                if settings.paused {
                    Label("Dijeda", systemImage: "pause.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 4) {
                ForEach(Category.allCases) { c in
                    Button { model.category = c } label: {
                        HStack(spacing: 4) {
                            Image(systemName: c.symbol)
                            Text(c.rawValue)
                            Text("\(model.count(c, store))").foregroundStyle(.secondary).font(.caption2)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(model.category == c ? Color.accentColor.opacity(0.25) : Color.clear)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .font(.callout)
        }
        .padding(14)
    }

    // MARK: List

    private func list(_ entries: [Entry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry, index: index, selected: index == model.selection)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onPaste(entry, false, nil) }
                            .onHover { inside in if inside { model.selection = index } }
                    }
                }
                .padding(6)
            }
            .overlay {
                if entries.isEmpty {
                    Text(model.category == .snippets ? "Belum ada snippet.\nTambahkan di Pengaturan → Snippet." : "Tidak ada item.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.selection) { sel in
                if entries.indices.contains(sel) { proxy.scrollTo(entries[sel].id) }
            }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private func preview(_ entry: Entry?) -> some View {
        switch entry {
        case nil:
            Text("Pilih item untuk melihat pratinjau").foregroundStyle(.secondary)
        case .snippet(let s):
            VStack(alignment: .leading, spacing: 0) {
                textPreview(s.text)
                Divider()
                actionBar(entry: .snippet(s), isText: true, item: nil)
            }
        case .clip(let item):
            VStack(alignment: .leading, spacing: 0) {
                switch item.kind {
                case .text:
                    textPreview(item.text ?? "")
                case .image:
                    imagePreview(item)
                case .file:
                    filePreview(item)
                }
                Divider()
                meta(item)
                actionBar(entry: .clip(item), isText: item.kind == .text, item: item)
            }
        }
    }

    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    private func imagePreview(_ item: ClipItem) -> some View {
        VStack(spacing: 8) {
            if let img = store.image(item) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
            if let ocr = item.ocrText, !ocr.isEmpty {
                DisclosureGroup("Teks terdeteksi di gambar") {
                    ScrollView {
                        Text(ocr).font(.caption).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                }
                .padding(.horizontal, 14).padding(.bottom, 6)
            }
        }
    }

    private func filePreview(_ item: ClipItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.filePaths ?? [], id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text((path as NSString).lastPathComponent).lineLimit(1)
                            Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Tampilkan di Finder")
                    }
                }
            }
            .padding(14)
        }
    }

    private func meta(_ item: ClipItem) -> some View {
        HStack(spacing: 12) {
            if let app = item.sourceAppName { Label(app, systemImage: "app") }
            Label(item.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            if item.kind == .text, let t = item.text {
                Text("\(t.count) karakter · \(t.components(separatedBy: .newlines).count) baris")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private func actionBar(entry: Entry, isText: Bool, item: ClipItem?) -> some View {
        HStack(spacing: 8) {
            Button("Paste") { onPaste(entry, false, nil) }
            if isText {
                if item?.rtf != nil {
                    Button("Paste polos") { onPaste(entry, true, nil) }
                }
                Menu("Ubah teks lalu paste") {
                    ForEach(TextTransform.allCases.filter { $0 != .plain }) { t in
                        Button(t.rawValue) { onPaste(entry, true, t) }
                    }
                }
                .fixedSize()
            }
            Spacer()
            if let item {
                Button { store.togglePin(item.id) } label: {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                }
                .help(item.pinned ? "Lepas pin (⌘P)" : "Pin (⌘P)")
                Button(role: .destructive) { store.remove(item.id) } label: {
                    Image(systemName: "trash")
                }
                .help("Hapus (⌘⌫)")
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "pilih")
            hint("↩", "paste")
            hint("⇧↩", "teks polos")
            hint("⌘1–9", "paste cepat")
            hint("⇥", "ganti tab")
            hint("⌘P", "pin")
            hint("⌘⌫", "hapus")
            hint("esc", "tutup")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.semibold)
            Text(text)
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            thumbnail.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if case .clip(let c) = entry, c.pinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
            }
            if index < 9 {
                Text("⌘\(index + 1)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var title: String {
        switch entry {
        case .clip(let c): return c.title
        case .snippet(let s): return s.name
        }
    }

    private var subtitle: String {
        switch entry {
        case .snippet(let s):
            return s.text.components(separatedBy: .newlines).first ?? ""
        case .clip(let c):
            let kind: String
            switch c.kind {
            case .text: kind = "Teks"
            case .image: kind = "Gambar"
            case .file: kind = "File"
            }
            let when = RelativeDateTimeFormatter().localizedString(for: c.date, relativeTo: Date())
            return [kind, c.sourceAppName, when].compactMap { $0 }.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch entry {
        case .snippet:
            icon("text.badge.star", .purple)
        case .clip(let c):
            switch c.kind {
            case .text:
                icon("text.alignleft", .blue)
            case .file:
                if let first = c.filePaths?.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable()
                } else {
                    icon("doc", .gray)
                }
            case .image:
                if let img = ClipStore.shared.image(c) {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    icon("photo", .green)
                }
            }
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.18))
            .overlay(Image(systemName: name).foregroundStyle(color))
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
