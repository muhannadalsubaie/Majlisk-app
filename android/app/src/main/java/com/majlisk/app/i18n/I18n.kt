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
/**
 * تسميات الأوراق الشامية: النصوص (من التطبيق والخادم) بالتسميات الخليجية، ونبدلها وقت العرض والقراءة.
 * الأنواع: سبيت ← بستوني، هاص ← كوبا، ديمن ← دينار، شريا ← سنك. والأكة ← قص (قبل اسم النوع أو لحالها).
 * الشايب والبنت والولد والأرقام نفسها.
 */
object CardNames {
    private val SUITS = mapOf("سبيت" to "بستوني", "هاص" to "كوبا", "ديمن" to "دينار", "شريا" to "سنك")
    private val L = "\\p{L}"
    private val suitRe = Regex("(?<![$L])(ال|لل|بال|وال|لـ|بـ)?(سبيت|هاص|ديمن|شريا)(?![$L])")
    private val aceRe = Regex("(?<![$L])أكة (سبيت|هاص|ديمن|شريا)(?![$L])")
    private val cache = HashMap<String, String>()

    fun levant(s: String): String {
        if (s.isEmpty() || !(s.contains("سبيت") || s.contains("هاص") || s.contains("ديمن") || s.contains("شريا") || s == "أكة")) return s
        synchronized(cache) { cache[s]?.let { return it } }
        // ورقة لحالها (خانة صف التركس)
        var r = if (s == "أكة") "قص" else s
        r = aceRe.replace(r) { m -> "قص ${m.groupValues[1]}" }
        r = suitRe.replace(r) { m -> m.groupValues[1] + SUITS.getValue(m.groupValues[2]) }
        synchronized(cache) { if (cache.size > 3000) cache.clear(); cache[s] = r }
        return r
    }
}

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
                // مكانين ورا بعض بمسافة ({0} {1}): الثاني كلمة وحدة (رقم أو نقاط)
                val parts = k.split(Regex("\\{\\d\\}"))
                val pattern = buildString {
                    append(Regex.escape(parts[0]))
                    for (j in 1 until parts.size) { append(if (j > 1 && parts[j - 1] == " ") "(\\S+)" else "(.*?)"); append(Regex.escape(parts[j])) }
                }
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
        if (l == AR) return if (Prefs.cardNames.value == "levant") CardNames.levant(s) else s
        if (s.isEmpty() || !arabic.containsMatchIn(s)) return s
        init()
        synchronized(cache) { cache[s]?.let { return it } }
        val r = translate(s, if (l == "fr") 1 else 0, 0)
        synchronized(cache) { if (cache.size > 4000) cache.clear(); cache[s] = r }
        return r
    }

    private fun translate(s: String, i: Int, depth: Int): String {
        if (s.isEmpty() || !arabic.containsMatchIn(s) || depth > 8) return s
        exact[s]?.let { return it[i] }
        // مسافات في الأطراف
        val t = s.trim()
        if (t.length != s.length && t.isNotEmpty()) return s.substring(0, s.indexOf(t[0])) + translate(t, i, depth + 1) + s.substring(s.lastIndexOf(t.last()) + 1)
        var best: String? = null
        for (tp in templates) {
            val m = tp.re.matchEntire(s) ?: continue
            var out = tp.out[i]
            m.groupValues.drop(1).forEachIndexed { n, g -> out = out.replace("{$n}", translate(g, i, depth + 1)) }
            best = out
            break
        }
        if (best != null && leftover(best) == 0) return best
        // نقسم على الفواصل ونترجم كل جزء (لو القالب بلع نص طويل فيه أكثر من جملة، نختار الأنظف)
        for ((sep, rep) in SEPARATORS) {
            if (!s.contains(sep)) continue
            val alt = s.split(sep).joinToString(rep) { translate(it, i, depth + 1) }
            return if (best == null || leftover(alt) < leftover(best)) alt else best
        }
        return best ?: s
    }

    /** كم حرف عربي باقي بعد الترجمة */
    private fun leftover(s: String) = letters.findAll(s).count()

    private val SEPARATORS = listOf("\n" to "\n", ". " to ". ", " — " to " — ", "، " to ", ", "،" to ",", ": " to ": ", " · " to " · ", " و" to " & ")
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
    // كل جزء معلّم بلغته: قارئ الشاشة يقرأ العربي بالناطق العربي والإنجليزي بالإنجليزي
    androidx.compose.material3.Text(
        spokenAnnotated(tr(text)), modifier = modifier, color = color, fontSize = fontSize, fontStyle = fontStyle,
        fontWeight = fontWeight, fontFamily = fontFamily, letterSpacing = letterSpacing, textDecoration = textDecoration,
        textAlign = textAlign, lineHeight = lineHeight, overflow = overflow, softWrap = softWrap, maxLines = maxLines,
        minLines = minLines, onTextLayout = onTextLayout ?: {}, style = style,
    )
}

/**
 * القراءة ثنائية اللغة: نقسم النص لأجزاء حسب الحروف (عربي / لاتيني)، وكل جزء ياخذ لغته.
 * المسافات والأرقام والرموز تمشي مع الجزء اللي قبلها (وأولها مع أول جزء).
 * لاتيني = إنجليزي، إلا لو التطبيق بالفرنسي فيصير فرنسي.
 */
fun langRuns(s: String): List<Triple<Int, Int, String>> {
    val latin = if (I18n.lang.value == "fr") "fr" else "en"
    fun cls(c: Char): String? = when {
        c in '\u0600'..'\u06FF' || c in '\u0750'..'\u077F' || c in '\uFB50'..'\uFDFF' || c in '\uFE70'..'\uFEFF' -> "ar"
        c in 'A'..'Z' || c in 'a'..'z' || (c in '\u00C0'..'\u024F' && c.isLetter()) -> latin
        else -> null
    }
    val out = ArrayList<Triple<Int, Int, String>>()
    var start = 0
    var cur: String? = null
    for (i in s.indices) {
        val k = cls(s[i]) ?: continue
        if (cur == null) cur = k
        else if (k != cur) { out += Triple(start, i, cur); start = i; cur = k }
    }
    out += Triple(start, s.length, cur ?: if (I18n.rtl) "ar" else latin)
    return out
}

/** نص معلّم بلغاته لقارئ الشاشة (Compose) */
fun spokenAnnotated(s: String): androidx.compose.ui.text.AnnotatedString =
    androidx.compose.ui.text.buildAnnotatedString {
        append(s)
        if (s.isNotEmpty()) for ((a, b, l) in langRuns(s)) if (b > a)
            addStyle(androidx.compose.ui.text.SpanStyle(localeList = androidx.compose.ui.text.intl.LocaleList(l)), a, b)
    }

/** نص معلّم بلغاته لقارئ الشاشة (الإعلانات) */
fun spoken(s: String): CharSequence {
    if (s.isEmpty()) return s
    val sp = android.text.SpannableString(s)
    for ((a, b, l) in langRuns(s)) if (b > a)
        sp.setSpan(android.text.style.LocaleSpan(java.util.Locale.forLanguageTag(l)), a, b, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    return sp
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
