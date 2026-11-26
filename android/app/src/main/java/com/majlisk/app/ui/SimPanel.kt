package com.majlisk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.i18n.Text
import com.majlisk.app.net.Api
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private val SIM_GAME_NAMES = mapOf(
    "baloot" to "بلوت", "domino" to "دومينو", "jackaroo" to "جاكارو", "ludo" to "لودو",
    "tarneeb" to "طرنيب", "trix" to "تريكس", "konkan" to "كونكان", "shayeb" to "شايب",
)

/**
 * لوحة محاكاة النشاط (حساب المطور بس، والخادم يرفض غيره): تشغيل وإيقاف، والحدود، والألعاب،
 * وفترة التحديث، والعدد الحالي، وإعادة الضبط
 */
@Composable
fun SimPanel() {
    val scope = rememberCoroutineScope()
    var on by remember { mutableStateOf(false) }
    var minP by remember { mutableStateOf("") }
    var maxP by remember { mutableStateOf("") }
    var minT by remember { mutableStateOf("") }
    var maxT by remember { mutableStateOf("") }
    var every by remember { mutableStateOf("") }
    val all = remember { mutableStateListOf<String>() }
    val games = remember { mutableStateListOf<String>() }
    var status by remember { mutableStateOf("جارٍ التحميل…") }
    var busy by remember { mutableStateOf(false) }

    fun apply(r: JSONObject) {
        val c = r.optJSONObject("config") ?: return
        on = c.optBoolean("on")
        minP = c.optInt("minPlayers").toString(); maxP = c.optInt("maxPlayers").toString()
        minT = c.optInt("minTables").toString(); maxT = c.optInt("maxTables").toString()
        every = c.optInt("everyMin").toString()
        all.clear(); r.optJSONArray("games")?.let { a -> (0 until a.length()).forEach { all += a.optString(it) } }
        games.clear(); c.optJSONArray("games")?.let { a -> (0 until a.length()).forEach { games += a.optString(it) } }
        status = if (on) "شغالة الحين: ${r.optInt("players")} حساب تلقائي و${r.optInt("tables")} طاولة" else "المحاكاة متوقفة"
    }
    fun send(extra: JSONObject.() -> Unit = {}) {
        busy = true
        scope.launch {
            runCatching {
                Api.post("/admin/sim", JSONObject().apply {
                    put("on", on)
                    minP.toIntOrNull()?.let { put("minPlayers", it) }; maxP.toIntOrNull()?.let { put("maxPlayers", it) }
                    minT.toIntOrNull()?.let { put("minTables", it) }; maxT.toIntOrNull()?.let { put("maxTables", it) }
                    every.toIntOrNull()?.let { put("everyMin", it) }
                    put("games", JSONArray(games.toList()))
                    extra()
                })
            }.onSuccess { apply(it); Announcer.announce("انحفظت إعدادات المحاكاة، ${status}") }
                .onFailure { Announcer.announce("ما انحفظت، جرّب مرة ثانية") }
            busy = false
        }
    }
    LaunchedEffect(Unit) { runCatching { Api.get("/admin/sim") }.onSuccess { apply(it) }.onFailure { status = "تعذّر التحميل" } }

    SectionTitle("محاكاة النشاط (نشاط المجلس)")
    Text("حسابات وطاولات تلقائية تطلع في قسم مستقل عليه ✦، ومكتوب عندها إنها تلقائية. ما تدخل في عدد المتصلين الحقيقي ولا الترتيب ولا الأصدقاء، وطاولاتها مقفلة.", color = Palette.textDim, fontSize = 12.sp)
    Text(status, color = Palette.goldSoft, fontSize = 13.sp)
    SwitchRow("تشغيل المحاكاة", on, { on = it; send() })
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NumField("أقل عدد حسابات", minP, Modifier.weight(1f)) { minP = it }
        NumField("أكثر عدد حسابات", maxP, Modifier.weight(1f)) { maxP = it }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NumField("أقل عدد طاولات", minT, Modifier.weight(1f)) { minT = it }
        NumField("أكثر عدد طاولات", maxT, Modifier.weight(1f)) { maxT = it }
    }
    NumField("فترة التحديث (دقايق)", every, Modifier.fillMaxWidth()) { every = it }
    Text("الألعاب المشمولة", color = Palette.text, fontSize = 14.sp)
    all.forEach { g ->
        SwitchRow(SIM_GAME_NAMES[g] ?: g, g in games, { if (it) { if (g !in games) games += g } else games.remove(g) })
    }
    PrimaryButton("حفظ الإعدادات", { send() }, enabled = !busy)
    SecondaryButton("إعادة ضبط بيانات المحاكاة (أسماء وتوزيع جديد)", { send { put("reset", true) } }, enabled = !busy, fill = true)
}

@Composable
private fun NumField(label: String, value: String, modifier: Modifier, onChange: (String) -> Unit) {
    androidx.compose.material3.OutlinedTextField(
        value, { onChange(it.filter(Char::isDigit).take(3)) }, label = { Text(label) }, singleLine = true, modifier = modifier,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700, focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim),
    )
}
