import SwiftUI

// MARK: - 设置主页

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PlaybackSettingsView(settings: settings)
                    } label: {
                        iconRow("播放设置", icon: "play.rectangle.fill", color: .red)
                    }
                    NavigationLink {
                        InterfaceSettingsView(settings: settings)
                    } label: {
                        iconRow("界面偏好", icon: "rectangle.on.rectangle", color: .yellow)
                    }
                    NavigationLink {
                        GestureSettingsView(settings: settings)
                    } label: {
                        iconRow("播放手势", icon: "hand.tap.fill", color: .blue)
                    }
                    NavigationLink {
                        MediaControlSettingsView(settings: settings)
                    } label: {
                        iconRow("媒体控制", icon: "play.circle.fill", color: .green)
                    }
                }

                Section("音视频") {
                    NavigationLink {
                        VideoSettingsView(settings: settings)
                    } label: {
                        iconRow("视频设置", icon: "video.fill", color: .blue)
                    }
                    NavigationLink {
                        AudioSettingsView(settings: settings)
                    } label: {
                        iconRow("音频设置", icon: "headphones", color: .indigo)
                    }
                }

                Section {
                    NavigationLink {
                        CacheManagerView()
                    } label: {
                        iconRow("缓存管理", icon: "trash.fill", color: .orange)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        iconRow("关于我们", icon: "info.circle.fill", color: .green)
                    }
                }

                Section {
                    Button {
                        settings.reset()
                    } label: {
                        Text("恢复默认设置").foregroundStyle(.red)
                    }
                }

                Section {
                    Text("“播放盒”是自有播放器，内核为 AVPlayer + 开源 MobileVLCKit。设置立即生效并保存到本地。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    private func iconRow(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 29, height: 29)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(title)
        }
    }
}

// MARK: - 播放设置

struct PlaybackSettingsView: View {
    @ObservedObject var settings: SettingsStore

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Form {
            Section("播放") {
                Picker("默认倍速", selection: Binding(
                    get: { settings.value.defaultSpeed },
                    set: { settings.value.defaultSpeed = $0 }
                )) {
                    ForEach(speeds, id: \.self) { value in
                        Text(speedText(value)).tag(value)
                    }
                }
                Toggle("循环播放", isOn: Binding(
                    get: { settings.value.loopPlayback },
                    set: { settings.value.loopPlayback = $0 }
                ))
            }

            Section("缓冲") {
                Picker("起播缓冲时长", selection: Binding(
                    get: { settings.value.bufferSeconds },
                    set: { settings.value.bufferSeconds = $0 }
                )) {
                    Text("2 秒（起播快）").tag(2.0)
                    Text("5 秒（平衡）").tag(5.0)
                    Text("10 秒（长片更稳）").tag(10.0)
                }
                Text("缓冲越短起播越快，网络抖动时更容易卡；越长越稳。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("播放设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func speedText(_ value: Double) -> String {
        if value == Double(Int(value)) { return "\(Int(value))x" }
        return String(format: "%.2fx", value)
    }
}

// MARK: - 界面偏好 / 列表配置

struct InterfaceSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                NavigationLink("列表配置") {
                    ListConfigView(settings: settings)
                }
            }
            Section {
                Text("列表配置控制“播放链接”与“本地文件”两页的显示方式。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("界面偏好")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ListConfigView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("标题栏显示文件数量", isOn: Binding(
                    get: { settings.value.showCountInTitle },
                    set: { settings.value.showCountInTitle = $0 }
                ))
                Toggle("列表项目显示时间", isOn: Binding(
                    get: { settings.value.showFileTime },
                    set: { settings.value.showFileTime = $0 }
                ))
            }

            Section("页面样式") {
                Toggle("缩略图铺满", isOn: Binding(
                    get: { settings.value.thumbnailFill },
                    set: { settings.value.thumbnailFill = $0 }
                ))
                Toggle("显示滚动条", isOn: Binding(
                    get: { settings.value.showScrollIndicators },
                    set: { settings.value.showScrollIndicators = $0 }
                ))
            }

            Section("预览图") {
                Toggle("显示媒体预览图", isOn: Binding(
                    get: { settings.value.showPreview },
                    set: { settings.value.showPreview = $0 }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("视频预览图时间")
                        Spacer()
                        Text("\(Int(settings.value.previewPercent))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { settings.value.previewPercent },
                        set: { settings.value.previewPercent = $0 }
                    ), in: 10...90, step: 5)
                }

                Toggle("优先使用内嵌预览图", isOn: Binding(
                    get: { settings.value.preferEmbeddedCover },
                    set: { settings.value.preferEmbeddedCover = $0 }
                ))

                Text("开启后优先使用文件自带封面，预览图时间设定则不生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("列表配置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 播放手势

struct GestureSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("双击暂停 / 继续播放", isOn: Binding(
                    get: { settings.value.doubleTapToggle },
                    set: { settings.value.doubleTapToggle = $0 }
                ))
                Toggle("左右滑动快进 / 快退", isOn: Binding(
                    get: { settings.value.swipeSeek },
                    set: { settings.value.swipeSeek = $0 }
                ))
            }
            Section {
                Text("向左滑快退 15 秒，向右滑快进 15 秒；手势仅在播放页生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("播放手势")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 媒体控制

struct MediaControlSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("播放时屏幕常亮", isOn: Binding(
                    get: { settings.value.keepAwake },
                    set: { settings.value.keepAwake = $0 }
                ))
                Toggle("后台 / 锁屏继续播放", isOn: Binding(
                    get: { settings.value.backgroundAudio },
                    set: { settings.value.backgroundAudio = $0 }
                ))
            }
            Section {
                Text("后台播放依赖系统的音频后台能力，静音时锁屏也能继续。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("媒体控制")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 视频设置

struct VideoSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("解码内核") {
                Picker("内核", selection: Binding(
                    get: { settings.value.engineMode },
                    set: { settings.value.engineMode = $0 }
                )) {
                    Text("自动（推荐）").tag("auto")
                    Text("系统内核（AVPlayer）").tag("av")
                    Text("VLC 内核（全格式）").tag("vlc")
                }
                .pickerStyle(.inline)
            }

            Section {
                Text("自动：常见格式用系统内核，MKV/AVI/FLV 等自动转 VLC。\n系统内核：起播快、功耗低，但格式有限。\nVLC：全格式，链接异常/特殊请求头兼容性更好，功耗略高。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("视频设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 音频设置

struct AudioSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("后台 / 锁屏继续播放", isOn: Binding(
                    get: { settings.value.backgroundAudio },
                    set: { settings.value.backgroundAudio = $0 }
                ))
            }
            Section {
                Text("关闭后离开 App 将自动暂停，适合省电。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("音频设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 缓存管理

struct CacheManagerView: View {
    @State private var thumbSize: String = "计算中…"
    @State private var mediaSize: String = "计算中…"
    @State private var cleared = false

    var body: some View {
        Form {
            Section("预览图缓存") {
                HStack {
                    Text("占用")
                    Spacer()
                    Text(thumbSize).foregroundStyle(.secondary)
                }
                Button("清空预览图缓存") {
                    clearThumbs()
                }
                .foregroundStyle(.red)
            }

            Section("下载文件") {
                HStack {
                    Text("占用")
                    Spacer()
                    Text(mediaSize).foregroundStyle(.secondary)
                }
                Text("下载文件请到“本地文件”页左滑删除，这里只做统计。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if cleared {
                Section {
                    Text("预览图缓存已清空，下次进入列表会自动重建。")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshSizes() }
    }

    private func refreshSizes() {
        thumbSize = sizeText(directorySize(ThumbnailStore.dir))
        mediaSize = sizeText(directorySize(Store.mediaDir))
    }

    private func clearThumbs() {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: ThumbnailStore.dir.path) {
            for name in names {
                try? fm.removeItem(at: ThumbnailStore.dir.appendingPathComponent(name))
            }
        }
        ThumbnailCenter.shared.clearCache()
        cleared = true
        refreshSizes()
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

// MARK: - 关于

struct AboutView: View {
    @State private var version = ""
    @State private var build = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("应用")
                    Spacer()
                    Text("播放盒").foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text("\(version)（\(build)）").foregroundStyle(.secondary)
                }
                HStack {
                    Text("播放内核")
                    Spacer()
                    Text("AVPlayer + VLC 3.7").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text(Bundle.main.bundleIdentifier ?? "-")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            Section("链接库 / 下载") {
                Text("链接存在本地（playerbox-state.json），下载文件在 Documents/Media，可在「文件」App 里直接取用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://github.com/ty7817/PlayerBox")!) {
                    HStack {
                        Text("项目主页（GitHub）")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("本 App 为自有实现，播放内核使用开源 MobileVLCKit（LGPL）；不包含任何破解或商业 App 代码。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于我们")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        }
    }
}
