import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseMessaging

/// إشعارات الجوال لدعوات الأصدقاء: تصل حتى لو التطبيق مقفل، والضغط عليها يدخلك الطاولة مباشرة.
/// رمز الجهاز يُرسل للخادم بعد تسجيل الدخول (وكل ما تغيّر).
final class Push: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = Push()
    /// طاولة من إشعار دعوة ضغطت عليه: الشاشة الرئيسية تقبل الدعوة وتفتح الطاولة
    @Published var pendingTable: String?
    /// انتقال من طاولة لطاولة صديق (من قائمة الأصدقاء داخل الطاولة): الشاشة الرئيسية تفتحها
    @Published var switchTable: String?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// بعد تسجيل الدخول: نطلب الإذن (مرة)، ونسجّل الجهاز للإشعارات
    func register() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        refreshToken()
    }

    /// رمز الجهاز للإشعارات (يتطلب رمز Apple أولاً): يُرسل للخادم كل مرة
    func refreshToken() {
        guard Messaging.messaging().apnsToken != nil else { return }
        Messaging.messaging().token { token, _ in if let token { self.upload(token) } }
    }

    private func upload(_ token: String) {
        guard Auth.auth().currentUser != nil else { return }
        Task { _ = try? await Api.post("/profile/push-token", ["token": token]) }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken { upload(fcmToken) }
    }

    /// والتطبيق مفتوح: الدعوة تظهر داخل التطبيق من الخادم مباشرة، فما نكرر الإشعار
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }

    /// ضغط على إشعار دعوة
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard info["type"] as? String == "invite", let id = info["tableId"] as? String,
              id.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return }
        await MainActor.run { self.pendingTable = id }
    }
}
