package com.majlisk.app.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.net.Api
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** ملف اللاعب: يُقرأ مباشرة من Firestore (الكتابة من الخادم فقط) */
data class Profile(
    val username: String = "",
    /** null حتى يُنشئ الخادم ملف اللاعب */
    val coins: Long? = null,
    val loaded: Boolean = false,
    val unlimited: Boolean = false,
)

/** المستخدم الحالي ورصيده، ويتحدثان فور أي تغيير */
object Session {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val auth = FirebaseAuth.getInstance()

    private val _user = MutableStateFlow(auth.currentUser)
    val user: StateFlow<FirebaseUser?> = _user
    private val _profile = MutableStateFlow<Profile?>(null)
    val profile: StateFlow<Profile?> = _profile

    private var doc: ListenerRegistration? = null

    init {
        auth.addAuthStateListener { a ->
            val u = a.currentUser
            if (u?.uid == _user.value?.uid && doc != null) return@addAuthStateListener
            _user.value = u
            doc?.remove()
            doc = null
            if (u == null) { _profile.value = null; return@addAuthStateListener }
            _profile.value = Profile()
            // الخادم ينشئ ملف اللاعب مع العملات الترحيبية عند أول دخول، ويمنح الهدايا لمرة واحدة
            scope.launch {
                runCatching { Api.post("/profile/ensure") }.onSuccess {
                    val gift = it.optInt("gift")
                    if (gift > 0) Announcer.announce("هدية: أُضيفت $gift عملة إلى رصيدك")
                }
            }
            doc = FirebaseFirestore.getInstance().collection("users").document(u.uid).addSnapshotListener { snap, _ ->
                if (snap == null) return@addSnapshotListener
                _profile.value = Profile(
                    username = snap.getString("username").orEmpty(),
                    coins = snap.getLong("coins") ?: snap.getDouble("coins")?.toLong(),
                    loaded = snap.exists(),
                    unlimited = snap.getBoolean("unlimited") == true,
                )
            }
        }
    }

    fun signOut() {
        auth.signOut()
    }
}
