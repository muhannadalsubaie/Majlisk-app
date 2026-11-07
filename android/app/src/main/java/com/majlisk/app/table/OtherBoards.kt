package com.majlisk.app.table

// الدومينو والجاكارو واللودو على طاولة مجلسك (نفس فكرة النسخة السابقة):
// الحالة والحركات المسموحة ونصوصها من الخادم، والتطبيق يرسم اللوحة ويعرض الأزرار ويرسل الحركة.
// لقارئ الشاشة: كل قطعة/ورقة/خيار زر بنص واضح، والضغط على اللوحة يقرأها كاملة، وحركات الجميع يعلنها الخادم.
// سحب بإصبعين: من اليمين لليسار = اللوحة كاملة، من اليسار لليمين = (الطرفان والنقاط) أو (أحجارك).

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
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
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.graphics.nativeCanvas
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
private fun PlayerLine(text: String, turn: Boolean, color: Color? = null, spoken: String? = null, trailing: (@Composable () -> Unit)? = null, avatar: Pair<String?, String>? = null) {
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
        avatar?.let { (u, n) -> com.majlisk.app.ui.Avatar(u, n, 30.dp) }
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
private fun DominoTileView(t: Tile, vertical: Boolean, unit: Float = 22f, dim: Boolean = false, modifier: Modifier = Modifier) {
    val w = if (vertical) unit else unit * 2
    val h = if (vertical) unit * 2 else unit
    Canvas(modifier.size(w.dp, h.dp)) {
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

/** لاعب على طاولة الدومينو: صورته واسمه وكم قطعة معه، بإطار ذهبي لما يكون دوره */
@Composable
private fun DominoSeatTag(name: String, uid: String?, count: Int, partner: Boolean, turn: Boolean, modifier: Modifier) {
    Column(
        modifier
            .border(1.dp, if (turn) Palette.gold else Color.Transparent, RoundedCornerShape(10.dp))
            .background(if (turn) Palette.gold.copy(alpha = 0.08f) else Color.Transparent, RoundedCornerShape(10.dp))
            .padding(4.dp)
            .clearAndSetSemantics { contentDescription = "$name${if (partner) "، شريكك" else ""}، $count قطع${if (turn) "، عليه الدور" else ""}" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        com.majlisk.app.ui.Avatar(uid, name, 32.dp)
        Text(name, color = Palette.text, fontSize = 12.sp, fontWeight = if (turn) FontWeight.Bold else FontWeight.Normal, maxLines = 1)
        Text("$count قطع", color = Palette.textDim, fontSize = 11.sp)
    }
}

/**
 * خط اللعب على شكل حرف U: يبدأ من فوق على اليسار وينزل، يمشي على الأسفل، ويطلع يمين لين فوق.
 * أول الخط (الطرف اليسار) فوق على اليسار، وآخره (الطرف اليمين) فوق على اليمين.
 * كل ما كثرت القطع تصغر عشان تكفي الطاولة كلها بلا صفوف.
 */
@Composable
private fun DominoSnake(line: List<PlacedTile>, modifier: Modifier) {
    androidx.compose.foundation.layout.BoxWithConstraints(
        modifier.height(290.dp)
            .background(Color(0xFF145036), RoundedCornerShape(16.dp))
            .border(1.dp, Color(0x55D4AF37), RoundedCornerShape(16.dp))
            .clearAndSetSemantics { },
        // المواضع محسوبة من فوق على اليسار مهما كان اتجاه الواجهة (العربية من اليمين)
        contentAlignment = androidx.compose.ui.AbsoluteAlignment.TopLeft,
    ) {
        val W = maxWidth.value; val H = maxHeight.value
        val n = line.size
        // أكبر من قبل (كانت 18) عشان تكون أوضح، وتصغر بس لما تكثر القطع
        var u = 26f
        while (u > 6f) {
            val m = u * 0.6f
            if (n * (2 * u + 2) <= 2 * (H - 2 * m - u) + (W - 2 * m - 2 * u)) break
            u -= 0.5f
        }
        val m = u * 0.6f; val g = 2f
        val lh = H - 2 * m - u; val lw = W - 2 * m - 2 * u
        if (line.isEmpty()) Text("الطاولة فارغة", color = Palette.textDim, modifier = Modifier.align(Alignment.Center))
        line.forEachIndexed { i, p ->
            val t = orient(p)
            val dist = i * (2 * u + g) + u
            when {
                // العمود اليسار نازل: أول القطعة فوق
                dist <= lh -> DominoTileView(t, true, u, modifier = Modifier.absoluteOffset((m).dp, (m + dist - u).dp))
                // الأسفل من اليسار لليمين
                dist <= lh + lw -> DominoTileView(Tile(t.b, t.a), false, u, modifier = Modifier.absoluteOffset((m + u + (dist - lh) - u).dp, (H - m - u).dp))
                // العمود اليمين طالع: أول القطعة تحت
                else -> DominoTileView(Tile(t.b, t.a), true, u, modifier = Modifier.absoluteOffset((W - m - u).dp, (H - m - u - (dist - lh - lw) - u).dp))
            }
        }
    }
}

/** نص الدور في الدومينو: "دورك" أو "دور فلان" */
private fun dominoTurnText(v: TableView, d: DominoView): String = when {
    d.phase == "chooseStarter" -> if (d.chooser == v.mySeat) "دورك: اختر من يبدأ، أنت أو شريكك" else "${names(v).getOrElse(d.chooser ?: 0) { "" }} يختار من يبدأ"
    d.phase == "matchOver" -> "انتهت المباراة"
    d.phase != "playing" -> "انتهت الصكة، الصكة التالية بعد لحظات"
    d.turn == v.mySeat -> "دورك"
    else -> "دور ${names(v).getOrElse(d.turn) { "" }}"
}

/** جلا (تمرير): لما ما عندك قطعة تصلح */
private fun dominoJala(conn: TableConnection, d: DominoView) = when {
    !d.myTurn -> Announcer.announceNow("ليس دورك")
    d.canPass -> act(conn, "domino", jsonOf("type" to "pass"))
    d.canDraw -> Announcer.announceNow("ما تقدر تجلي، اسحب من البنك")
    else -> Announcer.announceNow("ما تقدر تجلي، عندك قطعة تصلح")
}

/** إيماءة الجلا (من فوق لتحت): لو فيه بنك (اللعب الفردي) تسحب لك قطعة، وإلا (الفرق) تجلي */
private fun dominoDrawOrJala(conn: TableConnection, d: DominoView) {
    if (d.myTurn && d.canDraw) act(conn, "domino", jsonOf("type" to "draw")) else dominoJala(conn, d)
}

/**
 * سحب بإصبعين في الدومينو: من اليمين لليسار = الطرفان، من تحت لفوق = الدور عند مين،
 * من اليسار لليمين = سجل الجولات، من فوق لتحت = سحب من البنك (الفردي) أو جلا (الفرق)
 */
@Composable
private fun Modifier.dominoSwipes(v: TableView, d: DominoView, conn: TableConnection, openLog: () -> Unit): Modifier = twoFingerSwipes {
    when (it) {
        SwipeDir.Left -> Announcer.announceNow(d.endsText)
        SwipeDir.Up -> Announcer.announceNow(dominoTurnText(v, d))
        SwipeDir.Right -> openLog()
        SwipeDir.Down -> dominoDrawOrJala(conn, d)
    }
}

/** أعلى طاولة الدومينو: النقاط، اللاعبون، وخط اللعب */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DominoBoard(v: TableView, d: DominoView, conn: TableConnection, isOwner: Boolean, openLog: () -> Unit) {
    val mySeat = v.mySeat
    val names = names(v)

    Column(Modifier.fillMaxWidth().dominoSwipes(v, d, conn, openLog), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = d.scoreText }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            d.scores.forEachIndexed { side, n -> ScoreTile(d.sideNames.getOrElse(side) { "" }, "$n", side == d.mySide, Modifier.weight(1f).clearAndSetSemantics { }) }
        }
        // اللاعبون حول الطاولة: المقابل فوق، والباقين يمين ويسار (مثل البلوت)، والقطع في النص
        val me = mySeat ?: 0
        val others = (1 until maxOf(d.players, 2)).map { (me + it) % d.players }
        val top = when (d.players) { 4 -> others[1]; 2 -> others[0]; else -> null }
        val right = if (d.players >= 3) others[0] else null
        val left = when (d.players) { 4 -> others[2]; 3 -> others[1]; else -> null }
        val seatTag: @Composable (Int, Modifier) -> Unit = { seat, m ->
            val partner = mySeat != null && d.players == 4 && seat == (me + 2) % 4
            DominoSeatTag(names.getOrElse(seat) { "" }, v.seatUids.getOrNull(seat), d.handCounts.getOrElse(seat) { 0 }, partner, d.turn == seat && d.phase == "playing", m)
        }
        top?.let { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { seatTag(it, Modifier) } }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            // في الواجهة العربية أول عنصر يصير يمين
            right?.let { seatTag(it, Modifier.width(66.dp)) }
            // الطاولة: للعين فقط، لمسها ما يقرأ شي (الطرفان بالإيماءة)
            DominoSnake(d.line, Modifier.weight(1f))
            left?.let { seatTag(it, Modifier.width(66.dp)) }
        }
        // المشاهد: اللاعب الرابع تحت في النص (الأربعة متقابلين)
        if (mySeat == null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { seatTag(0, Modifier) }
        d.ends?.let { (left, right) ->
            Text("يمين $right — يسار $left${if (d.boneyard > 0) " — في البنك ${d.boneyard}" else ""}", color = Palette.goldSoft,
                modifier = Modifier.fillMaxWidth().clearAndSetSemantics { }, textAlign = TextAlign.Center)
        }
        if (d.phase != "playing") Text(dominoTurnText(v, d),
            color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        if (d.phase == "matchOver" && isOwner) PrimaryButton("مباراة جديدة", { conn.send("start") })
    }
}

/** قطعك في أسفل الشاشة فوق الميكروفون، ومعها زر جلا (وسحب من البنك إن وجد) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DominoHand(v: TableView, d: DominoView, conn: TableConnection, openLog: () -> Unit) {
    if (v.mySeat == null) return
    var chooseSide by remember { mutableStateOf<DominoHandTile?>(null) }
    // الإيماءات مسجّلة من لوحة الدومينو، وتشتغل في أي مكان في الشاشة
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // فاز فريقك بالصكة: تختار من يبدأ (أنت أو شريكك)
        if (d.starterOptions.isNotEmpty()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                d.starterOptions.forEach { (seat, text) ->
                    PrimaryButton(text, { act(conn, "domino", jsonOf("type" to "starter", "starter" to seat)) }, modifier = Modifier.weight(1f))
                }
            }
        }
        if (d.myTurn && (d.canDraw || d.canPass)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (d.canDraw) PrimaryButton("سحب من البنك", { act(conn, "domino", jsonOf("type" to "draw")) }, modifier = Modifier.weight(1f))
                if (d.canPass) PrimaryButton("جلا", { dominoJala(conn, d) }, modifier = Modifier.weight(1f))
            }
        }
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
                ) { DominoTileView(h.tile, vertical = true, unit = 24f, dim = d.myTurn && !h.legal) }
            }
        }
    }

    val pick = chooseSide
    val e = d.ends
    if (pick != null && e != null) {
        MajliskDialog("القطعة تصلح على الطرفين: وش تبي تصير الجهتين؟", { chooseSide = null }) {
            // على اليمين (يطابق ${e.second}) تصير الجهتين ${e.first}، وعلى اليسار تصير ${e.second}
            PrimaryButton("الجهتين ${e.first}", { chooseSide = null; act(conn, "domino", jsonOf("type" to "play", "tile" to pick.tile.json(), "side" to "right")) })
            PrimaryButton("الجهتين ${e.second}", { chooseSide = null; act(conn, "domino", jsonOf("type" to "play", "tile" to pick.tile.json(), "side" to "left")) })
            SecondaryButton("إلغاء", { chooseSide = null }, fill = true)
        }
    }
}

/** سجل الدومينو: حركات كل جولة بالترتيب، تتنقل بين الجولات (يبدأ من الجولة الحالية) */
@Composable
fun DominoLogDialog(d: DominoView, onClose: () -> Unit) {
    var page by remember { mutableStateOf(d.log.lastIndex.coerceAtLeast(0)) }
    val entry = d.log.getOrNull(page)
    val current = page == d.log.lastIndex
    MajliskDialog(if (entry == null) "السجل" else "سجل الجولة ${entry.first}${if (current) " (الحالية)" else ""}", onClose) {
        val lines = entry?.second.orEmpty()
        if (lines.isEmpty()) Note(if (entry == null) "ما فيه حركات بعد." else "ما انلعبت حجار في هذه الجولة بعد.")
        lines.forEach { Text(it, color = Palette.text, fontSize = 16.sp, modifier = Modifier.fillMaxWidth()) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (page > 0) SecondaryButton("الجولة السابقة", { page-- }, modifier = Modifier.weight(1f), fill = true)
            if (page < d.log.lastIndex) SecondaryButton("الجولة التالية", { page++ }, modifier = Modifier.weight(1f), fill = true)
        }
        PrimaryButton("إغلاق", onClose)
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
    // أماكن الأحجار (من فوق لتحت): أحجارك أولاً ثم كل لاعب
    var posOpen by remember { mutableStateOf(false) }
    if (posOpen) {
        MajliskDialog("أماكن الأحجار", { posOpen = false }) {
            jackarooPositions(j, mySeat).forEach { (title, color, lines) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(12.dp).background(JK_COLORS.getOrElse(color) { Palette.gold }, RoundedCornerShape(6.dp)))
                    Text("$title، ${JK_COLOR_NAMES.getOrElse(color) { "" }}", color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                }
                lines.forEach { Text(it, color = Palette.text, fontSize = 16.sp, modifier = Modifier.fillMaxWidth()) }
            }
            PrimaryButton("إغلاق", { posOpen = false })
        }
    }
    val myTeam = (mySeat ?: 0) % 2
    val usLabel = if (mySeat == null) "فريق ${names[0]}" else "فريقك"
    val themLabel = if (mySeat == null) "فريق ${names[1]}" else "الخصم"

    Column(
        // سحب بإصبعين: من اليمين لليسار = اللوحة كاملة، من اليسار لليمين = أحجارك،
        // من تحت لفوق = الدور عند مين، من فوق لتحت = قائمة أماكن الأحجار
        Modifier.fillMaxWidth().twoFingerSwipes {
            when (it) {
                SwipeDir.Left -> Announcer.announceNow(j.boardText)
                SwipeDir.Right -> Announcer.announceNow(j.mineText)
                SwipeDir.Up -> Announcer.announceNow(jackarooTurnText(v, j))
                SwipeDir.Down -> posOpen = true
            }
        },
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
        // اللوحة: للعين فقط، لمسها ما يقرأ شي (أماكن الأحجار بالإيماءات)
        Box(
            Modifier.fillMaxWidth().clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.widthIn(max = boardSide(340)).fillMaxWidth().aspectRatio(1f)) { drawJackaroo(j, mySeat ?: 0) }
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
        // اللاعبون: كل اثنين في صف، فتكفي الطاولة صفحة وحدة
        names.chunked(2).forEachIndexed { row, pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEachIndexed { col, n ->
                    val seat = row * 2 + col
                    val partner = mySeat != null && seat == (mySeat + 2) % 4
                    Box(Modifier.weight(1f)) {
                        PlayerLine("${if (seat == mySeat) "$n (أنت)" else n}${if (partner) " (شريكك)" else ""}، ${j.handCounts.getOrElse(seat) { 0 }} أوراق",
                            j.turn == seat && j.phase == "playing", JK_COLORS[seat],
                            spoken = "${if (seat == mySeat) "أنت" else n}${if (partner) "، شريكك" else ""}، ${JK_COLOR_NAMES[seat]}، ${j.handCounts.getOrElse(seat) { 0 }} أوراق", avatar = v.seatUids.getOrNull(seat) to n)
                    }
                }
            }
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
        }
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

/** حجم لوحة اللودو والجاكارو: يتكيّف مع طول شاشة الجوال، فتكفي الطاولة كلها صفحة وحدة بلا تمرير */
@Composable
private fun boardSide(full: Int): androidx.compose.ui.unit.Dp {
    val h = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp
    return minOf(full, maxOf(170, h - 550)).dp
}

/** لوحة اللودو أكبر (شلنا النرد الكبير اللي تحتها): تاخذ عرض الشاشة لو فيه مكان بالطول */
@Composable
private fun ludoSide(): androidx.compose.ui.unit.Dp {
    val h = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp
    return minOf(440, maxOf(200, h - 440)).dp
}

/** قطع الدومينو على الطاولة: أصغر شوي في الجوالات القصيرة */
@Composable
private fun dominoUnit(): Float = if (androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp < 740) 15f else 18f

/** الدور عند مين في الجاكارو */
private fun jackarooTurnText(v: TableView, j: JackarooView): String {
    val names = names(v)
    val me = v.mySeat
    if (j.phase == "over") {
        val w = j.winnerTeam ?: 0
        return if (me != null) (if (w == me % 2) "انتهت اللعبة، فاز فريقك" else "انتهت اللعبة، فاز الفريق الآخر")
        else "انتهت اللعبة، فاز فريق ${names[w]} و${names[w + 2]}"
    }
    if (j.turn == me) return if (j.burning) "دورك، ما عندك لعب صالح، احرق ورقة" else "دورك"
    return "الدور عند ${names.getOrElse(j.turn) { "" }}"
}

/**
 * "أحجار فلان: 1 في البيت، 2 على المسار، باقي له…" ← العنوان وسطر لكل حجر
 * (الفاصل بين الأحجار فاصلة بعدها رقم الحجر، لأن وصف المكان نفسه فيه فواصل)
 */
private fun splitMarbles(text: String): Pair<String, List<String>> {
    val i = text.indexOf(": ")
    if (i < 0) return text to emptyList()
    val lines = text.substring(i + 2).split(Regex("، (?=\\d)")).filter { it.isNotBlank() }.map { "حجر $it" }
    return text.substring(0, i) to lines
}

/** أماكن الأحجار: أحجارك أولاً (أو أحجار شريكك لو تلعب بها)، ثم باقي اللاعبين بترتيب اللعب */
private fun jackarooPositions(j: JackarooView, mySeat: Int?): List<Triple<String, Int, List<String>>> {
    val all = j.boardText.split(". ")
    val out = mutableListOf<Triple<String, Int, List<String>>>()
    if (mySeat != null) {
        val (title, lines) = splitMarbles(j.mineText)
        out += Triple(title, if (title.startsWith("أحجارك")) mySeat else (mySeat + 2) % 4, lines)
    }
    val start = mySeat ?: 0
    for (k in 0 until 4) {
        val seat = (start + k) % 4
        if (seat == mySeat || seat >= all.size) continue
        val (title, lines) = splitMarbles(all[seat])
        out += Triple(title, seat, lines)
    }
    return out
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
        // رقم الخانة (ثابت للجميع، نفس الرقم اللي ينقال في الإعلان) داخل الدائرة جنب كل نقطة
        val tp = at(p.toFloat(), R - 12)
        drawContext.canvas.nativeCanvas.drawText("$p", tp.x, tp.y + 2.3f * k, android.graphics.Paint().apply {
            isAntiAlias = true; textAlign = android.graphics.Paint.Align.CENTER; textSize = 6.5f * k
            color = android.graphics.Color.argb(190, 255, 255, 255)
        })
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

// ترتيب الألوان مع ترتيب اللعب: أحمر ← أزرق ← أصفر ← أخضر (الفرق: أحمر+أصفر ضد أزرق+أخضر)
private val LUDO_COLORS = listOf(Color(0xFFD9453B), Color(0xFF2F7FD8), Color(0xFFE6B422), Color(0xFF2EA661))
private val LUDO_COLOR_NAMES = listOf("الأحمر", "الأزرق", "الأصفر", "الأخضر")

@Composable
fun LudoBoard(v: TableView, l: LudoView, conn: TableConnection, isOwner: Boolean) {
    val mySeat = v.mySeat
    val names = names(v)
    val partner = if (mySeat == null) -1 else (mySeat + 2) % 4
    // آخر رمية لكل لاعب (نرد صغير جنب اسمه)، نتذكرها من الحالات اللي توصل
    val rolls = remember { androidx.compose.runtime.mutableStateMapOf<Int, Int>() }
    // عدّاد رميات لكل لاعب: يزيد مع كل رمية جديدة فيتدحرج نرده
    val rollTicks = remember { androidx.compose.runtime.mutableStateMapOf<Int, Int>() }
    val prev = remember { arrayOf<Any?>(null, null, null, 0) } // المرحلة، الدور، آخر حركة، عدّاد الرميات
    androidx.compose.runtime.LaunchedEffect(l.moveSig) {
        // السيرفر الجديد يرسل آخر رمية مع عدّادها: النرد الجديد يطلع على طول ويحل محل القديم
        if (l.rollSeq > 0) {
            val pSeq = prev[3] as Int
            if (l.rollSeq != pSeq && l.rolledSeat != null && l.rolledValue != null) {
                rolls[l.rolledSeat] = l.rolledValue
                if (pSeq != 0) rollTicks[l.rolledSeat] = (rollTicks[l.rolledSeat] ?: 0) + 1
            }
            prev[0] = l.phase; prev[1] = l.turn; prev[2] = l.lastSig; prev[3] = l.rollSeq
            return@LaunchedEffect
        }
        val (pPhase, pTurn, pLast) = Triple(prev[0] as String?, prev[1] as Int?, prev[2] as String?)
        if (l.phase == "move" && l.dice != null && (pPhase != "move" || pTurn != l.turn)) {
            rolls[l.turn] = l.dice; rollTicks[l.turn] = (rollTicks[l.turn] ?: 0) + 1
        } else if (l.lastSeat != null && l.lastRoll != null && l.lastSig != pLast && pPhase != "move" && pPhase != null) {
            rolls[l.lastSeat] = l.lastRoll; rollTicks[l.lastSeat] = (rollTicks[l.lastSeat] ?: 0) + 1
        } else if (l.lastSeat != null && l.lastRoll != null && rolls[l.lastSeat] == null) rolls[l.lastSeat] = l.lastRoll
        prev[0] = l.phase; prev[1] = l.turn; prev[2] = l.lastSig
    }

    // قارئ الشاشة شغّال: يبقى كل شي زي ما هو (الإيماءة وأزرار الاختيار)
    val reader = Announcer.readerOn
    // الرقم اللي اختاره (لما يكون عنده أكثر من رقم، مثل ستة وثلاثة): الحجر اللي يلمسه يمشي فيه
    var pickedDie by remember { mutableStateOf<Int?>(null) }
    val doRoll = { act(conn, "ludo", jsonOf("type" to "roll")) }
    // لمس حجر على اللوحة: يتحرك بالرقم المختار (أو أول رقم يقدر يمشيه)
    val tapBoard = { at: Offset, w: Float ->
        if (l.myTurn && l.phase == "move" && l.options.isNotEmpty()) {
            val U = w / 15f
            val movable = l.options.map { it.token }.toSet()
            val hit = ludoTokenPoints(w, l, mySeat ?: 0)
                .filter { it.first == l.movableOwner && it.second in movable }
                .map { it to (it.third - at).getDistance() }
                .filter { it.second < U * 0.9f }
                .minByOrNull { it.second }?.first
            if (hit != null) {
                val opts = l.options.filter { it.token == hit.second }
                val o = opts.firstOrNull { it.die == pickedDie } ?: opts.first()
                pickedDie = null
                act(conn, "ludo", jsonOf("type" to "move", "token" to o.token, "die" to o.die))
            }
        }
    }
    val latestTap = androidx.compose.runtime.rememberUpdatedState(tapBoard)
    // السجل (من فوق لتحت): قائمة فيها كل لاعب وأحجاره في أي خانة، تتنقل فيها
    var logOpen by remember { mutableStateOf(false) }
    if (logOpen) {
        MajliskDialog("أماكن الأحجار", { logOpen = false }) {
            l.positions.forEach { (name, color, tokens) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(12.dp).background(LUDO_COLORS.getOrElse(color) { Palette.gold }, RoundedCornerShape(6.dp)))
                    Text("$name، ${LUDO_COLOR_NAMES.getOrElse(color) { "" }}", color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                }
                tokens.forEach { Text(it, color = Palette.text, fontSize = 16.sp, modifier = Modifier.fillMaxWidth()) }
            }
            PrimaryButton("إغلاق", { logOpen = false })
        }
    }

    // سحب بإصبعين: من فوق لتحت = أماكن الأحجار، من تحت لفوق = الدور عند مين،
    // من اليمين لليسار = آخر رمية نرد، من اليسار لليمين = ترمي النرد مباشرة
    Column(
        Modifier.fillMaxWidth().twoFingerSwipes {
            when (it) {
                SwipeDir.Down -> logOpen = true
                SwipeDir.Up -> Announcer.announceNow(l.turnText)
                SwipeDir.Left -> Announcer.announceNow(l.diceText)
                SwipeDir.Right -> if (l.canRoll) act(conn, "ludo", jsonOf("type" to "roll")) else Announcer.announceNow(if (l.myTurn) "اختر الحجر أولاً" else l.turnText)
            }
        },
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // اسم كل لاعب عند زاوية لونه في اللوحة، وجنبه نرد بآخر رقم جاه
        val corner = { o: Int ->
            val turns = (3 - (mySeat ?: 0) + 4) % 4
            var p = (YARDS[o].first + 2.5f) to (YARDS[o].second + 2.5f)
            repeat(turns) { p = p.second to 14f - p.first }
            (p.first < 7f) to (p.second < 7f) // (فوق؟، يسار؟)
        }
        // عند كل لون: صورة اللاعب الدائرية واسمه، وجنبها النرد بآخر رقم رماه (يتحرك أول ما يرمي)
        val label: @Composable (Int) -> Unit = { o ->
            val n = names.getOrElse(o) { "" }
            // آخر رمية من السيرفر مباشرة (تتحدث على طول لكل اللاعبين)، وإلا آخر رمية محفوظة له
            val roll = if (l.rollSeq > 0 && l.rolledSeat == o && l.rolledValue != null) l.rolledValue else rolls[o]
            val turn = l.turn == o && l.phase != "over"
            val left = corner(o).second
            // دحرجة النرد مع كل رمية جديدة
            val spin = remember { androidx.compose.animation.core.Animatable(0f) }
            val tick = rollTicks[o] ?: 0
            androidx.compose.runtime.LaunchedEffect(tick) {
                if (tick > 0) { spin.snapTo(0f); spin.animateTo(360f, androidx.compose.animation.core.tween(450)) }
            }
            val mine = o == mySeat && !reader
            val distinct = l.pool.distinct()
            val dice: @Composable () -> Unit = {
                if (mine && l.myTurn && l.phase == "move" && distinct.size > 1) {
                    // أكثر من رقم: كل رقم نرد صغير، تختار واحد ثم تلمس الحجر
                    val usable = l.options.map { it.die }.toSet()
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        distinct.forEach { d ->
                            val on = (pickedDie ?: l.options.firstOrNull()?.die) == d
                            Box(
                                Modifier.border(3.dp, if (on) Palette.gold else Color.Transparent, RoundedCornerShape(8.dp)).padding(2.dp)
                                    .graphicsLayer { alpha = if (d in usable) 1f else 0.4f }
                                    .clickable(enabled = d in usable) { pickedDie = d },
                            ) { Dice(d, LUDO_COLORS[o], 32) }
                        }
                    }
                } else {
                    val canTap = mine && l.canRoll
                    Box(
                        Modifier.graphicsLayer { rotationZ = spin.value }
                            .then(if (canTap) Modifier.border(3.dp, Palette.gold, RoundedCornerShape(10.dp)).padding(3.dp).clickable { doRoll() } else Modifier),
                    ) { Dice(if (canTap && l.pool.isEmpty()) null else roll, LUDO_COLORS[o], if (canTap) 46 else 40) }
                }
            }
            Row(
                Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "${if (o == mySeat) "أنت" else n}${if (l.teams && o == partner) "، شريكك" else ""}، ${LUDO_COLOR_NAMES[o]}، وصل ${l.home(o)} من 4${if (roll != null) "، آخر رمية $roll" else ""}${if (turn) "، عليه الدور" else ""}"
                },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // النرد جهة اللوحة: لاعب اليسار نرده يمين صورته، ولاعب اليمين يسارها
                if (!left) dice()
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Box(
                        Modifier.border(3.dp, if (turn) Palette.gold else LUDO_COLORS[o], androidx.compose.foundation.shape.CircleShape).padding(3.dp),
                    ) { com.majlisk.app.ui.Avatar(v.seatUids.getOrNull(o), n, 52.dp) }
                    Text("$n${if (o == mySeat) " (أنت)" else if (l.teams && o == partner) " (شريكك)" else ""}", color = Palette.text, fontSize = 13.sp,
                        fontWeight = if (turn) FontWeight.Bold else FontWeight.Normal, maxLines = 1,
                        modifier = Modifier.background(Color(0x66000000), RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 1.dp))
                    Text("وصل ${l.home(o)}/4", color = Palette.textDim, fontSize = 11.sp)
                }
                if (left) dice()
            }
        }
        val cornerRow: @Composable (Boolean) -> Unit = { top ->
            val here = l.seats.filter { corner(it).first == top }
            if (here.isNotEmpty()) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Row(Modifier.widthIn(max = 360.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    // في الواجهة العربية أول عنصر يصير يمين: نحط لاعب اليمين أولاً
                    Box(Modifier.weight(1f), contentAlignment = androidx.compose.ui.AbsoluteAlignment.CenterRight) { here.firstOrNull { !corner(it).second }?.let { label(it) } }
                    Box(Modifier.weight(1f), contentAlignment = androidx.compose.ui.AbsoluteAlignment.CenterLeft) { here.firstOrNull { corner(it).second }?.let { label(it) } }
                }
            }
        }
        cornerRow(true)
        // اللوحة: للعين فقط، لمسها ما يقرأ شي (أماكن الأحجار بالإيماءات)
        Box(
            Modifier.fillMaxWidth().clearAndSetSemantics { },
            contentAlignment = Alignment.Center,
        ) {
            val movable = if (l.myTurn && l.phase == "move") l.options.map { l.movableOwner to it.token } else emptyList()
            // بدون قارئ الشاشة: تلمس الحجر اللي تبيه ويتحرك
            Canvas(
                Modifier.widthIn(max = ludoSide()).fillMaxWidth().aspectRatio(1f)
                    // اللمس يستخدم آخر حالة دائماً (ما يعلق على حالة قديمة لو تغيّرت بدون ما تتغير البصمة)
                    .pointerInput(reader) { if (!reader) detectTapGestures { latestTap.value(it, size.width.toFloat()) } },
            ) { drawLudo(l, mySeat ?: 0, movable) }
        }
        cornerRow(false)
        if (l.phase == "over") {
            val won = l.winner != null && mySeat != null && (if (l.teams) l.winner == mySeat % 2 else l.winner == mySeat)
            val w = l.winner ?: 0
            Text(if (won) "🎉 فزت!" else if (l.teams) "فاز فريق ${names[w]} و${names[w + 2]}" else "فاز ${names.getOrElse(w) { "" }}",
                color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            if (isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        } else {
            // النرد الكبير تحت اللوحة انشال (النرد جنب اسمك يكفي)؛ زر الرمي لقارئ الشاشة بس
            if (l.myTurn && l.phase == "roll" && reader) PrimaryButton("ارمِ النرد", { act(conn, "ludo", jsonOf("type" to "roll")) })
        }
        // قارئ الشاشة: الاختيارات كما هي (كل حجر مع الرقم اللي يمشيه)
        if (reader && l.myTurn && l.phase == "move" && l.options.size > 1) {
            Text(l.prompt.ifEmpty { "اختر الحجر" }, color = Color.Transparent, modifier = Modifier.size(1.dp).semantics { heading() })
            l.options.forEach { o -> SecondaryButton(o.text, { act(conn, "ludo", jsonOf("type" to "move", "token" to o.token, "die" to o.die)) }, fill = true) }
        }
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

/** مكان كل حجر على اللوحة (نفس حساب الرسم، مع إزاحة الأحجار المتكدسة): (اللون، رقم الحجر، النقطة) */
private fun ludoTokenPoints(width: Float, l: LudoView, bottom: Int): List<Triple<Int, Int, Offset>> {
    val U = width / 15f
    val turns = (3 - bottom + 4) % 4
    fun rot(cell: Pair<Float, Float>): Pair<Float, Float> { var p = cell; repeat(turns) { p = p.second to 14f - p.first }; return p }
    fun xy(cell: Pair<Float, Float>): Offset { val (r, c) = rot(cell); return Offset(c * U + U / 2, r * U + U / 2) }
    val out = mutableListOf<Triple<Int, Int, Offset>>()
    val seen = HashMap<String, Int>()
    for (o in l.seats) {
        l.tokens.getOrNull(o).orEmpty().forEachIndexed { i, p ->
            val cell = when {
                p == -1 -> (YARDS[o].first + YARD_SPOTS[i].first - 0.5f) to (YARDS[o].second + YARD_SPOTS[i].second - 0.5f)
                p == LudoView.FINISH -> CENTER_SPOT[o]
                p > LudoView.LAST_TRACK && p - LudoView.LAST_TRACK - 1 < 5 -> HOME_CELLS[o][p - LudoView.LAST_TRACK - 1]
                p > LudoView.LAST_TRACK -> ((HOME_CELLS[o][4].first + CENTER_SPOT[o].first) / 2) to ((HOME_CELLS[o][4].second + CENTER_SPOT[o].second) / 2)
                else -> TRACK_CELLS[LudoView.absPos(o, p)]
            }
            val pt = xy(cell)
            val key = "${pt.x.toInt()},${pt.y.toInt()}"
            val n = seen[key] ?: 0
            seen[key] = n + 1
            out += Triple(o, i, Offset(pt.x + n * U * 0.18f, pt.y - n * U * 0.18f))
        }
    }
    return out
}

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
        // رقم الخانة ثابت للجميع من 1 إلى 52 (نفس الأرقام اللي ينطقها الإعلان لكل اللاعبين)
        val num = i + 1
        drawContext.canvas.nativeCanvas.drawText("$num", p.x, p.y + U * 0.16f, android.graphics.Paint().apply {
            isAntiAlias = true; textAlign = android.graphics.Paint.Align.CENTER; textSize = U * 0.42f
            color = if (start >= 0) android.graphics.Color.WHITE else android.graphics.Color.argb(200, 13, 43, 32)
        })
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
                // ممر المنزل 6 خانات: الخمس الملوّنة، والسادسة عند حافة الوسط
                p > LudoView.LAST_TRACK && p - LudoView.LAST_TRACK - 1 < 5 -> HOME_CELLS[o][p - LudoView.LAST_TRACK - 1]
                p > LudoView.LAST_TRACK -> ((HOME_CELLS[o][4].first + CENTER_SPOT[o].first) / 2) to ((HOME_CELLS[o][4].second + CENTER_SPOT[o].second) / 2)
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
                d != null -> {
                    when {
                        (first && d.line.isEmpty() && d.phase == "playing") || (phase != null && phase != "playing" && d.phase == "playing") -> Sounds.dominoShuffle()
                        !first && (d.lastKind == "play" || d.lastKind == "draw") -> Sounds.dominoTile()
                    }
                    // انتهت الصكة (أو المباراة): بعد طقة آخر قطعة
                    if (!first && phase == "playing" && (d.phase == "handOver" || d.phase == "matchOver")) Sounds.dominoEnd(0.5)
                }
                // الجاكارو: توزيع الورق، وصوت الورقة، ونقرة لكل خطوة يمشيها الحجر
                j != null -> {
                    if ((first && !j.hasMove) || (!first && deal != null && deal != j.dealNo)) Sounds.deal(true)
                    if (!first && j.hasMove) {
                        Sounds.jackarooCard()
                        if (j.lastSteps > 0) Sounds.marbleSteps(j.lastSteps, at = 0.25)
                        // أكل حجر: بعد ما يوصل الحجر
                        if (j.captures > 0) Sounds.capture(at = 0.25 + j.lastSteps.coerceIn(1, 13) * Sounds.STEP_GAP)
                    }
                }
                // لودو: صوت النرد مع كل رمية، ونقرة لكل خطوة يمشيها الحجر
                l != null && !first -> {
                    val newTurnRoll = l.phase == "move" && (phase != "move" || ludoTurn != l.turn)
                    val moveChanged = l.lastSig != ludoLast && l.lastSig != "null"
                    // رمى ثم تحرك مباشرة (خيار واحد) أو ما فيه حركة: النرد ثم النقرات
                    val rolledNow = newTurnRoll || (moveChanged && phase != "move")
                    if (rolledNow) Sounds.dice()
                    if (moveChanged && l.moved) {
                        val at = if (rolledNow && !newTurnRoll) 0.6 else 0.0
                        Sounds.steps(l.lastSteps, at = at)
                        // أكل حجر: بعد ما يوصل الحجر
                        if (l.captures > 0) Sounds.capture(at = at + l.lastSteps.coerceIn(1, 13) * Sounds.STEP_GAP)
                    }
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
