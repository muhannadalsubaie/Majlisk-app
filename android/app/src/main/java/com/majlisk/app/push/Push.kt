package com.majlisk.app.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.majlisk.app.data.Session
import com.majlisk.app.net.Api
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * إشعارات الجوال لدعوات الأصدقاء: تصل حتى لو التطبيق مقفل، والضغط عليها يدخلك الطاولة مباشرة.
 * رمز الجهاز يُرسل للخادم بعد تسجيل الدخول (وكل ما تغيّر).
 */
object Push {
    /** طاولة من إشعار دعوة ضغطت عليه: الشاشة الرئيسية تقبل الدعوة وتفتح الطاولة */
    val pendingTable = MutableStateFlow<String?>(null)
    /** انتقال من طاولة لطاولة صديق (من قائمة الأصدقاء داخل الطاولة): الشاشة الرئيسية تفتحها */
    val switchTable = MutableStateFlow<String?>(null)

    /** قناة الإشعارات بصوت التطبيق. صوت القناة ما يتغير بعد إنشائها، فالقناة الجديدة باسم جديد والقديمة تنحذف */
    const val CHANNEL = "invites2"

    fun createChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val sound = android.net.Uri.parse("android.resource://${ctx.packageName}/${com.majlisk.app.R.raw.notify}")
        val attrs = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "دعوات اللعب", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "لما يدعوك صديق للعب"
            setSound(sound, attrs)
        })
        // القناة القديمة (بصوت الجوال الافتراضي)
        runCatching { nm.deleteNotificationChannel("invites") }
    }

    /** يرسل رمز هذا الجهاز للخادم (بعد تسجيل الدخول) */
    fun register() {
        if (FirebaseAuth.getInstance().currentUser == null) return
        runCatching {
            FirebaseMessaging.getInstance().token.addOnSuccessListener { token -> upload(token) }
        }
    }

    fun upload(token: String) {
        if (FirebaseAuth.getInstance().currentUser == null) return
        Session.scope.launch { runCatching { Api.post("/profile/push-token", jsonOf("token" to token)) } }
    }

    /** إشعار دعوة ضغط عليه المستخدم (من بيانات النية) */
    fun fromIntent(extras: android.os.Bundle?) {
        val id = extras?.getString("tableId") ?: return
        if (extras.getString("type") == "invite" && Regex("^[0-9a-f]{64}$").matches(id)) pendingTable.value = id
    }
}

class MajliskMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = Push.upload(token)

    /** والتطبيق مفتوح: الدعوة تظهر داخل التطبيق من الخادم مباشرة، فما نكرر الإشعار */
    override fun onMessageReceived(message: RemoteMessage) {}
}
