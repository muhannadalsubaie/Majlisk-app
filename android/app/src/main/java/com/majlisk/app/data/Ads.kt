package com.majlisk.app.data

import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.gms.ads.rewarded.ServerSideVerificationOptions
import com.google.firebase.auth.FirebaseAuth
import com.majlisk.app.BuildConfig
import com.majlisk.app.MainActivity
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.net.Api
import kotlinx.coroutines.launch

/**
 * إعلان بمكافأة: Google تبلغ الخادم مباشرة (موقّعاً) بعد مشاهدة الإعلان كاملاً،
 * والخادم يضيف العملتين — التطبيق لا يضيف شيئاً بنفسه.
 */
object Ads {
    private var initialized = false

    fun watch() {
        val activity = MainActivity.current ?: return
        Session.scope.launch {
            val left = runCatching { Api.post("/ads/status").optInt("left", 1) }.getOrElse {
                Announcer.announce("تعذّر عرض الإعلان الآن، حاول بعد قليل"); return@launch
            }
            if (left <= 0) { Announcer.announce("وصلت للحد اليومي من الإعلانات، جرّب غداً"); return@launch }
            if (!initialized) { MobileAds.initialize(activity) {}; initialized = true }
            Announcer.announce("جارٍ تحميل الإعلان")
            RewardedAd.load(activity, BuildConfig.ADMOB_REWARDED, AdRequest.Builder().build(), object : RewardedAdLoadCallback() {
                override fun onAdFailedToLoad(error: LoadAdError) {
                    Announcer.announce("لا يوجد إعلان متاح الآن، حاول بعد قليل")
                }

                override fun onAdLoaded(ad: RewardedAd) {
                    val uid = FirebaseAuth.getInstance().currentUser?.uid.orEmpty()
                    ad.setServerSideVerificationOptions(ServerSideVerificationOptions.Builder().setUserId(uid).build())
                    Announcer.announce("جارٍ عرض الإعلان")
                    ad.show(activity) { Announcer.announce("انتهى الإعلان، ستُضاف عملتان إلى رصيدك خلال لحظات") }
                }
            })
        }
    }
}
