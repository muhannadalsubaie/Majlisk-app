package com.majlisk.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthProvider
import com.majlisk.app.MainActivity
import com.majlisk.app.R
import com.majlisk.app.net.Api
import com.majlisk.app.net.ApiError
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.tasks.await

object AuthService {
    private val auth get() = FirebaseAuth.getInstance()

    suspend fun signIn(email: String, password: String) {
        if (password.isEmpty()) throw ApiError("missing-password")
        auth.signInWithEmailAndPassword(email, password).await()
    }

    suspend fun signUp(username: String, email: String, password: String) {
        Usernames.validate(username)?.let { throw ApiError(it) }
        if (password.isEmpty()) throw ApiError("missing-password")
        // فحص مبدئي قبل إنشاء الحساب؛ الحجز الفعلي الذرّي يتم بعده في الخادم
        val check = Api.postPublic("/username/available", jsonOf("username" to username))
        if (!check.optBoolean("available")) throw ApiError(check.optString("error", "taken"))
        auth.createUserWithEmailAndPassword(email, password).await()
        sendVerification()
        // إن فشل الحجز هنا (سباق نادر) تظهر شاشة اختيار الاسم تلقائياً
        runCatching { Api.post("/profile/username", jsonOf("username" to username)) }
    }

    /** نافذة اختيار حساب Google في الجهاز، ثم الدخول بنفس الحساب في Firebase */
    suspend fun google() {
        val activity = MainActivity.current ?: throw ApiError("cancelled")
        val option = GetSignInWithGoogleOption.Builder(activity.getString(R.string.default_web_client_id)).build()
        val result = try {
            CredentialManager.create(activity).getCredential(activity, GetCredentialRequest.Builder().addCredentialOption(option).build())
        } catch (e: GetCredentialCancellationException) {
            throw ApiError("cancelled")
        }
        val cred = result.credential
        if (cred !is CustomCredential || cred.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) throw ApiError("cancelled")
        val idToken = GoogleIdTokenCredential.createFrom(cred.data).idToken
        auth.signInWithCredential(GoogleAuthProvider.getCredential(idToken, null)).await()
    }

    /** الدخول بحساب Apple عبر صفحة Apple (Firebase يفتحها ويعود للتطبيق) */
    suspend fun apple() {
        val activity = MainActivity.current ?: throw ApiError("cancelled")
        val provider = OAuthProvider.newBuilder("apple.com").apply {
            setScopes(listOf("email", "name"))
            addCustomParameter("locale", "ar")
        }.build()
        val pending = auth.pendingAuthResult
        if (pending != null) pending.await() else auth.startActivityForSignInWithProvider(activity, provider).await()
    }

    /** الحسابات الجديدة بالبريد (من بعد إضافة هذه الخطوة) تتحقق من بريدها برابط قبل الدخول */
    private const val VERIFY_SINCE = 1_793_318_400_000L

    fun needsVerification(u: com.google.firebase.auth.FirebaseUser?): Boolean =
        u != null && !u.isEmailVerified && u.providerData.any { it.providerId == "password" } &&
            (u.metadata?.creationTimestamp ?: 0) >= VERIFY_SINCE

    suspend fun sendVerification() {
        auth.setLanguageCode("ar")
        runCatching { auth.currentUser?.sendEmailVerification()?.await() }
    }

    /** يحدّث حالة الحساب من Firebase: هل ضغط رابط التحقق؟ */
    suspend fun checkVerified(): Boolean {
        val u = auth.currentUser ?: return false
        runCatching { u.reload().await() }
        val ok = auth.currentUser?.isEmailVerified == true
        // توكن جديد حتى يعرف الخادم أن البريد موثّق
        if (ok) runCatching { auth.currentUser?.getIdToken(true)?.await() }
        return ok
    }

    suspend fun resetPassword(email: String) {
        if (email.isEmpty()) throw ApiError("ERROR_INVALID_EMAIL")
        auth.sendPasswordResetEmail(email).await()
    }

    fun openUrl(context: Context, url: String) {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }
}
