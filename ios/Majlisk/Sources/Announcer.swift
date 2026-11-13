import UIKit

/// إعلانات VoiceOver: أحداث اللعب تُصفّ وتُقرأ بالترتيب، وردود الإيماءات السريعة تُقرأ فوراً.
enum Announcer {
    static var readerOn: Bool { UIAccessibility.isVoiceOverRunning }

    /// يُضاف لطابور VoiceOver ويُقرأ بعد ما قبله
    static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            let s = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
            UIAccessibility.post(notification: .announcement, argument: s)
        }
    }

    /// ننقل مؤشر VoiceOver بعد حركتك: إعلان حركتك القادم يقطع قراءة العنصر المنقول إليه
    private static var interruptUntil = Date.distantPast

    /// بعد ما تلعب وينتقل المؤشر لـ«أوراقك»: أول إعلان يجي بعدها (ورقة اللاعب اللي بعدك) يقطع القراءة على طول،
    /// حتى لو تأخر اللاعب (كانت المهلة ٣ ثواني بس فيروح الإعلان بالطابور ورا قراءة المؤشر)
    static func interruptNextEvents() { interruptUntil = Date().addingTimeInterval(30) }

    /// إعلانات اللعب: تنتظر بعضها، إلا بعد نقل المؤشر بحركتك فتقطع قراءة العنصر الجديد
    static func announceEvent(_ text: String) {
        DispatchQueue.main.async {
            if Date() < interruptUntil { interruptUntil = .distantPast; announceNow(text) } else { announce(text) }
        }
    }

    /// يُقرأ الآن (ردّ إيماءة أو زر قراءة سريعة)
    static func announceNow(_ text: String) {
        DispatchQueue.main.async {
            let s = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: false])
            UIAccessibility.post(notification: .announcement, argument: s)
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
