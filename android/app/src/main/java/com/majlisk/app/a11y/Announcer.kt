package com.majlisk.app.a11y

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.accessibility.AccessibilityManager
import java.lang.ref.WeakReference

/**
 * إعلانات قارئ الشاشة (TalkBack): أحداث اللعب تُقرأ بالترتيب واحداً بعد الآخر،
 * وردود الإيماءات السريعة تُقرأ فوراً (تقطع ما قبلها).
 */
object Announcer {
    private var view = WeakReference<View>(null)
    private var manager: AccessibilityManager? = null
    private val main = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<String>()
    private var speaking = false

    fun attach(activity: Activity) {
        view = WeakReference(activity.window.decorView)
        manager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    }

    /** هل TalkBack (أو قارئ شاشة آخر) يعمل الآن */
    val readerOn: Boolean
        get() = manager?.let { it.isEnabled && it.isTouchExplorationEnabled } ?: false

    /** يُضاف للطابور ويُقرأ بعد ما قبله */
    fun announce(text: String) {
        if (text.isBlank()) return
        main.post {
            queue.addLast(text)
            if (!speaking) next()
        }
    }

    /** يُقرأ الآن (ردّ إيماءة أو زر قراءة سريعة) */
    fun announceNow(text: String) {
        main.post {
            queue.clear()
            speaking = false
            main.removeCallbacksAndMessages(TOKEN)
            @Suppress("DEPRECATION")
            view.get()?.announceForAccessibility(text)
        }
    }

    private val TOKEN = Any()

    private fun next() {
        val text = queue.removeFirstOrNull() ?: run { speaking = false; return }
        speaking = true
        @Suppress("DEPRECATION")
        view.get()?.announceForAccessibility(text)
        // TalkBack يقطع الإعلان السابق بالتالي: ننتظر تقديراً لمدة نطقه قبل الإعلان التالي
        val ms = (700 + text.length * 65L).coerceAtMost(6000)
        main.postAtTime({ next() }, TOKEN, android.os.SystemClock.uptimeMillis() + ms)
    }
}
