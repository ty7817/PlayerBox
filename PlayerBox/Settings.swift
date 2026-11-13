import Foundation
import SwiftUI

struct AppSettings: Codable {
    // 播放
    var defaultSpeed: Double = 1.0
    var loopPlayback: Bool = false
    var bufferSeconds: Double = 2
    var engineMode: String = "auto"

    // 手势
    var doubleTapToggle: Bool = true
    var swipeSeek: Bool = true
    var brightnessSwipe: Bool = true
    var volumeSwipe: Bool = true

    // 媒体控制
    var keepAwake: Bool = true
    var backgroundAudio: Bool = true

    // 列表配置
    var showCountInTitle: Bool = true
    var showFileTime: Bool = true
    var thumbnailFill: Bool = true
    var showScrollIndicators: Bool = false
    var showPreview: Bool = true
    var previewPercent: Double = 10
    var preferEmbeddedCover: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultSpeed = try c.decodeIfPresent(Double.self, forKey: .defaultSpeed) ?? 1.0
        loopPlayback = try c.decodeIfPresent(Bool.self, forKey: .loopPlayback) ?? false
        bufferSeconds = try c.decodeIfPresent(Double.self, forKey: .bufferSeconds) ?? 2
        engineMode = try c.decodeIfPresent(String.self, forKey: .engineMode) ?? "auto"
        doubleTapToggle = try c.decodeIfPresent(Bool.self, forKey: .doubleTapToggle) ?? true
        swipeSeek = try c.decodeIfPresent(Bool.self, forKey: .swipeSeek) ?? true
        brightnessSwipe = try c.decodeIfPresent(Bool.self, forKey: .brightnessSwipe) ?? true
        volumeSwipe = try c.decodeIfPresent(Bool.self, forKey: .volumeSwipe) ?? true
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        backgroundAudio = try c.decodeIfPresent(Bool.self, forKey: .backgroundAudio) ?? true
        showCountInTitle = try c.decodeIfPresent(Bool.self, forKey: .showCountInTitle) ?? true
        showFileTime = try c.decodeIfPresent(Bool.self, forKey: .showFileTime) ?? true
        thumbnailFill = try c.decodeIfPresent(Bool.self, forKey: .thumbnailFill) ?? true
        showScrollIndicators = try c.decodeIfPresent(Bool.self, forKey: .showScrollIndicators) ?? false
        showPreview = try c.decodeIfPresent(Bool.self, forKey: .showPreview) ?? true
        previewPercent = try c.decodeIfPresent(Double.self, forKey: .previewPercent) ?? 10
        preferEmbeddedCover = try c.decodeIfPresent(Bool.self, forKey: .preferEmbeddedCover) ?? true
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var value: AppSettings {
        didSet { save() }
    }

    private let key = "playerbox.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else {
            value = AppSettings()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func reset() {
        value = AppSettings()
    }
}
