package com.majlisk.app.table

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.customActions
import kotlinx.coroutines.delay
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.i18n.Text
import com.majlisk.app.i18n.tr
import com.majlisk.app.model.CardsBoardInfo
import com.majlisk.app.model.CardsDraw
import com.majlisk.app.model.CardsHeap
import com.majlisk.app.model.CardsProgress
import com.majlisk.app.model.CardsRowInfo
import com.majlisk.app.ui.Palette

/** لون العقد: شايب الهاص أحمر، البنات بنفسجي، الديمن ذهبي، اللطوش أزرق، التركس أخضر */
fun boardTone(tone: String): Color = when (tone) {
    "red" -> Color(0xFFE57373)
    "purple" -> Color(0xFFB39DDB)
    "blue" -> Color(0xFF81B7E8)
    "green" -> Color(0xFF7FCF9A)
    else -> Palette.gold
}

/** رأس اللوحة: اسم العقد بلونه، وتحته وش تتجنب، وعقود المملكة (انلعب مشطوب، الحين بلونه، الباقي باهت) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CardsBoardHeader(b: CardsBoardInfo) {
    val tone = boardTone(b.tone)
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (b.title.isNotEmpty()) Text(b.title, color = tone, fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1,
            modifier = Modifier.semantics { heading() })
        if (b.sub.isNotEmpty()) Text(b.sub, color = Palette.textDim, fontSize = 12.sp, maxLines = 2, textAlign = TextAlign.Center)
        if (b.steps.isNotEmpty()) FlowRow(
            Modifier.fillMaxWidth().padding(top = 4.dp)
                .semantics(mergeDescendants = true) {
                    contentDescription = tr("العقود: " + b.steps.joinToString("، ") { "${it.label} ${when (it.state) { "done" -> "انلعب"; "now" -> "الحين"; else -> "باقي" }}" })
                },
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            b.steps.forEach { st ->
                val now = st.state == "now"
                Text(
                    if (st.state == "done") "✓ ${st.label}" else st.label,
                    color = if (now) Color(0xFF1A1406) else if (st.state == "done") Palette.textDim else Palette.text,
                    fontSize = 11.sp, fontWeight = if (now) FontWeight.Bold else FontWeight.Normal, maxLines = 1,
                    modifier = Modifier
                        .background(if (now) tone else Color(0x14FFFFFF), RoundedCornerShape(20.dp))
                        .padding(horizontal = 8.dp, vertical = 2.dp)
                        .alpha(if (st.state == "done") 0.6f else 1f)
                        .clearAndSetSemantics { },
                )
            }
        }
    }
}

/** الأوراق الخطرة في العقد (شايب الهاص، البنات): اللي ما انأكلت واضحة، واللي انأكلت باهتة وتحتها اسم اللي أكلها */
@Composable
fun CardsMarksRow(b: CardsBoardInfo) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.clearAndSetSemantics { }) {
        b.marks.forEach { m ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CardsFace(m.card, 26, 38, modifier = Modifier.alpha(if (m.by == null) 1f else 0.4f))
                Text(m.by ?: " ", color = boardTone(b.tone), fontSize = 9.sp, maxLines = 1, modifier = Modifier.width(44.dp), textAlign = TextAlign.Center)
            }
        }
    }
}

/** خانة فاضية مكان الورقة اللي تنزل بعدها في صف التركس (ذهبية إذا معك) */
@Composable
private fun RowSlot(label: String, mine: Boolean) {
    Box(
        Modifier.size(24.dp, 34.dp)
            .background(if (mine) Palette.gold.copy(alpha = 0.35f) else Color(0x10FFFFFF), RoundedCornerShape(6.dp))
            .border(1.dp, if (mine) Palette.gold else Color(0x55FFFFFF), RoundedCornerShape(6.dp)),
        contentAlignment = Alignment.Center,
    ) { Text(label, color = if (mine) Palette.gold else Palette.textDim, fontSize = 9.sp, maxLines = 1) }
}

/** صفوف التركس على الطاولة: كل نوع صف، الولد في النص، والأصغر من جهة والأكبر من الجهة الثانية */
@Composable
fun TrixRows(rows: List<CardsRowInfo>) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        rows.forEach { r ->
            Row(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = tr(r.text) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                val red = r.id.endsWith("H") || r.id.endsWith("D")
                Text(r.title, color = if (red) Color(0xFFEF9A9A) else Palette.text, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    modifier = Modifier.width(40.dp).clearAndSetSemantics { })
                Row(
                    Modifier.weight(1f).clearAndSetSemantics { },
                    horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
                ) {
                    r.low?.let { RowSlot(it, r.lowMine) }
                    Row(horizontalArrangement = Arrangement.spacedBy(if (r.cards.size > 6) (-11).dp else 2.dp)) { r.cards.forEach { CardsFace(it, 24, 34) } }
                    r.high?.let { RowSlot(it, r.highMine) }
                }
            }
        }
    }
}

/** ظهر الورقة (كومة السحب) */
@Composable
private fun CardBack(w: Int, h: Int) {
    Box(
        Modifier.size(w.dp, h.dp)
            .background(Brush.linearGradient(listOf(Color(0xFF7A2E2E), Color(0xFF4A1A1A))), RoundedCornerShape(7.dp))
            .border(2.dp, Color(0xFFE9D7A6), RoundedCornerShape(7.dp)),
    )
}

/** الكنكان: كومة السحب (مقلوبة) وكومة الأرض (آخر ورقة مكشوفة)، وتنضغط إذا تقدر تسحب منها */
@Composable
fun KonkanHeaps(stock: CardsHeap?, discard: CardsHeap?, onStock: () -> Unit, onDiscard: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
        stock?.let { st ->
            Column(
                Modifier.border(2.dp, if (st.can) Palette.gold else Color.Transparent, RoundedCornerShape(10.dp)).padding(4.dp)
                    .then(if (st.can) Modifier.clickable(role = Role.Button, onClick = onStock) else Modifier)
                    .semantics(mergeDescendants = true) { contentDescription = tr(st.text) },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box { CardBack(40, 58); Box(Modifier.padding(start = 3.dp, top = 3.dp)) { CardBack(40, 58) } }
                Text("السحب ${st.count}", color = Palette.textDim, fontSize = 10.sp, modifier = Modifier.clearAndSetSemantics { })
            }
        }
        discard?.let { d ->
            Column(
                Modifier.border(2.dp, if (d.can) Palette.gold else Color.Transparent, RoundedCornerShape(10.dp)).padding(4.dp)
                    .then(if (d.can) Modifier.clickable(role = Role.Button, onClick = onDiscard) else Modifier)
                    .semantics(mergeDescendants = true) { contentDescription = tr(d.text) },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (d.card != null) CardsFace(d.card, 40, 58)
                else Box(Modifier.size(40.dp, 58.dp).border(1.dp, Color(0x55FFFFFF), RoundedCornerShape(7.dp)))
                Text("الأرض ${d.count}", color = Palette.textDim, fontSize = 10.sp, modifier = Modifier.clearAndSetSemantics { })
            }
        }
    }
}

/** شريط الفتح في الكنكان: مجموع تنزيلك من الـ51 (يصير أخضر لما يكمل) */
@Composable
fun KonkanProgress(p: CardsProgress) {
    val done = p.value >= p.need
    val frac = (p.value.toFloat() / p.need).coerceIn(0f, 1f)
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = tr(p.text) }) {
        Text(p.text, color = if (done) Color(0xFF7FCF9A) else Palette.goldSoft, fontSize = 12.sp, maxLines = 2, modifier = Modifier.clearAndSetSemantics { })
        Box(Modifier.fillMaxWidth().height(6.dp).background(Color(0x22FFFFFF), RoundedCornerShape(3.dp)).clearAndSetSemantics { }) {
            Box(Modifier.fillMaxWidth(frac).height(6.dp).background(if (done) Color(0xFF7FCF9A) else Palette.gold, RoundedCornerShape(3.dp)))
        }
    }
}

/**
 * الشايب: أوراق اللي تسحب منه مقلوبة صغيرة فوق الطاولة. تضغط وحدة: تنقلب (3D) وتنزل لأوراقك وتنرسل الحركة.
 * قارئ الشاشة: عنصر واحد «أوراق فلان»، والإجراءات «كرت 1، كرت 2…».
 */
@Composable
fun ShayebDrawRow(d: CardsDraw, onPick: (Int) -> Unit) {
    var picked by remember(d.seat, d.count) { mutableStateOf<Int?>(null) }
    LaunchedEffect(picked) {
        picked?.let {
            // صوت السحب على طول وقت الضغط (ما ينعاد لما يوصل رد الخادم)
            com.majlisk.app.data.Sounds.cardsFx(listOf("c-draw"), null); com.majlisk.app.data.Sounds.markLocal("cards")
            delay(320); onPick(it)
        }
    }
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = tr("اسحب من ${d.name}: معه ${d.count} ${if (d.count == 1) "ورقة" else "أوراق"} مقلوبة. اختر كرت من الإجراءات")
            customActions = (1..d.count).map { i -> com.majlisk.app.i18n.A11yAction("كرت $i") { if (picked == null) picked = i - 1; true } }
        },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text("اسحب من ${d.name}", color = Palette.goldSoft, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clearAndSetSemantics { })
        Row(Modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(if (d.count > 9) (-8).dp else 4.dp)) {
            repeat(d.count) { i ->
                val on = picked == i
                val rot by animateFloatAsState(if (on) 180f else 0f, tween(300), label = "flip")
                val drop by animateFloatAsState(if (on) 1f else 0f, tween(300), label = "drop")
                Box(
                    Modifier.graphicsLayer {
                        rotationY = rot
                        cameraDistance = 12f * density
                        translationY = drop * 60.dp.toPx()
                        scaleX = 1f + drop * 0.25f; scaleY = 1f + drop * 0.25f
                    }.clickable(enabled = picked == null) { picked = i },
                ) {
                    Box(
                        Modifier.size(26.dp, 38.dp)
                            .background(Brush.linearGradient(listOf(Color(0xFF7A2E2E), Color(0xFF4A1A1A))), RoundedCornerShape(5.dp))
                            .border(1.5.dp, if (on) Palette.gold else Color(0xFFE9D7A6), RoundedCornerShape(5.dp)),
                    )
                }
            }
        }
    }
}
