package com.majlisk.app.net

import com.google.firebase.auth.FirebaseAuth
import com.majlisk.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** خطأ من الخادم: code هو رمز الخطأ (مثل not-enough-coins) */
class ApiError(val code: String) : Exception(code)

object Api {
    val BASE: String = BuildConfig.API_URL

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .pingInterval(25, TimeUnit.SECONDS)
        .build()

    private val JSON = "application/json".toMediaType()

    suspend fun token(): String {
        val user = FirebaseAuth.getInstance().currentUser ?: throw ApiError("unauthenticated")
        return user.getIdToken(false).await().token ?: throw ApiError("unauthenticated")
    }

    /** طلب POST بتوكن المستخدم الحالي */
    suspend fun post(path: String, body: JSONObject = JSONObject()): JSONObject =
        send(path, body, token())

    /** طلب بلا تسجيل دخول (مثل فحص توفر اسم المستخدم) */
    suspend fun postPublic(path: String, body: JSONObject = JSONObject()): JSONObject =
        send(path, body, null)

    suspend fun get(path: String): JSONObject {
        val req = Request.Builder().url(BASE + path).header("Authorization", "Bearer ${token()}").build()
        return execute(req)
    }

    private suspend fun send(path: String, body: JSONObject, token: String?): JSONObject {
        val b = Request.Builder().url(BASE + path).post(body.toString().toRequestBody(JSON))
        if (token != null) b.header("Authorization", "Bearer $token")
        return execute(b.build())
    }

    private suspend fun execute(req: Request): JSONObject = withContext(Dispatchers.IO) {
        val res = http.newCall(req).await()
        res.use {
            val text = it.body?.string().orEmpty()
            val json = runCatching { JSONObject(text) }.getOrDefault(JSONObject())
            if (!it.isSuccessful) throw ApiError(json.optString("error").ifEmpty { "http-${it.code}" })
            json
        }
    }

    fun wsUrl(path: String, token: String): String =
        BASE.replaceFirst("http", "ws") + path + "?token=" + java.net.URLEncoder.encode(token, "UTF-8")
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) { if (cont.isActive) cont.resumeWithException(ApiError("network")) }
        override fun onResponse(call: Call, response: Response) { cont.resume(response) }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}

fun jsonOf(vararg pairs: Pair<String, Any?>): JSONObject = JSONObject().apply { pairs.forEach { (k, v) -> put(k, v ?: JSONObject.NULL) } }
