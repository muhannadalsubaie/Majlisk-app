package com.majlisk.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.majlisk.app.R
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Billing
import com.majlisk.app.data.Profile
import com.majlisk.app.net.Api
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.launch

/** ألوان الباقة الاحترافية: ليلي وذهبي */
object Pro {
    val night = Color(0xFF10161C)
    val night2 = Color(0xFF1F2A35)
    val deep = Color(0xFF0B0F14)
    val gold = Color(0xFFD9B45A)
    val goldLight = Color(0xFFF1DDA0)
    val goldDark = Color(0xFF8A6A22)
    val ink = Color(0xFF2A1E05)
    val dim = Color(0xFFB9C4BD)
    val emerald = Color(0xFF1B7557)
    val emeraldLight = Color(0xFF2FA57B)
}

/** مزايا الباقة (نفس الترتيب في كل الشاشات) */
val PRO_FEATURES = listOf(
    "اللعب بدون عملات طول مدة الاشتراك",
    "طاولات وألوان وأشكال مميزة لكل الألعاب",
    "طاولة ثابتة باسمك وبكلمة مرور",
    "إعلان المشاريع يدوي، والقيد والقطع",
    "زر «ورق» متاح لك حتى لو مو دورك",
    "تشغيل وإيقاف المؤقت أثناء اللعب",
    "إهداء الباقة لأي لاعب",
)

/** زر ذهبي بارز (عمق وظل) */
@Composable
fun GoldButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, emerald: Boolean = false) =
    RaisedButton(text, onClick, modifier.fillMaxWidth(), base = if (emerald) Pro.emerald else Pro.gold, content = if (emerald) Color.White else Pro.ink, enabled = enabled, minHeight = 56.dp, fontSize = 19.sp)

@Composable
private fun Crown(size: Int, modifier: Modifier = Modifier) {
    Box(
        modifier.size(size.dp).rotate(-6f).shadow(8.dp, RoundedCornerShape(30))
            .background(Brush.verticalGradient(listOf(Pro.goldLight, Pro.gold, Pro.goldDark)), RoundedCornerShape(30)),
        contentAlignment = Alignment.Center,
    ) { Text("👑", fontSize = (size * 0.5f).sp) }
}

/** بطاقة صغيرة لميزة: رمز فوق ونص تحت */
@Composable
private fun FeatureTile(icon: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(18.dp)).background(Pro.deep).border(1.dp, Pro.goldLight.copy(alpha = 0.2f), RoundedCornerShape(18.dp))
            .padding(vertical = 10.dp, horizontal = 4.dp).semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(icon, fontSize = 28.sp, modifier = Modifier.clearAndSetSemantics { })
        Text(label, color = Color(0xFFF4EFE2), fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, lineHeight = 15.sp)
    }
}

/** بطاقة السعر الذهبية */
@Composable
private fun PriceCard(price: String) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Brush.verticalGradient(listOf(Color(0xFF2A2413), Color(0xFF1A160B))))
            .border(1.5.dp, Pro.gold, RoundedCornerShape(20.dp)).padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics(mergeDescendants = true) { contentDescription = "السعر $price في الشهر، عرض لمدة 6 أشهر فقط" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(price, color = Pro.goldLight, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold)
        Text(" / شهر", color = Color(0xFFF4EFE2), fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Text("عرض لمدة\n6 أشهر فقط", color = Pro.dim, fontSize = 12.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.End, lineHeight = 16.sp)
    }
}

/**
 * نافذة العرض: تطلع أول ما يفتح التطبيق لغير المشتركين (وما ترجع قبل يومين لو قال «ليس الآن»)
 */
@Composable
fun ProOfferDialog(onSubscribe: () -> Unit, onDismiss: () -> Unit) {
    var price by remember { mutableStateOf(Billing.PRO_PRICE) }
    LaunchedEffect(Unit) { price = Billing.proPrice() }
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Column(
                Modifier.fillMaxWidth().shadow(24.dp, RoundedCornerShape(30.dp))
                    .clip(RoundedCornerShape(30.dp))
                    .background(Brush.verticalGradient(listOf(Pro.night2, Pro.night)))
                    .border(1.5.dp, Pro.goldLight.copy(alpha = 0.35f), RoundedCornerShape(30.dp))
                    .verticalScroll(rememberScrollState())
                    .padding(start = 18.dp, end = 18.dp, bottom = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // شريط العرض
                Text("عرض لفترة محدودة", color = Pro.ink, fontSize = 13.sp, fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier.clip(RoundedCornerShape(bottomStart = 14.dp, bottomEnd = 14.dp))
                        .background(Brush.verticalGradient(listOf(Pro.goldLight, Pro.gold))).padding(horizontal = 18.dp, vertical = 6.dp))
                // الشعار مع التاج
                Box(Modifier.size(112.dp)) {
                    Image(painterResource(R.drawable.logo), contentDescription = "شعار مجلسك",
                        modifier = Modifier.size(104.dp).align(Alignment.BottomStart).shadow(14.dp, RoundedCornerShape(26.dp))
                            .clip(RoundedCornerShape(26.dp)).border(3.dp, Pro.gold, RoundedCornerShape(26.dp)))
                    Crown(38, Modifier.align(Alignment.TopEnd).clearAndSetSemantics { })
                }
                Text("الباقة الاحترافية", color = Pro.goldLight, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.semantics { heading() })
                Text("ارفع مستوى مجلسك", color = Pro.dim, fontSize = 14.sp)
                // نماذج مصغرة من المميزات
                val tiles = listOf("🎲" to "طاولات مميزة", "🃏" to "ورق وأحجار بأشكالك", "🪙" to "العب بدون عملات",
                    "🔒" to "طاولة ثابتة بكلمة مرور", "⏱️" to "تحكم بالمؤقت ومشاريع يدوية", "🎁" to "أهدِ الباقة لصديقك")
                tiles.chunked(3).forEach { row ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { (i, t) -> FeatureTile(i, t, Modifier.weight(1f)) }
                    }
                }
                PriceCard(price)
                GoldButton("اشترك الآن", onSubscribe, emerald = true)
                Text("ليس الآن", color = Pro.dim, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(role = androidx.compose.ui.semantics.Role.Button, onClick = onDismiss).padding(top = 12.dp),
                    textAlign = TextAlign.Center)
            }
        }
    }
}

/** شاشة الباقة الاحترافية: المزايا والسعر والاشتراك، والإهداء */
@Composable
fun ProScreen(profile: Profile?, onBack: () -> Unit, onGift: () -> Unit, onLook: () -> Unit = {}) {
    var price by remember { mutableStateOf(Billing.PRO_PRICE) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { price = Billing.proPrice() }
    Screen {
        TopBar("الباقة الاحترافية", onBack = onBack)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Crown(60)
            Column {
                Text("الباقة الاحترافية", color = Pro.goldLight, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                Text("كل مزايا مجلسك في اشتراك واحد", color = Pro.dim, fontSize = 13.sp)
            }
        }
        if (profile?.isPro == true) {
            val until = java.text.SimpleDateFormat("d/M/yyyy", java.util.Locale.US).format(java.util.Date(profile.proUntil))
            Text("✓ مشترك في الباقة حتى $until", color = Pro.goldLight, fontSize = 16.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Pro.deep).border(1.dp, Pro.gold, RoundedCornerShape(16.dp)).padding(14.dp))
        }
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Pro.deep).border(1.dp, Pro.goldLight.copy(alpha = 0.16f), RoundedCornerShape(20.dp)).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp),
        ) {
            PRO_FEATURES.forEach { f ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp), modifier = Modifier.semantics(mergeDescendants = true) { }) {
                    Text("✓", color = Pro.gold, fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.clearAndSetSemantics { })
                    Text(f, color = Color(0xFFF4EFE2), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        PriceCard(price)
        if (profile?.isPro != true) GoldButton(if (busy) "جارٍ…" else "اشترك الآن", {
            busy = true
            scope.launch { Billing.buyPro(); busy = false }
        }, enabled = !busy, emerald = true)
        // إعدادات المشترك: تخصيص الشكل
        if (profile?.isPro == true) GoldButton("🎨 تخصيص الشكل", onLook)
        SecondaryButton("🎁 إهداء الباقة للاعب ثاني", onGift, fill = true)
        SecondaryButton("استعادة المشتريات", { scope.launch { Billing.syncPro(announce = true) } }, fill = true)
        Note("الاشتراك يتجدد تلقائياً كل شهر، وتقدر تلغيه في أي وقت من اشتراكات Google Play.")
    }
}

/** إهداء الباقة: اسم المستخدم ← نتأكد منه ← الدفع عنه (شهر، ما يتجدد تلقائياً) */
@Composable
fun GiftScreen(onBack: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Screen {
        TopBar("إهداء الباقة", onBack = onBack)
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(96.dp).rotate(4f).shadow(12.dp, RoundedCornerShape(28.dp))
                .background(Brush.verticalGradient(listOf(Pro.goldLight, Pro.gold, Pro.goldDark)), RoundedCornerShape(28.dp))
                .clearAndSetSemantics { }, contentAlignment = Alignment.Center) { Text("🎁", fontSize = 50.sp) }
        }
        Body("اكتب اسم المستخدم اللي تبي تهديه الباقة الاحترافية لمدة شهر، وادفع بالنيابة عنه.")
        OutlinedTextField(
            value = name, onValueChange = { name = it; found = null; error = "" },
            label = { Text("اسم المستخدم") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color(0xFFF4EFE2), unfocusedTextColor = Color(0xFFF4EFE2), focusedBorderColor = Pro.gold, unfocusedBorderColor = Pro.goldLight.copy(alpha = 0.4f), focusedLabelColor = Pro.goldLight, unfocusedLabelColor = Pro.dim),
        )
        if (found == null) SecondaryButton("تأكد من الاسم", {
            busy = true; error = ""
            scope.launch {
                runCatching { Api.post("/gift/lookup", jsonOf("username" to name.trim())) }
                    .onSuccess { r ->
                        when {
                            !r.optBoolean("found") -> error = "ما لقينا لاعب بهذا الاسم"
                            r.optBoolean("self") -> error = "هذا اسمك أنت — للاشتراك لنفسك ارجع لشاشة الباقة"
                            else -> found = r.optString("username")
                        }
                    }
                    .onFailure { error = "تعذّر التأكد الآن، حاول مرة ثانية" }
                if (error.isNotEmpty()) Announcer.announce(error) else Announcer.announce("لقينا ${found.orEmpty()}")
                busy = false
            }
        }, enabled = name.isNotBlank() && !busy, fill = true)
        if (error.isNotEmpty()) Text(error, color = Pro.goldLight, fontSize = 14.sp)
        found?.let { who ->
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Pro.night2).padding(12.dp).semantics(mergeDescendants = true) { },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(46.dp).clip(CircleShape).background(Pro.emerald), contentAlignment = Alignment.Center) {
                    Text(who.take(1), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                }
                Column(Modifier.weight(1f)) {
                    Text(who, color = Color(0xFFF4EFE2), fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Text("الباقة الاحترافية · شهر واحد · ${Billing.PRO_PRICE}", color = Pro.dim, fontSize = 13.sp)
                }
                Text("✓", color = Color(0xFF7FD48F), fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
            }
            GoldButton(if (busy) "جارٍ…" else "ادفع وأهدِ الباقة", {
                busy = true
                scope.launch { if (Billing.buyGift(who)) onBack(); busy = false }
            }, enabled = !busy)
            Note("يوصله إشعار بالهدية وتتفعل الباقة عنده شهر. ما تتجدد تلقائياً، وإذا انتهى الشهر تقدر تدفع وتجدد له شهر ثاني.")
        }
    }
}
