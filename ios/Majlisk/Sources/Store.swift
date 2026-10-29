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

    /// استكمال أي شراء دُفع ولم تُسلَّم عملاته بعد (يُستدعى بعد الدخول)، ومتابعة ما يكتمل لاحقاً
    static func recover() {
        Task {
            var total = 0
            for await v in Transaction.unfinished {
                if case .verified(let t) = v, packs.contains(where: { $0.id == t.productID }) {
                    total += (try? await deliver(t)) ?? 0
                }
            }
            if total > 0 { Announcer.announce("أُضيفت \(total) عملة من شراء سابق إلى رصيدك") }
        }
        Task {
            for await v in Transaction.updates {
                if case .verified(let t) = v, packs.contains(where: { $0.id == t.productID }), let n = try? await deliver(t), n > 0 {
                    Announcer.announce("أُضيفت \(n) عملة إلى رصيدك")
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
