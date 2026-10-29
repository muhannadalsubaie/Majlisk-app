import UIKit
import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        Sounds.shared.preload()
        return true
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
        let root = AppRoot()
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
@MainActor func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = vc?.presentedViewController { vc = presented }
    return vc
}
