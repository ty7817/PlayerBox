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
