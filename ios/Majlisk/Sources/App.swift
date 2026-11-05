import UIKit
import SwiftUI
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        Push.shared.configure()
        Sounds.shared.preload()
        Sounds.shared.appOpen()
        return true
    }

    /// رمز Apple للإشعارات: نسلّمه لـ Firebase بنفسنا (بدل الربط التلقائي)، ونرسل رمز الجهاز للخادم
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Push.shared.refreshToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push register failed: \(error)")
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// إيماءات القراءة السريعة: مع VoiceOver، السحب بثلاث أصابع يصل للتطبيق كطلب تمرير (accessibilityScroll)
/// حين لا يكون في الشاشة ما يُمرَّر في ذلك الاتجاه. النافذة آخر من يستلمه، فنحوّله لحدث تقرؤه الطاولة.
/// اتجاه الحدث = اتجاه حركة الأصابع: left = من اليمين لليسار، right = من اليسار لليمين، up = من تحت لفوق.
final class MajliskWindow: UIWindow {
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let dir: SwipeDir
        switch direction {
        case .left: dir = .left
        case .right: dir = .right
        case .up: dir = .up
        case .down: dir = .down
        default: return false
        }
        return Gestures.shared.fire(dir)
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = MajliskWindow(windowScene: windowScene)
        // التطبيق عربي بالكامل: من اليمين لليسار دائماً، مهما كانت لغة الجهاز
        let root = RootOrDemo()
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = UIColor(Palette.green900)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for ctx in URLContexts { _ = GIDSignIn.sharedInstance.handle(ctx.url) }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        NotificationCenter.default.post(name: .appForeground, object: nil)
    }
}

extension Notification.Name {
    static let appForeground = Notification.Name("majlisk.foreground")
}

/// الشاشة الحالية (للإعلانات وتسجيل الدخول التي تحتاج من يعرضها)
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
}


/// الجذر: التطبيق، أو (في نسخة التطوير فقط) طاولة تجريبية لصور الشاشات: -demoTable domino|jackaroo|ludo
struct RootOrDemo: View {
    var body: some View {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoTable"), i + 1 < ProcessInfo.processInfo.arguments.count {
            DemoTable(name: ProcessInfo.processInfo.arguments[i + 1])
        } else { AppRoot() }
        #else
        AppRoot()
        #endif
    }
}

#if DEBUG
/// طاولة من حالة لعب محفوظة (Media/demo) بنفس ترتيب شاشة الطاولة — لصور الشاشات فقط
struct DemoTable: View {
    let name: String
    @StateObject private var conn = TableConnection("demo")
    var body: some View {
        if let path = Bundle.main.path(forResource: name, ofType: "json", inDirectory: "Media/demo"),
           let data = FileManager.default.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? JSON {
            let v = TableView(json)
            Screen(fill: true) {
                HStack(spacing: 8) {
                    SmallButton("القائمة") {}
                    Text("طاولة \(v.title)\(v.ownerName.isEmpty ? "" : " — المالك \(v.ownerName)")").foregroundColor(Palette.textDim).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let d = v.domino { DominoBoard(v: v, d: d, conn: conn, isOwner: true) {} }
                else if let j = v.jackaroo { JackarooBoard(v: v, j: j, conn: conn, isOwner: true) }
                else if let l = v.ludo { LudoBoard(v: v, l: l, conn: conn, isOwner: true) }
                Spacer(minLength: 0)
                if let d = v.domino { DominoHand(v: v, d: d, conn: conn) }
                HStack { Spacer(); ChatButton(conn: conn) {} }
                HStack { Spacer(); VoiceButton(tableId: v.id, uid: "u1") }
            }
        } else {
            Text("demo not found: \(name)")
        }
    }
}
#endif
