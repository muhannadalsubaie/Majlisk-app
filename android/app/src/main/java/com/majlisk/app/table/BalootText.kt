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
    /** الأكلة اللي على الشاشة (بعد آخر ورقة تبقى الأكلة المنتهية ظاهرة لحظة) */
    private val shownTrickNo = if (g.trick.isEmpty() && shownTrick.isNotEmpty()) g.trickNo - 1 else g.trickNo
    /** المشاريع تنكشف وتنقرأ في اللفة الثانية فقط */
    val revealing = g.phase == "playing" && shownTrickNo == 1
    fun name(s: Int) = view.seats.getOrNull(s)?.username ?: "مقعد ${s + 1}"
    private fun teamWord(s: Int) = if (mySeat == null) "فريق ${name(s)}" else if (teamOf(s) == teamOf(me)) "فريقك" else "الخصم"

    /** الأوراق الموجودة على الطاولة الآن ومن لعب كل ورقة، بالترتيب */
    fun trick(): String = when {
        // القراءة دائماً للأكلة الحالية (لا الأكلة السابقة الظاهرة لحظة على الشاشة)
        g.trick.isNotEmpty() -> g.trick.joinToString("، ") { "${name(it.seat)}: ${it.card.label}" }
        (g.phase == "bidding" || g.phase == "doubling" || g.phase == "waraq") && g.qaba != null -> "ورقة الأرض: ${g.qaba.label}"
        else -> "لا توجد أوراق على الطاولة"
    }

    /** نوع اللعب يبقى مكتوب ومقروء طول الجولة (حتى بعد توزيع كل الأوراق) */
    val contractHidden: Boolean get() = false

    /** نوع اللعب: من اشترى، وعلى ماذا، والدبل */
    fun contract(): String {
        val c = g.contract ?: run {
            val ground = g.qaba?.let { "، ورقة الأرض ${it.label}" }.orEmpty()
            // اشترى أحد وما تأكد بعد (حكم ينتظر التأكيد، صن/أشكل ممكن ياخذه اللي قبله، حكم ثاني)
            g.pendingBuy?.let { (seat, k) ->
                val kind = when (k) { "sun" -> "صن"; "ashkal" -> "أشكل"; "secondHokm" -> "حكم ثاني"; else -> "حكم" }
                val who = if (seat == mySeat) "أنت اشتريت $kind" else "${name(seat)} اشترى $kind، ${teamWord(seat)}"
                return "$who$ground، ${start()}"
            }
            return "لم يشترِ أحد بعد، اللفة ${if (g.bidRound == 1) "الأولى" else "الثانية"}$ground، ${start()}"
        }
        val mode = if (c.mode == "sun") "صن" else "حكم ${SUIT_NAMES[c.trump]}"
        val parts = mutableListOf(if (c.buyer == mySeat) "أنت اشتريت $mode" else "${name(c.buyer)} اشترى $mode، ${teamWord(c.buyer)}")
        if (c.qabaTo != c.buyer) parts += "ورقة الأرض لـ${if (c.qabaTo == mySeat) "ك" else name(c.qabaTo)}"
        parts += start()
        val d = g.doubling
        when {
            d.gahwa -> parts += "قهوة${by()}"
            d.level > 1 -> {
                val label = mapOf(2 to "دبل", 3 to "ثري", 4 to "فور")[d.level]
                parts += "$label${by()}${if (c.mode == "hokm") (if (d.locked) " مقفل" else " مفتوح") else ""}"
            }
            else -> parts += "بدون دبل"
        }
        return parts.joinToString("، ")
    }

    /** البداية (أول من يلعب) عند اللاعب اللي بعد الموزّع */
    private fun start(): String {
        val first = (g.dealer + 1) % 4
        return if (first == mySeat) "البداية عندك" else "البداية عند ${name(first)}"
    }

    /**
     * المشاريع: في اللفة الأولى مين عنده مشروع ونوعه (سرا، خمسين، مية) بلا تفاصيل، وفي اللفة الثانية
     * نوعه وأوراقه بعد ما ينكشف، وبعد اللفة الثانية تنمسح
     */
    fun projects(): String {
        val active = g.phase == "playing" && shownTrickNo <= 1
        val lines = (if (active) g.declared else emptyList()).map { d ->
            val who = if (d.seat == mySeat) "أنت" else name(d.seat)
            val cards = d.cards
            if (cards != null) "$who: " + d.kinds.mapIndexed { i, k -> cards.getOrNull(i)?.let { "$k: $it" } ?: k }.joinToString("، و")
            else if (d.cancelled) "$who: أُلغي المشروع"
            else "$who: ${d.kinds.joinToString(" و")}"
        }.toMutableList()
        g.balootSeat?.let { lines += "${if (it == mySeat) "أنت" else name(it)}: بلوت" }
        val projects = if (lines.isEmpty()) "لا توجد مشاريع معلنة" else lines.joinToString(". ")
        return if (g.phase == "playing") "$projects. ${tricks()}" else projects
    }

    /** عدد الأكلات لكل فريق في الصكة الحالية (لنا ولهم، وللمشاهد بأسماء الفريقين) */
    fun tricks(): String {
        val a = g.tricksWon.getOrElse(0) { 0 }; val b = g.tricksWon.getOrElse(1) { 0 }
        if (mySeat == null) return "الأكلات: فريق ${name(0)} و${name(2)} $a، فريق ${name(1)} و${name(3)} $b"
        val mine = if (teamOf(me) == 0) a else b; val theirs = if (teamOf(me) == 0) b else a
        return "الأكلات: لنا $mine، لهم $theirs"
    }

    /** أوراق مشروع هذا المقعد المكشوفة (في اللفة الثانية فقط) */
    fun faces(seat: Int): List<com.majlisk.app.model.Card> = if (!revealing) emptyList() else g.declared.filter { it.seat == seat }.flatMap { it.faces }

    /** دور مين الآن، وفي أي مرحلة */
    fun turn(): String {
        if (g.phase == "matchOver") return "انتهت المباراة"
        val who = if (g.turn == mySeat) "دورك" else "دور ${name(g.turn)}"
        return when (g.phase) {
            "bidding" -> who
            "doubling" -> if (g.myTurn) "دورك تقرر الدبل" else "بانتظار قرار الدبل"
            "waraq" -> if (g.myTurn) "دورك: بس أو ورق" else "بانتظار ${name(g.turn)}: بس أو ورق"
            else -> "$who في اللعب"
        }
    }

    /** مين قال آخر دبل: الدبل والفور من المدبّل، والثري والقهوة من المشتري */
    private fun lastDoubler(): Int? {
        val c = g.contract ?: return null
        val d = g.doubling
        if (d.level <= 1) return null
        return if (!d.gahwa && d.level % 2 == 0) d.doubler else c.buyer
    }
    private fun by(): String = lastDoubler()?.let { if (it == mySeat) " منك" else " من ${name(it)}" }.orEmpty()

    fun statusLine(): String? {
        val c = g.contract ?: return null
        val mode = if (c.mode == "sun") "صن" else "حكم ${SUIT_NAMES[c.trump]} ${SUIT_SYMBOLS[c.trump]}"
        val level = if (g.doubling.gahwa) "قهوة" else mapOf(2 to "دبل", 3 to "ثري", 4 to "فور")[g.doubling.level]
        val lock = if (c.mode == "hokm" && g.doubling.level > 1 && !g.doubling.gahwa) (if (g.doubling.locked) " (مقفل)" else " (مفتوح)") else ""
        // المشتري ونوع اللعب جنبه، طول الجولة
        val kind = if (c.mode == "sun" && c.qabaTo != c.buyer) "أشكل" else mode
        return "المشتري ${name(c.buyer)} — $kind${level?.let { " — $it${by()}" }.orEmpty()}$lock"
    }
}
