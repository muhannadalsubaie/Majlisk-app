package com.majlisk.app.a11y

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.accessibility.AccessibilityManager
import java.lang.ref.WeakReference

/**
 * إعلانات قارئ الشاشة (TalkBack): بالترتيب، كل إعلان بعد ما يخلص اللي قبله.
 */
object Announcer {
    private var view = WeakReference<View>(null)
    private var manager: AccessibilityManager? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(activity: Activity) {
        view = WeakReference(activity.window.decorView)
        manager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    }

    /** هل TalkBack (أو قارئ شاشة آخر) يعمل الآن */
    val readerOn: Boolean
        get() = manager?.let { it.isEnabled && it.isTouchExplorationEnabled } ?: false

    /**
     * طابور القراءة: TalkBack أحياناً يقطع الإعلان اللي يقرؤه لما يجيه إعلان جديد،
     * فنرسل كل إعلان بعد ما يخلص اللي قبله (وقت تقريبي من طول النص) فيُقرأ كل شي بالترتيب
     */
    private val queue = ArrayDeque<String>()
    private var busyUntil = 0L
    private var scheduled = false
    /** وقت تقريبي لقراءة النص بسرعة قارئ الشاشة المعتادة */
    private fun readTime(text: String) = 350L + text.length * 55L

    private fun pump() {
        scheduled = false
        val now = System.currentTimeMillis()
        if (now < busyUntil) { scheduled = true; main.postDelayed(::pump, busyUntil - now); return }
        val next = queue.removeFirstOrNull() ?: return
        busyUntil = now + readTime(next)
        @Suppress("DEPRECATION")
        view.get()?.announceForAccessibility(next)
        if (queue.isNotEmpty()) { scheduled = true; main.postDelayed(::pump, busyUntil - now) }
    }

    /** يُقرأ بعد ما يخلص اللي قبله (ما يقطعه) */
    fun announce(text: String) {
        if (text.isBlank()) return
        main.post {
            queue.addLast(text)
            if (!scheduled) pump()
        }
    }

    /** ننقل مؤشر قارئ الشاشة بعد حركتك: إعلان حركتك القادم يقطع قراءة العنصر المنقول إليه */
    @Volatile private var interruptUntil = 0L

    /** بعد ما تلعب وينتقل المؤشر لـ«أوراقك»: أول إعلان يجي بعدها (ورقة اللاعب اللي بعدك) يقطع القراءة على طول،
     *  حتى لو تأخر اللاعب (كانت المهلة ٣ ثواني بس) */
    fun interruptNextEvents() { interruptUntil = System.currentTimeMillis() + 30_000 }

    /** إعلانات اللعب: تنتظر بعضها، إلا بعد نقل المؤشر بحركتك فتقطع قراءة العنصر الجديد */
    fun announceEvent(text: String) {
        if (System.currentTimeMillis() < interruptUntil) { interruptUntil = 0; announceNow(text) } else announce(text)
    }

    /**
     * يُقرأ الآن: يقطع ما يقرؤه TalkBack (إعلان قديم تأخر) ويقرأ الجديد مباشرة.
     * لأحداث اللعب وردود الإيماءات، فلا تتراكم القراءة خلف اللعب.
     */
    fun announceNow(text: String) {
        if (text.isBlank()) return
        main.post {
            // اللي ينتظر في الطابور قديم: الجديد يحل محله
            queue.clear()
            main.removeCallbacksAndMessages(null)
            scheduled = false
            runCatching { manager?.takeIf { it.isEnabled }?.interrupt() }
            busyUntil = System.currentTimeMillis() + readTime(text)
            @Suppress("DEPRECATION")
            view.get()?.announceForAccessibility(text)
        }
    }

}
