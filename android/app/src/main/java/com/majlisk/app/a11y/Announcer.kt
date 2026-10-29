package com.majlisk.app.a11y

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.accessibility.AccessibilityManager
import java.lang.ref.WeakReference

/**
 * إعلانات قارئ الشاشة (TalkBack): تُرسل فوراً، وTalkBack يقرؤها بالترتيب.
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

    /** يُرسل لـ TalkBack فوراً، وهو يقرأ الإعلانات بالترتيب دون انتظار إضافي منا */
    fun announce(text: String) {
        if (text.isBlank()) return
        main.post {
            @Suppress("DEPRECATION")
            view.get()?.announceForAccessibility(text)
        }
    }

    /** يُقرأ الآن (ردّ إيماءة أو زر قراءة سريعة) */
    fun announceNow(text: String) = announce(text)

}
