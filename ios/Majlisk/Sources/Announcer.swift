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

    static func interruptNextEvents() { interruptUntil = Date().addingTimeInterval(3) }

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
    func fire(_ dir: SwipeDir) -> Bool { handler?(dir) ?? false }
}

/// إعدادات الجهاز (كتم الأصوات، نغمة الدور)
enum Prefs {
    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
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
    static var turnChime: Bool {
        get { UserDefaults.standard.object(forKey: "turnChime") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "turnChime") }
    }
}
