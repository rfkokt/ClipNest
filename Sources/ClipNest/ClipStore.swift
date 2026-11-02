import AppKit
import CryptoKit
import Vision

final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []
    @Published var snippets: [Snippet] = [] { didSet { saveSnippets() } }

    let baseDir: URL
    let imagesDir: URL
    private var historyURL: URL { baseDir.appendingPathComponent("history.json") }
    private var snippetsURL: URL { baseDir.appendingPathComponent("snippets.json") }
    private var pendingSave: DispatchWorkItem?
    private let thumbCache = NSCache<NSString, NSImage>()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("ClipNest", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: historyURL),
           let list = try? dec.decode([ClipItem].self, from: data) {
            items = list
        }
        if let data = try? Data(contentsOf: snippetsURL),
           let list = try? dec.decode([Snippet].self, from: data) {
            snippets = list
        }
        prune()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = items
        let url = historyURL
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: snippetsURL, options: .atomic)
        }
    }

    // MARK: Mutations

    func add(_ new: ClipItem) {
        if let idx = items.firstIndex(where: { isDuplicate($0, new) }) {
            var existing = items.remove(at: idx)
            existing.date = Date()
            existing.sourceAppName = new.sourceAppName ?? existing.sourceAppName
            existing.sourceBundleID = new.sourceBundleID ?? existing.sourceBundleID
            items.insert(existing, at: 0)
            // The new copy wrote its own image file; it is not needed.
            if let name = new.imageName, name != existing.imageName { deleteImage(name) }
        } else {
            items.insert(new, at: 0)
            if new.kind == .image, AppSettings.shared.ocrImages { runOCR(for: new) }
        }
        prune()
        scheduleSave()
    }

    private func isDuplicate(_ a: ClipItem, _ b: ClipItem) -> Bool {
        guard a.kind == b.kind else { return false }
        switch a.kind {
        case .text: return a.text == b.text
        case .image: return a.imageHash != nil && a.imageHash == b.imageHash
        case .file: return a.filePaths == b.filePaths
        }
    }

    func bump(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: idx)
        item.date = Date()
        items.insert(item, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        if let name = item.imageName { deleteImage(name) }
        scheduleSave()
    }

    func clearUnpinned() {
        for item in items where !item.pinned {
            if let name = item.imageName { deleteImage(name) }
        }
        items.removeAll { !$0.pinned }
        scheduleSave()
    }

    /// Drops expired items and trims to the size limit. Pinned items are never removed.
    func prune() {
        let s = AppSettings.shared
        var removed: [ClipItem] = []
        if s.retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(s.retentionDays) * 86_400)
            removed += items.filter { !$0.pinned && $0.date < cutoff }
            items.removeAll { !$0.pinned && $0.date < cutoff }
        }
        var unpinnedSeen = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinnedSeen += 1
            if unpinnedSeen > s.maxItems { removed.append(item); return false }
            return true
        }
        for item in removed { if let name = item.imageName { deleteImage(name) } }
        if !removed.isEmpty { scheduleSave() }
    }

    // MARK: Images

    /// Writes PNG data to disk and returns (file name, sha256).
    func storeImage(_ png: Data) -> (String, String) {
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let name = "\(UUID().uuidString).png"
        try? png.write(to: imagesDir.appendingPathComponent(name))
        return (name, hash)
    }

    func imageURL(_ item: ClipItem) -> URL? {
        item.imageName.map { imagesDir.appendingPathComponent($0) }
    }

    func image(_ item: ClipItem) -> NSImage? {
        guard let name = item.imageName else { return nil }
        if let cached = thumbCache.object(forKey: name as NSString) { return cached }
        guard let img = NSImage(contentsOf: imagesDir.appendingPathComponent(name)) else { return nil }
        thumbCache.setObject(img, forKey: name as NSString)
        return img
    }

    private func deleteImage(_ name: String) {
        thumbCache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    /// Recognizes text in an image so it can be found through search.
    private func runOCR(for item: ClipItem) {
        guard let url = imageURL(item) else { return }
        let id = item.id
        DispatchQueue.global(qos: .utility).async {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[idx].ocrText = text
                self.scheduleSave()
            }
        }
    }
}
