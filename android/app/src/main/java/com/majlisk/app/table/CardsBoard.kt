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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
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

/** لاعب حول الطاولة: صورته (ومؤقت الدور حولها)، واسمه، وكم ورقة معه، وملاحظته */
@Composable
private fun CardsSeatTag(v: TableView, s: com.majlisk.app.model.CardsSeat) {
    val me = s.seat == v.mySeat
    Column(
        Modifier.width(76.dp).semantics(mergeDescendants = true) {
            contentDescription = tr("${if (me) "أنت" else s.name}، ${s.count} ${if (s.count == 1) "ورقة" else "أوراق"}${if (s.note.isNotEmpty()) "، ${s.note}" else ""}${if (s.turn) "، عليه الدور" else ""}")
        },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TurnAvatar(v, s.seat, s.turn, v.seatUids.getOrNull(s.seat), s.name, 44.dp)
        Text(if (me) "أنت" else s.name, color = Palette.text, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text("🂠 ${s.count}", color = Palette.textDim, fontSize = 11.sp)
        Text(s.note.ifEmpty { " " }, color = Palette.goldSoft, fontSize = 11.sp, maxLines = 1)
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

    // أصوات الحركات (توزيع، ورقة، أكلة، سحب، تنزيل…): مرة لكل حركة، وأول ما تفتح الطاولة ما نشغل القديم
    var heardFx by remember { mutableStateOf(c.fx?.n) }
    LaunchedEffect(c.fx?.n) {
        val fx = c.fx ?: return@LaunchedEffect
        if (fx.n == heardFx) return@LaunchedEffect
        heardFx = fx.n
        val mine = v.mySeat
        // ورقتك: صوتها اشتغل وقت الضغط، فما نعيده لما يوصل رد الخادم
        val keys = if (mine != null && fx.by == mine && Sounds.consumeLocal("cards") && fx.keys.firstOrNull()?.let { it == "c-card" || it == "c-row" || it == "c-draw" } == true) fx.keys.drop(1) else fx.keys
        Sounds.cardsFx(keys, fx.win?.let { w -> if (mine == null || mine < 0) null else mine in w })
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
        // الطاولة مثل البلوت: اللاعبين حولها (اللي بعدك على جنب، واللي قدامك فوق) ووسطها الأرض
        val myIdx = c.seats.indexOfFirst { it.seat == v.mySeat }
        val n = c.seats.size
        val others = if (myIdx >= 0) (1 until n).map { c.seats[(myIdx + it) % n] } else c.seats.drop(1)
        val top = when (others.size) { 1 -> others[0]; 3 -> others[1]; else -> null }
        val side1 = when (others.size) { 2 -> others[0]; 3 -> others[0]; else -> null }
        val side2 = when (others.size) { 2 -> others[1]; 3 -> others[2]; else -> null }
        val stack = c.piles.firstOrNull { it.id == "stack" }
        // الأكلة المكتملة: تبقى على الطاولة لحظة (تشوف آخر ورقة) وتنشال مع صوت الأخذ، بدل ما تنتظر أول ورقة في الأكلة الجاية
        var doneHidden by remember { mutableStateOf(false) }
        val doneKey = if (c.centerDone) c.center.joinToString { "${it.first}:${it.second.id}" } else ""
        LaunchedEffect(doneKey) { doneHidden = false; if (doneKey.isNotEmpty()) { delay(850); doneHidden = true } }
        val centerShown = if (c.centerDone && doneHidden) emptyList() else c.center
        val board = c.board
        val trixRows = board?.rows.orEmpty()
        // فيه مجموعات تحت الطاولة (تنزيلات الكنكان): الطاولة أصغر عشان تبان كلها
        val hasRows = c.piles.any { it.id != "stack" }
        // المشاهد ما عنده أوراق ولا أزرار: ما نحجز لها مكان
        val watcher = myIdx < 0
        // رأس اللوحة: اسم العقد بلونه، ووش تتجنب، وعقود المملكة
        board?.let { CardsBoardHeader(it) }
        // الشايب: أوراق اللي تسحب منه مقلوبة فوق الطاولة
        board?.draw?.let { d -> ShayebDrawRow(d) { i -> press("draw:$i", false) } }
        Column(
            Modifier.fillMaxWidth()
                .background(androidx.compose.ui.graphics.Brush.radialGradient(listOf(Color(0x661B4D39), Color.Transparent)), RoundedCornerShape(24.dp))
                .padding(vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (trixRows.isNotEmpty()) {
                // التركس: اللاعبين في صف واحد فوق، والطاولة كلها بعرض الشاشة لصفوف الأنواع الأربعة
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    listOfNotNull(side1, top, side2).forEach { CardsSeatTag(v, it) }
                }
                Box(
                    Modifier.fillMaxWidth()
                        .background(Color(0xFF0F3B2A), RoundedCornerShape(22.dp))
                        .border(3.dp, Color(0xFF6B4A2B), RoundedCornerShape(22.dp)),
                ) { TrixRows(trixRows) }
            } else {
                Box(Modifier.heightIn(min = if (hasRows) 0.dp else 92.dp), contentAlignment = Alignment.Center) { top?.let { CardsSeatTag(v, it) } }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.width(76.dp), contentAlignment = Alignment.Center) { side1?.let { CardsSeatTag(v, it) } }
                    // وسط الطاولة: الأكلة الحالية (وفوقها الأوراق الخطرة وعداد العقد)، أو السحب والأرض (الكنكان)، أو كومة الأزواج (الشايب)
                    val heaps = board?.stock != null || board?.discard != null
                    val marks = board?.marks.orEmpty()
                    Box(
                        Modifier.weight(1f).height(if (marks.isNotEmpty()) 176.dp else if (hasRows) 112.dp else 150.dp)
                            .background(Color(0xFF0F3B2A), RoundedCornerShape(70.dp))
                            .border(3.dp, Color(0xFF6B4A2B), RoundedCornerShape(70.dp))
                            .then(if (heaps) Modifier else Modifier.semantics(mergeDescendants = true) {
                                contentDescription = tr(stack?.let { "${it.title}: ${it.text}" }
                                    ?: listOfNotNull(c.readLeft, board?.read?.takeIf { it.isNotEmpty() }).joinToString(". "))
                            }),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (stack != null) {
                            stack.cards.forEachIndexed { i, f ->
                                CardsFace(f, 40, 58, modifier = Modifier.graphicsLayer {
                                    rotationZ = ((i * 37) % 30 - 15).toFloat()
                                    translationX = (((i * 53) % 24) - 12).toFloat()
                                    translationY = (((i * 29) % 16) - 8).toFloat()
                                })
                            }
                        } else if (heaps) {
                            KonkanHeaps(board?.stock, board?.discard, { press("draw:stock", false) }, { press("draw:pile", false) })
                        } else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            if (marks.isNotEmpty()) CardsMarksRow(board!!)
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 70.dp)) {
                                centerShown.forEach { (seat, face) ->
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        CardsFace(face, 40, 58)
                                        Text(if (seat < 0) "الأرض" else c.seats.firstOrNull { it.seat == seat }?.name.orEmpty(), color = Palette.textDim, fontSize = 10.sp, maxLines = 1,
                                            modifier = Modifier.width(50.dp).clearAndSetSemantics { }, textAlign = TextAlign.Center)
                                    }
                                }
                            }
                            board?.counter?.takeIf { it.isNotEmpty() }?.let {
                                Text(it, color = boardTone(board?.tone.orEmpty()), fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.clearAndSetSemantics { })
                            }
                        }
                    }
                    Box(Modifier.width(76.dp), contentAlignment = Alignment.Center) { side2?.let { CardsSeatTag(v, it) } }
                }
            }
            // المشاهد: أول لاعب تحت الطاولة
            if (myIdx < 0) c.seats.firstOrNull()?.let { CardsSeatTag(v, it) }
        }
        // المجموعات (تنزيلات الكنكان، صفوف التركس): تنضغط في الكنكان للصق المحدد عليها
        Column(Modifier.fillMaxWidth().weight(1f).heightIn(min = if (hasRows) 120.dp else 0.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            var lastGroup = ""
            c.piles.filter { it.id != "stack" }.forEach { p ->
                // الكنكان: تنزيلات كل لاعب تحت اسمه
                if (p.group.isNotEmpty() && p.group != lastGroup) {
                    lastGroup = p.group
                    Text(p.group, color = Palette.gold, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 2.dp).clearAndSetSemantics { })
                }
                val canLay = c.select && c.myTurn && p.id.startsWith("meld:")
                Row(
                    Modifier.fillMaxWidth().background(Color(0x18FFFFFF), RoundedCornerShape(10.dp))
                        .then(if (canLay) Modifier.clickable(role = Role.Button) { press("pile:${p.id}", true) } else Modifier)
                        .padding(4.dp)
                        .semantics(mergeDescendants = true) { contentDescription = tr("${p.title}، ${p.text}${if (canLay) "، اضغط للصق الأوراق المحددة" else ""}") },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text(p.title, color = Palette.goldSoft, fontSize = 12.sp, maxLines = 1, modifier = Modifier.width(56.dp))
                    // صف طويل (التركس يوصل 13 ورقة): الأوراق فوق بعض شوي عشان يبان الصف كامل
                    Row(horizontalArrangement = Arrangement.spacedBy(if (p.cards.size > 8) (-8).dp else 3.dp)) { p.cards.forEach { CardsFace(it, 24, 34) } }
                }
            }
        }
        val shownButtons = c.buttons.filter { !(board?.draw != null && it.id.startsWith("draw:")) }
        // الكنكان: شريط الفتح (مجموع تنزيلك من الـ51)
        board?.progress?.let { KonkanProgress(it) }
        // الأزرار: مكان محجوز دايماً
        FlowRow(Modifier.fillMaxWidth().heightIn(min = if (watcher && !(c.over && isOwner)) 0.dp else 44.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // أزرار صغيرة مثل أزرار الشراء في البلوت (وأوراق السحب في الشايب ترسم مقلوبة فوق، ما تطلع أزرار)
            shownButtons.forEach { b -> com.majlisk.app.ui.SmallButton(b.label, { press(b.id, b.needsSelection) }, primary = b.primary) }
            if (c.over && isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        }
        // أوراقك: كل ورقة مربوطة بمكانها في اليد (مثل البلوت) فالمؤشر ما يقفز بعد ما تلعب
        if (!watcher) Text(if (c.select && selected.isNotEmpty()) "محدد ${selected.size}" else " ", color = Palette.goldSoft, fontSize = 12.sp,
            modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }, textAlign = TextAlign.Center)
        val handActions = buildList {
            board?.draw?.let { d -> for (k in 1..d.count) add(com.majlisk.app.i18n.A11yAction("اسحب كرت $k") { press("draw:${k - 1}", false); true }) }
            shownButtons.forEach { b -> add(com.majlisk.app.i18n.A11yAction(b.label) { press(b.id, b.needsSelection); true }) }
        }
        val slotFocus = remember { mutableMapOf<Int, FocusRequester>() }
        var playedPos by remember { mutableStateOf<Int?>(null) }
        val handSize = c.hand.size
        LaunchedEffect(handSize) {
            val p = playedPos ?: return@LaunchedEffect
            playedPos = null
            if (p >= handSize && handSize > 0 && Announcer.readerOn) { delay(50); runCatching { slotFocus[handSize - 1]?.requestFocus() } }
        }
        FlowRow(Modifier.fillMaxWidth().heightIn(min = if (watcher) 0.dp else 76.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
                                    else -> { playedPos = i; Sounds.cardsFx(listOf(if (c.board?.rows.isNullOrEmpty()) "c-card" else "c-row"), null); Sounds.markLocal("cards"); send(jsonOf("op" to "card", "id" to h.face.id)) }
                                }
                            }
                            .semantics(mergeDescendants = true) {
                                contentDescription = tr(h.label + if (sel) "، محددة" else "")
                                // الأزرار والسحب كإجراءات على الورقة (مثل الشراء في البلوت): الكفيف ما يحتاج يروح للأزرار
                                if (handActions.isNotEmpty()) customActions = handActions
                            },
                    ) { CardsFace(h.face, 40, 58, dim = c.myTurn && !c.select && !h.legal) }
                }
            }
        }
    }
}
