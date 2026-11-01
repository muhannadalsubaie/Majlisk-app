package com.majlisk.app.table

// الدومينو والجاكارو واللودو على طاولة مجلسك (نفس فكرة النسخة السابقة):
// الحالة والحركات المسموحة ونصوصها من الخادم، والتطبيق يرسم اللوحة ويعرض الأزرار ويرسل الحركة.
// لقارئ الشاشة: كل قطعة/ورقة/خيار زر بنص واضح، والضغط على اللوحة يقرأها كاملة، وحركات الجميع يعلنها الخادم.
// سحب بإصبعين: من اليمين لليسار = اللوحة كاملة، من اليسار لليمين = (الطرفان والنقاط) أو (أحجارك).

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
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
import com.majlisk.app.model.DominoHandTile
import com.majlisk.app.model.DominoView
import com.majlisk.app.model.JackarooHandCard
import com.majlisk.app.model.JackarooView
import com.majlisk.app.model.LudoView
import com.majlisk.app.model.PlacedTile
import com.majlisk.app.model.TableView
import com.majlisk.app.model.Tile
import com.majlisk.app.net.jsonOf
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import org.json.JSONObject
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

private fun names(v: TableView) = v.seats.mapIndexed { i, s -> s?.username ?: "المقعد ${i + 1}" }
private fun act(conn: TableConnection, game: String, action: JSONObject) = conn.send(jsonOf("type" to game, "action" to action))

/** مربع نقاط (مثل البلوت) */
@Composable
private fun ScoreTile(label: String, value: String, mine: Boolean, modifier: Modifier) {
    Column(
        modifier.background(Palette.green800, RoundedCornerShape(14.dp))
            .border(1.dp, if (mine) Palette.gold else Palette.green700, RoundedCornerShape(14.dp))
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(label, color = Palette.textDim, fontSize = 14.sp, textAlign = TextAlign.Center)
        Text(value, color = Palette.gold, fontWeight = FontWeight.Bold, fontSize = 26.sp)
    }
}

/** سطر لاعب: إطار ذهبي على من عليه الدور، وخط بلونه */
@Composable
private fun PlayerLine(text: String, turn: Boolean, color: Color? = null, spoken: String? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth()
            .border(1.dp, if (turn) Palette.gold else Color.Transparent, RoundedCornerShape(12.dp))
            .background(if (turn) Color(0x14D4AF37) else Color.Transparent, RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .let { m -> if (spoken != null) m.semantics(mergeDescendants = true) { contentDescription = spoken } else m },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (color != null) Box(Modifier.size(12.dp).background(color, RoundedCornerShape(6.dp)))
        Text(text, color = Palette.text, fontSize = 15.sp, fontWeight = if (turn) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

// ═════════════ الدومينو ═════════════

/** مواضع النقاط في نصف القطعة (كسور من العرض والارتفاع) */
private val PIPS = mapOf(
    0 to emptyList(), 1 to listOf(.5f to .5f), 2 to listOf(.25f to .25f, .75f to .75f), 3 to listOf(.25f to .25f, .5f to .5f, .75f to .75f),
    4 to listOf(.25f to .25f, .75f to .25f, .25f to .75f, .75f to .75f),
    5 to listOf(.25f to .25f, .75f to .25f, .5f to .5f, .25f to .75f, .75f to .75f),
    6 to listOf(.25f to .2f, .75f to .2f, .25f to .5f, .75f to .5f, .25f to .8f, .75f to .8f),
)

/** قطعة دومينو للعين: عمودية (a فوق) أو أفقية (a يمين) */
@Composable
private fun DominoTileView(t: Tile, vertical: Boolean, unit: Int = 22, dim: Boolean = false) {
    val w = if (vertical) unit else unit * 2
    val h = if (vertical) unit * 2 else unit
    Canvas(Modifier.size(w.dp, h.dp)) {
        val face = if (dim) Color(0xFFCFCABB) else Color(0xFFFAF7EE)
        drawRoundRect(face, cornerRadius = CornerRadius(size.minDimension * 0.18f))
        drawRoundRect(Color(0xFF9E9886), cornerRadius = CornerRadius(size.minDimension * 0.18f), style = Stroke(1.dp.toPx()))
        val half = if (vertical) Size(size.width, size.height / 2) else Size(size.width / 2, size.height)
        // الفاصل
        if (vertical) drawLine(Color(0xFF333333), Offset(size.width * 0.12f, size.height / 2), Offset(size.width * 0.88f, size.height / 2), 1.5.dp.toPx())
        else drawLine(Color(0xFF333333), Offset(size.width / 2, size.height * 0.12f), Offset(size.width / 2, size.height * 0.88f), 1.5.dp.toPx())
        val r = min(half.width, half.height) * 0.1f
        fun pips(n: Int, origin: Offset) = PIPS[n].orEmpty().forEach { (x, y) ->
            drawCircle(Color(0xFF1A1A1A), r, Offset(origin.x + x * half.width, origin.y + y * half.height))
        }
        if (vertical) { pips(t.a, Offset.Zero); pips(t.b, Offset(0f, half.height)) }
        else { pips(t.a, Offset(half.width, 0f)); pips(t.b, Offset.Zero) }
    }
}

/** نعرض القطعة بحيث يلاصق رقمها المطابق جارتها في الخط (نفس النسخة السابقة) */
private fun orient(p: PlacedTile): Tile {
    if (p.side == "first") return p.tile
    val inner = if (p.tile.a == p.outer) p.tile.b else p.tile.a
    return if (p.side == "right") Tile(inner, p.outer) else Tile(p.outer, inner)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DominoBoard(v: TableView, d: DominoView, conn: TableConnection, isOwner: Boolean) {
    val mySeat = v.mySeat
    val names = names(v)
    var chooseSide by remember { mutableStateOf<DominoHandTile?>(null) }
    val readBoard = { Announcer.announceNow("${d.lineText}. ${d.endsText}") }
    val readScore = { Announcer.announceNow("${d.endsText}. ${d.scoreText}${if (d.boneyard > 0) ". في البنك ${d.boneyard} قطعة" else ""}") }

    Column(
        Modifier.fillMaxWidth().twoFingerSwipes { if (it == SwipeDir.Left) readBoard() else if (it == SwipeDir.Right) readScore() },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = d.scoreText }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            d.scores.forEachIndexed { side, n -> ScoreTile(d.sideNames.getOrElse(side) { "" }, "$n", side == d.mySide, Modifier.weight(1f).clearAndSetSemantics { }) }
        }
        names.forEachIndexed { seat, n ->
            if (seat != mySeat && seat < d.players) {
                val partner = mySeat != null && d.players == 4 && seat == (mySeat + 2) % 4
                PlayerLine("$n${if (partner) " (شريكك)" else ""}، ${d.handCounts.getOrElse(seat) { 0 }} قطع", d.turn == seat && d.phase == "playing")
            }
        }
        // الطاولة: تُقرأ كاملة بالضغط عليها
        FlowRow(
            Modifier.fillMaxWidth()
                .background(Color(0xFF145036), RoundedCornerShape(16.dp))
                .border(1.dp, Color(0x55D4AF37), RoundedCornerShape(16.dp))
                .clickable(role = Role.Button) { readBoard() }
                .semantics(mergeDescendants = true) { contentDescription = "${d.lineText}. ${d.endsText}" }
                .padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (d.line.isEmpty()) Text("الطاولة فارغة", color = Palette.textDim)
            d.line.forEach { p -> Box(Modifier.align(Alignment.CenterVertically)) { DominoTileView(orient(p), vertical = p.tile.isDouble) } }
        }
        d.ends?.let { (left, right) ->
            Text("يمين $right — يسار $left${if (d.boneyard > 0) " — في البنك ${d.boneyard}" else ""}", color = Palette.goldSoft,
                modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }, textAlign = TextAlign.Center)
        }
        if (d.phase != "playing") Text(if (d.phase == "matchOver") "انتهت المباراة" else "انتهت الصكة، الصكة التالية بعد لحظات",
            color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        if (d.myTurn && (d.canDraw || d.canPass)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (d.canDraw) PrimaryButton("سحب من البنك", { act(conn, "domino", jsonOf("type" to "draw")) }, modifier = Modifier.weight(1f))
                if (d.canPass) PrimaryButton("دق", { act(conn, "domino", jsonOf("type" to "pass")) }, modifier = Modifier.weight(1f))
            }
        }
        if (d.phase == "matchOver" && isOwner) PrimaryButton("مباراة جديدة", { conn.send("start") })

        if (mySeat != null) {
            Text("قطعك", color = Color.Transparent, modifier = Modifier.size(1.dp).semantics { heading() })
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                d.hand.forEach { h ->
                    Box(
                        Modifier
                            .border(2.dp, if (h.legal) Palette.gold else Color.Transparent, RoundedCornerShape(8.dp))
                            .clickable(role = Role.Button) {
                                when {
                                    !d.myTurn -> Announcer.announceNow("ليس دورك")
                                    !h.legal -> Announcer.announceNow(h.label)
                                    h.askSide -> chooseSide = h
                                    else -> act(conn, "domino", jsonOf("type" to "play", "tile" to h.tile.json()))
                                }
                            }
                            .semantics(mergeDescendants = true) { contentDescription = h.label }
                            .padding(4.dp),
                    ) { DominoTileView(h.tile, vertical = true, unit = 30, dim = d.myTurn && !h.legal) }
                }
            }
        } else Note("أنت تشاهد هذه الطاولة.")
    }

    val pick = chooseSide
    val e = d.ends
    if (pick != null && e != null) {
        MajliskDialog("أين تلعب القطعة؟", { chooseSide = null }) {
            PrimaryButton("اليمين (على ${e.second})", { chooseSide = null; act(conn, "domino", jsonOf("type" to "play", "tile" to pick.tile.json(), "side" to "right")) })
            PrimaryButton("اليسار (على ${e.first})", { chooseSide = null; act(conn, "domino", jsonOf("type" to "play", "tile" to pick.tile.json(), "side" to "left")) })
            SecondaryButton("إلغاء", { chooseSide = null }, fill = true)
        }
    }
}

// ═════════════ الجاكارو ═════════════

private val JK_COLORS = listOf(Color(0xFFD4AF37), Color(0xFFC0392B), Color(0xFF2E86DE), Color(0xFF27AE60))
private val JK_COLOR_NAMES = listOf("الذهبي", "الأحمر", "الأزرق", "الأخضر")

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun JackarooBoard(v: TableView, j: JackarooView, conn: TableConnection, isOwner: Boolean) {
    val mySeat = v.mySeat
    val names = names(v)
    var picked by remember { mutableStateOf<JackarooHandCard?>(null) }
    val readBoard = { Announcer.announceNow(j.boardText) }
    val readMine = { Announcer.announceNow(j.mineText) }
    val myTeam = (mySeat ?: 0) % 2
    val usLabel = if (mySeat == null) "فريق ${names[0]}" else "فريقك"
    val themLabel = if (mySeat == null) "فريق ${names[1]}" else "الخصم"

    Column(
        Modifier.fillMaxWidth().twoFingerSwipes { if (it == SwipeDir.Left) readBoard() else if (it == SwipeDir.Right) readMine() },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
                contentDescription = "في منطقة الأمان: $usLabel ${j.safeCount(myTeam)} من 8، $themLabel ${j.safeCount(1 - myTeam)} من 8"
            },
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ScoreTile(usLabel, "${j.safeCount(myTeam)}/8", true, Modifier.weight(1f).clearAndSetSemantics { })
            ScoreTile(themLabel, "${j.safeCount(1 - myTeam)}/8", false, Modifier.weight(1f).clearAndSetSemantics { })
        }
        Box(
            Modifier.fillMaxWidth().clickable(role = Role.Button) { readBoard() }
                .semantics(mergeDescendants = true) { contentDescription = "اللوحة: ${j.boardText}" },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.widthIn(max = 340.dp).fillMaxWidth().aspectRatio(1f)) { drawJackaroo(j, mySeat ?: 0) }
            // أوراق اللفة الحالية في وسط الطاولة (تنمسح مع كل لفة جديدة)
            Row(Modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
                j.centerCards.forEachIndexed { i, c ->
                    Box(
                        Modifier.size(40.dp, 58.dp)
                            .graphicsLayer { rotationZ = (i - (j.centerCards.size - 1) / 2f) * 8f }
                            .background(Color.White, RoundedCornerShape(6.dp))
                            .border(1.dp, Color(0xFFB9B4A6), RoundedCornerShape(6.dp)),
                        contentAlignment = Alignment.Center,
                    ) { Text("${c.rank}${c.symbol}", color = if (c.red) Color(0xFFC62828) else Color(0xFF1A1A1A), fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }
        names.forEachIndexed { seat, n ->
            val partner = mySeat != null && seat == (mySeat + 2) % 4
            PlayerLine("${if (seat == mySeat) "$n (أنت)" else n}${if (partner) " (شريكك)" else ""}، ${j.handCounts.getOrElse(seat) { 0 }} أوراق",
                j.turn == seat && j.phase == "playing", JK_COLORS[seat],
                spoken = "${if (seat == mySeat) "أنت" else n}${if (partner) "، شريكك" else ""}، ${JK_COLOR_NAMES[seat]}، ${j.handCounts.getOrElse(seat) { 0 }} أوراق")
        }
        if (j.phase == "over") {
            val w = j.winnerTeam ?: 0
            Text(if (mySeat == null) "فاز فريق ${names[w]} و${names[w + 2]}" else if (w == myTeam) "🎉 فاز فريقك!" else "فاز الفريق الآخر",
                color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            if (isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        }
        if (mySeat != null) {
            Text("أوراقك${if (j.burning) "، اختر ورقة لحرقها" else ""}", color = Color.Transparent, modifier = Modifier.size(1.dp).semantics { heading() })
            if (j.burning) Text("لا لعب صالح: اختر ورقة لحرقها", color = Palette.goldSoft, modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }, textAlign = TextAlign.Center)
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                j.hand.forEach { h ->
                    Box(
                        Modifier.size(58.dp, 84.dp)
                            .background(if (j.myTurn && !h.usable) Color(0xFFCFCABB) else Color.White, RoundedCornerShape(8.dp))
                            .border(2.dp, if (h.usable) Palette.gold else Color(0xFFB9B4A6), RoundedCornerShape(8.dp))
                            .clickable(role = Role.Button) {
                                when {
                                    !j.myTurn -> Announcer.announceNow("ليس دورك")
                                    j.burning -> act(conn, "jackaroo", jsonOf("type" to "burn", "card" to h.card.json()))
                                    h.moves.isEmpty() -> Announcer.announceNow("${h.label.substringBefore("،")} لا تصلح الآن")
                                    h.moves.size == 1 -> act(conn, "jackaroo", jsonOf("type" to "play", "card" to h.card.json(), "move" to h.moves[0].move))
                                    else -> picked = h
                                }
                            }
                            .semantics(mergeDescendants = true) { contentDescription = h.label },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("${h.card.rank}${h.card.symbol}", color = if (h.card.red) Color(0xFFC62828) else Color(0xFF1A1A1A), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        } else Note("أنت تشاهد هذه الطاولة.")
    }

    picked?.let { h ->
        MajliskDialog("${h.label.substringBefore("،")}: اختر الحركة", { picked = null }) {
            h.moves.forEach { m ->
                PrimaryButton(m.text, { picked = null; act(conn, "jackaroo", jsonOf("type" to "play", "card" to h.card.json(), "move" to m.move)) })
            }
            SecondaryButton("إلغاء", { picked = null }, fill = true)
        }
    }
}

/** رسم لوحة الجاكارو (نفس رسم النسخة السابقة): المسار دائرة، ولكل لاعب قاعدة ومنطقة أمان وبيت */
private fun DrawScope.drawJackaroo(j: JackarooView, bottom: Int) {
    val k = size.minDimension / 320f
    val L = j.segment * 4
    val c = 160f; val R = 130f
    val start = { o: Int -> o * j.segment }
    val base = start(bottom)
    fun at(pos: Float, r: Float = R): Offset {
        val a = PI / 2 + 2 * PI * (pos - base) / L
        return Offset((c + r * cos(a)).toFloat() * k, (c + r * sin(a)).toFloat() * k)
    }
    drawCircle(Color(0xFF0B241B), (R + 30) * k, Offset(c * k, c * k))
    drawCircle(Color(0x33D4AF37), (R + 30) * k, Offset(c * k, c * k), style = Stroke(1f * k))
    for (p in 0 until L) {
        val owner = (0..3).firstOrNull { start(it) == p }
        drawCircle(if (owner != null) JK_COLORS[owner] else Color(0x33FFFFFF), (if (owner != null) 6f else 3.5f) * k, at(p.toFloat()))
    }
    for (o in 0..3) {
        for (s in 0 until 4) drawCircle(JK_COLORS[o], 5f * k, at((start(o) - 1).toFloat(), R - 16 - s * 14), style = Stroke(1.5f * k))
        j.marbles.getOrNull(o).orEmpty().forEachIndexed { i, m ->
            val p = when (m.zone) {
                "track" -> at(m.pos.toFloat())
                "safe" -> at((start(o) - 1).toFloat(), R - 16 - m.pos * 14)
                else -> at(start(o) + 3 + i * 1.6f, R + 18)
            }
            val alpha = if (m.zone == "home") 0.55f else 1f
            drawCircle(JK_COLORS[o].copy(alpha = alpha), 7f * k, p)
            drawCircle(Color(0xAA000000), 7f * k, p, style = Stroke(1.5f * k))
        }
    }
}

// ═════════════ لودو ═════════════

private val LUDO_COLORS = listOf(Color(0xFFD9453B), Color(0xFF2EA661), Color(0xFFE6B422), Color(0xFF2F7FD8))
private val LUDO_COLOR_NAMES = listOf("الأحمر", "الأخضر", "الأصفر", "الأزرق")

@Composable
fun LudoBoard(v: TableView, l: LudoView, conn: TableConnection, isOwner: Boolean) {
    val mySeat = v.mySeat
    val names = names(v)
    val readBoard = { Announcer.announceNow(l.boardText) }
    val readMine = { Announcer.announceNow(l.mineText) }
    val partner = if (mySeat == null) -1 else (mySeat + 2) % 4
    // آخر رمية لكل لاعب (نرد صغير جنب اسمه)، نتذكرها من الحالات اللي توصل
    val rolls = remember { androidx.compose.runtime.mutableStateMapOf<Int, Int>() }
    androidx.compose.runtime.LaunchedEffect(l.moveSig) {
        if (l.lastSeat != null && l.lastRoll != null) rolls[l.lastSeat] = l.lastRoll
        if (l.phase == "move" && l.dice != null) rolls[l.turn] = l.dice
    }

    Column(
        Modifier.fillMaxWidth().twoFingerSwipes { if (it == SwipeDir.Left) readBoard() else if (it == SwipeDir.Right) readMine() },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        l.seats.forEach { o ->
            val n = names.getOrElse(o) { "" }
            val roll = rolls[o]
            PlayerLine(
                "$n${if (o == mySeat) " (أنت)" else if (l.teams && o == partner) " (شريكك)" else ""} — ${l.home(o)}/4",
                l.turn == o && l.phase != "over", LUDO_COLORS[o],
                spoken = "${if (o == mySeat) "أنت" else n}${if (l.teams && o == partner) "، شريكك" else ""}، ${LUDO_COLOR_NAMES[o]}، وصل ${l.home(o)} من 4${if (roll != null) "، آخر رمية $roll" else ""}",
                trailing = roll?.let { r -> @Composable { Dice(r, LUDO_COLORS[o], 26) } },
            )
        }
        Box(
            Modifier.fillMaxWidth().clickable(role = Role.Button) { readBoard() }
                .semantics(mergeDescendants = true) { contentDescription = "اللوحة: ${l.boardText}" },
            contentAlignment = Alignment.Center,
        ) {
            val movable = if (l.myTurn && l.phase == "move") l.options.map { l.movableOwner to it.token } else emptyList()
            Canvas(Modifier.widthIn(max = 360.dp).fillMaxWidth().aspectRatio(1f)) { drawLudo(l, mySeat ?: 0, movable) }
        }
        if (l.phase == "over") {
            val won = l.winner != null && mySeat != null && (if (l.teams) l.winner == mySeat % 2 else l.winner == mySeat)
            val w = l.winner ?: 0
            Text(if (won) "🎉 فزت!" else if (l.teams) "فاز فريق ${names[w]} و${names[w + 2]}" else "فاز ${names.getOrElse(w) { "" }}",
                color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            if (isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
                Dice(if (l.phase == "move") l.dice else l.lastRoll, LUDO_COLORS.getOrElse(l.turn) { Palette.gold })
                if (l.myTurn && l.phase == "roll") PrimaryButton("ارمِ النرد", { act(conn, "ludo", jsonOf("type" to "roll")) })
                if (!l.myTurn) Text("دور ${names.getOrElse(l.turn) { "" }}", color = Palette.textDim, modifier = Modifier.clearAndSetSemantics { })
            }
        }
        if (l.myTurn && l.phase == "move" && l.options.size > 1) {
            Text("رميت ${l.dice ?: 0}: اختر الحجر", color = Color.Transparent, modifier = Modifier.size(1.dp).semantics { heading() })
            l.options.forEach { o -> SecondaryButton(o.text, { act(conn, "ludo", jsonOf("type" to "move", "token" to o.token)) }, fill = true) }
        }
        if (mySeat == null) Note("أنت تشاهد هذه الطاولة.")
    }
}

/** النرد: نقاط للعين، والرقم يُعلن صوتياً */
@Composable
private fun Dice(value: Int?, color: Color, sizeDp: Int = 54) {
    val spots = mapOf(1 to listOf(4), 2 to listOf(0, 8), 3 to listOf(0, 4, 8), 4 to listOf(0, 2, 6, 8), 5 to listOf(0, 2, 4, 6, 8), 6 to listOf(0, 2, 3, 5, 6, 8))
    Canvas(Modifier.size(sizeDp.dp).clearAndSetSemantics { }) {
        val r = size.width * 0.19f
        drawRoundRect(Color.White, cornerRadius = CornerRadius(r))
        drawRoundRect(color, cornerRadius = CornerRadius(r), style = Stroke(size.width * 0.055f))
        val on = value?.let { spots[it] }.orEmpty()
        for (i in on) {
            val x = (i % 3 + 0.5f) / 3f * size.width
            val y = (i / 3 + 0.5f) / 3f * size.height
            drawCircle(Color(0xFF1A1A1A), size.width * 0.08f, Offset(x, y))
        }
    }
}

// رسم اللوحة (15×15) — نفس خانات النسخة السابقة
private val TRACK_CELLS: List<Pair<Float, Float>> = buildList {
    listOf(1, 2, 3, 4, 5).forEach { add(6f to it.toFloat()) }
    listOf(5, 4, 3, 2, 1, 0).forEach { add(it.toFloat() to 6f) }
    add(0f to 7f)
    listOf(0, 1, 2, 3, 4, 5).forEach { add(it.toFloat() to 8f) }
    listOf(9, 10, 11, 12, 13, 14).forEach { add(6f to it.toFloat()) }
    add(7f to 14f)
    listOf(14, 13, 12, 11, 10, 9).forEach { add(8f to it.toFloat()) }
    listOf(9, 10, 11, 12, 13, 14).forEach { add(it.toFloat() to 8f) }
    add(14f to 7f)
    listOf(14, 13, 12, 11, 10, 9).forEach { add(it.toFloat() to 6f) }
    listOf(5, 4, 3, 2, 1, 0).forEach { add(8f to it.toFloat()) }
    add(7f to 0f); add(6f to 0f)
}
private val HOME_CELLS: List<List<Pair<Float, Float>>> = listOf(
    listOf(1, 2, 3, 4, 5).map { 7f to it.toFloat() },
    listOf(1, 2, 3, 4, 5).map { it.toFloat() to 7f },
    listOf(13, 12, 11, 10, 9).map { 7f to it.toFloat() },
    listOf(13, 12, 11, 10, 9).map { it.toFloat() to 7f },
)
private val YARDS = listOf(0f to 0f, 0f to 9f, 9f to 9f, 9f to 0f)
private val YARD_SPOTS = listOf(1.5f to 1.5f, 1.5f to 3.5f, 3.5f to 1.5f, 3.5f to 3.5f)
private val CENTER_SPOT = listOf(7f to 6.25f, 6.25f to 7f, 7f to 7.75f, 7.75f to 7f)

private fun DrawScope.drawLudo(l: LudoView, bottom: Int, movable: List<Pair<Int, Int>>) {
    val U = size.minDimension / 15f
    // ندير اللوحة حتى يكون بيت صاحب الجهاز أسفل اليسار
    val turns = (3 - bottom + 4) % 4
    fun rot(cell: Pair<Float, Float>): Pair<Float, Float> {
        var p = cell
        repeat(turns) { p = p.second to 14f - p.first }
        return p
    }
    fun xy(cell: Pair<Float, Float>): Offset { val (r, c) = rot(cell); return Offset(c * U + U / 2, r * U + U / 2) }
    val paper = Color(0xFFF8F3E3)
    drawRoundRect(Color(0xFF0B241B), cornerRadius = CornerRadius(U * 0.6f))
    YARDS.forEachIndexed { o, y ->
        val a = rot(y); val b = rot(y.first + 5 to y.second + 5)
        val x0 = min(a.second, b.second) * U; val y0 = min(a.first, b.first) * U
        drawRoundRect(LUDO_COLORS[o].copy(alpha = if (o in l.seats) 0.9f else 0.25f), Offset(x0 + 1, y0 + 1), Size(6 * U - 2, 6 * U - 2), CornerRadius(U * 0.45f))
        drawRoundRect(paper, Offset(x0 + U, y0 + U), Size(4 * U, 4 * U), CornerRadius(U * 0.35f))
    }
    TRACK_CELLS.forEachIndexed { i, cell ->
        val p = xy(cell)
        val start = LudoView.STARTS.indexOf(i)
        drawRect(if (start >= 0) LUDO_COLORS[start] else paper, Offset(p.x - U / 2 + 0.5f, p.y - U / 2 + 0.5f), Size(U - 1, U - 1))
        drawRect(Color(0x550D2B20), Offset(p.x - U / 2 + 0.5f, p.y - U / 2 + 0.5f), Size(U - 1, U - 1), style = Stroke(1f))
        if (i in LudoView.SAFE && start < 0) drawStar(p, U * 0.32f, Color(0x990D2B20))
    }
    HOME_CELLS.forEachIndexed { o, cells -> cells.forEach { cell ->
        val p = xy(cell)
        drawRect(LUDO_COLORS[o], Offset(p.x - U / 2 + 0.5f, p.y - U / 2 + 0.5f), Size(U - 1, U - 1))
    } }
    // الوسط: أربعة مثلثات، كل مثلث بلون صاحبه جهة ممره
    val c0 = xy(6f to 6f); val c2 = xy(8f to 8f)
    val L = min(c0.x, c2.x) - U / 2; val T = min(c0.y, c2.y) - U / 2; val R = L + 3 * U; val B = T + 3 * U
    val M = Offset((L + R) / 2, (T + B) / 2)
    for (o in 0..3) {
        val edge = xy(HOME_CELLS[o][4])
        val pts = when {
            edge.x < L -> listOf(Offset(L, T), Offset(L, B))
            edge.x > R -> listOf(Offset(R, T), Offset(R, B))
            edge.y < T -> listOf(Offset(L, T), Offset(R, T))
            else -> listOf(Offset(L, B), Offset(R, B))
        }
        drawPath(Path().apply { moveTo(pts[0].x, pts[0].y); lineTo(pts[1].x, pts[1].y); lineTo(M.x, M.y); close() }, LUDO_COLORS[o])
    }
    // الأحجار (أكثر من حجر في خانة: تُزاح قليلاً)
    val seen = HashMap<String, Int>()
    for (o in l.seats) {
        l.tokens.getOrNull(o).orEmpty().forEachIndexed { i, p ->
            val cell = when {
                p == -1 -> (YARDS[o].first + YARD_SPOTS[i].first - 0.5f) to (YARDS[o].second + YARD_SPOTS[i].second - 0.5f)
                p == LudoView.FINISH -> CENTER_SPOT[o]
                p > LudoView.LAST_TRACK -> HOME_CELLS[o][p - LudoView.LAST_TRACK - 1]
                else -> TRACK_CELLS[LudoView.absPos(o, p)]
            }
            val pt = xy(cell)
            val key = "${pt.x.toInt()},${pt.y.toInt()}"
            val n = seen[key] ?: 0
            seen[key] = n + 1
            val q = Offset(pt.x + n * U * 0.18f, pt.y - n * U * 0.18f)
            if (movable.any { it.first == o && it.second == i }) drawCircle(Color(0xFFD4AF37), U * 0.5f, q, style = Stroke(U * 0.14f))
            val r = if (p == LudoView.FINISH) U * 0.23f else U * 0.36f
            drawCircle(LUDO_COLORS[o], r, q)
            drawCircle(Color(0xFF0D2B20), r, q, style = Stroke(U * 0.09f))
            if (p != LudoView.FINISH) drawCircle(Color(0xAAFFFFFF), U * 0.14f, q)
        }
    }
}

private fun DrawScope.drawStar(c: Offset, r: Float, color: Color) {
    val path = Path()
    for (k in 0 until 10) {
        val rr = if (k % 2 == 0) r else r * 0.45f
        val a = -PI / 2 + k * PI / 5
        val x = (c.x + rr * cos(a)).toFloat(); val y = (c.y + rr * sin(a)).toFloat()
        if (k == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    drawPath(path, color)
}

// ═════════════ الأصوات والإعلانات ═════════════

/** أصوات الدومينو والجاكارو واللودو ونص "دورك" (حتى والتطبيق في الخلفية) */
class OtherGameSounds {
    private var sig: String? = null
    private var wasMyTurn = false
    private var lastPrompt: String? = null
    private var phase: String? = null
    private var deal: Int? = null
    private var ludoLast: String? = null
    private var ludoTurn: Int? = null

    fun update(v: TableView) {
        val d = v.domino; val j = v.jackaroo; val l = v.ludo
        val newSig = d?.moveSig ?: j?.moveSig ?: l?.moveSig
        if (newSig == null) { sig = null; wasMyTurn = false; lastPrompt = null; phase = null; deal = null; ludoLast = null; ludoTurn = null; return }
        val first = sig == null
        val changed = sig != newSig
        sig = newSig
        if (changed) {
            when {
                // الدومينو: صوت خلط القطع مع كل توزيع، وطقة القطعة لما تنلعب أو تنسحب
                d != null -> when {
                    (first && d.line.isEmpty() && d.phase == "playing") || (phase != null && phase != "playing" && d.phase == "playing") -> Sounds.dominoShuffle()
                    !first && (d.lastKind == "play" || d.lastKind == "draw") -> Sounds.dominoTile()
                }
                // الجاكارو: توزيع الورق، وصوت الورقة، ونقرة لكل خطوة يمشيها الحجر
                j != null -> {
                    if ((first && !j.hasMove) || (!first && deal != null && deal != j.dealNo)) Sounds.deal(true)
                    if (!first && j.hasMove) { Sounds.jackarooCard(); if (j.lastSteps > 0) Sounds.steps(j.lastSteps, at = 0.25) }
                }
                // لودو: صوت النرد مع كل رمية، ونقرة لكل خطوة يمشيها الحجر
                l != null && !first -> {
                    val newTurnRoll = l.phase == "move" && (phase != "move" || ludoTurn != l.turn)
                    val moveChanged = l.lastSig != ludoLast && l.lastSig != "null"
                    // رمى ثم تحرك مباشرة (خيار واحد) أو ما فيه حركة: النرد ثم النقرات
                    val rolledNow = newTurnRoll || (moveChanged && phase != "move")
                    if (rolledNow) Sounds.dice()
                    if (moveChanged && l.moved) Sounds.steps(l.lastSteps, at = if (rolledNow && !newTurnRoll) 0.6 else 0.0)
                }
            }
        }
        phase = d?.phase ?: j?.phase ?: l?.phase
        deal = j?.dealNo
        ludoLast = l?.lastSig
        ludoTurn = l?.turn
        val myTurn = d?.myTurn ?: j?.myTurn ?: l?.myTurn ?: false
        val prompt = d?.prompt ?: j?.prompt ?: l?.prompt ?: ""
        if (myTurn && !wasMyTurn) Sounds.turn(Announcer.readerOn)
        // نص الدور (مع الطرفين في الدومينو، أو "اختر الحجر" في لودو): مرة لكل تغيّر
        if (myTurn && prompt.isNotEmpty() && (prompt != lastPrompt || !wasMyTurn) && changed) Announcer.announce(prompt)
        lastPrompt = if (myTurn) prompt else null
        wasMyTurn = myTurn
    }
}
