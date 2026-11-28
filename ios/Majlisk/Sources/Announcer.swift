import UIKit

/**
 * إعلانات VoiceOver: طابور واحد بالترتيب، ونحن اللي نحدد متى يُقرأ كل إعلان.
 *
 * ليش بهالشكل:
 * - ما نستخدم «انتظر دورك» حق VoiceOver (accessibilitySpeechQueueAnnouncement): VoiceOver أحياناً يحبس
 *   الإعلان المعلّم بها (مثلاً لما تتغير الشاشة بعد آخر ورقة) وما يقوله إلا لما يجي إعلان ثاني.
 *   كل إعلان يُرسل مباشرة، وطابورنا يضمن إنه ما يُرسل إلا بعد ما خلص اللي قبله (بلاغ الانتهاء من VoiceOver).
 * - كل إعلان بلغة وحدة: النص اللي فيه عربي وإنجليزي (اسم لاعب) ينقسم قطع، كل قطعة إعلان بلغتها،
 *   فالاسم ينقال بصوت إنجليزي والورقة بصوت عربي.
 * - لو انقطع إعلان (VoiceOver قرأ شي ثاني فوقه، مثل تغيّر الشاشة بعد آخر ورقة) نعيده لين مرتين.
 * - لو حرّكت المؤشر بإصبعك: ننتظر شوي عشان VoiceOver يقرأ العنصر، بعدين نكمل الطابور.
 *   إلا بعد حركتك (تلعب ورقة): الإعلان الجاي يُقرأ على طول.
 */
enum Announcer {
    static var readerOn: Bool { UIAccessibility.isVoiceOverRunning }

    private struct Item { let text: String; let lang: String }
    private static var queue: [Item] = []
    /// الإعلان اللي VoiceOver يقرأه الحين (نص القراءة نفسه، يرجع في بلاغ الانتهاء)
    private static var current: Item?
    private static var currentSpoken = ""
    /// كم مرة أعدنا الإعلان الحالي بعد ما انقطع (نعيده لين مرتين)
    private static var retries = 0
    /// رقم الإرسال: احتياط الوقت يخص إرسال واحد بس
    private static var serial = 0
    /// حرّكت المؤشر بإصبعك: الطابور ينتظر لين هالوقت (VoiceOver يقرأ العنصر)
    private static var holdUntil = Date.distantPast
    /// بعد حركتك: الإعلان الجاي ما ينتظر قراءة العنصر اللي انتقل له المؤشر
    private static var skipHoldUntil = Date.distantPast
    private static var observers: [NSObjectProtocol] = []

    private static func listen() {
        guard observers.isEmpty else { return }
        let c = NotificationCenter.default
        observers.append(c.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { n in
            let text = n.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            let ok = n.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool ?? true
            guard let cur = current, text == currentSpoken else { return }
            current = nil
            // انقطع قبل ما يكمل: نرجعه أول الطابور (لين مرتين)
            if !ok && retries < 2 { retries += 1; queue.insert(cur, at: 0) } else { retries = 0 }
            pump()
        })
        observers.append(c.addObserver(forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { _ in
            // تحريك المؤشر: نعطي VoiceOver وقت يقرأ العنصر (إلا لو هو انتقال بعد حركتك)
            if Date() >= skipHoldUntil { holdUntil = Date().addingTimeInterval(1.0) }
        })
    }

    /// وقت تقريبي للقراءة: احتياط لو ما وصل بلاغ الانتهاء (سخي، عشان ما نقطع إعلان لسا يُقرأ)
    private static func watchdog(_ text: String) -> TimeInterval { 1.5 + Double(text.count) * 0.12 }

    private static func pump() {
        listen()
        guard current == nil, !queue.isEmpty else { return }
        let wait = holdUntil.timeIntervalSinceNow
        if wait > 0 && Date() >= skipHoldUntil {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.05) { pump() }
            return
        }
        let item = queue.removeFirst()
        current = item
        serial += 1
        let mine = serial
        let s = NSAttributedString(string: item.text, attributes: [.accessibilitySpeechLanguage: item.lang])
        currentSpoken = s.string
        UIAccessibility.post(notification: .announcement, argument: s)
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdog(item.text)) {
            guard serial == mine, current != nil else { return }
            current = nil; retries = 0
            pump()
        }
    }

    /// النص قطع، كل قطعة بلغتها («Mohanad» بالإنجليزي ثم «10 هاص» بالعربي)
    private static func items(_ text: String) -> [Item] {
        langRuns(text).compactMap { r, l in
            let piece = String(String(text[r]).drop { $0 == ":" || $0 == "،" || $0 == "," || $0.isWhitespace })
                .trimmingCharacters(in: .whitespaces)
            return piece.contains(where: { $0.isLetter || $0.isNumber }) ? Item(text: piece, lang: l) : nil
        }
    }

    /// يُقرأ بعد ما يخلص اللي قبله
    static func announce(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        DispatchQueue.main.async {
            guard readerOn else { return }
            queue.append(contentsOf: items(text))
            pump()
        }
    }

    /// بعد ما تلعب وينتقل المؤشر لأوراقك: الإعلانات الجاية ما تنتظر قراءة العنصر اللي انتقل له المؤشر
    static func interruptNextEvents() {
        skipHoldUntil = Date().addingTimeInterval(3)
        holdUntil = .distantPast
    }

    /// أحداث اللعب: بالترتيب ورا بعض (urgent محفوظ للتوافق، الطابور نفسه يكفي)
    static func announceEvent(_ text: String, urgent: Bool = false) { announce(text) }

    /// يُقرأ الحين (ردّ إيماءة أو زر): يقطع اللي يُقرأ، والأحداث اللي تنتظر تكمل بعده
    static func announceNow(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        DispatchQueue.main.async {
            guard readerOn else { return }
            listen()
            let parts = items(text)
            guard !parts.isEmpty else { return }
            // اللي كان يُقرأ ينقطع بإرسالنا وما نعيده (أنت طلبت شي ثاني)
            current = nil; retries = 0
            holdUntil = .distantPast
            queue.insert(contentsOf: parts, at: 0)
            pump()
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
