import Foundation
import Combine

// MARK: - 链接

enum LinkKind: String, Codable, CaseIterable, Hashable {
    case hls
    case file
    case page

    var label: String {
        switch self {
        case .hls: return "HLS 流"
        case .file: return "文件直链"
        case .page: return "网页"
        }
    }

    var icon: String {
        switch self {
        case .hls: return "dot.radiowaves.left.and.right"
        case .file: return "doc"
        case .page: return "globe"
        }
    }
}

struct MediaLink: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var kind: LinkKind
    var addedAt: Date = Date()
    var localFile: String? = nil
}

struct LocalFile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: Int64
    let modified: Date

    var ext: String { (name as NSString).pathExtension.lowercased() }

    var sizeText: String {
        let mb = Double(size) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(size) / 1024)
    }
}

// MARK: - 全局状态

struct AppState: Codable {
    var links: [MediaLink] = []
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var state: AppState = AppState() {
        didSet { save() }
    }

    @Published var message: String = ""

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("playerbox-state.json")
    }

    static var mediaDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AppState.self, from: data) {
            state = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func addLink(title: String, url: String) -> MediaLink {
        var raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? LinkDetector.suggestTitle(for: raw)
            : title.trimmingCharacters(in: .whitespaces)
        let link = MediaLink(title: name, url: raw, kind: LinkDetector.detect(raw))
        state.links.insert(link, at: 0)
        return link
    }

    func delete(_ link: MediaLink) {
        state.links.removeAll { $0.id == link.id }
    }

    func attach(localFile: String, to linkID: UUID) {
        guard let idx = state.links.firstIndex(where: { $0.id == linkID }) else { return }
        state.links[idx].localFile = localFile
    }

    func localURL(for link: MediaLink) -> URL? {
        guard let name = link.localFile, !name.isEmpty else { return nil }
        let url = Store.mediaDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func files() -> [LocalFile] {
        let fm = FileManager.default
        let url = Store.mediaDir
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        return names.compactMap { name -> LocalFile? in
            guard !name.hasPrefix(".") else { return nil }
            let full = url.appendingPathComponent(name)
            let attrs = try? fm.attributesOfItem(atPath: full.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attrs?[.modificationDate] as? Date) ?? Date()
            return LocalFile(name: name, size: size, modified: modified)
        }
        .sorted { $0.modified > $1.modified }
    }

    func deleteFile(_ file: LocalFile) {
        let full = Store.mediaDir.appendingPathComponent(file.name)
        try? FileManager.default.removeItem(at: full)
        for i in state.links.indices where state.links[i].localFile == file.name {
            state.links[i].localFile = nil
        }
    }
}

// MARK: - 链接类型识别

enum LinkDetector {
    static let fileExtensions = ["mp4", "mov", "m4v", "ts", "webm", "mkv", "avi", "flv",
                                "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"]

    static func detect(_ urlString: String) -> LinkKind {
        let lower = urlString.lowercased()
        if lower.contains(".m3u8") || lower.hasPrefix("m3u8") { return .hls }
        for ext in fileExtensions where lower.contains("." + ext) { return .file }
        return .page
    }

    static func fileExtension(_ urlString: String) -> String? {
        guard var path = URL(string: urlString)?.path.lowercased() else { return nil }
        if let q = path.firstIndex(of: "?") { path = String(path[path.startIndex..<q]) }
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? nil : ext
    }

    static func suggestTitle(for urlString: String) -> String {
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            return host
        }
        return "未命名链接"
    }

    /// 内置解码器能否直接播
    static func nativePlayable(_ ext: String?) -> Bool {
        guard let ext = ext else { return false }
        return ["mp4", "mov", "m4v", "ts", "mp3", "m4a", "aac", "wav", "flac", "opus"].contains(ext)
    }
}
