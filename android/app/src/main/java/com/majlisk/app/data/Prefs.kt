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

    var turnChime: Boolean
        get() = sp.getBoolean("turnChime", true)
        set(v) { sp.edit().putBoolean("turnChime", v).apply() }
}
