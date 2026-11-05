import AVFoundation

/// مؤثرات اللعبة (حزم Kenney، رخصة CC0) — نفس أصوات التطبيق الحالي وتوقيتها.
/// تحترم "كتم عام لجميع الأصوات"، ومعتدلة حتى لا تغطي قارئ الشاشة.
final class Sounds {
    /// الوقت بين طقطقة كل خطوة يمشيها الحجر (نفس مهلة الخادم: الدور ما ينتقل لين يوصل الحجر)
    static let stepGap = 0.22
    static let shared = Sounds()
    private var data: [String: Data] = [:]
    private var urls: [String: URL] = [:]
    private var playing: [AVAudioPlayer] = []
    private var recent: [String: Date] = [:]

    private let files = [
        "card1", "card2", "card3", "card4",
        "shove1", "shove2", "shove3", "shove4", "shuffle", "fan", "chips1", "chips2", "collide",
        "cup1", "slide7", "chips3", "chips4", "chips5", "chips6", "collide2", "collide3", "collide4",
        "lay1", "lay2", "handle1", "match-win", "match-lose", "kaboot", "bid",
        "app-open", "table-join", "table-leave", "proj-sira", "proj-fifty", "bid-sun", "voice-join", "voice-leave",
        "voice-pass", "voice-wala", "voice-sun", "voice-hokm", "voice-hokm2", "voice-ashkal",
        "voice-double", "voice-three", "voice-four", "voice-gahwa", "voice-locked", "voice-open", "voice-turn", "voice-qablak", "proj-hundred", "proj-400",
        "voice-confirm", "voice-hokm2-S", "voice-hokm2-H", "voice-hokm2-C", "voice-hokm2-D", "mic-on", "mic-off",
        "domino-shuffle", "domino-tile", "dice", "step1", "step2", "marble1", "marble2", "deal", "capture", "jackaroo-card", "voice-first", "voice-second", "voice-paper", "voice-sawa", "voice-ekka", "domino-end", "proj-baloot", "trump-cut", "hand-end",
    ]

    func preload() {
        // يمتزج مع صوت VoiceOver والمحادثة دون أن يوقفهما
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        for f in files {
            if let url = Bundle.main.url(forResource: f, withExtension: "mp3", subdirectory: "Media/sounds")
                ?? Bundle.main.url(forResource: f, withExtension: "mp3", subdirectory: "sounds"),
               let d = try? Data(contentsOf: url) { data[f] = d; urls[f] = url }
        }
    }

    private func play(_ name: String, at: Double = 0, gain: Float = 0.8, vary: Bool = true) {
        if Prefs.muted { return }
        guard let d = data[name] else { return }
        let run = { [weak self] in
            guard let self else { return }
            let g = gain * (vary ? Float.random(in: 0.9...1) : 1)
            // المحادثة الصوتية شغّالة: الصوت ينخلط في صوت المحادثة نفسه، فما ينخفض لما تفتح الميكروفون
            if let dev = VoiceAudioDevice.active, let url = self.urls[name] { dev.effects.play(name, url: url, gain: g); return }
            guard let p = try? AVAudioPlayer(data: d) else { return }
            // بلا تغيير سرعة: AVAudioPlayer يمطّ الصوت مع الحفاظ على طبقته، فتتكرر ضربة الورقة وتتقطع.
            // التنويع بفرق بسيط في العلو فقط
            p.volume = g
            p.prepareToPlay()
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
    func deal(newHand: Bool) { play("deal", gain: 1, vary: false) }

    /// أكل حجر خصم (اللودو والجاكارو): نفس الصوت للعبتين
    func capture(at: Double = 0) { play("capture", at: at, gain: 1, vary: false) }

    /// نغمة فتح التطبيق (قانون بمقام الراست)
    func appOpen() { play("app-open", vary: false) }

    /// لاعب انضم للطاولة أو رجع اتصاله (هارب يطلع) / غادرها أو انقطع اتصاله (فقاعتان تنزلان)
    func tableJoin() { play("table-join", gain: 0.7, vary: false) }
    func tableLeave() { play("table-leave", gain: 0.7, vary: false) }

    /// كلمات المزايدة والدبل منطوقة بالترتيب (من الخادم): حكم، صن، بس، ولا، دبل، مقفل...
    func voices(_ keys: [String]) {
        for (i, k) in keys.enumerated() { play("voice-\(k)", at: Double(i) * 0.7, gain: 1, vary: false) }
    }

    /// أحد انضم للمحادثة الصوتية / غادرها
    /// الدومينو: خلط القطع عند التوزيع، وطقة القطعة على الطاولة
    func dominoShuffle() { play("domino-shuffle", gain: 1, vary: false) }
    func dominoTile() { play("domino-tile", gain: 1) }
    /// نهاية الصكة في الدومينو: هارب هادئ
    func dominoEnd(at: Double = 0) { play("domino-end", at: at, gain: 1, vary: false) }
    /// الجاكارو: صوت وضع الورقة
    func jackarooCard() { play("jackaroo-card", gain: 1) }
    /// لودو: رمي النرد
    func dice() { play("dice", gain: 0.9) }
    /// مشي الحجر في اللودو: نقرة لكل خطوة
    func steps(_ n: Int, at: Double = 0) {
        for i in 0..<min(max(n, 1), 13) { play(i % 2 == 0 ? "step1" : "step2", at: at + Double(i) * Sounds.stepGap, gain: 0.9) }
    }
    /// مشي حجر الجاكارو: نقرة خفيفة لكل خطوة (غير صوت اللودو)
    func marbleSteps(_ n: Int, at: Double = 0) {
        for i in 0..<min(max(n, 1), 13) { play(i % 2 == 0 ? "marble1" : "marble2", at: at + Double(i) * Sounds.stepGap, gain: 0.9) }
    }

    /// جرس خفيف لك أنت لما تفتح الميكروفون أو تسكّره
    func micToggle(_ open: Bool) { play(open ? "mic-on" : "mic-off", gain: 0.8, vary: false) }
    func voiceJoin() { play("voice-join", gain: 0.7, vary: false) }
    func voiceLeave() { play("voice-leave", gain: 0.7, vary: false) }

    func collect() { play("slide7", gain: 1, vary: false) }

    func turn(soft: Bool) {
        guard !Prefs.muted else { return }
        // مشغّل جديد كل مرة (المحادثة الصوتية تغيّر إعدادات الصوت فيتعطل المشغّل القديم)،
        // وبصوت واضح حتى مع VoiceOver (كان خافتاً معه فما ينسمع)
        DispatchQueue.main.async { [weak self] in
            // نغمة الدور (ملف voice-turn)
            guard let self else { return }
            if let dev = VoiceAudioDevice.active, let url = self.urls["voice-turn"] { dev.effects.play("voice-turn", url: url, gain: 1); return }
            guard let d = self.data["voice-turn"], let p = try? AVAudioPlayer(data: d) else { return }
            p.volume = 1
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
        // نهاية كل جولة: صوت هادئ (أجراس صغيرة)
        play("hand-end", gain: 0.9, vary: false)
    }

    func matchEnd(won: Bool) { play(won ? "match-win" : "match-lose", gain: 0.8, vary: false) }
    func card() { play(pick("card1", "card2", "card3", "card4"), gain: 1) }
    /// القطع بالحكم: ضربة ورقة
    /// القطع بالحكم: ورقة ومعها رنة عملة
    func cut() { play("trump-cut", gain: 1, vary: false) }
    /// المشاريع: لكل مشروع صوته (أكبر مشروع في الإعلان)، أصوات ورق وفيش مسجّلة تكبر مع المشروع
    func project(_ kinds: [String]) {
        if kinds.contains("أربعمية") { play("proj-400", gain: 0.8, vary: false) }
        else if kinds.contains("مية") { play("proj-hundred", gain: 0.8, vary: false) }
        else if kinds.contains("خمسين") { play("proj-fifty", gain: 0.8, vary: false) }
        else { play("proj-sira", gain: 0.8, vary: false) }
    }
    /// مشروع البلوت: تسجيلك «بلوت»
    func baloot() { play("proj-baloot", gain: 0.8, vary: false) }
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
