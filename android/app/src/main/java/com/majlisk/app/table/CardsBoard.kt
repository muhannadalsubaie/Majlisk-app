package com.majlisk.app.table

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
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
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Sounds
import com.majlisk.app.data.TableConnection
import com.majlisk.app.i18n.Text
import com.majlisk.app.i18n.tr
import com.majlisk.app.model.CardFace
import com.majlisk.app.model.CardsView
import com.majlisk.app.model.TableView
import com.majlisk.app.net.jsonOf
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import kotlinx.coroutines.delay
import org.json.JSONArray

/** ورقة مرسومة: رقمها ونوعها (الأحمر للهاص والديمن)، والجوكر نجمة */
@Composable
fun CardsFace(c: CardFace, w: Int, h: Int, dim: Boolean = false, modifier: Modifier = Modifier) {
    Box(
        modifier.size(w.dp, h.dp)
            .background(if (dim) Color(0xFFCFCABB) else Color.White, RoundedCornerShape(7.dp))
            .border(1.dp, Color(0xFFB9B4A6), RoundedCornerShape(7.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "${c.short}${c.symbol}",
            color = if (c.joker) Color(0xFF6A3FB5) else if (c.red) Color(0xFFC62828) else Color(0xFF1A1A1A),
            fontSize = (w * 0.36f).sp, fontWeight = FontWeight.Bold, maxLines = 1,
            modifier = Modifier.clearAndSetSemantics { },
        )
    }
}

/**
 * لوحة ألعاب الورق الجديدة (طرنيب، تريكس، كنكان، شايب): نفس الشكل للأربع، والخادم يحدد المحتوى.
 * كل جزء له مكان محجوز (الحالة، النقاط، اللاعبين، الأرض، الأزرار، الأوراق) فالشاشة ما تتحرك.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CardsBoard(v: TableView, c: CardsView, conn: TableConnection, isOwner: Boolean, modifier: Modifier = Modifier) {
    val latest by rememberUpdatedState(c)
    // الكنكان: الأوراق المحددة (تنمسح لما تنلعب أو يخلص دورك)
    var selected by remember { mutableStateOf(setOf<Int>()) }
    val handIds = c.hand.map { it.face.id }.toSet()
    if (selected.any { it !in handIds }) selected = selected.filter { it in handIds }.toSet()
    val send = { action: org.json.JSONObject ->
        if (Announcer.readerOn) Announcer.interruptNextEvents()
        conn.send(jsonOf("type" to "cards", "action" to action))
    }
    val press = { id: String, needs: Boolean ->
        when {
            needs && selected.isEmpty() -> Announcer.announceNow("حدد أوراق أول")
            else -> {
                val a = jsonOf("op" to "button", "id" to id)
                if (needs || id.startsWith("pile:")) a.put("cards", JSONArray(selected.toList()))
                send(a)
                if (needs || id.startsWith("pile:")) selected = emptySet()
            }
        }
    }

    // جاك الدور: نغمة الدور، وقارئ الشاشة يقول وش المطلوب
    LaunchedEffect(c.myTurn, c.prompt) {
        if (c.myTurn) {
            Sounds.turn(Announcer.readerOn)
            if (c.prompt.isNotEmpty() && Announcer.readerOn) { delay(350); Announcer.announce(c.prompt) }
        }
    }

    Column(
        modifier.fillMaxWidth().twoFingerSwipes {
            val x = latest
            Announcer.announceNow(when (it) { SwipeDir.Up -> x.readUp; SwipeDir.Down -> x.readDown; SwipeDir.Left -> x.readLeft; SwipeDir.Right -> x.readRight })
        },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        // الحالة: سطر واحد ثابت
        Text(c.status.ifEmpty { " " }, color = Palette.goldSoft, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().semantics { heading() })
        // النقاط
        Row(Modifier.fillMaxWidth().heightIn(min = 34.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            c.scores.forEach { (name, value) ->
                Column(
                    Modifier.weight(1f).background(Color(0xFF173D2C), RoundedCornerShape(10.dp)).padding(vertical = 3.dp)
                        .semantics(mergeDescendants = true) { contentDescription = tr("$name $value") },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(name, color = Palette.textDim, fontSize = 11.sp, maxLines = 1)
                    Text("$value", color = Palette.gold, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        // اللاعبين: اسم كل واحد، وكم ورقة معه، وملاحظته، ومؤقت اللي عليه الدور
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            c.seats.forEach { s ->
                Column(
                    Modifier.weight(1f).heightIn(min = 58.dp).background(Color(0x22FFFFFF), RoundedCornerShape(10.dp)).padding(4.dp)
                        .semantics(mergeDescendants = true) {
                            contentDescription = tr("${if (s.seat == v.mySeat) "أنت" else s.name}، ${s.count} ${if (s.count == 1) "ورقة" else "أوراق"}${if (s.note.isNotEmpty()) "، ${s.note}" else ""}")
                        },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(if (s.seat == v.mySeat) "أنت" else s.name, color = Palette.text, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                        TurnClock(v, s.seat, s.turn)
                    }
                    Text("🂠 ${s.count}", color = Palette.textDim, fontSize = 12.sp)
                    Text(s.note.ifEmpty { " " }, color = Palette.goldSoft, fontSize = 11.sp, maxLines = 1)
                }
            }
        }
        // الأرض: الأكلة الحالية (أو آخر المكب في الكنكان) — مكان ثابت
        Box(
            Modifier.fillMaxWidth().height(96.dp).background(Color(0xFF0F3B2A), RoundedCornerShape(14.dp))
                .semantics(mergeDescendants = true) { contentDescription = tr(c.readLeft) },
            contentAlignment = Alignment.Center,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                c.center.forEach { (seat, face) ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CardsFace(face, 46, 66)
                        Text(if (seat < 0) "المكب" else c.seats.firstOrNull { it.seat == seat }?.name.orEmpty(), color = Palette.textDim, fontSize = 10.sp, maxLines = 1,
                            modifier = Modifier.width(56.dp).clearAndSetSemantics { }, textAlign = TextAlign.Center)
                    }
                }
            }
        }
        // المجموعات (تنزيلات الكنكان، صفوف التركس): تنضغط في الكنكان للصق المحدد عليها
        Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            c.piles.forEach { p ->
                val canLay = c.select && c.myTurn && p.id.startsWith("meld:")
                Row(
                    Modifier.fillMaxWidth().background(Color(0x18FFFFFF), RoundedCornerShape(10.dp))
                        .then(if (canLay) Modifier.clickable(role = Role.Button) { press("pile:${p.id}", true) } else Modifier)
                        .padding(4.dp)
                        .semantics(mergeDescendants = true) { contentDescription = tr("${p.title}، ${p.text}${if (canLay) "، اضغط للصق الأوراق المحددة" else ""}") },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text(p.title, color = Palette.goldSoft, fontSize = 12.sp, maxLines = 1, modifier = Modifier.width(70.dp))
                    p.cards.forEach { CardsFace(it, 24, 34) }
                }
            }
        }
        // الأزرار: مكان محجوز دايماً
        FlowRow(Modifier.fillMaxWidth().heightIn(min = 52.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            c.buttons.forEach { b ->
                if (b.primary) PrimaryButton(b.label, { press(b.id, b.needsSelection) })
                else SecondaryButton(b.label, { press(b.id, b.needsSelection) })
            }
            if (c.over && isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        }
        // أوراقك: كل ورقة مربوطة بمكانها في اليد (مثل البلوت) فالمؤشر ما يقفز بعد ما تلعب
        Text(if (c.select && selected.isNotEmpty()) "محدد ${selected.size}" else " ", color = Palette.goldSoft, fontSize = 12.sp,
            modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }, textAlign = TextAlign.Center)
        val slotFocus = remember { mutableMapOf<Int, FocusRequester>() }
        var playedPos by remember { mutableStateOf<Int?>(null) }
        val handSize = c.hand.size
        LaunchedEffect(handSize) {
            val p = playedPos ?: return@LaunchedEffect
            playedPos = null
            if (p >= handSize && handSize > 0 && Announcer.readerOn) { delay(50); runCatching { slotFocus[handSize - 1]?.requestFocus() } }
        }
        FlowRow(Modifier.fillMaxWidth().heightIn(min = 76.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            c.hand.forEachIndexed { i, h ->
                key(i) {
                    val fr = remember { FocusRequester() }
                    DisposableEffect(Unit) {
                        slotFocus[i] = fr
                        onDispose { if (slotFocus[i] === fr) slotFocus.remove(i) }
                    }
                    val sel = h.face.id in selected
                    Box(
                        Modifier.focusRequester(fr)
                            .border(2.dp, if (sel) Palette.gold else if (h.legal && !c.select) Palette.gold.copy(alpha = 0.6f) else Color.Transparent, RoundedCornerShape(8.dp))
                            .padding(2.dp)
                            .clickable(role = Role.Button) {
                                when {
                                    c.select -> { selected = if (sel) selected - h.face.id else selected + h.face.id; Announcer.announceNow(if (sel) "شلت التحديد" else "محددة") }
                                    !c.myTurn -> Announcer.announceNow("ليس دورك")
                                    !h.legal -> Sounds.illegal()
                                    else -> { playedPos = i; send(jsonOf("op" to "card", "id" to h.face.id)) }
                                }
                            }
                            .semantics(mergeDescendants = true) { contentDescription = tr(h.label + if (sel) "، محددة" else "") },
                    ) { CardsFace(h.face, 40, 58, dim = c.myTurn && !c.select && !h.legal) }
                }
            }
        }
    }
}
