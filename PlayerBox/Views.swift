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

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationSupport.mask
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
            .onChange(of: settings.value.previewPercent) { _, _ in
                thumbs.ensureRemote(store.state.links)
            }
            .onChange(of: settings.value.preferEmbeddedCover) { _, _ in
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

// MARK: - 播放器画面

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
        uiView.playerLayer.videoGravity = .resizeAspect
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

    @State private var controlsVisible = true
    @State private var controlsLocked = false
    @State private var dragMode: DragMode = .none
    @State private var dragStartSeconds: Double = 0
    @State private var dragStartValue: Float = 0
    @State private var dragSeekTarget: Double = 0

    @State private var previewImage: UIImage? = nil
    @State private var previewGenerator: AVAssetImageGenerator? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var previewRequested: Double = -1

    private let seekSecondsPerScreen: Double = 300

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoArea

            if showStartupSpinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if useVLC && vlc.stateText.contains("失败") {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(vlc.stateText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            if dragMode == .seek && !useWeb {
                VStack {
                    Spacer()
                    seekPreview
                        .padding(.bottom, 168)
                }
                .allowsHitTesting(false)
            }

            if controlsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if !errorText.isEmpty { errorBanner }
                    bottomBar
                }
            }

            if controlsLocked {
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            controlsLocked = false
                            controlsVisible = true
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }

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
        .statusBarHidden(true)
        .onAppear { prepare() }
        .onDisappear { teardown() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            guard isLooping, let player = player else { return }
            player.seek(to: .zero)
            player.play()
        }
    }

    // MARK: 画面与手势

    private var videoArea: some View {
        GeometryReader { geo in
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
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(tapGesture)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in handleDragChanged(value, size: geo.size) }
                    .onEnded { value in handleDragEnded(value) }
            )
        }
        .ignoresSafeArea()
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            guard !controlsLocked else { return }
            if settings.value.doubleTapToggle { togglePlayback() }
        }
        .exclusively(before: TapGesture(count: 1).onEnded {
            guard settings.value.singleTapToggle, !controlsLocked else { return }
            controlsVisible.toggle()
        })
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        if dragMode == .none {
            let dx = value.translation.width
            let dy = value.translation.height
            guard max(abs(dx), abs(dy)) > 10 else { return }

            if abs(dx) > abs(dy) {
                guard settings.value.swipeSeek else { return }
                dragMode = .seek
                dragStartSeconds = displayCurrent
                dragSeekTarget = displayCurrent
                previewRequested = -1
                requestPreview(at: displayCurrent)
            } else if value.startLocation.x <= size.width / 2 {
                guard settings.value.brightnessSwipe else { return }
                dragMode = .brightness
                dragStartValue = Float(UIScreen.main.brightness)
            } else {
                guard settings.value.volumeSwipe else { return }
                dragMode = .volume
                dragStartValue = VolumeControl.shared.current()
            }
        }

        switch dragMode {
        case .seek:
            let delta = Double(value.translation.width / max(size.width, 1)) * seekSecondsPerScreen
            let maxTime = displayDuration > 0 ? displayDuration : max(dragStartSeconds + 3600, 1)
            let next = min(max(dragStartSeconds + delta, 0), maxTime)
            dragSeekTarget = next
            if abs(next - previewRequested) > 0.5 {
                previewRequested = next
                requestPreview(at: next)
            }

        case .brightness:
            let level = min(max(dragStartValue + Float(-value.translation.height / max(size.height, 1)), 0), 1)
            UIScreen.main.brightness = CGFloat(level)

        case .volume:
            let level = min(max(dragStartValue + Float(-value.translation.height / max(size.height, 1)), 0), 1)
            VolumeControl.shared.set(level)

        case .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        if dragMode == .seek {
            seek(dragSeekTarget)
            previewTask?.cancel()
            dragMode = .none
        } else {
            dragMode = .none
        }
    }

    private func requestPreview(at seconds: Double) {
        guard let generator = previewGenerator else { return }
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                guard !Task.isCancelled else { return }
                previewImage = UIImage(cgImage: cg)
            } else if previewImage == nil {
                previewImage = cachedSourceImage()
            }
        }
    }

    private func cachedSourceImage() -> UIImage? {
        let percent = settings.value.previewPercent
        let cover = settings.value.preferEmbeddedCover

        if let name = target.direct?.lastPathComponent {
            let key = ThumbnailStore.key(forLocal: name, percent: percent, preferCover: cover)
            if let image = ThumbnailCenter.shared.image(key: key) { return image }
        }
        if let remote = target.remote?.absoluteString {
            let key = ThumbnailStore.key(forRemote: remote, percent: percent, preferCover: cover)
            if let image = ThumbnailCenter.shared.image(key: key) { return image }
        }
        return nil
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack(spacing: 24) {
            Button { closePlayer() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            Button { OrientationSupport.toggle() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            Button { isLooping.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 20))
                    .foregroundStyle(isLooping ? Color(red: 0.35, green: 0.85, blue: 0.4) : Color.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            Text(displayTitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 6)

            Spacer(minLength: 8)

            Button { captureScreenshot() } label: {
                Image(systemName: "camera")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button(speedText(Float(value))) { setSpeed(Float(value)) }
                }
            } label: {
                Text(speedText(speed))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.16), in: Circle())
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
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 26) {
                Spacer()
                Button { toggleMute() } label: {
                    Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(useVLC ? 0.3 : 0.85))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .disabled(useVLC)

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
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 10) {
                Text(timeText(barValue))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .leading)

                progressBar

                Text(timeText(displayDuration))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack {
                Button {
                    controlsLocked = true
                    controlsVisible = false
                } label: {
                    Image(systemName: "lock.open")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }

                Spacer()

                Button { jump(-15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 48)
                        .contentShape(Rectangle())
                }

                Spacer(minLength: 10)

                Button { togglePlayback() } label: {
                    Image(systemName: playingIcon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 48)
                        .contentShape(Rectangle())
                }

                Spacer(minLength: 10)

                Button { jump(15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 48)
                        .contentShape(Rectangle())
                }

                Spacer()

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
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let progress = displayDuration > 0 ? min(max(barValue / displayDuration, 0), 1) : 0
            let seeking = dragMode == .seek
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(seeking ? 0.35 : 0.22))
                    .frame(height: seeking ? 5 : 3)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, geo.size.width * progress), height: seeking ? 5 : 3)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(Color.white)
                    .frame(width: seeking ? 13 : 8, height: seeking ? 13 : 8)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: geo.size.width * progress - (seeking ? 6.5 : 4))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .animation(.easeOut(duration: 0.16), value: seeking)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        bus.scrubbing = true
                        let ratio = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                        scrubValue = Double(ratio) * max(displayDuration, 1)
                    }
                    .onEnded { _ in
                        bus.scrubbing = false
                        seek(scrubValue)
                    }
            )
        }
        .frame(height: 22)
    }

    private var seekPreview: some View {
        VStack(spacing: 6) {
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 172, height: 97)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 172, height: 97)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.35))
                    )
            }

            Text(timeText(dragSeekTarget))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
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

    private var barValue: Double {
        if dragMode == .seek { return dragSeekTarget }
        return bus.scrubbing ? scrubValue : displayCurrent
    }

    private var displayCurrent: Double { useVLC ? vlc.currentSeconds : current }
    private var displayDuration: Double { useVLC ? vlc.durationSeconds : duration }

    private var playingIcon: String {
        if useVLC { return vlc.isPlaying ? "pause.fill" : "play.fill" }
        return player?.timeControlStatus == .playing ? "pause.fill" : "play.fill"
    }

    private var showStartupSpinner: Bool {
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
        VolumeControl.shared.attach()
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

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        previewGenerator = generator

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
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !bus.scrubbing, dragMode != .seek else { return }
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
        previewTask?.cancel()
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
            let dest = Store.mediaDir.appendingPathComponent(name)
            do {
                try data.write(to: dest, options: .atomic)
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
            .onChange(of: settings.value.previewPercent) { _, _ in
                thumbs.ensureLocal(files)
            }
            .onChange(of: settings.value.preferEmbeddedCover) { _, _ in
                thumbs.ensureLocal(files)
            }
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
