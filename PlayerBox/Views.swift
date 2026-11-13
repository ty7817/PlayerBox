import SwiftUI
import AVKit
import WebKit
import Combine
import UIKit

// MARK: - App

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            DownloadCenter.shared.backgroundCompletion = completionHandler
        }
    }
}

@main
struct PlayerBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        TabView {
            LinksView(store: store)
                .tabItem { Label("链接", systemImage: "list.bullet.rectangle") }
            DownloadsView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            FilesView(store: store)
                .tabItem { Label("本地", systemImage: "folder") }
        }
        .tint(Color(red: 0, green: 0.52, blue: 0.6))
    }
}

// MARK: - 链接页

struct LinksView: View {
    @ObservedObject var store: Store
    @ObservedObject private var thumbs = ThumbnailCenter.shared
    @State private var showAdd = false
    @State private var playing: PlayTarget? = nil
    @State private var toast = ""

    var body: some View {
        NavigationStack {
            List {
                if store.state.links.isEmpty {
                    Section {
                        Text("还没有链接。点右上角 + 添加，支持 m3u8 直播流、mp4 直链、网页播放页。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(store.state.links) { link in
                    Button {
                        playing = PlayTarget(title: link.title,
                                             remote: URL(string: link.url),
                                             direct: store.localURL(for: link),
                                             kind: link.kind)
                    } label: {
                        row(link)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(link)
                        } label: { Label("删除", systemImage: "trash") }
                        Button {
                            download(link)
                        } label: { Label("下载", systemImage: "arrow.down") }
                            .tint(Color(red: 0, green: 0.52, blue: 0.6))
                    }
                }
            }
            .navigationTitle("播放链接")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task(id: store.state.links.count) {
                thumbs.ensureRemote(store.state.links)
            }
            .sheet(isPresented: $showAdd) { AddLinkView(store: store) }
            .fullScreenCover(item: $playing) { target in
                PlayerScreen(target: target)
            }
            .alert("提示", isPresented: Binding(
                get: { !toast.isEmpty },
                set: { if !$0 { toast = "" } }
            )) {
                Button("好") { toast = "" }
            } message: { Text(toast) }
        }
    }

    private func row(_ link: MediaLink) -> some View {
        HStack(spacing: 12) {
            thumb(for: link)
            VStack(alignment: .leading, spacing: 3) {
                Text(link.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(link.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(link.kind.label)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    if link.localFile != nil {
                        Text("已下载")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
                    }
                }
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumb(for link: MediaLink) -> some View {
        let key = ThumbnailStore.key(forRemote: link.url)
        if let image = thumbs.image(key: key) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 64, height: 40)
                .overlay(
                    Image(systemName: link.kind.icon)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
                )
        }
    }

    private func download(_ link: MediaLink) {
        guard let remote = URL(string: link.url) else {
            toast = "链接格式不正确"
            return
        }
        let base = sanitizedName(link.title)
        if link.kind == .hls {
            DownloadCenter.shared.startStreamDownload(title: link.title, playlistURL: remote,
                                                     localName: base + ".ts", linkID: link.id)
            toast = "已开始下载 HLS 流（需保持 App 在前台直到完成）"
        } else {
            let ext = LinkDetector.fileExtension(link.url) ?? "mp4"
            DownloadCenter.shared.startFileDownload(title: link.title, remoteURL: remote,
                                                   localName: base + "." + ext, linkID: link.id)
            toast = "已加入下载列表"
        }
    }

    private func sanitizedName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title.components(separatedBy: bad).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "video-\(Int(Date().timeIntervalSince1970))" : trimmed
    }
}

struct AddLinkView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("链接信息") {
                    TextField("名称（可留空）", text: $title)
                    TextField("https://…/index.m3u8", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("添加") {
                        store.addLink(title: title, url: url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("添加链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - 播放目标

struct PlayTarget: Identifiable {
    let id = UUID()
    let title: String
    let remote: URL?
    let direct: URL?
    let kind: LinkKind
}

// MARK: - 播放页

struct PlayerScreen: View {
    let target: PlayTarget
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vlc = VLCController()

    @State private var player: AVPlayer? = nil
    @State private var useWeb = false
    @State private var useVLC = false
    @State private var errorText = ""
    @State private var isReady = false
    @State private var speed: Float = 1
    @State private var isMuted = false
    @State private var isLooping = false
    @State private var showShare = false
    @State private var toast = ""
    @State private var cancellable: AnyCancellable? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            overlay
        }
        .onAppear { prepare() }
        .onDisappear { player?.pause(); vlc.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            guard isLooping, let player = player else { return }
            player.seek(to: .zero)
            player.play()
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    @ViewBuilder
    private var content: some View {
        if useWeb {
            WebView(urlString: target.remote?.absoluteString ?? "")
                .ignoresSafeArea()
        } else if useVLC {
            VLCVideoSurface(player: vlc.player)
                .ignoresSafeArea()
        } else if let player = player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
        } else {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.3)
        }
    }

    private var overlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    player?.pause()
                    vlc.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if let file = target.direct {
                    ShareLink(item: file) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                if !errorText.isEmpty && !useWeb {
                    Button(useVLC ? "用网页播" : "用 VLC 内核") {
                        if useVLC { switchToWeb() } else { switchToVLC() }
                    }
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if useVLC && !vlc.stateText.isEmpty {
                Text(vlc.stateText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }

            if !useVLC && !isReady && player != nil && !useWeb {
                Text("缓冲中…")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
            }

            Spacer()

            if (player != nil || useVLC) && !useWeb {
                actionBar
            }

            if !toast.isEmpty {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if useVLC {
                Button { vlc.toggle() } label: {
                    pill(vlc.isPlaying ? "暂停" : "播放", icon: vlc.isPlaying ? "pause.fill" : "play.fill")
                }
            }

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button {
                        setSpeed(Float(value))
                    } label: {
                        Text(speedText(Float(value)))
                    }
                }
            } label: {
                pill(speedText(speed), icon: "speedometer")
            }

            Button { jump(-15) } label: { pill("-15s", icon: "gobackward.15") }
            Button { jump(15) } label: { pill("+15s", icon: "goforward.15") }

            if !useVLC {
                Button { toggleMute() } label: {
                    pill(isMuted ? "静音" : "有声", icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
            }

            Menu {
                Toggle("循环播放", isOn: $isLooping)
                Button("复制链接") { copyLink() }
                Button("分享 / 用外部播放器打开") { showShare = true }
            } label: {
                pill("更多", icon: "ellipsis")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 18)
    }

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    private var shareItems: [Any] {
        if let file = target.direct { return [file] }
        if let remote = target.remote { return [remote] }
        return []
    }

    private func prepare() {
        activateAudioSession()

        if target.kind == .page && target.direct == nil {
            useWeb = true
            return
        }

        guard let url = target.direct ?? target.remote else {
            errorText = "这条链接没有可播放的地址"
            return
        }

        let ext = url.pathExtension.lowercased()
        if target.kind == .file, !ext.isEmpty, !LinkDetector.nativePlayable(ext) {
            startVLC(url)
            return
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.defaultRate = speed
        player = newPlayer
        newPlayer.play()

        cancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    isReady = true
                case .failed:
                    errorText = item.error?.localizedDescription ?? "播放失败：可能是格式不受支持或链接已失效"
                default:
                    break
                }
            }
    }

    private func startVLC(_ url: URL) {
        player?.pause()
        player = nil
        errorText = ""
        useVLC = true
        vlc.load(url)
        vlc.play()
        vlc.setRate(speed)
    }

    private func switchToVLC() {
        guard let url = target.direct ?? target.remote else { return }
        startVLC(url)
    }

    private func switchToWeb() {
        player?.pause()
        vlc.pause()
        useVLC = false
        useWeb = true
        errorText = ""
    }

    private func setSpeed(_ value: Float) {
        speed = value
        if useVLC { vlc.setRate(value); return }
        guard let player = player else { return }
        player.defaultRate = value
        if player.timeControlStatus == .playing {
            player.rate = value
        }
    }

    private func jump(_ seconds: Double) {
        if useVLC { vlc.jump(seconds); return }
        guard let player = player else { return }
        var target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        if CMTimeCompare(target, .zero) < 0 { target = .zero }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func copyLink() {
        let text = target.remote?.absoluteString ?? target.direct?.path ?? ""
        UIPasteboard.general.string = text
        flash("链接已复制")
    }

    private func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toast == text { toast = "" }
        }
    }

    private func speedText(_ value: Float) -> String {
        if value == Float(Int(value)) { return "\(Int(value))x" }
        return String(format: "%.2fx", value)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct WebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil, let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - 下载页

struct DownloadsView: View {
    @ObservedObject private var center = DownloadCenter.shared

    var body: some View {
        NavigationStack {
            List {
                if center.items.isEmpty {
                    ContentUnavailableView("暂无下载", systemImage: "arrow.down.circle",
                                           description: Text("在链接页左滑选「下载」"))
                }
                ForEach(center.items) { item in
                    DownloadRow(item: item)
                        .swipeActions(edge: .trailing) {
                            if !item.isFinished && !item.isFailed {
                                Button(role: .destructive) {
                                    center.cancel(item)
                                } label: { Label("取消", systemImage: "xmark") }
                            }
                        }
                }
            }
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清理") { center.clearFinished() }
                        .font(.footnote)
                }
            }
        }
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                Text(item.statusText)
                    .font(.caption2)
                    .foregroundStyle(item.isFailed ? Color.red : Color.secondary)
            }
            if !item.isFinished && !item.isFailed {
                ProgressView(value: item.progress)
            }
            if !item.detail.isEmpty {
                Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 本地文件

struct FilesView: View {
    @ObservedObject var store: Store
    @ObservedObject private var thumbs = ThumbnailCenter.shared
    @State private var playTarget: PlayTarget? = nil

    var body: some View {
        let files = store.files()
        NavigationStack {
            List {
                if files.isEmpty {
                    ContentUnavailableView("暂无文件", systemImage: "folder",
                                           description: Text("下载完成的视频会出现在这里，也会同步到「文件」App"))
                }
                ForEach(files) { file in
                    Button {
                        let url = Store.mediaDir.appendingPathComponent(file.name)
                        playTarget = PlayTarget(title: file.name, remote: nil, direct: url, kind: .file)
                    } label: {
                        HStack(spacing: 12) {
                            localThumb(for: file)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Text("\(file.sizeText) · \(file.modified.formatted(date: .numeric, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: Store.mediaDir.appendingPathComponent(file.name)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteFile(file)
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("本地文件")
            .task(id: files.count) { thumbs.ensureLocal(files) }
            .fullScreenCover(item: $playTarget) { target in
                PlayerScreen(target: target)
            }
        }
    }

    @ViewBuilder
    private func localThumb(for file: LocalFile) -> some View {
        let key = ThumbnailStore.key(forLocal: file.name)
        if let image = thumbs.image(key: key) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 64, height: 40)
                .overlay(
                    Image(systemName: "film")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
                )
        }
    }
}
