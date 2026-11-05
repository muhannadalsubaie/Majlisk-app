package com.majlisk.app.a11y

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * وين مؤشر قارئ الشاشة الحين: نراقب أحداث TalkBack اللي يرسلها التطبيق (انتقال المؤشر لعنصر)،
 * ونحفظ اسم العنصر اللي انتقل له. تستخدمه شاشة البلوت: الورقة اللي لعبتها تبقى مكانها (مخفية)
 * والمؤشر عليها بصمت، وأول ما تحرك المؤشر لأي عنصر ثاني تختفي.
 */
object A11yFocus {
    /** (اسم العنصر اللي عليه المؤشر، رقم يزيد مع كل انتقال) */
    val moved = MutableStateFlow<Pair<String, Long>>("" to 0L)

    fun attach(activity: Activity) {
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        root.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onRequestSendAccessibilityEvent(host: ViewGroup, child: View, event: AccessibilityEvent): Boolean {
                if (event.eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) {
                    val label = event.contentDescription?.toString()?.takeIf { it.isNotBlank() } ?: event.text.joinToString(" ")
                    moved.value = label to (moved.value.second + 1)
                }
                return super.onRequestSendAccessibilityEvent(host, child, event)
            }
        }
    }
}
