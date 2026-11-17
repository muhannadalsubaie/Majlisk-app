package com.majlisk.app.model

import org.json.JSONArray
import org.json.JSONObject

// ملّاك (لعبة العقارات): الحالة من الخادم (كلها مكشوفة) ومعها "ui" لهذا اللاعب:
// الأزرار المتاحة ونصوص قارئ الشاشة ووصف الخانات.

/** نوع الخانة: city / station / utility / chance / chest / tax / go / jail / rest / goToJail */
data class MallakSquare(val name: String, val kind: String, val group: Int = -1, val price: Int = 0)

/** اللوحة (نفس لوحة الخادم): 40 خانة */
val MALLAK_BOARD: List<MallakSquare> = listOf(
    MallakSquare("الانطلاق", "go"), MallakSquare("الهفوف", "city", 0, 60), MallakSquare("صندوق المجلس", "chest"),
    MallakSquare("المبرز", "city", 0, 70), MallakSquare("الزكاة", "tax"), MallakSquare("مطار الرياض", "station", -1, 200),
    MallakSquare("بريدة", "city", 1, 100), MallakSquare("فرصة", "chance"), MallakSquare("عنيزة", "city", 1, 100),
    MallakSquare("الرس", "city", 1, 120), MallakSquare("السجن", "jail"), MallakSquare("أبها", "city", 2, 140),
    MallakSquare("الكهرباء", "utility", -1, 150), MallakSquare("خميس مشيط", "city", 2, 140), MallakSquare("النماص", "city", 2, 160),
    MallakSquare("قطار الشمال", "station", -1, 200), MallakSquare("الشفا", "city", 3, 180), MallakSquare("صندوق المجلس", "chest"),
    MallakSquare("الهدا", "city", 3, 180), MallakSquare("الحوية", "city", 3, 200), MallakSquare("الاستراحة", "rest"),
    MallakSquare("الدمام", "city", 4, 220), MallakSquare("فرصة", "chance"), MallakSquare("الخبر", "city", 4, 220),
    MallakSquare("الظهران", "city", 4, 240), MallakSquare("مطار الدمام", "station", -1, 200), MallakSquare("البلد", "city", 5, 260),
    MallakSquare("الحمراء", "city", 5, 260), MallakSquare("المياه", "utility", -1, 150), MallakSquare("أبحر", "city", 5, 280),
    MallakSquare("روح للسجن", "goToJail"), MallakSquare("تبوك", "city", 6, 300), MallakSquare("العلا", "city", 6, 300),
    MallakSquare("صندوق المجلس", "chest"), MallakSquare("أملج", "city", 6, 320), MallakSquare("مطار جدة", "station", -1, 200),
    MallakSquare("فرصة", "chance"), MallakSquare("الدرعية", "city", 7, 350), MallakSquare("رسوم البلدية", "tax"),
    MallakSquare("طريق الملك فهد", "city", 7, 400),
)

/** ألوان المجموعات (نفس الخادم) */
val MALLAK_GROUP_COLORS = listOf(0xFF8B5A2B, 0xFF5BC0EB, 0xFFD63AF9, 0xFFF28C28, 0xFFE63946, 0xFFF4D35E, 0xFF2A9D8F, 0xFF1D3FBB)
/** لون كل لاعب (6 مقاعد) */
val MALLAK_PLAYER_COLORS = listOf(0xFFE53935, 0xFF1E88E5, 0xFFFDD835, 0xFF43A047, 0xFF8E24AA, 0xFFFF7043)
val MALLAK_PLAYER_COLOR_NAMES = listOf("الأحمر", "الأزرق", "الأصفر", "الأخضر", "البنفسجي", "البرتقالي")

data class MallakPlayer(val seat: Int, val cash: Int, val pos: Int, val inJail: Boolean, val jailCards: Int, val bankrupt: Boolean)
data class MallakAction(val type: String, val label: String, val amount: Int? = null)
data class MallakProp(val square: Int, val name: String, val houses: Int, val mortgaged: Boolean, val build: Boolean, val sell: Boolean, val mortgage: Boolean, val unmortgage: Boolean)
data class MallakPlayerUi(val seat: Int, val text: String, val cash: Int, val pos: Int, val bankrupt: Boolean, val inJail: Boolean)

data class MallakView(
    val phase: String,
    val turn: Int,
    val seats: List<Int>,
    /** حسب رقم المقعد (6)، null لغير المشارك */
    val players: List<MallakPlayer?>,
    val owner: List<Int?>,
    val houses: List<Int>,
    val mortgaged: List<Boolean>,
    val dice: Pair<Int, Int>?,
    val rollSeq: Int,
    /** آخر حركة حجر: مين ومن وين لوين ونوعها (roll / card / jail)، ورقمها (للحركة على الشاشة) */
    val moveSeat: Int, val moveFrom: Int, val moveTo: Int, val moveKind: String, val moveSeq: Int,
    val cardSeq: Int,
    val winner: Int?,
    // من ui
    val myTurn: Boolean,
    val prompt: String,
    val actions: List<MallakAction>,
    val myProps: List<MallakProp>,
    val canTrade: Boolean,
    val squares: List<String>,
    val playersUi: List<MallakPlayerUi>,
    val hereText: String,
    val turnText: String,
    val tradeText: String,
    val auctionText: String,
    val cardText: String,
    val log: List<String>,
) {
    val alive: List<Int> get() = seats.filter { players.getOrNull(it)?.bankrupt == false }

    companion object {
        fun parse(s: JSONObject, ui: JSONObject, log: JSONArray?): MallakView {
            val players = s.optJSONArray("players").mapIndexed { a, i ->
                a.optJSONObject(i)?.let { MallakPlayer(it.optInt("seat"), it.optInt("cash"), it.optInt("pos"), it.optBoolean("inJail"), it.optInt("jailCards"), it.optBoolean("bankrupt")) }
            }
            val dice = s.optJSONArray("dice")?.let { if (it.length() == 2) it.optInt(0) to it.optInt(1) else null }
            val lm = s.optJSONObject("lastMove")
            return MallakView(
                phase = s.optString("phase"),
                turn = s.optInt("turn"),
                seats = s.optJSONArray("seats").ints(),
                players = players,
                owner = s.optJSONArray("owner").mapIndexed { a, i -> if (a.isNull(i)) null else a.optInt(i) },
                houses = s.optJSONArray("houses").ints(),
                mortgaged = s.optJSONArray("mortgaged").mapIndexed { a, i -> a.optBoolean(i) },
                dice = dice,
                rollSeq = s.optInt("rollSeq"),
                moveSeat = lm?.optInt("seat") ?: -1, moveFrom = lm?.optInt("from") ?: 0, moveTo = lm?.optInt("to") ?: 0,
                moveKind = lm?.optString("kind") ?: "", moveSeq = lm?.optInt("seq") ?: 0,
                cardSeq = s.optJSONObject("lastCard")?.optInt("seq") ?: 0,
                winner = s.optIntOrNull("winner"),
                myTurn = ui.optBoolean("myTurn"),
                prompt = ui.optString("prompt"),
                actions = ui.optJSONArray("actions").objects().map { MallakAction(it.optString("type"), it.optString("label"), it.optIntOrNull("amount")) },
                myProps = ui.optJSONArray("myProps").objects().map {
                    MallakProp(it.optInt("square"), it.optString("name"), it.optInt("houses"), it.optBoolean("mortgaged"),
                        it.optBoolean("build"), it.optBoolean("sell"), it.optBoolean("mortgage"), it.optBoolean("unmortgage"))
                },
                canTrade = ui.optBoolean("canTrade"),
                squares = ui.optJSONArray("squares").mapIndexed { a, i -> a.optString(i) },
                playersUi = ui.optJSONArray("players").objects().map {
                    MallakPlayerUi(it.optInt("seat"), it.optString("text"), it.optInt("cash"), it.optInt("pos"), it.optBoolean("bankrupt"), it.optBoolean("inJail"))
                },
                hereText = ui.optString("hereText"),
                turnText = ui.optString("turnText"),
                tradeText = ui.optString("tradeText"),
                auctionText = ui.optString("auctionText"),
                cardText = ui.optString("cardText"),
                log = log.mapIndexed { a, i -> a.optString(i) },
            )
        }
    }
}
