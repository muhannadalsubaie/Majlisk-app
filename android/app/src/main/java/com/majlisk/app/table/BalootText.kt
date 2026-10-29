package com.majlisk.app.table

import com.majlisk.app.model.GameView
import com.majlisk.app.model.PlayedCard
import com.majlisk.app.model.SUIT_NAMES
import com.majlisk.app.model.SUIT_SYMBOLS
import com.majlisk.app.model.TableView
import com.majlisk.app.model.teamOf

/** نصوص القراءة السريعة في البلوت — نفس صياغة التطبيق الحالي */
class BalootText(private val view: TableView, private val g: GameView, private val shownTrick: List<PlayedCard>) {
    private val mySeat = view.mySeat
    private val me = mySeat ?: 0
    fun name(s: Int) = view.seats.getOrNull(s)?.username ?: "مقعد ${s + 1}"
    private fun teamWord(s: Int) = if (mySeat == null) "فريق ${name(s)}" else if (teamOf(s) == teamOf(me)) "فريقك" else "الخصم"

    /** الأوراق الموجودة على الطاولة الآن ومن لعب كل ورقة، بالترتيب */
    fun trick(): String = when {
        // القراءة دائماً للأكلة الحالية (لا الأكلة السابقة الظاهرة لحظة على الشاشة)
        g.trick.isNotEmpty() -> g.trick.joinToString("، ") { "${name(it.seat)}: ${it.card.label}" }
        (g.phase == "bidding" || g.phase == "doubling") && g.qaba != null -> "ورقة الأرض: ${g.qaba.label}"
        else -> "لا توجد أوراق على الطاولة"
    }

    /** نوع اللعب: من اشترى، وعلى ماذا، والدبل */
    fun contract(): String {
        val c = g.contract ?: run {
            val ground = g.qaba?.let { "، ورقة الأرض ${it.label}" }.orEmpty()
            return "لم يشترِ أحد بعد، المزايدة في الجولة ${if (g.bidRound == 1) "الأولى" else "الثانية"}$ground"
        }
        val mode = if (c.mode == "sun") "صن" else "حكم ${SUIT_NAMES[c.trump]}"
        val parts = mutableListOf(if (c.buyer == mySeat) "أنت اشتريت $mode" else "${name(c.buyer)} اشترى $mode، ${teamWord(c.buyer)}")
        if (c.qabaTo != c.buyer) parts += "القبلة لـ${if (c.qabaTo == mySeat) "ك" else name(c.qabaTo)}"
        val d = g.doubling
        when {
            d.gahwa -> parts += "قهوة"
            d.level > 1 -> {
                val label = mapOf(2 to "دبل", 3 to "ثري", 4 to "فور")[d.level]
                parts += "$label${if (c.mode == "hokm") (if (d.locked) " مقفل" else " مفتوح") else ""}"
            }
            else -> parts += "بدون دبل"
        }
        return parts.joinToString("، ")
    }

    /** المشاريع المعلنة ومن أعلنها (وأوراقها بعد الأكلة الأولى) */
    fun projects(): String {
        val lines = g.declared.map { d ->
            val who = if (d.seat == mySeat) "أنت" else name(d.seat)
            val items = d.kinds.mapIndexed { i, k -> d.cards?.getOrNull(i)?.let { "$k: $it" } ?: k }
            "$who: ${items.joinToString("، و")}${if (d.cancelled) "، ملغى" else ""}"
        }.toMutableList()
        g.balootSeat?.let { lines += "${if (it == mySeat) "أنت" else name(it)}: بلوت" }
        if (lines.isEmpty()) return "لا توجد مشاريع معلنة"
        val w = g.projectsWinningTeam
        if (w != null && g.declared.isNotEmpty()) {
            lines += "المشاريع المحتسبة لـ${if (mySeat == null) "فريق ${name(w)}" else if (w == teamOf(me)) "فريقك" else "الخصم"}"
        }
        return lines.joinToString(". ")
    }

    /** دور مين الآن، وفي أي مرحلة */
    fun turn(): String {
        if (g.phase == "matchOver") return "انتهت المباراة"
        val who = if (g.turn == mySeat) "دورك" else "دور ${name(g.turn)}"
        return when (g.phase) {
            "bidding" -> "$who في المزايدة"
            "doubling" -> if (g.myTurn) "دورك تقرر الدبل" else "بانتظار قرار الدبل"
            else -> "$who في اللعب"
        }
    }

    fun statusLine(): String? {
        val c = g.contract ?: return null
        val mode = if (c.mode == "sun") "صن" else "حكم ${SUIT_NAMES[c.trump]} ${SUIT_SYMBOLS[c.trump]}"
        val level = if (g.doubling.gahwa) "قهوة" else mapOf(2 to "دبل", 3 to "ثري", 4 to "فور")[g.doubling.level]
        val lock = if (c.mode == "hokm" && g.doubling.level > 1 && !g.doubling.gahwa) (if (g.doubling.locked) " (مقفل)" else " (مفتوح)") else ""
        return "$mode — ${name(c.buyer)}${level?.let { " — $it" }.orEmpty()}$lock"
    }
}
