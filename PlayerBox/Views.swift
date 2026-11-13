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
            SettingsView()
                .tabItem { Label("设置", systemImage: "gear") }
        }
        .tint(Color(red: 0, green: 0.52, blue: 0.6))
    }
}

// MARK: - 链接页

struct LinksView: View {
    @ObservedObject var store: Store
    @ObservedObject private var thumbs = ThumbnailCenter.shared
    @ObservedObject private var settings = SettingsStore.shared
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
            .navigationTitle(navTitle)
            .scrollIndicators(settings.value.showScrollIndicators ? .visible : .hidden)
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

    private var navTitle: String {
        settings.value.showCountInTitle ? "播放链接（\(store.state.links.count)）" : "播放链接"
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
        if settings.value.showPreview {
            let key = ThumbnailStore.key(forRemote: link.url,
                                         percent: settings.value.previewPercent,
                                         preferCover: settings.value.preferEmbeddedCover)
            if let image = thumbs.image(key: key) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: settings.value.thumbnailFill ? .fill : .fit)
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                placeholder(for: link)
            }
        } else {
            placeholder(for: link)
        }
    }

    private func placeholder(for link: MediaLink) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 64, height: 40)
            .overlay(
                Image(systemName: link.kind.icon)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
            )
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

// MARK: - 播放器画面（无系统控制条）

final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - 播放页

final class PlayerUIBus: ObservableObject {
    var scrubbing = false
}

struct PlayerScreen: View {
    let target: PlayTarget
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vlc = VLCController()
    @StateObject private var bus = PlayerUIBus()
    @ObservedObject private var settings = SettingsStore.shared

    @State private var player: AVPlayer? = nil
    @State private var useWeb = false
    @State private var useVLC = false
    @State private var errorText = ""
    @State private var isReady = false
    @State private var speed: Float = 1
    @State private var isMuted = false
    @State private var isLooping = false
    @State private var toast = ""
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var scrubValue: Double = 0
    @State private var timeObserver: Any? = nil
    @State private var cancellable: AnyCancellable? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoArea

            if isBuffering {
                VStack(spacing: 10) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text("缓冲中…").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            if useVLC && !vlc.stateText.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text(vlc.stateText).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if !errorText.isEmpty { errorBanner }
                bottomBar
            }
            .padding(.top, 6)

            if !toast.isEmpty {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.65), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 190)
            }
        }
        .onAppear { prepare() }
        .onDisappear { teardown() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            guard isLooping, let player = player else { return }
            player.seek(to: .zero)
            player.play()
        }
    }

    // MARK: 画面

    private var videoArea: some View {
        Group {
            if useWeb {
                WebView(urlString: target.remote?.absoluteString ?? "")
            } else if useVLC {
                VLCVideoSurface(player: vlc.player)
            } else if let player = player {
                PlayerLayerView(player: player)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if settings.value.doubleTapToggle { togglePlayback() }
        }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                guard settings.value.swipeSeek else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                jump(dx > 0 ? 15 : -15)
                flash(dx > 0 ? "快进 15 秒" : "快退 15 秒")
            }
        )
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { closePlayer() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            Text(displayTitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if let file = target.direct {
                ShareLink(item: file) {
                    topIcon("square.and.arrow.up")
                }
            } else if let remote = target.remote {
                ShareLink(item: remote) {
                    topIcon("square.and.arrow.up")
                }
            }

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button(speedText(Float(value))) { setSpeed(Float(value)) }
                }
            } label: {
                Text(speedText(speed))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.14), in: Circle())
            }

            Menu {
                Toggle("循环播放", isOn: $isLooping)
                Button("复制链接") { copyLink() }
                Button("截图保存到本地") { captureScreenshot() }
                if !errorText.isEmpty && !useWeb {
                    if useVLC {
                        Button("用网页播") { switchToWeb() }
                    } else if target.kind != .page {
                        Button("用 VLC 内核") { switchToVLC() }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .top)
        )
    }

    private func topIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(timeText(displayCurrent))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)

                Slider(value: Binding(
                    get: { bus.scrubbing ? scrubValue : displayCurrent },
                    set: { scrubValue = $0 }
                ), in: 0...max(displayDuration, 1), onEditingChanged: { editing in
                    if editing {
                        scrubValue = displayCurrent
                        bus.scrubbing = true
                    } else {
                        bus.scrubbing = false
                        seek(scrubValue)
                    }
                })
                .tint(.white)

                Text(timeText(displayDuration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 42) {
                Button { jump(-15) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "gobackward.15").font(.system(size: 19))
                        Text("-15s").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
                }

                Button { togglePlayback() } label: {
                    Image(systemName: playingIcon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                }

                Button { jump(15) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "goforward.15").font(.system(size: 19))
                        Text("+15s").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
                }
            }

            HStack(spacing: 22) {
                Button { toggleMute() } label: {
                    bottomLabel(isMuted ? "静音" : "有声", icon: isMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .disabled(useVLC)
                .opacity(useVLC ? 0.3 : 1)

                Button { isLooping.toggle() } label: {
                    bottomLabel(isLooping ? "循环开" : "循环关", icon: "repeat")
                }

                Button { jump(-30) } label: {
                    bottomLabel("退 30s", icon: "backward.end")
                }

                Button { jump(30) } label: {
                    bottomLabel("进 30s", icon: "forward.end")
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.62)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func bottomLabel(_ text: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 15))
            Text(text).font(.system(size: 9))
        }
        .foregroundStyle(.white.opacity(0.78))
        .frame(minWidth: 44, minHeight: 40)
        .contentShape(Rectangle())
    }

    private var errorBanner: some View {
        Text(errorText)
            .font(.caption)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    // MARK: 状态

    private var displayTitle: String {
        if !target.title.isEmpty { return target.title }
        if let remote = target.remote { return remote.lastPathComponent }
        if let direct = target.direct { return direct.lastPathComponent }
        return "播放"
    }

    private var displayCurrent: Double { useVLC ? vlc.currentSeconds : current }
    private var displayDuration: Double { useVLC ? vlc.durationSeconds : duration }

    private var playingIcon: String {
        if useVLC { return vlc.isPlaying ? "pause.fill" : "play.fill" }
        return player?.timeControlStatus == .playing ? "pause.fill" : "play.fill"
    }

    private var isBuffering: Bool {
        guard !useWeb, !useVLC, player != nil, errorText.isEmpty else { return false }
        return !isReady
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func speedText(_ value: Float) -> String {
        if value == Float(Int(value)) { return "\(Int(value))x" }
        return String(format: "%.2fx", value)
    }

    // MARK: 生命周期

    private func prepare() {
        speed = Float(settings.value.defaultSpeed)
        isLooping = settings.value.loopPlayback
        activateAudioSession()

        if settings.value.keepAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        if target.kind == .page && target.direct == nil && target.remote != nil {
            useWeb = true
            return
        }

        guard let url = target.direct ?? target.remote else {
            errorText = "这条链接没有可播放的地址"
            return
        }

        let mode = settings.value.engineMode
        let ext = url.pathExtension.lowercased()

        if mode == "vlc", target.kind != .page {
            startVLC(url)
            return
        }

        if target.kind == .file, !ext.isEmpty, !LinkDetector.nativePlayable(ext), mode == "auto" {
            startVLC(url)
            return
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = settings.value.bufferSeconds
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.defaultRate = speed
        player = newPlayer
        newPlayer.play()

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !bus.scrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite, seconds >= 0 { current = seconds }
        }

        cancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    isReady = true
                    Task { @MainActor in
                        if let loaded = try? await item.asset.load(.duration) {
                            let seconds = CMTimeGetSeconds(loaded)
                            if seconds.isFinite, seconds > 0 { duration = seconds }
                        }
                    }
                case .failed:
                    errorText = item.error?.localizedDescription ?? "播放失败：可能格式不受支持或链接已失效"
                default:
                    break
                }
            }
    }

    private func teardown() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        cancellable = nil
        player?.pause()
        player = nil
        vlc.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func closePlayer() {
        teardown()
        dismiss()
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

    private func togglePlayback() {
        if useVLC { vlc.toggle(); return }
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
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

    private func seek(_ seconds: Double) {
        if useVLC { vlc.seek(toSeconds: seconds); return }
        guard let player = player else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func jump(_ seconds: Double) {
        seek(displayCurrent + seconds)
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

    private func captureScreenshot() {
        guard let url = target.direct ?? target.remote else {
            flash("截图失败：没有可用地址")
            return
        }
        let seconds = max(0, displayCurrent)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        Task { @MainActor in
            guard let cg = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image,
                  let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) else {
                flash("截图失败：当前画面无法提取")
                return
            }
            let name = "shot-\(Int(Date().timeIntervalSince1970)).jpg"
            let url = Store.mediaDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                flash("截图已保存到「本地文件」")
            } catch {
                flash("截图保存失败")
            }
        }
    }

    private func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toast == text { toast = "" }
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let quiet = !settings.value.backgroundAudio
        try? session.setCategory(quiet ? .ambient : .playback, mode: .moviePlayback, options: [])
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
    @ObservedObject private var settings = SettingsStore.shared
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
                                Text(subtitle(file))
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
            .navigationTitle(navTitle(files))
            .scrollIndicators(settings.value.showScrollIndicators ? .visible : .hidden)
            .task(id: files.count) { thumbs.ensureLocal(files) }
            .fullScreenCover(item: $playTarget) { target in
                PlayerScreen(target: target)
            }
        }
    }

    private func navTitle(_ files: [LocalFile]) -> String {
        settings.value.showCountInTitle ? "本地文件（\(files.count)）" : "本地文件"
    }

    private func subtitle(_ file: LocalFile) -> String {
        if settings.value.showFileTime {
            return "\(file.sizeText) · \(file.modified.formatted(date: .numeric, time: .shortened))"
        }
        return file.sizeText
    }

    @ViewBuilder
    private func localThumb(for file: LocalFile) -> some View {
        if settings.value.showPreview {
            let key = ThumbnailStore.key(forLocal: file.name,
                                         percent: settings.value.previewPercent,
                                         preferCover: settings.value.preferEmbeddedCover)
            if let image = thumbs.image(key: key) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: settings.value.thumbnailFill ? .fill : .fit)
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                localPlaceholder()
            }
        } else {
            localPlaceholder()
        }
    }

    private func localPlaceholder() -> some View {
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
