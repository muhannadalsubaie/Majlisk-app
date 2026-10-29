package com.majlisk.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
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
    var chime by remember { mutableStateOf(Prefs.turnChime) }
    var confirmDelete by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val site = Api.BASE.removeSuffix("/api")

    val body = @Composable {
        TopBar("الإعدادات", onBack = onBack)
        SectionTitle("الصوت")
        SwitchRow("كتم عام لجميع الأصوات", muted, { muted = it; Prefs.muted = it })
        SwitchRow("نغمة دورك", chime, { chime = it; Prefs.turnChime = it })
        if (!embedded) {
            SectionTitle("الحساب")
            SecondaryButton("تسجيل الخروج", { Session.signOut() }, fill = true)
            DangerButton("حذف الحساب", { confirmDelete = true })
            SecondaryButton("سياسة الخصوصية", { AuthService.openUrl(context, "$site/privacy.html") }, fill = true)
        }
        // رخصة صور الكروت (LGPL) تشترط ذكرها مع رابط المصدر والرخصة
        Note("صور الكروت: Vectorized Playing Cards لكريس أغيلار (Chris Aguilar)، رخصة LGPL-3.0.")
        SecondaryButton("مصدر صور الكروت", { AuthService.openUrl(context, "https://github.com/richardschneider/cardsJS/tree/master/cards") }, fill = true)
        SecondaryButton("رخصة صور الكروت", { AuthService.openUrl(context, "https://www.gnu.org/licenses/lgpl-3.0.html") }, fill = true)
        Note("المؤثرات الصوتية: Kenney، رخصة CC0")
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
