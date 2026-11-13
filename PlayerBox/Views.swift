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
            Image(systemName: link.kind.icon)
                .frame(width: 26)
                .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
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
    @State private var player: AVPlayer? = nil
    @State private var useWeb = false
    @State private var errorText = ""
    @State private var cancellable: AnyCancellable? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if useWeb {
                WebView(urlString: target.remote?.absoluteString ?? "")
                    .ignoresSafeArea()
            } else if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack(spacing: 10) {
                    Button {
                        player?.pause()
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
                        Button("用网页播") {
                            player?.pause()
                            useWeb = true
                            errorText = ""
                        }
                        .font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
            }
        }
        .onAppear { prepare() }
        .onDisappear { player?.pause() }
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
            errorText = "内置播放器不支持 .\(ext)。点右上角分享按钮，可用 VLC / nPlayer / Infuse 打开"
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        newPlayer.play()

        cancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                if status == .failed {
                    errorText = item.error?.localizedDescription ?? "播放失败：可能是格式不受支持或链接已失效"
                }
            }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }
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

// MARK: - 本地文件

struct FilesView: View {
    @ObservedObject var store: Store
    @State private var playTarget: PlayTarget? = nil

    var body: some View {
        NavigationStack {
            List {
                let files = store.files()
                if files.isEmpty {
                    ContentUnavailableView("暂无文件", systemImage: "folder",
                                           description: Text("下载完成的视频会出现在这里；也会同步到「文件」App"))
                }
                ForEach(files) { file in
                    Button {
                        let url = Store.mediaDir.appendingPathComponent(file.name)
                        playTarget = PlayTarget(title: file.name, remote: nil, direct: url, kind: .file)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "film")
                                .frame(width: 26)
                                .foregroundStyle(Color(red: 0, green: 0.52, blue: 0.6))
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
            .fullScreenCover(item: $playTarget) { target in
                PlayerScreen(target: target)
            }
        }
    }
}
