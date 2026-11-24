package com.majlisk.app.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * ألعاب الورق الجديدة (طرنيب، تريكس، كنكان، شايب): الخادم يرسل لكل لاعب «وش يشوف» بس —
 * أوراقه وأزرار حركاته المسموحة ونصوص قارئ الشاشة — والتطبيق يرسم ويرسل الحركة كما هي.
 */
data class CardFace(val id: Int, val r: String, val s: String) {
    val red: Boolean get() = s == "H" || s == "D"
    val joker: Boolean get() = r == "JK"
    val symbol: String get() = when (s) { "S" -> "♠"; "H" -> "♥"; "D" -> "♦"; "C" -> "♣"; else -> "" }
    /** الرقم على الورقة: A K Q J والأرقام، والجوكر نجمة */
    val short: String get() = if (joker) "★" else r
}

data class CardsSeat(val seat: Int, val name: String, val count: Int, val note: String, val turn: Boolean)
data class CardsPile(val id: String, val title: String, val text: String, val cards: List<CardFace>)
data class CardsHandCard(val face: CardFace, val label: String, val legal: Boolean)
data class CardsButton(val id: String, val label: String, val primary: Boolean, val needsSelection: Boolean)

/** أصوات آخر حركة من الخادم: رقمها يتغير مع كل حركة فيها صوت. win = مقاعد الفائزين لما تخلص المباراة */
data class CardsFx(val n: Int, val keys: List<String>, val win: List<Int>?, val by: Int?)

data class CardsView(
    val game: String,
    val over: Boolean,
    val myTurn: Boolean,
    val prompt: String,
    val status: String,
    val scores: List<Pair<String, Int>>,
    val seats: List<CardsSeat>,
    val center: List<Pair<Int, CardFace>>,
    /** الأكلة اكتملت: تنعرض لحظة وتنشال */
    val centerDone: Boolean,
    val piles: List<CardsPile>,
    val hand: List<CardsHandCard>,
    val select: Boolean,
    val buttons: List<CardsButton>,
    val readUp: String,
    val readDown: String,
    val readLeft: String,
    val readRight: String,
    val fx: CardsFx?,
) {
    companion object {
        private fun face(o: JSONObject?) = CardFace(o?.optInt("id") ?: 0, o?.optString("r").orEmpty(), o?.optString("s").orEmpty())
        private fun JSONArray?.objs(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

        fun parse(c: JSONObject): CardsView {
            val u = c.optJSONObject("ui") ?: JSONObject()
            val reads = u.optJSONObject("reads") ?: JSONObject()
            return CardsView(
                game = c.optString("game"),
                over = c.optBoolean("over"),
                myTurn = u.optBoolean("myTurn"),
                prompt = u.optString("prompt"),
                status = u.optString("status"),
                scores = u.optJSONArray("scores").objs().map { it.optString("name") to it.optInt("value") },
                seats = u.optJSONArray("seats").objs().map { CardsSeat(it.optInt("seat"), it.optString("name"), it.optInt("count"), it.optString("note"), it.optBoolean("turn")) },
                center = u.optJSONArray("center").objs().map { it.optInt("seat") to face(it.optJSONObject("card")) },
                centerDone = u.optBoolean("centerDone"),
                piles = u.optJSONArray("piles").objs().map { p -> CardsPile(p.optString("id"), p.optString("title"), p.optString("text"), p.optJSONArray("cards").objs().map { face(it) }) },
                hand = u.optJSONArray("hand").objs().map { CardsHandCard(face(it), it.optString("label"), it.optBoolean("legal")) },
                select = u.optBoolean("select"),
                buttons = u.optJSONArray("buttons").objs().map { CardsButton(it.optString("id"), it.optString("label"), it.optBoolean("primary"), it.optBoolean("needsSelection")) },
                readUp = reads.optString("up"),
                readDown = reads.optString("down"),
                readLeft = reads.optString("left"),
                readRight = reads.optString("right"),
                fx = c.optJSONObject("fx")?.let { f ->
                    CardsFx(
                        f.optInt("n"),
                        f.optJSONArray("keys")?.let { a -> (0 until a.length()).map { a.optString(it) } }.orEmpty(),
                        f.optJSONArray("win")?.let { a -> (0 until a.length()).map { a.optInt(it) } },
                        if (f.has("by")) f.optInt("by") else null,
                    )
                },
            )
        }
    }
}
