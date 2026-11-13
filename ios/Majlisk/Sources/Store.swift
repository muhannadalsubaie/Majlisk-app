import Foundation
import StoreKit
import GoogleMobileAds
import FirebaseAuth

struct StorePack: Identifiable { let id: String; let coins: Int; let bonus: Int; var price: String }

/**
 * شراء العملات (App Store). التطبيق لا يضيف أي عملة بنفسه: يرسل رقم العملية للخادم،
 * والخادم يتحقق من Apple مباشرة ثم يضيف العملات مرة واحدة. أي شراء لم يكتمل تسليمه يُستكمل عند الفتح التالي.
 */
enum Store {
    static let packs = [
        StorePack(id: "coins_20", coins: 20, bonus: 0, price: "3.99 ر.س"),
        StorePack(id: "coins_70", coins: 70, bonus: 10, price: "9.99 ر.س"),
        StorePack(id: "coins_190", coins: 190, bonus: 40, price: "19.99 ر.س"),
        StorePack(id: "coins_550", coins: 550, bonus: 150, price: "44.99 ر.س"),
    ]

    /// الباقات بأسعارها الحقيقية من المتجر (بعملة المستخدم)، أو السعر المقترح إن تعذّر الجلب
    static func loadPacks() async -> [StorePack] {
        let products = (try? await Product.products(for: packs.map(\.id))) ?? []
        return packs.map { p in
            var x = p
            if let prod = products.first(where: { $0.id == p.id }) { x.price = prod.displayPrice }
            return x
        }
    }

    /// يسلّم الشراء للخادم، ثم ينهيه في المتجر. يرجع عدد العملات المضافة (0 إن سُلّم من قبل)
    private static func deliver(_ t: Transaction) async throws -> Int {
        let r = try await Api.post("/purchases/verify", ["platform": "ios", "productId": t.productID, "transactionId": String(t.id)])
        await t.finish()
        return r.bool("duplicate") ? 0 : r.int("coins")
    }

    static func buy(_ id: String) async {
        guard let pack = packs.first(where: { $0.id == id }) else { return }
        do {
            guard let product = try await Product.products(for: [id]).first else { Announcer.announce("الشراء غير متاح الآن، حاول لاحقاً"); return }
            let token = try await Api.post("/purchases/account-token").str("token")
            var options: Set<Product.PurchaseOption> = []
            if let uuid = UUID(uuidString: token) { options.insert(.appAccountToken(uuid)) }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let t) = verification else { Announcer.announce("تعذّر التحقق من الشراء"); return }
                Announcer.announce("جارٍ تأكيد الشراء…")
                let added = try await deliver(t)
                let what = pack.bonus > 0 ? "\(pack.coins - pack.bonus) عملة زائد \(pack.bonus) هدية" : "\(pack.coins) عملة"
                Announcer.announce(added > 0 ? "تم! أُضيف إلى رصيدك \(what)" : "تم تأكيد شراء \(what)")
            case .userCancelled: Announcer.announce("أُلغي الشراء")
            case .pending: Announcer.announce("الدفع قيد المعالجة، وستُضاف العملات عند اكتماله")
            @unknown default: Announcer.announce("تعذّر إتمام الشراء الآن")
            }
        } catch {
            Announcer.announce("تعذّر إتمام الشراء الآن، لم يُخصم منك شيء أو ستُضاف العملات تلقائياً عند الفتح التالي")
        }
    }

    // ───── الباقة الاحترافية ─────
    static let proSub = "pro_monthly"
    static let proGift = "pro_gift_1m"
    static let proPriceFallback = "11.49 ر.س"

    /// سعر الاشتراك الشهري من المتجر (بعملة المستخدم)
    static func proPrice() async -> String {
        (try? await Product.products(for: [proSub]).first?.displayPrice) ?? proPriceFallback
    }

    private static func purchaseOptions() async throws -> Set<Product.PurchaseOption> {
        let token = try await Api.post("/purchases/account-token").str("token")
        var options: Set<Product.PurchaseOption> = []
        if let uuid = UUID(uuidString: token) { options.insert(.appAccountToken(uuid)) }
        return options
    }

    /// يسلّم الاشتراك للخادم (يحفظ تاريخ نهايته) ثم ينهيه في المتجر
    @discardableResult
    private static func deliverSub(_ t: Transaction) async throws -> Bool {
        let r = try await Api.post("/pro/verify", ["platform": "ios", "transactionId": String(t.id)])
        await t.finish()
        return r.bool("pro")
    }

    private static func deliverGift(_ t: Transaction, to username: String) async throws -> Bool {
        let r = try await Api.post("/gift/verify", ["platform": "ios", "transactionId": String(t.id), "username": username])
        let ok = r.bool("ok")
        if ok { await t.finish(); Prefs.pendingGiftTo = nil }
        return ok
    }

    /// الاشتراك الشهري في الباقة الاحترافية. يرجع true لو تفعّل
    static func buyPro() async -> Bool {
        do {
            guard let product = try await Product.products(for: [proSub]).first else { Announcer.announce("الاشتراك غير متاح الآن، حاول لاحقاً"); return false }
            switch try await product.purchase(options: try await purchaseOptions()) {
            case .success(let v):
                guard case .verified(let t) = v else { Announcer.announce("تعذّر التحقق من الشراء"); return false }
                Announcer.announce("جارٍ تفعيل الباقة…")
                let ok = try await deliverSub(t)
                Announcer.announce(ok ? "تم! تفعّلت الباقة الاحترافية" : "تعذّر تفعيل الباقة الآن، تتفعل تلقائياً عند الفتح التالي")
                return ok
            case .userCancelled: Announcer.announce("أُلغي الشراء"); return false
            case .pending: Announcer.announce("الدفع قيد المعالجة، وتتفعل الباقة عند اكتماله"); return false
            @unknown default: return false
            }
        } catch {
            Announcer.announce("تعذّر الاشتراك الآن، لو انخصم منك تتفعل الباقة تلقائياً عند الفتح التالي")
            return false
        }
    }

    /// إهداء شهر من الباقة لاعب ثاني (اسم المستخدم متأكد منه قبل). يرجع true لو وصلت الهدية
    static func buyGift(to username: String) async -> Bool {
        do {
            guard let product = try await Product.products(for: [proGift]).first else { Announcer.announce("الإهداء غير متاح الآن، حاول لاحقاً"); return false }
            Prefs.pendingGiftTo = username
            switch try await product.purchase(options: try await purchaseOptions()) {
            case .success(let v):
                guard case .verified(let t) = v else { Announcer.announce("تعذّر التحقق من الشراء"); return false }
                let ok = try await deliverGift(t, to: username)
                if ok { Announcer.announce("تم! وصلت الهدية إلى \(username)") }
                return ok
            case .userCancelled: Prefs.pendingGiftTo = nil; Announcer.announce("أُلغي الشراء"); return false
            case .pending: Announcer.announce("الدفع قيد المعالجة، وتوصل الهدية عند اكتماله"); return false
            @unknown default: return false
            }
        } catch {
            Announcer.announce("تعذّر الإهداء الآن، لو انخصم منك توصل الهدية تلقائياً عند الفتح التالي")
            return false
        }
    }

    /// يحدّث حالة الاشتراك (التجديد التلقائي والإلغاء) — عند الفتح ومن «استعادة المشتريات»
    @discardableResult
    static func syncPro(announce: Bool = false) async -> Bool {
        if announce { try? await AppStore.sync() }
        var pro = false
        for await v in Transaction.currentEntitlements {
            if case .verified(let t) = v, t.productID == proSub {
                pro = ((try? await deliverSub(t)) ?? false) || pro
            }
        }
        if announce { Announcer.announce(pro ? "تمت استعادة الاشتراك" : "ما لقينا اشتراك على هذا الحساب في المتجر") }
        return pro
    }

    /// يسلّم أي شراء: عملات، أو هدية (للاعب المحفوظ اسمه)، أو تجديد اشتراك
    private static func handle(_ t: Transaction) async -> Int {
        if packs.contains(where: { $0.id == t.productID }) { return (try? await deliver(t)) ?? 0 }
        if t.productID == proSub { _ = try? await deliverSub(t); return 0 }
        if t.productID == proGift, let to = Prefs.pendingGiftTo, (try? await deliverGift(t, to: to)) == true {
            Announcer.announce("وصلت هديتك إلى \(to)")
        }
        return 0
    }

    /// استكمال أي شراء دُفع ولم يُسلَّم بعد (يُستدعى بعد الدخول)، ومتابعة ما يكتمل لاحقاً (ومنها تجديد الاشتراك)
    static func recover() {
        Task {
            var total = 0
            for await v in Transaction.unfinished {
                if case .verified(let t) = v { total += await handle(t) }
            }
            if total > 0 { Announcer.announce("أُضيفت \(total) عملة من شراء سابق إلى رصيدك") }
            await syncPro()
        }
        Task {
            for await v in Transaction.updates {
                if case .verified(let t) = v {
                    let n = await handle(t)
                    if n > 0 { Announcer.announce("أُضيفت \(n) عملة إلى رصيدك") }
                }
            }
        }
    }
}

/**
 * إعلان بمكافأة: Google تبلغ الخادم مباشرة (موقّعاً) بعد مشاهدة الإعلان كاملاً،
 * والخادم يضيف العملتين — التطبيق لا يضيف شيئاً بنفسه.
 */
enum Ads {
    static let unit = "ca-app-pub-4779146366215281/7054564670"
    private static var started = false
    private static var current: RewardedAd?

    static func watch() {
        Task { @MainActor in
            guard let status = try? await Api.post("/ads/status") else { Announcer.announce("تعذّر عرض الإعلان الآن، حاول بعد قليل"); return }
            if status.int("left", 1) <= 0 { Announcer.announce("وصلت للحد اليومي من الإعلانات، جرّب غداً"); return }
            if !started { await MobileAds.shared.start(); started = true }
            Announcer.announce("جارٍ تحميل الإعلان")
            do {
                let ad = try await RewardedAd.load(with: unit, request: Request())
                let ssv = ServerSideVerificationOptions()
                ssv.userIdentifier = Auth.auth().currentUser?.uid
                ad.serverSideVerificationOptions = ssv
                current = ad
                guard let vc = topViewController() else { return }
                ad.present(from: vc) {
                    Announcer.announce("انتهى الإعلان، ستُضاف عملتان إلى رصيدك خلال لحظات")
                }
            } catch {
                Announcer.announce("لا يوجد إعلان متاح الآن، حاول بعد قليل")
            }
        }
    }
}
