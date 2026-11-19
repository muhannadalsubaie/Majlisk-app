import UIKit

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

    private static func post(_ text: String, queued: Bool) {
        current = text
        busyUntil = Date().addingTimeInterval(readTime(text))
        let s = spokenNS(text, queued: queued) // كل جزء بلغته
        UIAccessibility.post(notification: .announcement, argument: s)
        // احتياط: لو ما وصل بلاغ الانتهاء نكمل بعد الوقت التقريبي
        let mine = text
        DispatchQueue.main.asyncAfter(deadline: .now() + readTime(text) + 0.6) {
            if current == mine { current = nil; pump() }
        }
    }

    private static func pump() {
        listen()
        guard current == nil, Date() >= busyUntil, !queue.isEmpty else { return }
        retries = 0
        // إعلاناتنا ما تقطع بعضها (ننتظر انتهاء اللي قبله بأنفسنا)، فاللودو يُرسل بدون «انتظر دورك» عند VoiceOver
        post(queue.removeFirst(), queued: !urgentQueue)
    }

    /**
     * نص فيه لغتين (اسم لاعب بالإنجليزي وسط كلام عربي): VoiceOver يقرأ الجملة كلها بصوت أول لغة،
     * فينقرأ الكرت بالإنجليزي. نقسمه قطع، كل قطعة بلغتها، وتنقرأ ورا بعض
     */
    private static func pieces(_ text: String) -> [String] {
        let runs = langRuns(text)
        guard runs.count > 1 else { return [text] }
        return runs.map { String(text[$0.0]) }.filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    /// يُقرأ بعد ما يخلص اللي قبله (ما يقطعه)
    static func announce(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        DispatchQueue.main.async {
            queue.append(contentsOf: pieces(text))
            pump()
        }
    }

    /// ننقل مؤشر VoiceOver بعد حركتك: إعلان حركتك القادم يقطع قراءة العنصر المنقول إليه
    private static var interruptUntil = Date.distantPast

    /// بعد ما تلعب وينتقل المؤشر لـ«أوراقك»: أول إعلان يجي بعدها (ورقة اللاعب اللي بعدك) يقطع القراءة على طول،
    /// حتى لو تأخر اللاعب (كانت المهلة ٣ ثواني بس فيروح الإعلان بالطابور ورا قراءة المؤشر)
    static func interruptNextEvents() { interruptUntil = Date().addingTimeInterval(30) }

    /// إعلانات اللعب: تنتظر بعضها، إلا بعد نقل المؤشر بحركتك فتقطع قراءة العنصر الجديد
    static func announceEvent(_ text: String, urgent: Bool = false) {
        DispatchQueue.main.async {
            urgentQueue = urgent
            if Date() < interruptUntil { interruptUntil = .distantPast; announceNow(text) } else { announce(text) }
        }
    }

    /// يُقرأ الآن (ردّ إيماءة أو زر قراءة سريعة): يقطع القديم، واللي ينتظر في الطابور قديم فينمسح
    static func announceNow(_ text0: String) {
        guard !text0.isEmpty else { return }
        let text = tr(text0)
        DispatchQueue.main.async {
            listen()
            // لغتين: أول قطعة الحين (تقطع القديم)، والباقي ورا بعض بعدها
            var parts = pieces(text)
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
