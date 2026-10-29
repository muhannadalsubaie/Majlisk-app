import AVFoundation
import UIKit

/// موسيقى القائمة: تبدأ مع فتح التطبيق وتتكرر في الشاشات الرئيسية، وتتوقف عند دخول طاولة
/// أو خروج التطبيق للخلفية. صوتها منخفض حتى لا تغطي VoiceOver.
final class MenuMusic {
    static let shared = MenuMusic()
    private var player: AVAudioPlayer?
    private var wanted = false
    private var foreground = true

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.foreground = false; self?.update()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.foreground = true; self?.update()
        }
    }

    func setWanted(_ w: Bool) { wanted = w; update() }

    func update() {
        if wanted && foreground && Prefs.music { start() } else { stop() }
    }

    private func start() {
        if player?.isPlaying == true { return }
        if player == nil {
            guard let url = Bundle.main.url(forResource: "menu", withExtension: "mp3", subdirectory: "Media/music"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.numberOfLoops = -1
            p.volume = 0.2
            player = p
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        player?.play()
    }

    private func stop() {
        player?.stop()
        player = nil
    }
}
