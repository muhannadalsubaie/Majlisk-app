package com.majlisk.app.data

import android.content.Context
import android.content.SharedPreferences

/** إعدادات الجهاز (كتم الأصوات، نغمة الدور) */
object Prefs {
    private lateinit var sp: SharedPreferences
    fun init(c: Context) { sp = c.getSharedPreferences("majlisk", Context.MODE_PRIVATE) }

    var muted: Boolean
        get() = sp.getBoolean("muted", false)
        set(v) { sp.edit().putBoolean("muted", v).apply() }

    /** آخر طاولة كنت فيها ومتى (للرجوع لها تلقائياً إن أُغلق التطبيق وفُتح خلال دقيقة) */
    var lastTable: String?
        get() = sp.getString("lastTable", null)
        set(v) { sp.edit().putString("lastTable", v).apply() }
    var lastTableAt: Long
        get() = sp.getLong("lastTableAt", 0)
        set(v) { sp.edit().putLong("lastTableAt", v).apply() }

}
