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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
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
fun MainMenuScreen(profile: Profile?, navigate: (Route) -> Unit, openTable: (String) -> Unit = {}) {
    var getCoins by remember { mutableStateOf(false) }
    Screen(scroll = false) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // صورتك الدائرية: تفتح الملف الشخصي
            Box(Modifier.clickable(role = androidx.compose.ui.semantics.Role.Button) { navigate(Route.Profile) }
                .semantics(mergeDescendants = true) { contentDescription = "الملف الشخصي" }) {
                Avatar(com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid, profile?.username.orEmpty(), 48.dp)
            }
            Column(Modifier.weight(1f)) {
                Title("مجلسك")
                if (!profile?.username.isNullOrEmpty()) Note("أهلاً ${profile?.username}")
                // عدد المتصلين في التطبيق كله (يتحدث على طول)، والضغط يعرض أسماءهم
                OnlineLine(openTable)
            }
            CoinsBadge(profile)
        }
        // شعار التطبيق في المنتصف، والقائمة في أسفل الشاشة
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { Logo(180) }
        // الباقة الاحترافية: زر ذهبي بارز (للمشترك: «باقتك الاحترافية»)
        if (profile?.proAccess == true || profile?.isPro == true) GoldButton(if (profile?.isPro == true) "👑 باقتك الاحترافية" else "👑 الباقة الاحترافية", { navigate(Route.Pro) })
        PrimaryButton("إنشاء طاولة", { navigate(Route.CreateTable) })
        PrimaryButton("انضمام إلى طاولة", { navigate(Route.JoinTable) })
        SecondaryButton("الأصدقاء", { navigate(Route.Friends) }, fill = true)
        SecondaryButton("الحصول على عملات 🪙", { getCoins = true }, fill = true)
        SecondaryButton("الملف الشخصي", { navigate(Route.Profile) }, fill = true)
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
    // من الواجهة الذهبية: اللعبة مختارة على طول
    var picked by remember { mutableStateOf<String?>(PendingGame.game.also { PendingGame.game = null }) }
    // الجاكارو: عادي أو كمبلكس — لودو: فردي أو فرق
    var variant by remember { mutableStateOf("classic") }
    var isPrivate by remember { mutableStateOf(false) }
    var pinned by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    // الرجوع من إعدادات اللعبة يرجعك لقائمة الألعاب أولاً، والرجوع منها للقائمة الرئيسية
    androidx.activity.compose.BackHandler(enabled = picked != null) { picked = null }
    if (picked == null) {
        Screen {
            TopBar("اختر اللعبة", onBack = { navigate(Route.Menu) })
            Spacer(Modifier.height(28.dp))
            GameTile("بلوت", com.majlisk.app.R.drawable.baloot_table) { picked = "baloot"; variant = "classic" }
            GameTile("دومينو", com.majlisk.app.R.drawable.domino_table) { picked = "domino"; variant = "classic" }
            GameTile("جاكارو", com.majlisk.app.R.drawable.jackaroo_table) { picked = "jackaroo"; variant = "classic" }
            GameTile("لودو", com.majlisk.app.R.drawable.ludo_table) { picked = "ludo"; variant = "classic" }
        }
        return
    }
    Screen {
        TopBar("طاولة ${gameTitle(picked!!, variant)}", onBack = { picked = null })
        val variants = when (picked) {
            "jackaroo" -> listOf("classic" to "عادي", "complex" to "كمبلكس")
            "ludo" -> listOf("classic" to "فردي", "teams" to "فرق")
            "domino" -> listOf("classic" to "100", "t150" to "150", "t200" to "200")
            else -> emptyList()
        }
        if (variants.isNotEmpty()) {
            Text(if (picked == "domino") "هدف المباراة (نقاط)" else "النسخة", color = Palette.textDim, modifier = Modifier.semantics { heading() })
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                variants.forEach { (id, label) ->
                    if (variant == id) PrimaryButton("✓ $label", { }, modifier = Modifier.weight(1f), description = "$label، محددة")
                    else SecondaryButton(label, { variant = id }, modifier = Modifier.weight(1f), fill = true)
                }
            }
        }
        val balance = if (profile?.unlimited == true) "لا محدود" else "${profile?.coins ?: "…"} عملة"
        SwitchRow("طاولة خاصة", isPrivate, { isPrivate = it })
        // الطاولة الثابتة بكلمة مرور: للمشترك في الباقة الاحترافية (ما تتقفل لو فضيت)
        if (profile?.isPro == true) {
            SwitchRow("👑 طاولة ثابتة بكلمة مرور", pinned, { pinned = it }, description = "ما تتقفل لو فضيت، وتدخلها بكلمة مرور")
            if (pinned) androidx.compose.material3.OutlinedTextField(
                value = password, onValueChange = { password = it.take(20) }, label = { Text("كلمة المرور (4 أحرف أو أكثر)") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700, focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim),
            )
        }
        if (error.isNotEmpty()) Text(error, color = Palette.goldSoft, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
        PrimaryButton("إنشاء الطاولة (2 🪙)", {
            busy = true; error = ""
            scope.launch {
                runCatching { Tables.create(isPrivate, picked!!, variant, if (pinned && profile?.isPro == true) password.trim() else null) }
                    .onSuccess { Announcer.announce("تم إنشاء الطاولة"); openTable(it) }
                    .onFailure { error = Tables.error(it, "تعذّر إنشاء الطاولة، حاول مرة أخرى"); Announcer.announce(error) }
                busy = false
            }
        }, enabled = !busy && (!pinned || password.trim().length >= 4))
    }
}

private val STATUS = mapOf("waiting" to "في الانتظار", "playing" to "قيد اللعب", "finished" to "في الانتظار")

@Composable
fun JoinTableScreen(navigate: (Route) -> Unit, openTable: (String) -> Unit) {
    var rows by remember { mutableStateOf<List<TableRow>?>(null) }
    var busy by remember { mutableStateOf("") }
    // ضغطة مطولة على طاولة: قائمة الموجودين فيها
    var showing by remember { mutableStateOf<TableRow?>(null) }
    // طاولة ثابتة بكلمة مرور: نطلب الكلمة قبل الدخول
    var asking by remember { mutableStateOf<TableRow?>(null) }
    var pass by remember { mutableStateOf("") }
    var passError by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    DisposableEffect(Unit) {
        // ترتيب ثابت (الطاولة لا تتحرك من مكانها كل حركة لعب، والجديدة تظهر فوق)، ولا نحدّث القائمة إلا إذا تغيّر ما يُقرأ،
        // حتى لا يعيد قارئ الشاشة قراءة الطاولة المحددة كل شوي
        // الطاولات الخاصة ما تظهر في القائمة (ولا من فيها)، وترجع تظهر أول ما تصير عامة
        val reg = Tables.listen { all ->
            val new = all.filter { !it.isPrivate }
            val old = rows
            val pos = old.orEmpty().withIndex().associate { it.value.id to it.index }
            val sorted = new.sortedBy { pos[it.id] ?: -1 }
            if (old == null || sorted != old) rows = sorted
        }
        onDispose { reg.remove() }
    }
    Screen {
        TopBar("الطاولات النشطة", onBack = { navigate(Route.Menu) })
        when {
            rows == null -> Text("جارٍ التحميل…", color = Palette.text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            rows!!.isEmpty() -> Text("لا توجد طاولات الآن — أنشئ طاولة جديدة.", color = Palette.text, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        }
        rows?.forEach { r -> androidx.compose.runtime.key(r.id) {
            val game = gameTitle(r.kind, r.variant)
            val spoken = "طاولة ${r.ownerName}، $game، ${if (r.isPrivate) "مقفلة، " else if (r.locked) "ثابتة بكلمة مرور، " else ""}عدد الموجودين ${r.people}، ${STATUS[r.status].orEmpty()}"
            SecondaryButton(
                "${if (r.isPrivate) "🔒 " else if (r.locked) "👑🔑 " else ""}طاولة ${r.ownerName} · $game · الموجودين ${r.people} · ${STATUS[r.status].orEmpty()}",
                {
                    if (r.locked) { asking = r; pass = ""; passError = ""; return@SecondaryButton }
                    busy = r.id
                    scope.launch {
                        runCatching { Tables.join(r.id) }
                            .onSuccess { openTable(r.id) }
                            .onFailure { Announcer.announce(Tables.error(it, "تعذّر الانضمام")) }
                        busy = ""
                    }
                },
                enabled = !r.isPrivate && busy != r.id,
                description = spoken,
                fill = true,
                onLongClick = { showing = r },
                longClickLabel = "عرض الموجودين",
            )
        } }
    }
    asking?.let { r ->
        MajliskDialog("كلمة مرور طاولة ${r.ownerName}", { asking = null }) {
            androidx.compose.material3.OutlinedTextField(
                value = pass, onValueChange = { pass = it.take(20); passError = "" }, label = { Text("كلمة المرور") },
                singleLine = true, modifier = Modifier.fillMaxWidth(),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700, focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim),
            )
            if (passError.isNotEmpty()) Text(passError, color = Palette.goldSoft)
            PrimaryButton("دخول", {
                busy = r.id
                scope.launch {
                    runCatching { Tables.join(r.id, pass.trim()) }
                        .onSuccess { asking = null; openTable(r.id) }
                        .onFailure { passError = Tables.error(it, "تعذّر الانضمام"); Announcer.announce(passError) }
                    busy = ""
                }
            }, enabled = pass.isNotBlank() && busy.isEmpty())
            SecondaryButton("إلغاء", { asking = null }, fill = true)
        }
    }
    showing?.let { r ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showing = null },
            confirmButton = { androidx.compose.material3.TextButton({ showing = null }) { Text("تم") } },
            title = { Text("الموجودين في طاولة ${r.ownerName}") },
            text = { Text(r.membersText) },
        )
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
        // النص مخفي عن قارئ الشاشة حتى لا يُقرأ الاسم مرتين
        Text(name, color = Palette.green900, fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).clearAndSetSemantics {})
        androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(image), contentDescription = null, modifier = Modifier.height(128.dp))
    }
}
