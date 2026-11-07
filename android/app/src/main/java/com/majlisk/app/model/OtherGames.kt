package com.majlisk.app.model

import org.json.JSONObject

// الدومينو والجاكارو واللودو: حالة اللعبة من الخادم، ومعها "ui" (الحركات المسموحة ونصوصها
// وقراءات اللوحة) محسوبة في الخادم لهذا اللاعب، فالتطبيق يرسم ويعرض الأزرار ويرسل الحركة كما هي.

// ───── الدومينو ─────

data class Tile(val a: Int, val b: Int) {
    fun json(): JSONObject = JSONObject().put("a", a).put("b", b)
    val isDouble get() = a == b
}

/** قطعة على الطاولة: الوجه الخارجي (الطرف الجديد) وأين وُضعت */
data class PlacedTile(val tile: Tile, val seat: Int, val outer: Int, val side: String)

data class DominoHandTile(val tile: Tile, val label: String, val legal: Boolean, val askSide: Boolean)

data class DominoView(
    val phase: String,
    val turn: Int,
    val players: Int,
    val target: Int,
    val scores: List<Int>,
    val line: List<PlacedTile>,
    val handCounts: List<Int>,
    val boneyard: Int,
    /** بصمة آخر حركة (للأصوات) */
    val moveSig: String,
    /** نوع آخر حركة: play / draw / pass */
    val lastKind: String?,
    // من ui
    val myTurn: Boolean,
    val canDraw: Boolean,
    val canPass: Boolean,
    val hand: List<DominoHandTile>,
    val ends: Pair<Int, Int>?,
    val endsText: String,
    val lineText: String,
    val scoreText: String,
    val sideNames: List<String>,
    val mySide: Int,
    val prompt: String,
    /** سجل كل جولة (صكة): رقمها وحركاتها بالترتيب */
    val log: List<Pair<Int, List<String>>> = emptyList(),
    /** من يختار البادئ (بعد فوز فريقه بالصكة) */
    val chooser: Int? = null,
    /** خياراتك لمن يبدأ (أنت أو شريكك) لو الاختيار لك */
    val starterOptions: List<Pair<Int, String>> = emptyList(),
) {
    companion object {
        fun parse(s: JSONObject, ui: JSONObject, log: org.json.JSONArray? = null): DominoView {
            val rules = s.optJSONObject("rules") ?: JSONObject()
            val tile = { o: JSONObject? -> Tile(o?.optInt("a") ?: 0, o?.optInt("b") ?: 0) }
            return DominoView(
                phase = s.optString("phase"),
                turn = s.optInt("turn"),
                players = rules.optInt("players", 4),
                target = rules.optInt("target", 100),
                scores = s.optJSONArray("scores").ints(),
                line = s.optJSONArray("line").objects().map { PlacedTile(tile(it.optJSONObject("tile")), it.optInt("seat"), it.optInt("outer"), it.optString("side")) },
                handCounts = s.optJSONArray("hands").mapIndexed { a, i -> a.optJSONArray(i)?.length() ?: 0 },
                boneyard = s.optJSONArray("boneyard")?.length() ?: 0,
                moveSig = "${s.opt("lastMove")}|${s.optString("phase")}|${s.optInt("handNo")}",
                lastKind = s.optJSONObject("lastMove")?.optString("kind"),
                myTurn = ui.optBoolean("myTurn"),
                canDraw = ui.optBoolean("canDraw"),
                canPass = ui.optBoolean("canPass"),
                hand = ui.optJSONArray("hand").objects().map {
                    DominoHandTile(tile(it.optJSONObject("tile")), it.optString("label"), it.optBoolean("legal"), it.optBoolean("askSide"))
                },
                ends = ui.optJSONObject("ends")?.let { it.optInt("left") to it.optInt("right") },
                endsText = ui.optString("endsText"),
                lineText = ui.optString("lineText"),
                scoreText = ui.optString("scoreText"),
                sideNames = ui.optJSONArray("sideNames").mapIndexed { a, i -> a.optString(i) },
                mySide = ui.optInt("mySide", -1),
                prompt = ui.optString("prompt"),
                log = log.objects().map { e -> e.optInt("hand") to e.optJSONArray("lines").mapIndexed { a, i -> a.optString(i) } },
                chooser = s.optIntOrNull("chooser"),
                starterOptions = ui.optJSONArray("starterOptions").objects().map { it.optInt("seat") to it.optString("text") },
            )
        }
    }
}

// ───── الجاكارو ─────

/** zone: home / track / safe — pos: موضع على المسار أو خانة الأمان */
data class Marble(val zone: String, val pos: Int)

data class JackarooCard(val rank: String, val suit: String) {
    fun json(): JSONObject = JSONObject().put("rank", rank).put("suit", suit)
    val red get() = suit == "H" || suit == "D"
    val symbol get() = when (suit) { "S" -> "♠"; "H" -> "♥"; "D" -> "♦"; else -> "♣" }
}

data class JackarooMove(val move: JSONObject, val text: String)
data class JackarooHandCard(val card: JackarooCard, val label: String, val usable: Boolean, val moves: List<JackarooMove>)

data class JackarooView(
    val phase: String,
    val turn: Int,
    val winnerTeam: Int?,
    val dealNo: Int,
    val segment: Int,
    val marbles: List<List<Marble>>,
    val handCounts: List<Int>,
    val moveSig: String,
    /** آخر حركة موجودة، وكم خطوة مشت (لصوت النقرات) */
    val hasMove: Boolean,
    val lastSteps: Int,
    /** كم حجر انأكل في آخر حركة (لصوت الأكل) */
    val captures: Int = 0,
    val myTurn: Boolean,
    val burning: Boolean,
    val hand: List<JackarooHandCard>,
    val boardText: String,
    val mineText: String,
    val prompt: String,
    /** الأوراق الملعوبة في هذا التوزيع بالترتيب */
    val pile: List<JackarooCard> = emptyList(),
) {
    /** أوراق اللفة الحالية في وسط الطاولة: تتجمع حتى أربع، ثم تنمسح وتبدأ اللفة التالية */
    val centerCards: List<JackarooCard> get() = if (pile.isEmpty()) emptyList() else pile.takeLast((pile.size - 1) % 4 + 1)

    /** عدد أحجار الفريق في منطقة الأمان */
    fun safeCount(team: Int) = listOf(team, team + 2).sumOf { o -> marbles.getOrNull(o).orEmpty().count { it.zone == "safe" } }

    companion object {
        fun parse(s: JSONObject, ui: JSONObject, mySeat: Int?): JackarooView {
            val rules = s.optJSONObject("rules") ?: JSONObject()
            val hands = s.optJSONArray("hands")
            val myCards = mySeat?.let { hands?.optJSONArray(it) }.let { a -> (0 until (a?.length() ?: 0)).map { i -> a!!.optJSONObject(i) } }
                .map { JackarooCard(it?.optString("rank").orEmpty(), it?.optString("suit").orEmpty()) }
            val uiHand = ui.optJSONArray("hand").objects()
            return JackarooView(
                phase = s.optString("phase"),
                turn = s.optInt("turn"),
                winnerTeam = s.optIntOrNull("winnerTeam"),
                dealNo = s.optInt("dealNo"),
                segment = rules.optInt("segment", 19),
                marbles = s.optJSONArray("marbles").mapIndexed { a, i ->
                    a.optJSONArray(i).objects().map { Marble(it.optString("zone"), it.optInt("pos")) }
                },
                handCounts = hands.mapIndexed { a, i -> a.optJSONArray(i)?.length() ?: 0 },
                moveSig = "${s.opt("lastMove")}|${s.optInt("dealNo")}|${s.optString("phase")}",
                hasMove = s.optJSONObject("lastMove") != null,
                captures = s.optJSONObject("lastMove")?.optJSONArray("captured")?.length() ?: 0,
                lastSteps = s.optJSONObject("lastMove")?.optJSONObject("move")?.let { m ->
                    when (m.optString("kind")) {
                        "forward", "back", "kingRun" -> m.optInt("steps")
                        "split" -> m.optJSONArray("parts").objects().sumOf { it.optInt("steps") }
                        "out", "swap" -> 1
                        else -> 0
                    }
                } ?: 0,
                myTurn = ui.optBoolean("myTurn"),
                burning = ui.optBoolean("burning"),
                hand = myCards.mapIndexed { i, c ->
                    val h = uiHand.getOrNull(i)
                    JackarooHandCard(
                        c, h?.optString("label").orEmpty(), h?.optBoolean("usable") == true,
                        h?.optJSONArray("moves").objects().map { JackarooMove(it.optJSONObject("move") ?: JSONObject(), it.optString("text")) },
                    )
                },
                boardText = ui.optString("boardText"),
                mineText = ui.optString("mineText"),
                prompt = ui.optString("prompt"),
                pile = s.optJSONArray("pile").objects().map { JackarooCard(it.optString("rank"), it.optString("suit")) },
            )
        }
    }
}

// ───── لودو ─────

data class LudoOption(val token: Int, val text: String, val die: Int = 0)

data class LudoView(
    val seats: List<Int>,
    val tokens: List<List<Int>>,
    val turn: Int,
    val phase: String,
    val dice: Int?,
    val lastRoll: Int?,
    /** من رمى آخر رمية */
    val lastSeat: Int?,
    /** آخر رمية من السيرفر (مين وكم) وعدّادها اللي يزيد مع كل رمية */
    val rolledSeat: Int? = null,
    val rolledValue: Int? = null,
    val rollSeq: Int = 0,
    val winner: Int?,
    val teams: Boolean,
    val moveSig: String,
    /** تحرك حجر في آخر حركة (للصوت) */
    val moved: Boolean,
    /** بصمة آخر حركة، وكم خطوة مشى الحجر */
    val lastSig: String,
    val lastSteps: Int,
    /** كم حجر انأكل في آخر حركة (لصوت الأكل) */
    val captures: Int = 0,
    val myTurn: Boolean,
    val options: List<LudoOption>,
    val movableOwner: Int,
    val boardText: String,
    val mineText: String,
    val prompt: String,
    /** سجل الرميات والحركات بالترتيب */
    val log: List<String> = emptyList(),
    /** قائمة الأماكن: كل لاعب (اسمه ولونه) وأحجاره في أي خانة */
    val positions: List<Triple<String, Int, List<String>>> = emptyList(),
    val turnText: String = "",
    val diceText: String = "",
    val canRoll: Boolean = false,
    /** الأرقام المتجمعة بانتظار الحركة (الستة ومعها اللي بعدها) */
    val pool: List<Int> = emptyList(),
) {
    fun home(owner: Int) = tokens.getOrNull(owner).orEmpty().count { it == FINISH }

    companion object {
        /** المسار 0..50 (51 خانة)، ممر المنزل 51..55 (5 خانات)، المنزل 56 */
        const val FINISH = 56
        const val LAST_TRACK = 50
        val STARTS = listOf(0, 13, 26, 39)
        val SAFE = setOf(0, 8, 13, 21, 26, 34, 39, 47)
        fun absPos(owner: Int, p: Int) = (STARTS[owner] + p) % 52

        fun parse(s: JSONObject, ui: JSONObject, log: org.json.JSONArray? = null): LudoView {
            val last = s.optJSONObject("lastMove")
            return LudoView(
                seats = s.optJSONArray("seats").ints(),
                tokens = s.optJSONArray("tokens").mapIndexed { a, i -> a.optJSONArray(i).ints() },
                turn = s.optInt("turn"),
                phase = s.optString("phase"),
                dice = s.optIntOrNull("dice"),
                lastRoll = last?.optIntOrNull("roll"),
                lastSeat = last?.optIntOrNull("seat"),
                rolledSeat = s.optJSONObject("lastRolled")?.optIntOrNull("seat"),
                rolledValue = s.optJSONObject("lastRolled")?.optIntOrNull("roll"),
                rollSeq = s.optJSONObject("lastRolled")?.optInt("seq") ?: 0,
                winner = s.optIntOrNull("winner"),
                teams = s.optJSONObject("rules")?.optBoolean("teams") == true,
                moveSig = "${s.opt("lastMove")}|${s.optInt("turn")}|${s.optString("phase")}|${s.opt("dice")}|${s.opt("pool")}|${s.optJSONObject("lastRolled")?.optInt("seq") ?: 0}",
                moved = last?.optJSONObject("token") != null,
                lastSig = "${s.opt("lastMove")}",
                captures = last?.optJSONArray("captured")?.length() ?: 0,
                lastSteps = last?.let { m ->
                    val from = m.optIntOrNull("from"); val to = m.optIntOrNull("to")
                    if (from == null || to == null) 0 else if (from == -1) 1 else to - from
                } ?: 0,
                myTurn = ui.optBoolean("myTurn"),
                options = ui.optJSONArray("options").objects().map { LudoOption(it.optInt("token"), it.optString("text"), it.optInt("die", s.optInt("dice"))) },
                movableOwner = ui.optInt("movableOwner", -1),
                boardText = ui.optString("boardText"),
                mineText = ui.optString("mineText"),
                prompt = ui.optString("prompt"),
                log = log.mapIndexed { a, i -> a.optString(i) },
                positions = ui.optJSONArray("positions").objects().map { Triple(it.optString("name"), it.optInt("color"), it.optJSONArray("tokens").mapIndexed { a, i -> a.optString(i) }) },
                turnText = ui.optString("turnText"),
                diceText = ui.optString("diceText"),
                canRoll = ui.optBoolean("canRoll"),
                pool = ui.optJSONArray("pool").ints(),
            )
        }
    }
}
