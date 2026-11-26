package com.majlisk.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import com.majlisk.app.i18n.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.AuthService
import com.majlisk.app.data.Billing
import com.majlisk.app.data.Prefs
import com.majlisk.app.data.Profile
import com.majlisk.app.data.Session
import com.majlisk.app.data.StorePack
import com.majlisk.app.data.Tables
import com.majlisk.app.net.Api
import kotlinx.coroutines.launch

/**
 * الإعدادات: تُفتح من القائمة الرئيسية كشاشة، أو من قائمة الطاولة (embedded) دون مغادرة الطاولة —
 * وهناك نُخفي قسم الحساب لأنه يُخرجك من اللعبة.
 */
@Composable
fun SettingsScreen(onBack: () -> Unit, embedded: Boolean) {
    var muted by remember { mutableStateOf(Prefs.muted) }
    var effects by remember { mutableStateOf(Prefs.effectsVolume) }
    var confirmDelete by remember { mutableStateOf(false) }
    var support by remember { mutableStateOf(false) }
    if (support) {
        val dev = com.majlisk.app.data.Session.profile.collectAsState().value.let { it?.dev == true || it?.unlimited == true }
        SupportScreen(dev) { support = false }
        return
    }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val site = Api.BASE.removeSuffix("/api")

    val body = @Composable {
        TopBar("الإعدادات", onBack = onBack)
        SectionTitle("اللغة")
        com.majlisk.app.i18n.LanguageButton()
        SectionTitle("الصوت")
        SwitchRow("كتم عام لجميع الأصوات", muted, { muted = it; Prefs.muted = it })
        // مستوى صوت المؤثرات: 70% المستوى الأصلي، وتقدر ترفعه لين 100% أو تنزله (كل خطوة 5%)
        Text("مستوى صوت المؤثرات: $effects%", color = Palette.text, fontSize = 15.sp)
        androidx.compose.material3.Slider(
            value = effects.toFloat(),
            onValueChange = { effects = (Math.round(it / 5f) * 5) },
            onValueChangeFinished = { Prefs.effectsVolume = effects; com.majlisk.app.data.Sounds.preview() },
            valueRange = 0f..100f, steps = 19,
            colors = androidx.compose.material3.SliderDefaults.colors(thumbColor = Palette.gold, activeTrackColor = Palette.gold, inactiveTrackColor = Palette.green700),
            modifier = Modifier.fillMaxWidth().semantics {
                contentDescription = com.majlisk.app.i18n.tr("مستوى صوت المؤثرات")
                stateDescription = "$effects%"
            },
        )
        SectionTitle("شكل الورق")
        // اختيارك أنت فقط ويتحفظ على جوالك
        SwitchRow("مروحة (الأوراق فوق بعض)", Prefs.handStyle.value == "fan", { if (it) Prefs.setHandStyle("fan") })
        SwitchRow("كروت جنب بعض (مفصولة)", Prefs.handStyle.value == "row", { if (it) Prefs.setHandStyle("row") })
        // أسماء الأوراق والأنواع في كل الألعاب (العرض وقارئ الشاشة)
        SectionTitle("تسميات الأوراق")
        SwitchRow("تسميات خليجية (أكة، شايب، بنت، ولد…)", Prefs.cardNames.value == "gulf", { if (it) Prefs.setCardNames("gulf") })
        SwitchRow("تسميات شامية (قص، كبة، ديناري، بستوني، سنك…)", Prefs.cardNames.value == "levant", { if (it) Prefs.setCardNames("levant") })
        // المطور بس: إعلان يوصل لكل مستخدمي التطبيق مرة وحدة
        val isDev = com.majlisk.app.data.Session.profile.collectAsState().value.let { it?.dev == true || it?.unlimited == true }
        if (isDev) {
            SectionTitle("إعلان المطور")
            var annText by remember { mutableStateOf("") }
            var annMsg by remember { mutableStateOf("") }
            androidx.compose.material3.OutlinedTextField(
                annText, { annText = it.take(1000) }, label = { Text("نص الإعلان") }, modifier = Modifier.fillMaxWidth(), minLines = 3,
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700, focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim),
            )
            Text("يوصل لكل اللي يفتحون التطبيق مرة وحدة (المتصلين الحين واللي يدخلون بعدين)، وما يقدرون يردون عليه.", color = Palette.textDim, fontSize = 12.sp)
            PrimaryButton("إرسال للكل", {
                val t = annText.trim()
                scope.launch { annMsg = if (com.majlisk.app.data.Announce.send(t)) { annText = ""; "انرسل الإعلان" } else "ما انرسل، جرّب مرة ثانية" }
            }, enabled = annText.isNotBlank())
            SecondaryButton("مسح الإعلان الحالي", { scope.launch { annMsg = if (com.majlisk.app.data.Announce.send("")) "انمسح الإعلان، ما بيطلع لأحد بعد الحين" else "ما انمسح، جرّب مرة ثانية" } }, fill = true)
            if (annMsg.isNotEmpty()) Text(annMsg, color = Palette.goldSoft, fontSize = 13.sp)
            SimPanel()
        }
        SectionTitle("الدردشة الكتابية")
        // اختيارك أنت فقط: ما يأثر على باقي اللاعبين
        val chatMode by com.majlisk.app.data.ChatSettings.mode.collectAsState()
        com.majlisk.app.data.ChatMode.entries.forEach { m ->
            SwitchRow(m.label, chatMode == m, { if (it) com.majlisk.app.data.ChatSettings.set(m) })
        }
        if (!embedded) {
            // خصوصية اللاعب: طاولتك العامة للأصدقاء فقط (الخاصة تبقى بدعوة أو طلب انضمام). محفوظة على حسابك
            SectionTitle("الخصوصية")
            var privacy by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) { runCatching { privacy = Api.post("/profile/privacy").optBoolean("on") } }
            SwitchRow("خصوصية اللاعب", privacy, { on ->
                privacy = on
                scope.launch { runCatching { privacy = Api.post("/profile/privacy", org.json.JSONObject().put("on", on)).optBoolean("on") }.onFailure { privacy = !on } }
            })
            Text(
                "إذا شغلته: طاولتك العامة ما يدخلها إلا أصدقاؤك. الطاولة الخاصة تبقى بدعوة أو طلب انضمام.",
                color = Palette.textDim, fontSize = 13.sp, modifier = Modifier.fillMaxWidth(),
            )
            SectionTitle("المساعدة")
            SecondaryButton("💬 المساعدة والدعم", { support = true }, fill = true)
            SectionTitle("الحساب")
            SecondaryButton("تسجيل الخروج", { Session.signOut() }, fill = true)
            DangerButton("حذف الحساب", { confirmDelete = true })
            SecondaryButton("سياسة الخصوصية", { AuthService.openUrl(context, "$site/privacy.html") }, fill = true)
            // في آخر الإعدادات العامة فقط، بخط صغير جداً: رخصة صور الكروت (LGPL) تشترط ذكرها مع رابط المصدر والرخصة
            val small = Modifier.fillMaxWidth()
            Text("صور الكروت: Vectorized Playing Cards لكريس أغيلار (Chris Aguilar)، رخصة LGPL-3.0. المؤثرات الصوتية: Kenney، رخصة CC0.", color = Palette.textDim, fontSize = 10.sp, lineHeight = 14.sp, modifier = small)
            Text("مصدر صور الكروت", color = Palette.textDim, fontSize = 10.sp, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
                modifier = small.clickable(role = androidx.compose.ui.semantics.Role.Button) { AuthService.openUrl(context, "https://github.com/richardschneider/cardsJS/tree/master/cards") })
            Text("رخصة صور الكروت", color = Palette.textDim, fontSize = 10.sp, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline,
                modifier = small.clickable(role = androidx.compose.ui.semantics.Role.Button) { AuthService.openUrl(context, "https://www.gnu.org/licenses/lgpl-3.0.html") })
        }
    }
    if (embedded) Column { body() } else Screen { body() }

    if (confirmDelete) {
        ConfirmDialog(
            "حذف الحساب",
            "سيتم حذف حسابك نهائياً: اسم المستخدم، والعملات، وقائمة الأصدقاء، وبيانات الدخول. لا يمكن التراجع عن هذا الإجراء.",
            "حذف نهائياً", danger = true,
            onConfirm = {
                confirmDelete = false
                Announcer.announce("جارٍ حذف الحساب…")
                scope.launch {
                    runCatching { Tables.deleteAccount() }
                        .onSuccess { Session.signOut(); Announcer.announce("تم حذف حسابك نهائياً") }
                        .onFailure { Announcer.announce("تعذّر حذف الحساب الآن، حاول مرة أخرى") }
                }
            },
            onCancel = { confirmDelete = false },
        )
    }
}

/** متجر العملات: الباقات بأسعار Google Play، والشراء عبره */
@Composable
fun ShopScreen(profile: Profile?, navigate: (Route) -> Unit) {
    var packs by remember { mutableStateOf<List<StorePack>?>(null) }
    var busy by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { packs = Billing.loadPacks() }
    val balance = if (profile?.unlimited == true) "لا محدود" else "${profile?.coins ?: "…"}"
    Screen {
        TopBar("شراء عملات", onBack = { navigate(Route.Menu) })
        Body("رصيدك الحالي: $balance 🪙")
        if (packs == null) Body("جارٍ تحميل الباقات…")
        packs?.forEach { p ->
            val base = p.coins - p.bonus
            val spoken = "$base عملة${if (p.bonus > 0) " زائد ${p.bonus} هدية" else ""}، بسعر ${p.price}"
            ItemRow {
                Column(Modifier.weight(1f)) {
                    Text("$base عملة", color = Palette.text, fontWeight = FontWeight.Bold)
                    if (p.bonus > 0) Text("+ ${p.bonus} هدية", color = Palette.goldSoft)
                }
                SmallButton(if (busy == p.id) "جارٍ…" else p.price, {
                    busy = p.id
                    scope.launch { Billing.buy(p.id); busy = "" }
                }, primary = true, enabled = busy.isEmpty(), description = "شراء $spoken")
            }
        }
    }
}
