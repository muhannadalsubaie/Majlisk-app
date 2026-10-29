package com.majlisk.app.model

import org.json.JSONObject

/** أسماء الأوراق كما في الخادم (shared/baloot/cards.ts) */
val SUITS = listOf("S", "H", "C", "D")
val SUIT_NAMES = mapOf("S" to "سبيت", "H" to "هاص", "C" to "شريا", "D" to "ديمن")
val SUIT_SYMBOLS = mapOf("S" to "♠", "H" to "♥", "C" to "♣", "D" to "♦")
val RANK_NAMES = mapOf("A" to "أكة", "K" to "شايب", "Q" to "بنت", "J" to "ولد", "10" to "10", "9" to "9", "8" to "8", "7" to "7")
private val RANK_ORDER = listOf("A", "K", "Q", "J", "10", "9", "8", "7")

data class Card(val suit: String, val rank: String) {
    val label: String get() = "${RANK_NAMES[rank]} ${SUIT_NAMES[suit]}"
    /** ملف الصورة في assets/cards */
    val asset: String get() = "cards/$suit$rank.webp"
    fun toJson(): JSONObject = JSONObject().put("suit", suit).put("rank", rank)

    companion object {
        fun from(o: JSONObject?): Card? = o?.let { Card(it.optString("suit"), it.optString("rank")) }
    }
}

/** ترتيب اليد: حسب اللون ثم الرتبة */
fun sortHand(hand: List<Card>): List<Card> =
    hand.sortedWith(compareBy({ SUITS.indexOf(it.suit) }, { RANK_ORDER.indexOf(it.rank) }))

/** مزايدة: نحتفظ بالكائن كما أرسله الخادم لنعيده كما هو */
data class Bid(val type: String, val suit: String?, val raw: JSONObject) {
    val label: String
        get() = when (type) {
            "pass" -> "بس"
            "sun" -> "صن"
            "ashkal" -> "أشكل"
            "secondHokm" -> "حكم ثاني"
            "qablak" -> "قبلك"
            "confirmHokm" -> "تأكيد الحكم"
            "hokm" -> "حكم ${SUIT_NAMES[suit]} ${SUIT_SYMBOLS[suit]}"
            else -> type
        }
}

fun teamOf(seat: Int) = seat % 2
