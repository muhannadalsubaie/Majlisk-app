package com.majlisk.app.i18n

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import com.majlisk.app.data.Prefs
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription

/**
 * لغة التطبيق: عربي (الأصل) أو إنجليزي أو فرنسي.
 * كل نص عربي (من التطبيق أو من الخادم) يتترجم وقت العرض أو القراءة من القاموس (assets/i18n.json):
 * نص مطابق، أو قالب فيه أماكن ({0}) تتعبى بأجزاء تتترجم هي بعد، وإلا نقسمه على الفواصل ونترجم كل جزء.
 */
object I18n {
    const val AR = "ar"
    val LANGS = listOf("ar" to "العربية", "en" to "English", "fr" to "Français")
    val lang = mutableStateOf(AR)
    private var loaded = false
    private val exact = HashMap<String, Array<String>>()
    private class Tpl(val re: Regex, val out: Array<String>, val weight: Int)
    private val templates = ArrayList<Tpl>()
    private val cache = HashMap<String, String>()
    private val arabic = Regex("[\u0600-\u06FF]")
    private val letters = Regex("[\u0621-\u064A]")

    fun init() {
        if (loaded) return
        loaded = true
        lang.value = runCatching { Prefs.app.getSharedPreferences("majlisk", 0).getString("lang", AR) }.getOrNull() ?: AR
        runCatching {
            val json = org.json.JSONObject(Prefs.app.assets.open("i18n.json").bufferedReader().use { it.readText() })
            for (k in json.keys()) {
                val o = json.getJSONObject(k)
                val out = arrayOf(o.optString("en"), o.optString("fr"))
                if (!k.contains("{0}")) { exact[k] = out; continue }
                // القالب: الأجزاء الثابتة لازم فيها حرف عربي (وإلا يطابق أي شي)
                val literal = k.replace(Regex("\\{\\d\\}"), "")
                if (!letters.containsMatchIn(literal)) continue
                val pattern = k.split(Regex("\\{\\d\\}")).joinToString("(.*?)") { Regex.escape(it) }
                templates += Tpl(Regex(pattern, RegexOption.DOT_MATCHES_ALL), out, literal.length)
            }
            templates.sortByDescending { it.weight }
        }
    }

    fun set(l: String) {
        lang.value = l
        synchronized(cache) { cache.clear() }
        runCatching { Prefs.app.getSharedPreferences("majlisk", 0).edit().putString("lang", l).apply() }
        sync()
    }

    /** نبلغ الخادم بلغتك (الإشعارات توصلك بها) — لو مسجّل دخول */
    fun sync() {
        val l = lang.value
        @OptIn(kotlinx.coroutines.DelicateCoroutinesApi::class)
        kotlinx.coroutines.GlobalScope.launch { runCatching { com.majlisk.app.net.Api.post("/profile/lang", org.json.JSONObject().put("lang", l)) } }
    }

    val rtl: Boolean get() = lang.value == AR

    fun tr(s: String): String {
        val l = lang.value
        if (l == AR || s.isEmpty() || !arabic.containsMatchIn(s)) return s
        init()
        synchronized(cache) { cache[s]?.let { return it } }
        val r = translate(s, if (l == "fr") 1 else 0, 0)
        synchronized(cache) { if (cache.size > 4000) cache.clear(); cache[s] = r }
        return r
    }

    private fun translate(s: String, i: Int, depth: Int): String {
        if (s.isEmpty() || !arabic.containsMatchIn(s) || depth > 6) return s
        exact[s]?.let { return it[i] }
        // مسافات في الأطراف
        val t = s.trim()
        if (t.length != s.length && t.isNotEmpty()) return s.substring(0, s.indexOf(t[0])) + translate(t, i, depth + 1) + s.substring(s.lastIndexOf(t.last()) + 1)
        for (tp in templates) {
            val m = tp.re.matchEntire(s) ?: continue
            var out = tp.out[i]
            m.groupValues.drop(1).forEachIndexed { n, g -> out = out.replace("{$n}", translate(g, i, depth + 1)) }
            return out
        }
        // نقسم على الفواصل ونترجم كل جزء
        for ((sep, rep) in SEPARATORS) {
            if (!s.contains(sep)) continue
            return s.split(sep).joinToString(rep) { translate(it, i, depth + 1) }
        }
        return s
    }

    private val SEPARATORS = listOf("\n" to "\n", "، " to ", ", "،" to ",", " — " to " — ", ". " to ". ", ": " to ": ", " · " to " · ", " و" to " & ")
}

/** ترجمة نص للغة التطبيق */
fun tr(s: String): String = I18n.tr(s)

/** نفس Text حق Material لكن يترجم النص للغة المختارة */
@Composable
fun Text(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    style: TextStyle = androidx.compose.material3.LocalTextStyle.current,
) {
    I18n.lang.value // يعيد الرسم لما تتغير اللغة
    androidx.compose.material3.Text(
        tr(text), modifier, color, fontSize, fontStyle, fontWeight, fontFamily, letterSpacing, textDecoration, textAlign,
        lineHeight, overflow, softWrap, maxLines, minLines, onTextLayout, style,
    )
}

/** إجراء قارئ الشاشة بعنوان مترجم */
fun A11yAction(label: String, action: () -> Boolean) = androidx.compose.ui.semantics.CustomAccessibilityAction(tr(label), action)

/** زر تغيير اللغة (🌐): قبل تسجيل الدخول فوق، وفي الإعدادات */
@Composable
fun LanguageButton(modifier: Modifier = Modifier) {
    var open by androidx.compose.runtime.remember { mutableStateOf(false) }
    val cur = I18n.LANGS.first { it.first == I18n.lang.value }.second
    androidx.compose.foundation.layout.Box(modifier) {
        androidx.compose.material3.Text(
            "🌐 $cur ▾",
            color = com.majlisk.app.ui.Palette.text,
            fontSize = androidx.compose.ui.unit.TextUnit(16f, androidx.compose.ui.unit.TextUnitType.Sp),
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(20))
                .background(com.majlisk.app.ui.Palette.green800)
                .border(androidx.compose.ui.unit.Dp(1f), com.majlisk.app.ui.Palette.gold, androidx.compose.foundation.shape.RoundedCornerShape(20))
                .clickable(role = androidx.compose.ui.semantics.Role.Button, onClickLabel = "Language / اللغة") { open = true }
                .padding(horizontal = androidx.compose.ui.unit.Dp(14f), vertical = androidx.compose.ui.unit.Dp(8f))
                .semantics { contentDescription = "Language, اللغة: $cur" },
        )
        androidx.compose.material3.DropdownMenu(open, { open = false }, containerColor = com.majlisk.app.ui.Palette.green800) {
            I18n.LANGS.forEach { (code, name) ->
                androidx.compose.material3.DropdownMenuItem(
                    text = { androidx.compose.material3.Text(if (code == I18n.lang.value) "✓ $name" else name, color = com.majlisk.app.ui.Palette.text) },
                    onClick = { open = false; I18n.set(code) },
                )
            }
        }
    }
}
