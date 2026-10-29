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
import com.android.billingclient.api.queryProductDetails
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
        return client.queryProductDetails(params).productDetailsList.orEmpty()
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
            }
        }
    }
}
