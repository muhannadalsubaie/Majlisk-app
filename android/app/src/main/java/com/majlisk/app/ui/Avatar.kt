package com.majlisk.app.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.net.Api
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.ByteArrayOutputStream

/** الصور الشخصية: تُحمّل من الخادم مرة وتُحفظ في الذاكرة، وتتحدث لما يغيّرها صاحبها */
object Avatars {
    private val cache = LruCache<String, Any>(64) // ImageBitmap أو NONE
    private val NONE = Any()
    /** رقم نسخة لكل صورة: يزيد لما تغيّر صورتك فتنعاد قراءتها */
    val versions = mutableStateMapOf<String, Int>()

    fun bump(uid: String) { cache.remove(uid); versions[uid] = (versions[uid] ?: 0) + 1 }

    suspend fun load(uid: String): ImageBitmap? {
        cache.get(uid)?.let { return if (it === NONE) null else it as ImageBitmap }
        val img = withContext(Dispatchers.IO) {
            runCatching {
                val req = Request.Builder().url("${Api.BASE}/avatar/$uid?v=${versions[uid] ?: 0}").build()
                Api.http.newCall(req).execute().use { r ->
                    if (!r.isSuccessful) null else r.body?.bytes()?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
                }
            }.getOrNull()
        }
        cache.put(uid, img ?: NONE)
        return img
    }

    /** نجهّز الصورة للرفع: مربعة من الوسط، 192×192، JPEG */
    fun prepare(bytes: ByteArray): String? {
        val src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val side = minOf(src.width, src.height)
        val square = Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
        val small = Bitmap.createScaledBitmap(square, 192, 192, true)
        val out = ByteArrayOutputStream()
        small.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}

/**
 * أيقونة دائرية بالصورة الشخصية، وإن ما فيه صورة فأول حرف من الاسم.
 * للعين فقط: الاسم جنبها يقرأه قارئ الشاشة.
 */
@Composable
fun Avatar(uid: String?, name: String, size: Dp = 36.dp, modifier: Modifier = Modifier) {
    val bot = uid.isNullOrEmpty() || uid.startsWith("bot-")
    val version = uid?.let { Avatars.versions[it] } ?: 0
    val img by produceState<ImageBitmap?>(null, uid, version) { value = if (bot) null else Avatars.load(uid!!) }
    Box(
        modifier.size(size).clip(CircleShape).background(Palette.green700).border(1.5.dp, Palette.gold, CircleShape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        val i = img
        if (i != null) Image(i, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(size))
        else Text(if (bot) "🤖" else name.trim().take(1), color = Palette.gold, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.42f).sp)
    }
}

/** الملف الشخصي: صورتك الدائرية واسمك، وتغيير الصورة أو حذفها */
@Composable
fun ProfileScreen(profile: com.majlisk.app.data.Profile?, onBack: () -> Unit) {
    val uid = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid.orEmpty()
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var busy by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    val upload: (ByteArray) -> Unit = { bytes ->
        val b64 = Avatars.prepare(bytes)
        if (b64 == null) com.majlisk.app.a11y.Announcer.announce("تعذّر فتح الصورة")
        else {
            busy = true
            scope.launch {
                runCatching { Api.post("/profile/avatar", org.json.JSONObject().put("image", b64)) }
                    .onSuccess { Avatars.bump(uid); com.majlisk.app.a11y.Announcer.announce("تم تغيير صورتك") }
                    .onFailure { com.majlisk.app.a11y.Announcer.announce("تعذّر رفع الصورة، حاول مرة أخرى") }
                busy = false
            }
        }
    }
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()?.let(upload)
    }
    Screen {
        TopBar("الملف الشخصي", onBack = onBack)
        androidx.compose.foundation.layout.Column(
            androidx.compose.ui.Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            Avatar(uid, profile?.username.orEmpty(), 140.dp)
            Title(profile?.username.orEmpty(), focus = false)
        }
        PrimaryButton("تغيير الصورة", {
            picker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly))
        }, enabled = !busy)
        SecondaryButton("حذف الصورة", {
            busy = true
            scope.launch {
                runCatching { Api.post("/profile/avatar", org.json.JSONObject().put("remove", true)) }
                    .onSuccess { Avatars.bump(uid); com.majlisk.app.a11y.Announcer.announce("تم حذف صورتك") }
                    .onFailure { com.majlisk.app.a11y.Announcer.announce("تعذّر حذف الصورة") }
                busy = false
            }
        }, enabled = !busy, fill = true)
        Note("صورتك تطلع دائرية جنب اسمك في الطاولات وعند أصدقائك.")
    }
}

