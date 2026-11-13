package com.majlisk.app.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.net.Api
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/** تذكرة دعم: شكوى أو استفسار، ورسائلها (صاحبها والمطور) */
data class Ticket(
    val id: String, val username: String, val kind: String, val images: Int, val at: Long, val status: String,
    val messages: List<Triple<String, String, Long>>,
) {
    val kindLabel get() = if (kind == "complaint") "شكوى" else "استفسار"
    val statusLabel get() = when (status) { "answered" -> "تم الرد"; "closed" -> "مغلقة"; else -> "بانتظار الرد" }
    companion object {
        fun parse(o: JSONObject) = Ticket(
            o.optString("id"), o.optString("username"), o.optString("kind"), o.optInt("images"), o.optLong("at"), o.optString("status"),
            (o.optJSONArray("messages") ?: JSONArray()).let { a -> (0 until a.length()).map { a.getJSONObject(it).let { m -> Triple(m.optString("from"), m.optString("text"), m.optLong("at")) } } },
        )
    }
}

private val fieldColors @Composable get() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, focusedBorderColor = Palette.gold,
    unfocusedBorderColor = Palette.green700, focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim,
)

/** نصغّر الصورة (أطول ضلع 1280) ونرسلها JPEG */
private fun prepareImage(bytes: ByteArray): String? {
    val src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    val k = minOf(1f, 1280f / maxOf(src.width, src.height))
    val img = if (k < 1f) Bitmap.createScaledBitmap(src, (src.width * k).toInt(), (src.height * k).toInt(), true) else src
    val out = ByteArrayOutputStream()
    img.compress(Bitmap.CompressFormat.JPEG, 75, out)
    return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
}

private fun time(ms: Long) = java.text.SimpleDateFormat("d/M h:mm a", java.util.Locale("ar")).format(java.util.Date(ms))

/**
 * المساعدة والدعم: شكوى أو استفسار (نص بدون حد، ولين 4 صور)، وتذاكرك وردود المطور عليها.
 * حساب المطور يشوف كل التذاكر ويرد عليها.
 */
@Composable
fun SupportScreen(dev: Boolean, onBack: () -> Unit) {
    var kind by remember { mutableStateOf<String?>(null) }
    var open by remember { mutableStateOf<Ticket?>(null) }
    var all by remember { mutableStateOf(false) }
    var tickets by remember { mutableStateOf<List<Ticket>?>(null) }
    var reload by remember { mutableStateOf(0) }
    LaunchedEffect(all, reload) {
        tickets = runCatching { Api.post("/support/list", jsonOf("all" to all)).optJSONArray("tickets") }.getOrNull()
            ?.let { a -> (0 until a.length()).map { Ticket.parse(a.getJSONObject(it)) } } ?: emptyList()
        open = open?.let { o -> tickets?.find { it.id == o.id } }
    }
    androidx.activity.compose.BackHandler(enabled = kind != null || open != null) { kind = null; open = null }
    when {
        kind != null -> NewTicket(kind!!, onDone = { kind = null; reload++ })
        open != null -> TicketView(open!!, dev && all, onBack = { open = null; reload++ }, onChanged = { reload++ })
        else -> Screen {
            TopBar(if (all) "تذاكر الدعم" else "المساعدة والدعم", onBack = onBack)
            if (!all) {
                Body("كيف نقدر نساعدك؟")
                PrimaryButton("📝 شكوى", { kind = "complaint" })
                PrimaryButton("❓ استفسار", { kind = "question" })
            }
            if (dev) SecondaryButton(if (all) "تذاكري أنا" else "🛠 تذاكر الدعم (المطور)", { all = !all; tickets = null }, fill = true)
            SectionTitle(if (all) "كل التذاكر" else "تذاكري")
            when {
                tickets == null -> Note("جارٍ التحميل…")
                tickets!!.isEmpty() -> Note(if (all) "ما فيه تذاكر" else "ما عندك تذاكر")
            }
            tickets?.forEach { t ->
                val who = if (all) "${t.username} · " else ""
                SecondaryButton("$who${t.kindLabel} · ${t.statusLabel} · ${time(t.at)}\n${t.messages.firstOrNull()?.second.orEmpty().take(60)}",
                    { open = t }, fill = true)
            }
        }
    }
}

@Composable
private fun NewTicket(kind: String, onDone: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var images by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris ->
        scope.launch {
            val added = withContext(Dispatchers.IO) {
                uris.mapNotNull { u -> runCatching { context.contentResolver.openInputStream(u)?.use { it.readBytes() }?.let(::prepareImage) }.getOrNull() }
            }
            images = (images + added).take(4)
            Announcer.announce("أُرفقت ${images.size} من 4 صور")
        }
    }
    Screen {
        TopBar(if (kind == "complaint") "شكوى جديدة" else "استفسار جديد", onBack = onDone)
        OutlinedTextField(
            value = text, onValueChange = { text = it; error = "" },
            label = { Text(if (kind == "complaint") "اكتب شكواك" else "اكتب استفسارك") },
            modifier = Modifier.fillMaxWidth().heightIn(min = 180.dp), colors = fieldColors,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            images.forEachIndexed { i, b64 ->
                val bmp = remember(b64) { Base64.decode(b64, Base64.NO_WRAP).let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
                Box(Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)).background(Palette.green800)
                    .clickable { images = images.filterIndexed { j, _ -> j != i }; Announcer.announce("حُذفت الصورة ${i + 1}") }
                    .semantics { contentDescription = "الصورة ${i + 1}، اضغط لحذفها" }) {
                    bmp?.let { Image(it, null, contentScale = ContentScale.Crop, modifier = Modifier.size(72.dp)) }
                }
            }
        }
        if (images.size < 4) SecondaryButton("📎 إرفاق صور (${images.size} من 4)", {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }, fill = true)
        if (error.isNotEmpty()) Text(error, color = Palette.goldSoft)
        PrimaryButton(if (busy) "جارٍ الإرسال…" else "إرسال", {
            busy = true
            scope.launch {
                runCatching { Api.post("/support/create", jsonOf("kind" to kind, "text" to text.trim(), "images" to JSONArray(images))) }
                    .onSuccess { Announcer.announce("وصلت رسالتك، وراح يوصلك الرد هنا وبإشعار"); onDone() }
                    .onFailure { error = "تعذّر الإرسال، حاول مرة ثانية"; Announcer.announce(error) }
                busy = false
            }
        }, enabled = text.isNotBlank() && !busy)
    }
}

@Composable
private fun TicketImage(id: String, i: Int) {
    val img by produceState<ImageBitmap?>(null, id, i) {
        value = Api.bytes("/support/image/$id/$i")?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size)?.asImageBitmap() }
    }
    Box(Modifier.fillMaxWidth().heightIn(min = 120.dp).clip(RoundedCornerShape(14.dp)).background(Palette.green800)
        .semantics { contentDescription = "صورة مرفقة ${i + 1}" }) {
        img?.let { Image(it, null, contentScale = ContentScale.FillWidth, modifier = Modifier.fillMaxWidth()) } ?: Note("جارٍ تحميل الصورة…", Modifier.padding(12.dp))
    }
}

@Composable
private fun TicketView(t: Ticket, asDev: Boolean, onBack: () -> Unit, onChanged: () -> Unit) {
    var reply by remember(t.id) { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Screen {
        TopBar("${t.kindLabel}${if (asDev) " · ${t.username}" else ""}", onBack = onBack)
        Note("${t.statusLabel} · ${time(t.at)}")
        t.messages.forEachIndexed { i, (from, text, at) ->
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                    .background(if (from == "dev") Palette.green700 else Palette.green800).padding(12.dp)
                    .semantics(mergeDescendants = true) { },
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(if (from == "dev") "الدعم" else if (asDev) t.username else "أنت", color = Palette.goldSoft, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Text(text, color = Palette.text, fontSize = 16.sp)
                Text(time(at), color = Palette.textDim, fontSize = 11.sp)
            }
            // الصور مع أول رسالة
            if (i == 0) (0 until t.images).forEach { TicketImage(t.id, it) }
        }
        if (t.status != "closed") {
            OutlinedTextField(value = reply, onValueChange = { reply = it }, label = { Text(if (asDev) "الرد على ${t.username}" else "أضف رسالة") },
                modifier = Modifier.fillMaxWidth().heightIn(min = 110.dp), colors = fieldColors)
            PrimaryButton(if (busy) "جارٍ…" else "إرسال الرد", {
                busy = true
                scope.launch {
                    runCatching { Api.post("/support/reply", jsonOf("id" to t.id, "text" to reply.trim())) }
                        .onSuccess { reply = ""; Announcer.announce("أُرسل الرد"); onChanged() }
                        .onFailure { Announcer.announce("تعذّر الإرسال") }
                    busy = false
                }
            }, enabled = reply.isNotBlank() && !busy)
            SecondaryButton("إغلاق التذكرة", { scope.launch { runCatching { Api.post("/support/close", jsonOf("id" to t.id)) }; onChanged(); onBack() } }, fill = true)
        }
    }
}
