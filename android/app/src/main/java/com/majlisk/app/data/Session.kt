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

    /** تشخيص: الدخول ضاع بدون ما يضغط اللاعب «تسجيل الخروج» — نرسل السبب لسجل الخادم (بدون بيانات شخصية) */
    private fun reportLost(what: String, detail: String = "") {
        scope.launch {
            runCatching { Api.postPublic("/diag/auth", com.majlisk.app.net.jsonOf("device" to Prefs.deviceId, "what" to what, "detail" to detail.replace(Regex("\\S+@\\S+"), "*"))) }
        }
    }

    init {
        // فتحنا التطبيق والحساب مو موجود، مع إنه كان مسجل وما ضغط «تسجيل الخروج»
        if (auth.currentUser == null && Prefs.lastUid != null && !Prefs.manualSignOut) reportLost("no-user-on-start")
        // الحساب موجود: نتأكد إن تجديد الدخول يشتغل، ولو فشل نسجّل السبب
        auth.currentUser?.let { u ->
            u.getIdToken(true).addOnFailureListener { e ->
                val code = (e as? com.google.firebase.auth.FirebaseAuthException)?.errorCode.orEmpty()
                reportLost("refresh-failed", "${e.javaClass.simpleName} $code ${e.message.orEmpty()}")
            }
        }
        auth.addAuthStateListener { a ->
            val u = a.currentUser
            if (u != null) { Prefs.lastUid = u.uid; Prefs.manualSignOut = false }
            else if (Prefs.lastUid != null && !Prefs.manualSignOut) { reportLost("signed-out-while-open"); Prefs.lastUid = null }
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
        // دخولك الجاي على هالجوال يرجّعه جوال الحساب
        Prefs.claimedUid = null
        Prefs.manualSignOut = true
        auth.signOut()
    }
}
