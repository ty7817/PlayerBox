import Foundation
import UIKit
import AVFoundation
import CryptoKit

// MARK: - 缩略图存放与生成

enum ThumbnailStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Thumbs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private static var mediaDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Media", isDirectory: true)
    }

    static func key(forRemote urlString: String, percent: Double, preferCover: Bool) -> String {
        digest("remote:\(urlString)|p\(Int(percent))|c\(preferCover ? 1 : 0)")
    }

    static func key(forLocal name: String, percent: Double, preferCover: Bool) -> String {
        digest("local:\(name)|p\(Int(percent))|c\(preferCover ? 1 : 0)")
    }

    private static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    static func fileURL(forKey key: String) -> URL { dir.appendingPathComponent(key) }

    static func cachedImage(key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(forKey: key)) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    static func generateRemote(urlString: String, localName: String?, isPage: Bool,
                               key: String, percent: Double, preferCover: Bool) async -> Bool {
        if cachedImage(key: key) != nil { return true }

        if let localName = localName {
            let local = mediaDir.appendingPathComponent(localName)
            if FileManager.default.fileExists(atPath: local.path),
               let image = await imageFromVideo(local, percent: percent, preferCover: preferCover) {
                return save(image, key: key)
            }
        }

        guard let url = URL(string: urlString) else { return false }

        if isPage {
            if let image = await imageFromPage(url) { return save(image, key: key) }
            return false
        }

        if let image = await imageFromVideo(url, percent: percent, preferCover: preferCover) {
            return save(image, key: key)
        }
        if let image = await imageFromPage(url) { return save(image, key: key) }
        return false
    }

    @discardableResult
    static func generateLocal(name: String, key: String, percent: Double, preferCover: Bool) async -> Bool {
        if cachedImage(key: key) != nil { return true }
        let local = mediaDir.appendingPathComponent(name)
        guard let image = await imageFromVideo(local, percent: percent, preferCover: preferCover) else { return false }
        return save(image, key: key)
    }

    // MARK: 抽帧

    private static func imageFromVideo(_ url: URL, percent: Double, preferCover: Bool) async -> UIImage? {
        let asset = AVURLAsset(url: url)

        if preferCover, let cover = await embeddedCover(asset) {
            return cover
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 405)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)

        var seconds = 1.0
        if let duration = try? await asset.load(.duration) {
            let total = CMTimeGetSeconds(duration)
            if total.isFinite, total > 0 {
                seconds = max(0.5, total * percent / 100.0)
            }
        }

        if let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
            return UIImage(cgImage: image)
        }
        if let image = try? await generator.image(at: .zero).image {
            return UIImage(cgImage: image)
        }
        return nil
    }

    private static func embeddedCover(_ asset: AVURLAsset) async -> UIImage? {
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    // MARK: 网页 og:image

    private static func imageFromPage(_ url: URL) async -> UIImage? {
        guard let imageURL = await ogImageURL(from: url) else { return nil }
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 12
        if let host = url.host {
            request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private static func ogImageURL(from url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        for chunk in html.components(separatedBy: "<meta").dropFirst() {
            let lower = chunk.lowercased()
            guard lower.contains("og:image") || lower.contains("twitter:image") else { continue }
            if let raw = attribute("content", in: chunk),
               let resolved = URL(string: raw, relativeTo: url)?.absoluteURL {
                return resolved
            }
        }
        return nil
    }

    private static func attribute(_ name: String, in text: String) -> String? {
        guard let range = text.range(of: name + "=", options: .caseInsensitive) else { return nil }
        var rest = String(text[range.upperBound...])
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = rest.first else { return nil }
        if first == "\"" || first == "'" {
            rest.removeFirst()
            guard let end = rest.firstIndex(of: first) else { return nil }
            let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let value = String(rest.prefix { !$0.isWhitespace && $0 != ">" })
        return value.isEmpty ? nil : value
    }

    // MARK: 存文件

    private static func save(_ image: UIImage, key: String) -> Bool {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return false }
        let maxSide: CGFloat = 640
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let data = scaled.jpegData(compressionQuality: 0.72) else { return false }
        do {
            try data.write(to: fileURL(forKey: key), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 缩略图调度中心

@MainActor
final class ThumbnailCenter: ObservableObject {
    static let shared = ThumbnailCenter()

    @Published var version = 0

    private var running: Set<String> = []
    private var memory: [String: UIImage] = [:]

    func image(key: String) -> UIImage? {
        if let cached = memory[key] { return cached }
        if let loaded = ThumbnailStore.cachedImage(key: key) {
            memory[key] = loaded
            return loaded
        }
        return nil
    }

    func ensureRemote(_ links: [MediaLink]) {
        let percent = SettingsStore.shared.value.previewPercent
        let preferCover = SettingsStore.shared.value.preferEmbeddedCover

        for link in links {
            let key = ThumbnailStore.key(forRemote: link.url, percent: percent, preferCover: preferCover)
            guard image(key: key) == nil, !running.contains(key) else { continue }
            running.insert(key)
            let urlString = link.url
            let localName = link.localFile
            let isPage = link.kind == .page
            Task { @MainActor in
                _ = await ThumbnailStore.generateRemote(urlString: urlString,
                                                       localName: localName,
                                                       isPage: isPage,
                                                       key: key,
                                                       percent: percent,
                                                       preferCover: preferCover)
                self.finish(key: key)
            }
        }
    }

    func ensureLocal(_ files: [LocalFile]) {
        let percent = SettingsStore.shared.value.previewPercent
        let preferCover = SettingsStore.shared.value.preferEmbeddedCover

        for file in files {
            let key = ThumbnailStore.key(forLocal: file.name, percent: percent, preferCover: preferCover)
            guard image(key: key) == nil, !running.contains(key) else { continue }
            running.insert(key)
            let name = file.name
            Task { @MainActor in
                _ = await ThumbnailStore.generateLocal(name: name, key: key,
                                                       percent: percent, preferCover: preferCover)
                self.finish(key: key)
            }
        }
    }

    private func finish(key: String) {
        running.remove(key)
        if let loaded = ThumbnailStore.cachedImage(key: key) {
            memory[key] = loaded
        }
        version += 1
    }

    func refresh(key: String) {
        memory[key] = nil
        version += 1
    }

    func clearCache() {
        memory.removeAll()
        running.removeAll()
        version += 1
    }
}
