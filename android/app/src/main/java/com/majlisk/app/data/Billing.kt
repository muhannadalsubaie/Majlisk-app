package com.majlisk.app.data

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.queryPurchasesAsync
import com.majlisk.app.MainActivity
import com.majlisk.app.MajliskApp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.net.Api
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

data class StorePack(val id: String, val coins: Int, val bonus: Int, val price: String)

/**
 * شراء العملات (Google Play). التطبيق لا يضيف أي عملة بنفسه: يرسل إثبات الشراء للخادم،
 * والخادم يتحقق من Google مباشرة ثم يضيف العملات مرة واحدة ويستهلك الشراء.
 * أي شراء لم يكتمل تسليمه يُستكمل تلقائياً عند الفتح التالي.
 */
object Billing {
    private val PACKS = listOf(
        StorePack("coins_20", 20, 0, "3.99 ر.س"),
        StorePack("coins_70", 70, 10, "9.99 ر.س"),
        StorePack("coins_190", 190, 40, "19.99 ر.س"),
        StorePack("coins_550", 550, 150, "44.99 ر.س"),
    )

    private var pendingBuy: CompletableDeferred<Pair<BillingResult, List<Purchase>?>>? = null

    private val client: BillingClient by lazy {
        BillingClient.newBuilder(MajliskApp.instance)
            .setListener { result, purchases -> pendingBuy?.complete(result to purchases) }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build()
    }

    private suspend fun ready(): Boolean {
        if (client.isReady) return true
        return suspendCancellableCoroutine { cont ->
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (cont.isActive) cont.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }
                override fun onBillingServiceDisconnected() { if (cont.isActive) cont.resume(false) }
            })
        }
    }

    private suspend fun details(): List<ProductDetails> {
        if (!ready()) return emptyList()
        val params = QueryProductDetailsParams.newBuilder().setProductList(PACKS.map {
            QueryProductDetailsParams.Product.newBuilder().setProductId(it.id).setProductType(BillingClient.ProductType.INAPP).build()
        }).build()
        // مكتبة الفوترة 8: النتيجة تجي في QueryProductDetailsResult
        return suspendCancellableCoroutine { cont ->
            client.queryProductDetailsAsync(params) { _, result ->
                if (cont.isActive) cont.resume(result.productDetailsList.orEmpty())
            }
        }
    }

    /** الباقات بأسعارها الحقيقية من المتجر (بعملة المستخدم)، أو السعر المقترح إن تعذّر الجلب */
    suspend fun loadPacks(): List<StorePack> {
        val list = runCatching { details() }.getOrDefault(emptyList())
        return PACKS.map { p -> p.copy(price = list.find { it.productId == p.id }?.oneTimePurchaseOfferDetails?.formattedPrice ?: p.price) }
    }

    /** يسلّم الشراء للخادم. يرجع عدد العملات المضافة (0 إن سُلّم من قبل) */
    private suspend fun deliver(p: Purchase): Int {
        val r = Api.post("/purchases/verify", jsonOf("platform" to "android", "productId" to p.products.first(), "purchaseToken" to p.purchaseToken))
        return if (r.optBoolean("duplicate")) 0 else r.optInt("coins")
    }

    suspend fun buy(id: String) {
        val activity = MainActivity.current ?: return
        val pack = PACKS.first { it.id == id }
        try {
            val product = details().find { it.productId == id } ?: run { Announcer.announce("الشراء غير متاح الآن، حاول لاحقاً"); return }
            val token = Api.post("/purchases/account-token").optString("token")
            val wait = CompletableDeferred<Pair<BillingResult, List<Purchase>?>>()
            pendingBuy = wait
            val flow = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).build()))
                .setObfuscatedAccountId(token)
                .build()
            client.launchBillingFlow(activity, flow)
            val (result, purchases) = wait.await()
            when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    val p = purchases?.firstOrNull { it.products.contains(id) } ?: return
                    if (p.purchaseState == Purchase.PurchaseState.PENDING) {
                        Announcer.announce("الدفع قيد المعالجة، وستُضاف العملات عند اكتماله"); return
                    }
                    Announcer.announce("جارٍ تأكيد الشراء…")
                    val added = deliver(p)
                    val what = if (pack.bonus > 0) "${pack.coins - pack.bonus} عملة زائد ${pack.bonus} هدية" else "${pack.coins} عملة"
                    Announcer.announce(if (added > 0) "تم! أُضيف إلى رصيدك $what" else "تم تأكيد شراء $what")
                }
                BillingClient.BillingResponseCode.USER_CANCELED -> Announcer.announce("أُلغي الشراء")
                else -> Announcer.announce("تعذّر إتمام الشراء الآن")
            }
        } catch (e: Exception) {
            Announcer.announce("تعذّر إتمام الشراء الآن، لم يُخصم منك شيء أو ستُضاف العملات تلقائياً عند الفتح التالي")
        } finally {
            pendingBuy = null
        }
    }

    // ───── الباقة الاحترافية ─────
    const val PRO_SUB = "pro_monthly"
    const val PRO_GIFT = "pro_gift_1m"
    const val PRO_PRICE = "11.49 ر.س"

    private suspend fun product(id: String, type: String): ProductDetails? {
        if (!ready()) return null
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(type).build(),
        )).build()
        return suspendCancellableCoroutine { cont ->
            client.queryProductDetailsAsync(params) { _, result -> if (cont.isActive) cont.resume(result.productDetailsList.orEmpty().firstOrNull()) }
        }
    }

    /** سعر الاشتراك الشهري من المتجر (بعملة المستخدم) */
    suspend fun proPrice(): String = runCatching {
        product(PRO_SUB, BillingClient.ProductType.SUBS)?.subscriptionOfferDetails?.firstOrNull()
            ?.pricingPhases?.pricingPhaseList?.lastOrNull()?.formattedPrice
    }.getOrNull() ?: PRO_PRICE

    /** يفتح نافذة الدفع من Google، ويرجع المشتريات (أو null لو ما كمل) */
    private suspend fun launch(product: ProductDetails, offerToken: String?): Purchase? {
        val activity = MainActivity.current ?: return null
        val token = Api.post("/purchases/account-token").optString("token")
        val wait = CompletableDeferred<Pair<BillingResult, List<Purchase>?>>()
        pendingBuy = wait
        try {
            val pp = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
            if (offerToken != null) pp.setOfferToken(offerToken)
            client.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(pp.build())).setObfuscatedAccountId(token).build())
            val (result, purchases) = wait.await()
            return when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> purchases?.firstOrNull { it.products.contains(product.productId) }
                BillingClient.BillingResponseCode.USER_CANCELED -> { Announcer.announce("أُلغي الشراء"); null }
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> { Announcer.announce("أنت مشترك أصلاً"); syncPro(); null }
                else -> { Announcer.announce("تعذّر إتمام الشراء الآن"); null }
            }
        } finally { pendingBuy = null }
    }

    /** الاشتراك الشهري في الباقة الاحترافية. يرجع true لو تفعّل */
    suspend fun buyPro(): Boolean = try {
        val product = product(PRO_SUB, BillingClient.ProductType.SUBS)
        val offer = product?.subscriptionOfferDetails?.firstOrNull()?.offerToken
        if (product == null || offer == null) { Announcer.announce("الاشتراك غير متاح الآن، حاول لاحقاً"); false }
        else {
            val p = launch(product, offer)
            when {
                p == null -> false
                p.purchaseState == Purchase.PurchaseState.PENDING -> { Announcer.announce("الدفع قيد المعالجة، وتتفعل الباقة عند اكتماله"); false }
                else -> {
                    Announcer.announce("جارٍ تفعيل الباقة…")
                    val ok = Api.post("/pro/verify", jsonOf("platform" to "android", "purchaseToken" to p.purchaseToken)).optBoolean("pro")
                    Announcer.announce(if (ok) "تم! تفعّلت الباقة الاحترافية" else "تعذّر تفعيل الباقة الآن، تتفعل تلقائياً عند الفتح التالي")
                    ok
                }
            }
        }
    } catch (e: Exception) {
        Announcer.announce("تعذّر الاشتراك الآن، لو انخصم منك تتفعل الباقة تلقائياً عند الفتح التالي"); false
    }

    /** إهداء شهر من الباقة لاعب ثاني (اسم المستخدم متأكد منه قبل). يرجع true لو وصلت الهدية */
    suspend fun buyGift(username: String): Boolean = try {
        val product = product(PRO_GIFT, BillingClient.ProductType.INAPP)
        if (product == null) { Announcer.announce("الإهداء غير متاح الآن، حاول لاحقاً"); false }
        else {
            Prefs.pendingGiftTo = username
            val p = launch(product, null)
            when {
                p == null -> { Prefs.pendingGiftTo = null; false }
                p.purchaseState == Purchase.PurchaseState.PENDING -> { Announcer.announce("الدفع قيد المعالجة، وتوصل الهدية عند اكتماله"); false }
                else -> deliverGift(p, username).also { if (it) Announcer.announce("تم! وصلت الهدية إلى $username") }
            }
        }
    } catch (e: Exception) {
        Announcer.announce("تعذّر الإهداء الآن، لو انخصم منك توصل الهدية تلقائياً عند الفتح التالي"); false
    }

    private suspend fun deliverGift(p: Purchase, username: String): Boolean {
        val r = Api.post("/gift/verify", jsonOf("platform" to "android", "purchaseToken" to p.purchaseToken, "username" to username))
        val ok = r.optBoolean("ok")
        if (ok) Prefs.pendingGiftTo = null
        return ok
    }

    /** يحدّث حالة الاشتراك من Google (التجديد التلقائي والإلغاء) — عند الفتح ومن «استعادة المشتريات» */
    suspend fun syncPro(announce: Boolean = false): Boolean {
        val ok = runCatching {
            if (!ready()) return@runCatching false
            val subs = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()).purchasesList
            var pro = false
            for (p in subs) {
                if (PRO_SUB !in p.products || p.purchaseState != Purchase.PurchaseState.PURCHASED) continue
                pro = Api.post("/pro/verify", jsonOf("platform" to "android", "purchaseToken" to p.purchaseToken)).optBoolean("pro") || pro
            }
            pro
        }.getOrDefault(false)
        if (announce) Announcer.announce(if (ok) "تمت استعادة الاشتراك" else "ما لقينا اشتراك على هذا الحساب في المتجر")
        return ok
    }

    /** استكمال أي شراء دُفع ولم تُسلَّم عملاته بعد (يُستدعى بعد الدخول) */
    fun recover() {
        Session.scope.launch {
            runCatching {
                if (!ready()) return@launch
                val purchases = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()).purchasesList
                var total = 0
                for (p in purchases) {
                    if (p.purchaseState != Purchase.PurchaseState.PURCHASED || PACKS.none { it.id in p.products }) continue
                    total += runCatching { deliver(p) }.getOrDefault(0)
                }
                if (total > 0) Announcer.announce("أُضيفت $total عملة من شراء سابق إلى رصيدك")
                // هدية دُفعت وما وصلت (انقطع النت مثلاً): نكملها لنفس اللاعب
                Prefs.pendingGiftTo?.let { to ->
                    purchases.firstOrNull { PRO_GIFT in it.products && it.purchaseState == Purchase.PurchaseState.PURCHASED }?.let { p ->
                        if (runCatching { deliverGift(p, to) }.getOrDefault(false)) Announcer.announce("وصلت هديتك إلى $to")
                    }
                }
                syncPro()
            }
        }
    }
}
