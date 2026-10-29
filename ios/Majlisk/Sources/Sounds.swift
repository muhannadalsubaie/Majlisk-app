import AVFoundation

/// مؤثرات اللعبة (حزم Kenney، رخصة CC0) — نفس أصوات التطبيق الحالي وتوقيتها.
/// تحترم "كتم عام لجميع الأصوات"، ومعتدلة حتى لا تغطي قارئ الشاشة.
final class Sounds {
    static let shared = Sounds()
    private var data: [String: Data] = [:]
    private var playing: [AVAudioPlayer] = []
    private var recent: [String: Date] = [:]

    private let files = [
        "card1", "card2", "card3", "card4", "slide1", "slide2", "slide3", "slide4",
        "shove1", "shove2", "shove3", "shove4", "shuffle", "fan", "chips1", "chips2", "collide",
        "cup1", "slide7", "chips3", "chips4", "chips5", "chips6", "collide2", "collide3",
        "lay1", "lay2", "handle1", "turn", "match-win", "match-lose", "kaboot", "bid",
    ]

    func preload() {
        // يمتزج مع صوت VoiceOver والمحادثة دون أن يوقفهما
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        for f in files {
            if let url = Bundle.main.url(forResource: f, withExtension: "mp3", subdirectory: "Media/sounds")
                ?? Bundle.main.url(forResource: f, withExtension: "mp3", subdirectory: "sounds"),
               let d = try? Data(contentsOf: url) { data[f] = d }
        }
    }

    private func play(_ name: String, at: Double = 0, gain: Float = 0.8, rate: Float = 1, vary: Bool = true) {
        if Prefs.muted { return }
        guard let d = data[name] else { return }
        let run = { [weak self] in
            guard let self, let p = try? AVAudioPlayer(data: d) else { return }
            p.volume = gain
            p.enableRate = true
            p.rate = rate * (vary ? Float.random(in: 0.95...1.05) : 1)
            p.play()
            self.playing.removeAll { !$0.isPlaying }
            self.playing.append(p)
        }
        if at <= 0 { DispatchQueue.main.async(execute: run) } else { DispatchQueue.main.asyncAfter(deadline: .now() + at, execute: run) }
    }

    private func pick(_ names: String...) -> String { names.randomElement()! }

    /// صوت المزايدة يُشغَّل فوراً عند ضغطة صاحبه، ثم يصل التحديث من الخادم: لا نكرره
    private func once(_ kind: String) -> Bool {
        if let t = recent[kind], Date().timeIntervalSince(t) < 2.5 { return false }
        recent[kind] = Date()
        return true
    }

    func deal(newHand: Bool) {
        var start = 0.0
        if newHand { play("shuffle", gain: 0.7); start = 1.1 }
        for i in 0..<4 { play(pick("slide1", "slide2", "slide3", "slide4"), at: start + Double(i) * 0.12, gain: 0.6) }
    }

    func collect() { play("slide7", gain: 0.8, vary: false) }

    func turn(soft: Bool) {
        guard Prefs.turnChime else { return }
        play("turn", gain: soft ? 0.35 : 0.7, vary: false)
    }

    func handEnd(_ result: String, kaboot: Bool) {
        if kaboot && result != "lose" {
            play("kaboot", gain: 0.8, vary: false)
            for (i, n) in ["chips3", "chips4", "chips5", "chips6", "collide2", "collide3"].enumerated() { play(n, at: 0.1 + Double(i) * 0.11, gain: 0.85) }
            return
        }
        switch result {
        case "win": play("chips3", gain: 0.85); play("chips4", at: 0.14, gain: 0.8); play("collide2", at: 0.32, gain: 0.75); play("handle1", at: 0.5, gain: 0.6)
        case "lose": play("lay1", gain: 0.7); play("lay2", at: 0.22, gain: 0.5)
        default: play("chips3", gain: 0.6); play("collide2", at: 0.2, gain: 0.5)
        }
    }

    func matchEnd(won: Bool) { play(won ? "match-win" : "match-lose", gain: 0.8, vary: false) }
    func card() { play(pick("card1", "card2", "card3", "card4")) }
    func cut() {
        play(pick("shove1", "shove2", "shove3", "shove4"), gain: 1)
        play(pick("card1", "card3"), at: 0.02, gain: 1, rate: 0.85)
    }
    func project() { play("fan", gain: 0.6); play("chips1", at: 0.25, gain: 0.7) }
    func baloot() { play("collide", gain: 0.7); play("chips2", at: 0.15, gain: 0.7) }
    func hokm() { if once("hokm") { play("bid", gain: 0.9, vary: false) } }
    func sun() { if once("sun") { play("bid", gain: 0.9, vary: false) } }
    func confirmHokm() { if once("confirm") { play("bid", gain: 0.7, vary: false) } }
    /// دبل/ثري/فور: الصوت يتكرر بعدد مستواه
    func double(_ level: Int) {
        guard once("double\(level)") else { return }
        for i in 0..<min(level, 4) { play("bid", at: Double(i) * 0.2, gain: 0.9, vary: false) }
    }
    func gahwa() {
        guard once("gahwa") else { return }
        for i in 0..<3 { play("bid", at: Double(i) * 0.2, gain: 0.9, vary: false) }
        play("cup1", at: 0.7, gain: 0.9)
    }
}
