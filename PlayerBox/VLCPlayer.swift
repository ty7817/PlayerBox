import Foundation
import SwiftUI
import UIKit
import MobileVLCKit

final class VLCController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()

    @Published var isPlaying = false
    @Published var stateText = ""
    @Published var currentText = "00:00"
    @Published var currentSeconds: Double = 0
    @Published var durationSeconds: Double = 0

    override init() {
        super.init()
        player.delegate = self
    }

    func load(_ url: URL) {
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": 1500,
            "clock-jitter": 0,
            "clock-syncro-slap": 250,
            "http-user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ])
        player.media = media
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func jump(_ seconds: Double) {
        var target = Int32(player.time.intValue) + Int32(seconds * 1000)
        if target < 0 { target = 0 }
        player.time = VLCTime(int: target)
    }

    func seek(toSeconds seconds: Double) {
        let ms = Int32(max(0, seconds) * 1000)
        player.time = VLCTime(int: ms)
    }

    func setRate(_ value: Float) {
        player.rate = value
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .playing:
            isPlaying = true
            stateText = ""
        case .paused:
            isPlaying = false
            stateText = "已暂停"
        case .buffering:
            stateText = "缓冲中…"
        case .opening:
            stateText = "打开中…"
        case .ended:
            isPlaying = false
            stateText = "播放结束"
        case .error:
            isPlaying = false
            stateText = "VLC 播放失败：可能链接需要特殊请求头或格式异常"
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let ms = Double(player.time.intValue)
        currentSeconds = max(0, ms / 1000)
        currentText = format(Int(player.time.intValue))
        let length = Double(player.media?.length.intValue ?? 0)
        if length > 0 { durationSeconds = length / 1000 }
    }

    private func format(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "00:00" }
        let total = milliseconds / 1000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        player.drawable = uiView
    }
}
