package com.majlisk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Ads
import com.majlisk.app.data.Profile
import com.majlisk.app.data.TableRow
import com.majlisk.app.data.Tables
import com.majlisk.app.data.gameTitle
import kotlinx.coroutines.launch

@Composable
fun CoinsBadge(profile: Profile?) {
    val text = when {
        profile?.unlimited == true -> "🪙 ∞"
        else -> "🪙 ${profile?.coins ?: "…"}"
    }
    val spoken = when {
        profile?.unlimited == true -> "رصيدك عملات لا محدودة، حساب المطوّر"
        profile?.coins == null -> "الرصيد غير متاح بعد"
        else -> "رصيدك ${profile?.coins} عملة"
    }
    Text(text, color = Palette.gold, style = androidx.compose.material3.MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { contentDescription = spoken })
}

@Composable
fun MainMenuScreen(profile: Profile?, navigate: (Route) -> Unit) {
    var getCoins by remember { mutableStateOf(false) }
    Screen(scroll = false) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Title("مجلسك")
                if (!profile?.username.isNullOrEmpty()) Note("أهلاً ${profile?.username}")
            }
            CoinsBadge(profile)
        }
        // شعار التطبيق في المنتصف، والقائمة في أسفل الشاشة
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { Logo(180) }
        PrimaryButton("إنشاء طاولة", { navigate(Route.CreateTable) })
        PrimaryButton("انضمام إلى طاولة", { navigate(Route.JoinTable) })
        SecondaryButton("الأصدقاء", { navigate(Route.Friends) }, fill = true)
        SecondaryButton("الحصول على عملات 🪙", { getCoins = true }, fill = true)
        SecondaryButton("الإعدادات", { navigate(Route.Settings) }, fill = true)
    }
    if (getCoins) {
        MajliskDialog("الحصول على عملات", { getCoins = false }) {
            PrimaryButton("شراء عملات", { getCoins = false; navigate(Route.Shop) })
            PrimaryButton("مشاهدة إعلان (+2 🪙)", { getCoins = false; Ads.watch() }, description = "مشاهدة إعلان للحصول على عملتين")
            SecondaryButton("إلغاء", { getCoins = false }, fill = true)
        }
    }
}

@Composable
fun CreateTableScreen(profile: Profile?, navigate: (Route) -> Unit, openTable: (String) -> Unit) {
    // أولاً تختار اللعبة، ثم إعدادات الطاولة
    var picked by remember { mutableStateOf<String?>(null) }
    var isPrivate by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    if (picked == null) {
        Screen {
            TopBar("اختر اللعبة", onBack = { navigate(Route.Menu) })
            Spacer(Modifier.height(28.dp))
            GameTile("بلوت", com.majlisk.app.R.drawable.baloot_table) { picked = "baloot" }
            Note("الدومينو والجاكارو واللودو تُضاف قريباً لهذه النسخة.")
        }
        return
    }
    Screen {
        TopBar("طاولة ${gameTitle(picked!!, "classic")}", onBack = { picked = null })
        val balance = if (profile?.unlimited == true) "لا محدود" else "${profile?.coins ?: "…"} عملة"
        Note("رصيدك: $balance. إنشاء الطاولة بعملتين، وكل روبوت تضيفه بعملة.")
        SwitchRow("طاولة خاصة", isPrivate, { isPrivate = it }, "الطاولة الخاصة تظهر في القائمة مقفلة، ولا يدخلها إلا من تدعوه.")
        if (error.isNotEmpty()) Text(error, color = Palette.goldSoft, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
        PrimaryButton("إنشاء الطاولة (2 🪙)", {
            busy = true; error = ""
            scope.launch {
                runCatching { Tables.create(isPrivate, picked!!, "classic") }
                    .onSuccess { Announcer.announce("تم إنشاء الطاولة"); openTable(it) }
                    .onFailure { error = Tables.error(it, "تعذّر إنشاء الطاولة، حاول مرة أخرى"); Announcer.announce(error) }
                busy = false
            }
        }, enabled = !busy)
    }
}

private val STATUS = mapOf("waiting" to "بانتظار اللاعبين", "playing" to "جارية", "finished" to "بانتظار مباراة جديدة")

@Composable
fun JoinTableScreen(navigate: (Route) -> Unit, openTable: (String) -> Unit) {
    var rows by remember { mutableStateOf<List<TableRow>?>(null) }
    var busy by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    DisposableEffect(Unit) {
        val reg = Tables.listen { rows = it }
        onDispose { reg.remove() }
    }
    Screen {
        TopBar("الطاولات النشطة", onBack = { navigate(Route.Menu) })
        Note("الانضمام بعملة واحدة. إن كانت المقاعد ممتلئة تدخل مشاهداً.")
        when {
            rows == null -> Text("جارٍ التحميل…", color = Palette.text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            rows!!.isEmpty() -> Text("لا توجد طاولات الآن — أنشئ طاولة جديدة.", color = Palette.text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        }
        rows?.forEach { r ->
            val game = gameTitle(r.kind, r.variant)
            val soon = r.kind != "baloot"
            val spoken = "$game، طاولة ${r.ownerName}، ${if (r.isPrivate) "مقفلة، " else ""}${r.players} من 4 لاعبين، ${r.people} حاضرين، ${STATUS[r.status].orEmpty()}${if (soon) "، قريباً في هذه النسخة" else ""}"
            SecondaryButton(
                "${if (r.isPrivate) "🔒 " else ""}طاولة ${r.ownerName} · $game · ${r.players}/4 · ${STATUS[r.status].orEmpty()}",
                {
                    busy = r.id
                    scope.launch {
                        runCatching { Tables.join(r.id) }
                            .onSuccess { openTable(r.id) }
                            .onFailure { Announcer.announce(Tables.error(it, "تعذّر الانضمام")) }
                        busy = ""
                    }
                },
                enabled = !r.isPrivate && !soon && busy != r.id,
                description = spoken,
                fill = true,
            )
        }
    }
}

/** مربع لعبة عريض: اسمها على اليمين وصورتها على اليسار، ويُقرأ زراً واحداً باسم اللعبة */
@Composable
fun GameTile(name: String, image: Int, onClick: () -> Unit) {
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp)
    Row(
        Modifier.fillMaxWidth().height(150.dp)
            .shadow(10.dp, shape)
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color(0xFFE2C45E), Palette.gold, Color(0xFFAE8E2D))), shape)
            .clickable(role = androidx.compose.ui.semantics.Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = name }
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, color = Palette.green900, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(image), contentDescription = null, modifier = Modifier.height(128.dp))
    }
}
