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
        "cup1", "slide7", "chips3", "chips4", "chips5", "chips6", "collide2", "collide3", "collide4",
        "lay1", "lay2", "handle1", "turn", "match-win", "match-lose", "kaboot", "bid",
        "app-open", "table-join", "table-leave", "proj-sira", "proj-fifty", "bid-sun", "voice-join", "voice-leave", "proj-hundred", "proj-400",
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

    /// التوزيع: ثماني أوراق متتالية بدون خلط (أول التوزيع وباقي الورق)
    func deal(newHand: Bool) {
        for (i, n) in ["slide1", "slide2", "slide3", "slide4", "slide1", "slide2", "slide3", "slide4"].enumerated() {
            play(n, at: Double(i) * 0.1, gain: 0.6)
        }
    }

    /// نغمة فتح التطبيق (قانون بمقام الراست)
    func appOpen() { play("app-open", vary: false) }

    /// لاعب انضم للطاولة أو رجع اتصاله (هارب يطلع) / غادرها أو انقطع اتصاله (فقاعتان تنزلان)
    func tableJoin() { play("table-join", gain: 0.7, vary: false) }
    func tableLeave() { play("table-leave", gain: 0.7, vary: false) }

    /// أحد انضم للمحادثة الصوتية / غادرها
    func voiceJoin() { play("voice-join", gain: 0.7, vary: false) }
    func voiceLeave() { play("voice-leave", gain: 0.7, vary: false) }

    func collect() { play("slide7", gain: 0.8, vary: false) }

    func turn(soft: Bool) {
        guard Prefs.turnChime, !Prefs.muted else { return }
        // مشغّل جديد كل مرة (المحادثة الصوتية تغيّر إعدادات الصوت فيتعطل المشغّل القديم)،
        // وبصوت واضح حتى مع VoiceOver (كان خافتاً معه فما ينسمع)
        DispatchQueue.main.async { [weak self] in
            guard let self, let d = self.data["turn"], let p = try? AVAudioPlayer(data: d) else { return }
            p.volume = 0.6
            p.play()
            self.playing.removeAll { !$0.isPlaying }
            self.playing.append(p)
        }
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
    /// القطع بالحكم: ضربة ورقة
    func cut() {
        play("collide4", gain: 1)
        play("slide7", at: 0.02, gain: 0.8)
    }
    /// المشاريع: لكل مشروع صوته (أكبر مشروع في الإعلان)، أصوات ورق وفيش مسجّلة تكبر مع المشروع
    func project(_ kinds: [String]) {
        if kinds.contains("أربعمية") { play("proj-400", gain: 0.8, vary: false) }
        else if kinds.contains(where: { $0 == "مية" || $0 == "مية وخمسين" }) { play("proj-hundred", gain: 0.8, vary: false) }
        else if kinds.contains("خمسين") { play("proj-fifty", gain: 0.8, vary: false) }
        else { play("proj-sira", gain: 0.8, vary: false) }
    }
    func baloot() { play("collide", gain: 0.7); play("chips2", at: 0.15, gain: 0.7) }
    func hokm() { if once("hokm") { play("bid", gain: 0.8, vary: false) } }
    /// الصن صوته غير الحكم: نقرة خفيفة
    func sun() { if once("sun") { play("bid-sun", gain: 0.8, vary: false) } }
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
