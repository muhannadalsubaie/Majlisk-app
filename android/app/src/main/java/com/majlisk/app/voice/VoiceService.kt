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
 * خدمة أمامية تُبقي المحادثة الصوتية تعمل والتطبيق في الخلفية (شاشة مقفلة أو تطبيق آخر):
 * بدونها يوقف Android الميكروفون ويُنهي التطبيق بعد قليل. تظهر كإشعار ثابت.
 */
class VoiceService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mic = intent?.getBooleanExtra("mic", false) == true &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val n = notification()
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

    private fun notification(): Notification {
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
            .setContentTitle("مجلسك — المحادثة الصوتية تعمل")
            .setContentText("اضغط للعودة إلى الطاولة")
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
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
