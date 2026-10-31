package com.majlisk.app.voice

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.majlisk.app.MainActivity

/**
 * من يحتاج يبقى التطبيق شغال في الخلفية: الطاولة (أصوات اللعب والاتصال بلا تقطيع) والمحادثة الصوتية.
 * الخدمة تشتغل ما دام فيه أحد منهم، وتتوقف لما يخلصون كلهم.
 */
object KeepAlive {
    private var table = false
    private var voice = false
    private var mic = false

    fun table(on: Boolean) { table = on; update() }
    fun voice(on: Boolean, withMic: Boolean) { voice = on; mic = on && withMic; update() }

    private fun update() {
        val ctx = com.majlisk.app.MajliskApp.instance
        val i = Intent(ctx, VoiceService::class.java).putExtra("mic", mic).putExtra("voice", voice)
        runCatching { if (table || voice) ContextCompat.startForegroundService(ctx, i) else ctx.stopService(i) }
    }
}

/**
 * خدمة أمامية تُبقي الطاولة والمحادثة الصوتية تعمل والتطبيق في الخلفية (شاشة مقفلة أو تطبيق آخر):
 * بدونها يوقف Android الميكروفون ويُنهي التطبيق بعد قليل. تظهر كإشعار ثابت.
 */
class VoiceService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mic = intent?.getBooleanExtra("mic", false) == true &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val n = notification(intent?.getBooleanExtra("voice", false) == true)
        try {
            when {
                Build.VERSION.SDK_INT >= 30 -> startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or (if (mic) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0))
                Build.VERSION.SDK_INT >= 29 -> startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                else -> startForeground(ID, n)
            }
        } catch (e: Exception) {
            // النظام رفض (بدأت والتطبيق في الخلفية): الصوت يعمل ما دام التطبيق ظاهراً فقط
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(voice: Boolean): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm?.getNotificationChannel(CHANNEL) == null) {
            nm?.createNotificationChannel(NotificationChannel(CHANNEL, "المحادثة الصوتية", NotificationManager.IMPORTANCE_LOW).apply {
                description = "يظهر أثناء المحادثة الصوتية حتى تستمر والتطبيق في الخلفية"
                setSound(null, null)
            })
        }
        val open = Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(if (voice) "مجلسك — المحادثة الصوتية تعمل" else "مجلسك — أنت في طاولة")
            .setContentText("اضغط للعودة إلى الطاولة")
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(if (voice) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /** أُغلق التطبيق من قائمة التطبيقات الأخيرة: تنتهي المحادثة معه */
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    private companion object {
        const val CHANNEL = "voice"
        const val ID = 7001
    }
}
