import Foundation
import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation

// MARK: - 横竖屏

enum OrientationSupport {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
    private static var lastRequest: TimeInterval = 0

    static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    static var isLandscape: Bool {
        guard let scene = scene else { return false }
        return scene.effectiveGeometry.interfaceOrientation.isLandscape
    }

    static func toggle() {
        let now = Date().timeIntervalSince1970
        guard now - lastRequest > 0.45 else { return }
        lastRequest = now
        apply(isLandscape ? .portrait : .landscape)
    }

    static func apply(_ wanted: UIInterfaceOrientationMask) {
        mask = wanted
        guard let scene = scene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted)) { _ in }
    }

    static func lockPortrait() {
        guard isLandscape else { return }
        apply(.portrait)
    }

    static func unlock() {
        mask = .allButUpsideDown
    }
}

// MARK: - 系统音量（MPVolumeView 隐藏滑杆）

final class VolumeControl {
    static let shared = VolumeControl()

    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 40, height: 40))
    private var stored: Float = 0

    private init() {
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        stored = AVAudioSession.sharedInstance().outputVolume
    }

    func attach() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }
        if volumeView.superview == nil {
            window.addSubview(volumeView)
        }
    }

    private var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    func current() -> Float {
        if let slider = slider { return slider.value }
        stored = AVAudioSession.sharedInstance().outputVolume
        return stored
    }

    func set(_ value: Float) {
        let level = min(max(value, 0), 1)
        stored = level
        if let slider = slider {
            slider.value = level
            slider.sendActions(for: .touchUpInside)
        }
    }
}

// MARK: - 手势状态

enum DragMode {
    case none
    case seek
    case brightness
    case volume
}

struct PlayerHUD: Equatable {
    var icon: String
    var title: String
    var detail: String
    var progress: Double
}
