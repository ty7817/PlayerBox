import Foundation
import Combine

// MARK: - 下载项

final class DownloadItem: Identifiable, ObservableObject {
    let id = UUID()
    let title: String
    let remoteURL: URL
    let linkID: UUID?
    var localName: String

    @Published var progress: Double = 0
    @Published var statusText: String = "等待中"
    @Published var isFinished: Bool = false
    @Published var isFailed: Bool = false
    @Published var detail: String = ""

    init(title: String, remoteURL: URL, localName: String, linkID: UUID?) {
        self.title = title
        self.remoteURL = remoteURL
        self.localName = localName
        self.linkID = linkID
    }
}

enum TransferError: LocalizedError {
    case encrypted
    case noSegments
    case badPlaylist
    case emptyFile
    case cancelled

    var errorDescription: String? {
        switch self {
        case .encrypted: return "这个 HLS 流用了 AES-128 加密，暂不支持离线下载"
        case .noSegments: return "m3u8 里没有找到分片地址"
        case .badPlaylist: return "m3u8 内容无法识别"
        case .emptyFile: return "下载回来是空文件"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - 下载中心（直链用后台队列，m3u8 用前台任务）

@MainActor
final class DownloadCenter: NSObject, ObservableObject {
    static let shared = DownloadCenter()

    @Published var items: [DownloadItem] = []
    var backgroundCompletion: (() -> Void)?

    private var sessionTasks: [Int: URLSessionDownloadTask] = [:]
    private var streamTasks: [UUID: Task<Void, Never>] = [:]

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.ty7817.playerbox.download")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        cfg.timeoutIntervalForResource = 3600
        return URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue.main)
    }()

    // MARK: 直链下载

    func startFileDownload(title: String, remoteURL: URL, localName: String, linkID: UUID?) {
        let item = DownloadItem(title: title, remoteURL: remoteURL, localName: localName, linkID: linkID)
        item.statusText = "连接中…"
        items.insert(item, at: 0)
        let task = session.downloadTask(with: remoteURL)
        sessionTasks[task.taskIdentifier] = task
        task.resume()
    }

    // MARK: m3u8 下载

    func startStreamDownload(title: String, playlistURL: URL, localName: String, linkID: UUID?) {
        let item = DownloadItem(title: title, remoteURL: playlistURL, localName: localName, linkID: linkID)
        item.statusText = "解析分片…"
        items.insert(item, at: 0)
        let dest = Store.mediaDir.appendingPathComponent(localName)
        let task = Task { [weak self] in
            do {
                try await M3U8Downloader.download(playlistURL: playlistURL, destURL: dest) { value in
                    Task { @MainActor in
                        item.progress = value
                        item.statusText = "下载中 \(Int(value * 100))%"
                    }
                }
                await MainActor.run {
                    item.progress = 1
                    item.statusText = "已完成"
                    item.isFinished = true
                    item.detail = localName
                    self?.linkLocalFile(name: localName, linkID: linkID)
                }
            } catch {
                await MainActor.run {
                    item.isFailed = true
                    item.statusText = "失败"
                    item.detail = error.localizedDescription
                    try? FileManager.default.removeItem(at: dest)
                }
            }
            await MainActor.run { self?.streamTasks[item.id] = nil }
        }
        streamTasks[item.id] = task
    }

    func cancel(_ item: DownloadItem) {
        if let stream = streamTasks[item.id] {
            stream.cancel()
            streamTasks[item.id] = nil
            item.statusText = "已取消"
            item.isFailed = true
            try? FileManager.default.removeItem(at: Store.mediaDir.appendingPathComponent(item.localName))
            return
        }
        for (id, task) in sessionTasks where task.originalRequest?.url == item.remoteURL {
            task.cancel()
            sessionTasks[id] = nil
        }
        item.statusText = "已取消"
        item.isFailed = true
    }

    func clearFinished() {
        items.removeAll { $0.isFinished || $0.isFailed }
    }

    private func linkLocalFile(name: String, linkID: UUID?) {
        guard let linkID = linkID else { return }
        Store.shared.attach(localFile: name, to: linkID)
    }
}

// MARK: - 后台下载回调

extension DownloadCenter: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let identifier = downloadTask.taskIdentifier
        let written = totalBytesWritten
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            guard let item = DownloadCenter.shared.item(forTask: identifier) else { return }
            if expected > 0 {
                item.progress = Double(written) / Double(expected)
            }
            item.statusText = "下载中 \(Int(item.progress * 100))%"
            item.detail = String(format: "%.1f / %.1f MB", Double(written) / 1_048_576, Double(max(expected, 0)) / 1_048_576)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let item = DownloadCenter.shared.item(forTask: identifier) else { return }
            let dest = Store.mediaDir.appendingPathComponent(item.localName)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: location, to: dest)
                item.progress = 1
                item.statusText = "已完成"
                item.isFinished = true
                item.detail = item.localName
                Store.shared.attach(localFile: item.localName, to: item.linkID)
            } catch {
                item.isFailed = true
                item.statusText = "保存失败"
                item.detail = error.localizedDescription
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let identifier = task.taskIdentifier
        let message = error.localizedDescription
        Task { @MainActor in
            DownloadCenter.shared.markFailed(taskID: identifier, message: message)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadCenter.shared.backgroundCompletion?()
            DownloadCenter.shared.backgroundCompletion = nil
        }
    }
}

extension DownloadCenter {
    func item(forTask id: Int) -> DownloadItem? {
        items.first { sessionTasks[$0.id] == nil && false }
            ?? items.first { item in
                sessionTasks.contains { $0.key == id && $0.value.originalRequest?.url == item.remoteURL }
            }
    }

    func markFailed(taskID: Int, message: String) {
        guard let item = item(forTask: taskID) else { return }
        if item.isFinished { return }
        item.isFailed = true
        item.statusText = "失败"
        item.detail = message
        sessionTasks[taskID] = nil
    }
}

// MARK: - m3u8 下载器

enum M3U8Downloader {
    static func download(playlistURL: URL, destURL: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        var current = playlistURL
        var body = try await fetchText(current)

        if body.contains("#EXT-X-STREAM-INF") {
            guard let variant = pickVariant(body, base: current) else { throw TransferError.badPlaylist }
            current = variant
            body = try await fetchText(current)
        }

        if body.contains("#EXT-X-KEY") {
            let lines = body.split(separator: "\n")
            for line in lines where line.contains("METHOD=") {
                if !line.contains("METHOD=NONE") { throw TransferError.encrypted }
            }
        }

        var segments: [URL] = []
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let url = URL(string: line, relativeTo: current) {
                segments.append(url.absoluteURL)
            }
        }
        guard !segments.isEmpty else { throw TransferError.noSegments }

        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destURL)
        var total = 0
        do {
            for (index, seg) in segments.enumerated() {
                try Task.checkCancellation()
                let (data, _) = try await URLSession.shared.data(from: seg)
                try handle.write(contentsOf: data)
                total += data.count
                progress(Double(index + 1) / Double(segments.count))
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        if total == 0 { throw TransferError.emptyFile }
    }

    private static func fetchText(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = String(data: data, encoding: .utf8) else { throw TransferError.badPlaylist }
        return text
    }

    private static func pickVariant(_ body: String, base: URL) -> URL? {
        var best: (bandwidth: Int, url: URL)? = nil
        var pendingBandwidth = 0
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingBandwidth = 0
                if let range = line.range(of: "BANDWIDTH=") {
                    let tail = line[range.upperBound...]
                    let digits = tail.prefix { $0.isNumber }
                    pendingBandwidth = Int(digits) ?? 0
                }
            } else if !line.isEmpty && !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: base)?.absoluteURL else { continue }
                if best == nil || pendingBandwidth > best!.bandwidth {
                    best = (pendingBandwidth, url)
                }
            }
        }
        return best?.url
    }
}
