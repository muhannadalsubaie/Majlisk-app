import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import UIKit

/// ملف اللاعب: يُقرأ مباشرة من Firestore (الكتابة من الخادم فقط)
struct Profile: Equatable {
    var username = ""
    /// nil حتى يُنشئ الخادم ملف اللاعب
    var coins: Int? = nil
    var loaded = false
    var unlimited = false
}

/// المستخدم الحالي ورصيده، ويتحدثان فور أي تغيير
@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    @Published private(set) var uid: String? = Auth.auth().currentUser?.uid
    @Published private(set) var profile: Profile? = nil
    /// حساب جديد بالبريد لم يضغط رابط التحقق بعد
    @Published private(set) var needsVerify = false
    private var doc: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.changed(user) }
        }
    }

    private func changed(_ user: User?) {
        if user?.uid == uid && doc != nil { return }
        uid = user?.uid
        doc?.remove()
        doc = nil
        guard let user else { profile = nil; needsVerify = false; return }
        needsVerify = AuthService.needsVerification(user)
        profile = Profile()
        // الخادم ينشئ ملف اللاعب مع العملات الترحيبية عند أول دخول، ويمنح الهدايا لمرة واحدة
        Task {
            if let r = try? await Api.post("/profile/ensure"), r.int("gift") > 0 {
                Announcer.announce("هدية: أُضيفت \(r.int("gift")) عملة إلى رصيدك")
            }
        }
        doc = Firestore.firestore().collection("users").document(user.uid).addSnapshotListener { [weak self] snap, _ in
            guard let snap else { return }
            let d = snap.data() ?? [:]
            self?.profile = Profile(
                username: d["username"] as? String ?? "",
                coins: (d["coins"] as? NSNumber)?.intValue,
                loaded: snap.exists,
                unlimited: d["unlimited"] as? Bool == true
            )
        }
    }

    func markVerified() { needsVerify = false }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }
}

/// نفس قواعد أسماء المستخدمين في الخادم (shared/username.ts) — القرار النهائي في الخادم
enum Usernames {
    static let min = 3, max = 16
    static let errors: [String: String] = [
        "too-short": "اسم المستخدم قصير — 3 أحرف على الأقل",
        "too-long": "اسم المستخدم طويل — 16 حرفاً كحد أقصى",
        "invalid-chars": "استخدم حروفاً عربية أو إنجليزية أو أرقاماً أو _ فقط، بدون مسافات",
        "only-underscores": "يجب أن يحتوي اسم المستخدم على حرف أو رقم",
        "taken": "اسم المستخدم مأخوذ، جرّب اسماً آخر",
        "already-set": "لديك اسم مستخدم مسبقاً",
    ]

    static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\x{064B}-\\x{065F}\\x{0670}\\x{0640}]", with: "", options: .regularExpression)
    }

    static func validate(_ raw: String) -> String? {
        let name = clean(raw)
        let n = name.unicodeScalars.count
        if n < min { return "too-short" }
        if n > max { return "too-long" }
        if name.range(of: "^[\\x{0621}-\\x{063A}\\x{0641}-\\x{064A}a-zA-Z0-9\\x{0660}-\\x{0669}_]+$", options: .regularExpression) == nil { return "invalid-chars" }
        if name.allSatisfy({ $0 == "_" }) { return "only-underscores" }
        return nil
    }
}

/// تسجيل الدخول: البريد، وGoogle، وApple
@MainActor
enum AuthService {
    static func signIn(email: String, password: String) async throws {
        if password.isEmpty { throw ApiError(code: "missing-password") }
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    static func signUp(username: String, email: String, password: String) async throws {
        if let invalid = Usernames.validate(username) { throw ApiError(code: invalid) }
        if password.isEmpty { throw ApiError(code: "missing-password") }
        // فحص مبدئي قبل إنشاء الحساب؛ الحجز الفعلي الذرّي يتم بعده في الخادم
        let check = try await Api.postPublic("/username/available", ["username": username])
        if !check.bool("available") { throw ApiError(code: check.str("error", "taken")) }
        try await Auth.auth().createUser(withEmail: email, password: password)
        await sendVerification()
        // إن فشل الحجز هنا (سباق نادر) تظهر شاشة اختيار الاسم تلقائياً
        _ = try? await Api.post("/profile/username", ["username": username])
    }

    /// نافذة حساب Google، ثم الدخول بنفس الحساب في Firebase
    static func google() async throws {
        guard let vc = topViewController(), let clientID = FirebaseApp.app()?.options.clientID else { throw ApiError(code: "cancelled") }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result: GIDSignInResult
        do { result = try await GIDSignIn.sharedInstance.signIn(withPresenting: vc) } catch { throw ApiError(code: "cancelled") }
        guard let idToken = result.user.idToken?.tokenString else { throw ApiError(code: "cancelled") }
        let cred = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        try await Auth.auth().signIn(with: cred)
    }

    /// الدخول بحساب Apple (نافذة النظام الأصلية)
    static func apple() async throws {
        let nonce = randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        let auth = try await AppleSignIn().run(request)
        guard let tokenData = auth.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { throw ApiError(code: "cancelled") }
        let cred = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: auth.fullName)
        try await Auth.auth().signIn(with: cred)
    }

    /// الحسابات الجديدة بالبريد (من بعد إضافة هذه الخطوة) تتحقق من بريدها برابط قبل الدخول
    private static let verifySince = Date(timeIntervalSince1970: 1_793_318_400)

    static func needsVerification(_ u: User) -> Bool {
        !u.isEmailVerified && u.providerData.contains { $0.providerID == "password" } && (u.metadata.creationDate ?? .distantPast) >= verifySince
    }

    static func sendVerification() async {
        Auth.auth().languageCode = "ar"
        try? await Auth.auth().currentUser?.sendEmailVerification()
    }

    /// يحدّث حالة الحساب من Firebase: هل ضغط رابط التحقق؟
    static func checkVerified() async -> Bool {
        guard let u = Auth.auth().currentUser else { return false }
        try? await u.reload()
        let ok = Auth.auth().currentUser?.isEmailVerified == true
        // توكن جديد حتى يعرف الخادم أن البريد موثّق
        if ok { _ = try? await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true) }
        return ok
    }

    static func resetPassword(_ email: String) async throws {
        if email.isEmpty { throw ApiError(code: "ERROR_INVALID_EMAIL") }
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    private static func randomNonce() -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<32).map { _ in chars.randomElement()! })
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// غلاف async لنافذة Apple
private final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var keep: AppleSignIn?

    @MainActor
    func run(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { c in
            cont = c
            keep = self
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential { cont?.resume(returning: cred) }
        else { cont?.resume(throwing: ApiError(code: "cancelled")) }
        cont = nil; keep = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        cont?.resume(throwing: ApiError(code: "cancelled"))
        cont = nil; keep = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        topViewController()?.view.window ?? UIWindow()
    }
}

/// رسالة خطأ الدخول بالعربي
func authMessage(_ e: Error) -> String {
    let errors: [String: String] = [
        "missing-password": "أدخل كلمة المرور",
        "cancelled": "تم إغلاق نافذة الدخول",
        "network": "تعذّر الاتصال بالإنترنت",
        "ERROR_INVALID_EMAIL": "البريد الإلكتروني غير صالح",
    ]
    if let api = e as? ApiError { return errors[api.code] ?? Usernames.errors[api.code] ?? "حدث خطأ، حاول مرة أخرى" }
    let ns = e as NSError
    if ns.domain == "FIRAuthErrorDomain", let code = AuthErrorCode(rawValue: ns.code) {
        switch code {
        case .invalidCredential, .wrongPassword, .userNotFound: return "البريد أو كلمة المرور غير صحيحة"
        case .invalidEmail: return "البريد الإلكتروني غير صالح"
        case .emailAlreadyInUse: return "هذا البريد مسجّل مسبقاً، سجّل الدخول بدلاً من ذلك"
        case .weakPassword: return "كلمة المرور قصيرة — 6 أحرف على الأقل"
        case .tooManyRequests: return "محاولات كثيرة، حاول بعد قليل"
        case .operationNotAllowed: return "طريقة الدخول هذه غير مفعّلة بعد"
        case .accountExistsWithDifferentCredential: return "بريد هذا الحساب مسجّل بطريقة دخول أخرى، ادخل بها"
        case .networkError: return "تعذّر الاتصال بالإنترنت"
        default: break
        }
    }
    return "حدث خطأ، حاول مرة أخرى"
}
