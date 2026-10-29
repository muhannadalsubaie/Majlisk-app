package com.majlisk.app

import android.app.Application
import com.majlisk.app.data.Prefs
import com.majlisk.app.data.Sounds

class MajliskApp : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        Prefs.init(this)
        Sounds.init(this)
    }

    companion object {
        lateinit var instance: MajliskApp
            private set
    }
}
