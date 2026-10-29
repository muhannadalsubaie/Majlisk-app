package com.majlisk.app.data

import android.media.AudioAttributes
import android.media.MediaPlayer
import com.majlisk.app.MajliskApp

/**
 * موسيقى القائمة: تبدأ مع فتح التطبيق وتتكرر في الشاشات الرئيسية، وتتوقف عند دخول طاولة
 * أو خروج التطبيق للخلفية. صوتها منخفض حتى لا تغطي قارئ الشاشة.
 */
object MenuMusic {
    private const val VOLUME = 0.2f
    private var player: MediaPlayer? = null
    private var wanted = false
    private var foreground = true

    fun setWanted(w: Boolean) { wanted = w; update() }
    fun setForeground(f: Boolean) { foreground = f; update() }

    fun update() {
        if (wanted && foreground && Prefs.music) start() else stop()
    }

    private fun start() {
        if (player?.isPlaying == true) return
        if (player == null) {
            val afd = runCatching { MajliskApp.instance.assets.openFd("music/menu.mp3") }.getOrNull() ?: return
            player = runCatching {
                MediaPlayer().apply {
                    setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    isLooping = true
                    setVolume(VOLUME, VOLUME)
                    prepare()
                }
            }.getOrNull()
            afd.close()
        }
        player?.start()
    }

    private fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
    }
}
