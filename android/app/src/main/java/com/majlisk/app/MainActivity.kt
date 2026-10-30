package com.majlisk.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CompletableDeferred
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.ui.AppRoot
import com.majlisk.app.ui.MajliskTheme

class MainActivity : ComponentActivity() {
    private var micResult: CompletableDeferred<Boolean>? = null
    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { micResult?.complete(it) }

    private val notifyPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /** إذن الإشعارات (Android 13+): يُطلب مرة واحدة عند فتح الميكروفون، حتى يظهر إشعار المحادثة في الخلفية */
    fun requestNotificationsOnce() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        val prefs = getSharedPreferences("majlisk", MODE_PRIVATE)
        if (prefs.getBoolean("askedNotify", false)) return
        prefs.edit().putBoolean("askedNotify", true).apply()
        notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    /** إذن الميكروفون: يُطلب أول مرة يفتح فيها اللاعب الميكروفون بنفسه */
    suspend fun requestMicPermission(): Boolean {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) return true
        val wait = CompletableDeferred<Boolean>()
        micResult = wait
        micPermission.launch(Manifest.permission.RECORD_AUDIO)
        return wait.await()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Announcer.attach(this)
        current = this
        setContent {
            // التطبيق عربي بالكامل: من اليمين لليسار دائماً، مهما كانت لغة الجهاز
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                MajliskTheme { AppRoot() }
            }
        }
    }


    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        /** النشاط الحالي (للإعلانات والشراء وتسجيل الدخول التي تحتاج نافذة) */
        var current: MainActivity? = null
            private set
    }
}
