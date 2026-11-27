import UIKit
import AVFoundation

/**
 * طريقة قراءة الإعلانات (تجربة، من الإعدادات):
 * voiceover: VoiceOver يقرأ، والنص ينقسم قطع كل قطعة بلغتها (الافتراضي)
 * single: VoiceOver يقرأ الجملة كاملة إعلان واحد، وكل جزء معلّم بلغته (بدون تقسيم)
 * app: التطبيق يقرأ بنفسه بمحرك الكلام (صوت عربي للعربي وصوت إنجليزي للإنجليزي)، فيعرف متى يخلص كل جزء
 */
enum AnnounceMode: String, CaseIterable {
    case voiceover, single, app
    static var current: AnnounceMode {
        get { AnnounceMode(rawValue: UserDefaults.standard.string(forKey: "announceMode") ?? "") ?? .voiceover }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "announceMode"); if newValue != .app { AppSpeech.shared.stop() } }
    }
    var label: String {
        switch self {
        case .voiceover: return "VoiceOver (مقسّم حسب اللغة)"
        case .single: return "VoiceOver جملة وحدة"
        case .app: return "صوت التطبيق ثنائي اللغة"
        }
    }
}

/// صوت التطبيق: يقرأ كل قطعة بصوت لغتها ورا بعض (المحرك نفسه يصفّها بالترتيب)
final class AppSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AppSpeech()
    private let synth = AVSpeechSynthesizer()
    private var voices: [String: AVSpeechSynthesisVoice] = [:]
    private var focusObserver: NSObjectProtocol?
    /// السرعة (0.3 بطيء إلى 0.65 سريع)، من الإعدادات
    static var rate: Float {
        get { UserDefaults.standard.object(forKey: "appSpeechRate") as? Float ?? 0.55 }
        set { UserDefaults.standard.set(min(0.65, max(0.3, newValue)), forKey: "appSpeechRate") }
    }
    var speaking: Bool { synth.isSpeaking }

    override init() {
        super.init()
        synth.delegate = self
        // يحرك المؤشر بإصبعه: VoiceOver بيقرأ العنصر، فنسكت عشان ما يتداخل الصوتين
        focusObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, Date() >= self.ignoreFocusUntil else { return }
            self.stop()
        }
    }
    /// نقل المؤشر من التطبيق نفسه (بعد حركتك): ما نسكت بسببه
    var ignoreFocusUntil = Date.distantPast

    private func voice(_ lang: String) -> AVSpeechSynthesisVoice? {
        if let v = voices[lang] { return v }
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        // الأفضل جودة، والعربي السعودي أول، والإنجليزي الأمريكي أول
        let prefer = lang == "ar" ? "ar-SA" : lang == "en" ? "en-US" : "fr-FR"
        let v = all.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
            return (a.language == prefer ? 0 : 1) < (b.language == prefer ? 0 : 1)
        }.first ?? AVSpeechSynthesisVoice(language: prefer)
        voices[lang] = v
        return v
    }

    /// يضيف النص للطابور (now = يقطع اللي يقرأه الحين)
    func speak(_ text: String, now: Bool) {
        if now { synth.stopSpeaking(at: .immediate) }
        for (r, l) in langRuns(text) {
            let piece = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ":،,").union(.whitespaces))
            guard piece.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            let u = AVSpeechUtterance(string: piece)
            u.voice = voice(l)
            u.rate = AppSpeech.rate
            u.postUtteranceDelay = 0.05
            synth.speak(u)
        }
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

/// إعلانات VoiceOver: أحداث اللعب تُصفّ وتُقرأ بالترتيب، وردود الإيماءات السريعة تُقرأ فوراً.
enum Announcer {
    static var readerOn: Bool { UIAccessibility.isVoiceOverRunning }

    /**
     * طابورنا (مثل الأندرويد): VoiceOver يقطع الإعلان اللي يقرؤه لما يجيه إعلان جديد،
     * فنرسل كل إعلان بعد ما يخلص اللي قبله (VoiceOver يبلغنا لما يخلص)، ولو انقطع نعيده.
     */
    private static var queue: [String] = []
    private static var current: String?
    private static var retries = 0
    private static var busyUntil = Date.distantPast
    private static var observer: NSObjectProtocol?
    /// وقت تقريبي لقراءة النص (احتياط لو ما وصل بلاغ الانتهاء)
    private static func readTime(_ text: String) -> TimeInterval { 0.5 + Double(text.count) * 0.06 }

    private static func listen() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { n in
            let text = n.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            let ok = n.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool ?? true
            guard let cur = current, text == cur else { return }
            // انقطع (VoiceOver قرأ شي ثاني فوقه): نعيده مرة وحدة
            if !ok && retries < 1 {
                retries += 1
                post(cur, queued: true)
                return
            }
            current = nil
            busyUntil = .distantPast
            pump()
        }
    }

    /// اللودو: الإعلان يقطع قراءة VoiceOver لعنصر تغيّر (ما ينتظره)، بس ما يقطع إعلاناتنا نفسها
    private static var urgentQueue = false
    /// بعد حركتك وإعلاننا لسا يُقرأ: الإعلان الجاي ينتظر إعلاننا (طابورنا)، بس يُرسل بدون «انتظر» عند VoiceOver
    /// (كان يُرسل بـ«انتظر» فيعلق عند VoiceOver ورا قراءة العنصر وما ينقال إلا مع الإعلان اللي بعده)
    private static var unqueuedNext = false

    private static func post(_ text: String, queued: Bool) {
        let s = spokenNS(text, queued: queued) // كل جزء بلغته
        // النص المقروء فعلاً (الأرقام فيه عربية): بلاغ الانتهاء يجي به، فنقارن عليه
        current = s.string
        busyUntil = Date().addingTimeInterval(readTime(text))
        UIAccessibility.post(notification: .announcement, argument: s)
        let mine = s.string
        // احتياط: لو ما وصل بلاغ الانتهاء نكمل بعد الوقت التقريبي
        DispatchQueue.main.asyncAfter(deadline: .now() + readTime(text) + 0.6) {
            guard current == mine else { return }
            // المُرسل بـ«انتظر» وما انقال (VoiceOver أحياناً يحبسه لين يجي إعلان ثاني): نعيده بدون انتظار مرة وحدة
            if queued && retries < 1 {
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if current == mine { post(text, queued: false) }
                }
                return
            }
            current = nil; pump()
        }
    }

    private static func pump() {
        listen()
        guard current == nil, Date() >= busyUntil, !queue.isEmpty else { return }
        retries = 0
        // إعلاناتنا ما تقطع بعضها (ننتظر انتهاء اللي قبله بأنفسنا)، فاللودو يُرسل بدون «انتظر دورك» عند VoiceOver
        let q = !urgentQueue && !unqueuedNext
        unqueuedNext = false
        post(queue.removeFirst(), queued: q)
    }

    /**
     * نص فيه لغتين (اسم لاعب بالإنجليزي وسط كلام عربي): VoiceOver يقرأ الجملة كلها بصوت أول لغة،
     * فينقرأ الكرت بالإنجليزي. نقسمه قطع، كل قطعة بلغتها، وتنقرأ ورا بعض
     */
    private static func pieces(_ text: String) -> [String] {
        // جملة وحدة: VoiceOver يقرأ الإعلان كامل، وكل جزء معلّم بلغته
        if AnnounceMode.current == .single { return [text] }
        let runs = langRuns(text)
        guard runs.count > 1 else { return [text] }
        // القطعة تبدأ بالكلام نفسه: «10 هاص» بدل «: 10 هاص» (الاسم قطعة، والورقة برقمها قطعة)
        return runs.map { String(String(text[$0.0]).drop { $0 == ":" || $0 == "،" || $0 == "," || $0.isWhitespace }) }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    /// يُقرأ بعد ما يخلص اللي قبله (ما يقطعه)
    static func announce(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        if AnnounceMode.current == .app {
            DispatchQueue.main.async { if readerOn { AppSpeech.shared.speak(text, now: false) } }
            return
        }
        DispatchQueue.main.async {
            queue.append(contentsOf: pieces(text))
            pump()
        }
    }

    /// ننقل مؤشر VoiceOver بعد حركتك: إعلان حركتك القادم يقطع قراءة العنصر المنقول إليه
    private static var interruptUntil = Date.distantPast

    /// بعد ما تلعب وينتقل المؤشر لـ«أوراقك»: أول إعلان يجي بعدها (ورقة اللاعب اللي بعدك) يقطع القراءة على طول،
    /// حتى لو تأخر اللاعب (كانت المهلة ٣ ثواني بس فيروح الإعلان بالطابور ورا قراءة المؤشر)
    static func interruptNextEvents() {
        interruptUntil = Date().addingTimeInterval(30)
        // صوت التطبيق: المؤشر ينتقل لأوراقك بعد حركتك، وهذا مو تحريك منك فما نسكت بسببه
        AppSpeech.shared.ignoreFocusUntil = Date().addingTimeInterval(1.5)
    }

    /// إعلانات اللعب: تنتظر بعضها، إلا بعد نقل المؤشر بحركتك فتقطع قراءة العنصر الجديد
    static func announceEvent(_ text: String, urgent: Bool = false) {
        if AnnounceMode.current == .app {
            DispatchQueue.main.async {
                guard readerOn else { return }
                // بعد حركتك: أول إعلان يقطع (لو صوتنا ساكت)، وإلا ينتظر دوره ورا اللي يُقرأ
                let cut = Date() < interruptUntil && !AppSpeech.shared.speaking
                if Date() < interruptUntil { interruptUntil = .distantPast }
                AppSpeech.shared.speak(tr(text), now: cut)
            }
            return
        }
        DispatchQueue.main.async {
            urgentQueue = urgent
            // القطع للعنصر اللي انتقل له المؤشر بس: لو إعلاننا نفسه لسا يُقرأ (اسم إنجليزي ثم «عشرة هاص» قطعتين)
            // ما نقطعه، كان يضيع باقيه (ينقال الاسم بس بدون الورقة)
            if Date() < interruptUntil {
                interruptUntil = .distantPast
                if current == nil && queue.isEmpty { announceNow(text) } else { unqueuedNext = true; announce(text) }
            } else { announce(text) }
        }
    }

    /// يُقرأ الآن (ردّ إيماءة أو زر قراءة سريعة): يقطع القديم، واللي ينتظر في الطابور قديم فينمسح
    static func announceNow(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        if AnnounceMode.current == .app {
            DispatchQueue.main.async { if readerOn { AppSpeech.shared.speak(text, now: true) } }
            return
        }
        DispatchQueue.main.async {
            listen()
            // لغتين: أول قطعة الحين (تقطع القديم)، والباقي ورا بعض بعدها
            var parts = pieces(text)
            if parts.isEmpty { parts = [text] }
            queue = Array(parts.dropFirst())
            retries = 1 // ما نعيده لو انقطع: الجديد أهم
            post(parts.removeFirst(), queued: false)
        }
    }
}

enum SwipeDir { case left, right, up, down }

/// إيماءات القراءة السريعة: شاشة الطاولة تسجّل ما تقرؤه لكل اتجاه
final class Gestures {
    static let shared = Gestures()
    var handler: ((SwipeDir) -> Bool)?
    /// صاحب المعالج الحالي (اللعبة المعروضة): لما تختفي لوحتها ينمسح، فما تنقرأ لعبة سابقة أبداً
    private var owner: String?
    func fire(_ dir: SwipeDir) -> Bool { handler?(dir) ?? false }
    func set(_ id: String, _ h: @escaping (SwipeDir) -> Bool) { owner = id; handler = h }
    func clear(_ id: String) { if owner == id { owner = nil; handler = nil } }
}

/// إعدادات الجهاز (كتم الأصوات، نغمة الدور)
enum Prefs {
    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }
    /// مستوى صوت المؤثرات من 0 إلى 100 (70 = المستوى الأصلي، وفوقه مجال 30% للرفع)
    static var effectsVolume: Int {
        get { UserDefaults.standard.object(forKey: "effectsVolume") as? Int ?? 70 }
        set { UserDefaults.standard.set(min(100, max(0, newValue)), forKey: "effectsVolume") }
    }
    /// الدردشة الكتابية: read / silent / off
    static var chatMode: String {
        get { UserDefaults.standard.string(forKey: "chatMode") ?? "read" }
        set { UserDefaults.standard.set(newValue, forKey: "chatMode") }
    }
    /// آخر طاولة كنت فيها ووقت آخر نبضة؛ لو أُغلق التطبيق ورجعت خلال دقيقة ترجع لها
    static var lastTable: String? {
        get { UserDefaults.standard.string(forKey: "lastTable") }
        set { UserDefaults.standard.set(newValue, forKey: "lastTable") }
    }
    static var lastTableAt: Double {
        get { UserDefaults.standard.double(forKey: "lastTableAt") }
        set { UserDefaults.standard.set(newValue, forKey: "lastTableAt") }
    }
    /// رقم هالجوال (ثابت): الحساب يكون مسجل في جوال واحد بس
    static var deviceId: String {
        if let d = UserDefaults.standard.string(forKey: "deviceId") { return d }
        let d = UUID().uuidString
        UserDefaults.standard.set(d, forKey: "deviceId")
        return d
    }
    /// نافذة عرض الباقة الاحترافية: آخر مرة طلعت (ما ترجع قبل يومين)
    static var offerShownAt: Double {
        get { UserDefaults.standard.double(forKey: "offerShownAt") }
        set { UserDefaults.standard.set(newValue, forKey: "offerShownAt") }
    }
    /// هدية دُفعت وما تأكد تسليمها: اسم المستلم (يُكمل تسليمها عند الفتح التالي)
    static var pendingGiftTo: String? {
        get { UserDefaults.standard.string(forKey: "pendingGiftTo") }
        set { UserDefaults.standard.set(newValue, forKey: "pendingGiftTo") }
    }
    /// الحساب اللي سجّل هالجوال نفسه جواله عند الخادم (عشان ما نعيدها كل ما فتحت التطبيق)
    static var claimedUid: String? {
        get { UserDefaults.standard.string(forKey: "claimedUid") }
        set { UserDefaults.standard.set(newValue, forKey: "claimedUid") }
    }
}
