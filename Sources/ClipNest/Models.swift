import AppKit

enum ClipKind: String, Codable {
    case text, image, file
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    var text: String?
    var rtf: Data?
    var imageName: String?
    var imageHash: String?
    var imageSize: CGSize?
    var ocrText: String?
    var filePaths: [String]?
    var sourceAppName: String?
    var sourceBundleID: String?
    var date = Date()
    var pinned = false

    /// One-line label used in lists and the menu bar.
    var title: String {
        switch kind {
        case .text:
            let line = (text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            return line.isEmpty ? "(spasi kosong)" : line
        case .image:
            if let s = imageSize { return "Gambar \(Int(s.width))×\(Int(s.height))" }
            return "Gambar"
        case .file:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count > 1 { return "\(names[0]) +\(names.count - 1) file" }
            return names.first ?? "File"
        }
    }

    /// Everything the search box can match against.
    var searchText: String {
        [text, ocrText, filePaths?.joined(separator: " "), sourceAppName]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
}

enum Category: String, CaseIterable, Identifiable {
    case all = "Semua"
    case text = "Teks"
    case image = "Gambar"
    case file = "File"
    case pinned = "Pin"
    case snippets = "Snippet"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .pinned: return "pin"
        case .snippets: return "text.badge.star"
        }
    }
}

enum TextTransform: String, CaseIterable, Identifiable {
    case plain = "Teks polos"
    case upper = "HURUF BESAR"
    case lower = "huruf kecil"
    case title = "Huruf Awal Kapital"
    case trim = "Hapus spasi di ujung"
    case singleLine = "Gabung jadi satu baris"
    case jsonPretty = "Rapikan JSON"
    case urlEncode = "URL encode"
    case urlDecode = "URL decode"
    case base64Encode = "Base64 encode"
    case base64Decode = "Base64 decode"

    var id: String { rawValue }

    func apply(_ s: String) -> String {
        switch self {
        case .plain: return s
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .title: return s.capitalized
        case .trim: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .singleLine:
            return s.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .jsonPretty:
            guard let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]),
                  let str = String(data: out, encoding: .utf8) else { return s }
            return str
        case .urlEncode:
            return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        case .urlDecode:
            return s.removingPercentEncoding ?? s
        case .base64Encode:
            return Data(s.utf8).base64EncodedString()
        case .base64Decode:
            guard let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let str = String(data: d, encoding: .utf8) else { return s }
            return str
        }
    }
}

/// Case-insensitive match: substring hits rank above subsequence ("fuzzy") hits.
func fuzzyScore(_ query: String, in text: String) -> Int? {
    let q = query.lowercased()
    let t = text.lowercased()
    if q.isEmpty { return 0 }
    if let r = t.range(of: q) {
        return 10_000 - t.distance(from: t.startIndex, to: r.lowerBound)
    }
    var score = 0
    var ti = t.startIndex
    var lastMatch: String.Index?
    for qc in q where !qc.isWhitespace {
        guard let found = t[ti...].firstIndex(of: qc) else { return nil }
        if let last = lastMatch, t.index(after: last) == found { score += 5 } else { score += 1 }
        lastMatch = found
        ti = t.index(after: found)
    }
    return score
}
