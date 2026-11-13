package com.majlisk.app.data

import android.content.Context
import android.content.SharedPreferences

/** إعدادات الجهاز (كتم الأصوات، نغمة الدور) */
object Prefs {
    private lateinit var sp: SharedPreferences
    lateinit var app: Context
    fun init(c: Context) { app = c.applicationContext; sp = c.getSharedPreferences("majlisk", Context.MODE_PRIVATE) }

    var muted: Boolean
        get() = sp.getBoolean("muted", false)
        set(v) { sp.edit().putBoolean("muted", v).apply() }

    /** الدردشة الكتابية: read / silent / off */
    var chatMode: String
        get() = sp.getString("chatMode", "read") ?: "read"
        set(v) { sp.edit().putString("chatMode", v).apply() }

    /** آخر طاولة كنت فيها ومتى (للرجوع لها تلقائياً إن أُغلق التطبيق وفُتح خلال دقيقة) */
    var lastTable: String?
        get() = sp.getString("lastTable", null)
        set(v) { sp.edit().putString("lastTable", v).apply() }
    var lastTableAt: Long
        get() = sp.getLong("lastTableAt", 0)
        set(v) { sp.edit().putLong("lastTableAt", v).apply() }

    /** رقم هالجوال (ثابت): الحساب يكون مسجل في جوال واحد بس */
    val deviceId: String
        get() = sp.getString("deviceId", null) ?: java.util.UUID.randomUUID().toString().also { sp.edit().putString("deviceId", it).apply() }
    /** الحساب اللي سجّل هالجوال نفسه جواله عند الخادم (عشان ما نعيدها كل ما فتحت التطبيق) */
    var claimedUid: String?
        get() = sp.getString("claimedUid", null)
        set(v) { sp.edit().putString("claimedUid", v).apply() }
    /** تشخيص: آخر حساب كان مسجل، وهل اللاعب ضغط «تسجيل الخروج» بنفسه */
    var lastUid: String?
        get() = sp.getString("lastUid", null)
        set(v) { sp.edit().putString("lastUid", v).apply() }
    var manualSignOut: Boolean
        get() = sp.getBoolean("manualSignOut", false)
        set(v) { sp.edit().putBoolean("manualSignOut", v).apply() }
    /** آخر دخول كان بحساب Google: لو ضاع الدخول بدون «تسجيل الخروج» نرجّعه تلقائياً بنفس الحساب */
    /** نافذة عرض الباقة الاحترافية: آخر مرة طلعت (ما ترجع قبل يومين) */
    var offerShownAt: Long
        get() = sp.getLong("offerShownAt", 0)
        set(v) { sp.edit().putLong("offerShownAt", v).apply() }
    /** هدية دُفعت وما تأكد تسليمها: اسم المستلم (يُكمل تسليمها عند الفتح التالي) */
    var pendingGiftTo: String?
        get() = sp.getString("pendingGiftTo", null)
        set(v) { sp.edit().putString("pendingGiftTo", v).apply() }
    var googleAuto: Boolean
        get() = sp.getBoolean("googleAuto", false)
        set(v) { sp.edit().putBoolean("googleAuto", v).apply() }

}
