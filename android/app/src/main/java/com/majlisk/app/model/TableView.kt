package com.majlisk.app.model

import org.json.JSONArray
import org.json.JSONObject

/** حالة الطاولة كما يرسلها الخادم لكل شخص (shared/table.ts → viewFor) */
data class SeatInfo(val username: String, val isBot: Boolean, val away: Boolean)
data class Person(val uid: String, val username: String)
data class VoiceMember(val uid: String, val username: String, val sessionId: String, val muted: Boolean, val mic: Boolean, val blocked: Boolean)

/** قائمة المحادثة الصوتية (من الحالة كاملة، أو من رسالة «voice» الخفيفة) */
fun parseVoice(a: org.json.JSONArray?): List<VoiceMember> = a.objects().map {
    VoiceMember(it.optString("uid"), it.optString("username"), it.optString("sessionId"), it.optBoolean("muted"), it.optBoolean("mic"), it.optBoolean("blocked"))
}
data class PlayedCard(val seat: Int, val card: Card)
data class Contract(val mode: String, val trump: String?, val buyer: Int, val qabaTo: Int)
data class Doubling(
    val level: Int, val gahwa: Boolean, val locked: Boolean,
    /** مين يقرر الدبل الحين: لاعب واحد، أو فريق (إلا اللي قال بس)، وما فيه أحد وقت اختيار مقفل/مفتوح */
    val awaitingSeat: Int? = null, val awaitingTeam: Int? = null, val passed: List<Int> = emptyList(), val lockPending: Int? = null,
    /** أول من دبّل (الثري والقهوة من المشتري، والفور من المدبّل) */
    val doubler: Int? = null,
) {
    val deciders: List<Int> get() = when {
        lockPending != null -> emptyList()
        awaitingSeat != null -> listOf(awaitingSeat)
        awaitingTeam != null -> listOf(awaitingTeam, awaitingTeam + 2).filter { it !in passed }
        else -> emptyList()
    }
    /** اسم الخيار: دبل، ثري، فور، قهوة */
    val label: String get() = listOf("دبل", "دبل", "ثري", "فور", "قهوة")[level.coerceIn(1, 4)]
}
data class Declared(val seat: Int, val kinds: List<String>, val cards: List<String>?, val cancelled: Boolean, val faces: List<Card> = emptyList())
data class LastHand(val points: List<Int>, val kaboot: Int?)

data class GameActions(
    val bids: List<Bid>,
    val doubleLabel: String?,
    val canPassDouble: Boolean,
    val chooseLock: Boolean,
    val legal: List<Card>,
    /** سوا: دورك تبدأ الأكلة وكل أوراقك مضمونة تاكل */
    val canSawa: Boolean = false,
    /** «ورق»: الزر يطلع، وwaraqDecision = دورك تختار بس أو ورق (بعد الشراء) */
    val canWaraq: Boolean = false,
    val waraqDecision: Boolean = false,
    /** إعلان المشروع (يدوي): دورك في اللفة الأولى ومعك مشروع ما أعلنته */
    val canProject: Boolean = false,
    /** القيد والقطع: أنواع المشروع اللي تقدر تعلنها، وفرش أوراق مشروعك، واللي تقدر تسجّل عليهم */
    val declareKinds: List<String> = emptyList(),
    val canShowProject: Boolean = false,
    val qaidTargets: List<Int> = emptyList(),
)

data class GameView(
    val phase: String,
    val scores: List<Int>,
    val turn: Int,
    /** الموزّع: البداية (أول من يلعب) عند اللاعب اللي بعده */
    val dealer: Int,
    val qaba: Card?,
    val bidRound: Int,
    val contract: Contract?,
    val doubling: Doubling,
    val trick: List<PlayedCard>,
    val lastTrick: List<PlayedCard>?,
    val trickNo: Int,
    /** كم أكلة لكل فريق في الصكة الحالية */
    val tricksWon: List<Int> = listOf(0, 0),
    val lastHand: LastHand?,
    val outcomeStatus: String,
    val outcomeWinner: Int?,
    val handCounts: List<Int>,
    val myHand: List<Card>,
    val balootSeat: Int?,
    val projectsWinningTeam: Int?,
    val declared: List<Declared>,
    val actions: GameActions,
    val hokmBidKey: String?,
    /** من اشترى الحكم الثاني (قبل وبعد ما يحدد اللون) */
    val secondHokmSeat: Int? = null,
    /** مهلة ما بعد التوزيع: الدور ما بدأ بعد (ما ينعلن «دور فلان» لين تخلص) */
    val dealing: Boolean = false,
    /** شراء ما تأكد بعد: المقعد ونوعه (hokm/sun/ashkal/secondHokm) */
    val pendingBuy: Pair<Int, String>? = null,
    /** «سوا»: أوراق الكل الباقية مكشوفة (كل لاعب قدامه أوراقه) لين تنحسب الصكة */
    val sawaHands: List<List<Card>>? = null,
) {
    val myTurn: Boolean
        get() = actions.bids.isNotEmpty() || actions.doubleLabel != null || actions.canPassDouble || actions.chooseLock || actions.legal.isNotEmpty() || actions.waraqDecision
}

data class HandRecord(
    val match: Int,
    val projects: List<Int>?,
    val teams: List<String>,
    val contract: String,
    val level: Int,
    val gahwa: Boolean,
    val buyer: String,
    val buyerTeam: Int,
    val abnat: List<Int>,
    val points: List<Int>,
    val buyerFailed: Boolean,
    val kaboot: Int?,
)

data class TableView(
    val id: String,
    val ownerUid: String,
    val isPrivate: Boolean,
    val mySeat: Int?,
    val seats: List<SeatInfo?>,
    val seatUids: List<String>,
    val spectators: List<Person>,
    val voice: List<VoiceMember>,
    val voiceBlocked: List<String>,
    val game: GameView?,
    val kind: String,
    val variant: String,
    /** لعبة غير البلوت بدأت (الدومينو أو الجاكارو أو اللودو) */
    val otherGame: Boolean,
    val history: List<HandRecord>,
    val domino: DominoView? = null,
    val jackaroo: JackarooView? = null,
    val ludo: LudoView? = null,
    /** كم لاعب يقدر يبدأ اللعبة */
    val startCounts: List<Int> = listOf(4),
    /** مؤقت الدور: الثواني المختارة (٠ = بدون)، واللي عليه الوقت، ومتى يخلص وقته (بساعة الجوال) */
    val clockLimit: Int = 0,
    val clockSeat: Int? = null,
    val clockDeadline: Long? = null,
    /** خيارات اللعبة من صفحة المقاعد: فرق، كمبلكس، هدف الدومينو */
    val optTeams: Boolean = true,
    val optComplex: Boolean = false,
    val optTarget: Int = 100,
    /** اسم مالك الطاولة */
    val ownerName: String = "",
    /** خيارات مباراة البلوت (الباقة الاحترافية): إعلان المشاريع يدوي، والقيد والقطع */
    val manualProjects: Boolean = false,
    val qaid: Boolean = false,
    /** زر سوا مسموح في هالمباراة */
    val sawaOn: Boolean = true,
    /** كل اللاعبين مشتركين: المالك يقدر يغير المؤقت أثناء اللعب */
    val allPro: Boolean = false,
) {
    val hasGame: Boolean get() = game != null || otherGame
    val playing: Boolean get() = (game != null && game.phase != "matchOver") ||
        (domino != null && domino.phase != "matchOver") || jackaroo?.phase == "playing" || (ludo != null && ludo.phase != "over")

    companion object {
        fun parse(o: JSONObject): TableView = TableView(
            id = o.optString("id"),
            ownerUid = o.optString("ownerUid"),
            isPrivate = o.optBoolean("isPrivate"),
            mySeat = o.optIntOrNull("mySeat"),
            seats = o.optJSONArray("seats").mapIndexed { a, i ->
                a.optJSONObject(i)?.let { SeatInfo(it.optString("username"), it.optBoolean("isBot"), it.optBoolean("away")) }
            },
            seatUids = o.optJSONArray("seatUids").mapIndexed { a, i -> a.optString(i, "") },
            spectators = o.optJSONArray("spectators").objects().map { Person(it.optString("uid"), it.optString("username")) },
            voice = parseVoice(o.optJSONArray("voice")),
            voiceBlocked = o.optJSONArray("voiceBlocked").mapIndexed { a, i -> a.optString(i) },
            game = o.optJSONObject("game")?.let(::parseGame),
            kind = o.optString("kind", "baloot"),
            variant = o.optString("variant", "classic"),
            otherGame = listOf("domino", "jackaroo", "ludo").any { o.optJSONObject(it) != null },
            history = o.optJSONArray("history").objects().map(::parseRecord),
            domino = o.optJSONObject("domino")?.let { DominoView.parse(it, o.optJSONObject("ui") ?: JSONObject(), o.optJSONArray("dominoLog")) },
            jackaroo = o.optJSONObject("jackaroo")?.let { JackarooView.parse(it, o.optJSONObject("ui") ?: JSONObject(), o.optIntOrNull("mySeat")) },
            startCounts = o.optJSONArray("startCounts")?.ints()?.takeIf { it.isNotEmpty() } ?: listOf(4),
            clockLimit = o.optJSONObject("clock")?.optInt("limit", 0) ?: 0,
            clockSeat = o.optJSONObject("clock")?.optIntOrNull("seat"),
            // الباقي من لحظة وصول الحالة (ما نعتمد على ساعة الخادم)
            clockDeadline = o.optJSONObject("clock")?.takeIf { !it.isNull("remainingMs") && it.has("remainingMs") }?.let { System.currentTimeMillis() + it.optLong("remainingMs") },
            optTeams = o.optJSONObject("options")?.optBoolean("teams", true) ?: true,
            optComplex = o.optJSONObject("options")?.optBoolean("complex") == true,
            optTarget = o.optJSONObject("options")?.optInt("target", 100) ?: 100,
            ownerName = o.optString("ownerName"),
            manualProjects = o.optBoolean("manualProjects"),
            qaid = o.optBoolean("qaid"),
            sawaOn = o.optBoolean("sawaOn", true),
            allPro = o.optBoolean("allPro"),
            ludo = o.optJSONObject("ludo")?.let { LudoView.parse(it, o.optJSONObject("ui") ?: JSONObject(), o.optJSONArray("ludoLog")) },
        )

        private fun parseGame(g: JSONObject): GameView {
            val a = g.optJSONObject("actions") ?: JSONObject()
            val outcome = g.optJSONObject("outcome") ?: JSONObject()
            val d = g.optJSONObject("doubling") ?: JSONObject()
            val hokmBid = g.optJSONObject("hokmBid")
            return GameView(
                phase = g.optString("phase"),
                scores = g.optJSONArray("scores").ints(),
                turn = g.optInt("turn"),
                dealer = g.optInt("dealer"),
                qaba = Card.from(g.optJSONObject("qaba")),
                bidRound = g.optInt("bidRound", 1),
                contract = g.optJSONObject("contract")?.let {
                    Contract(it.optString("mode"), it.optStringOrNull("trump"), it.optInt("buyer"), it.optInt("qabaTo"))
                },
                doubling = Doubling(d.optInt("level", 1), d.optBoolean("gahwa"), d.optBoolean("locked"), d.optIntOrNull("awaitingSeat"), d.optIntOrNull("awaitingTeam"), d.optJSONArray("passed").ints(), d.optIntOrNull("lockPending"), d.optIntOrNull("doubler")),
                trick = played(g.optJSONArray("trick")),
                lastTrick = g.optJSONObject("lastTrick")?.let { played(it.optJSONArray("cards")) },
                trickNo = g.optInt("trickNo"),
                tricksWon = g.optJSONArray("tricksWon")?.let { a -> List(a.length()) { a.optInt(it) } } ?: listOf(0, 0),
                lastHand = g.optJSONObject("lastHand")?.let { LastHand(it.optJSONArray("points").ints(), it.optIntOrNull("kaboot")) },
                outcomeStatus = outcome.optString("status", "ongoing"),
                outcomeWinner = outcome.optIntOrNull("winner"),
                handCounts = g.optJSONArray("handCounts").ints(),
                myHand = g.optJSONArray("myHand").objects().mapNotNull { Card.from(it) },
                balootSeat = g.optIntOrNull("balootSeat"),
                projectsWinningTeam = g.optJSONObject("projects")?.optIntOrNull("winningTeam"),
                declared = g.optJSONArray("declared").objects().map {
                    Declared(
                        it.optInt("seat"),
                        it.optJSONArray("kinds").mapIndexed { x, i -> x.optString(i) },
                        it.optJSONArray("cards")?.let { c -> c.mapIndexed { x, i -> x.optString(i) } },
                        it.optBoolean("cancelled"),
                        it.optJSONArray("faces").objects().mapNotNull { c -> Card.from(c) },
                    )
                },
                actions = GameActions(
                    bids = a.optJSONArray("bids").objects().map { Bid(it.optString("type"), it.optStringOrNull("suit"), it) },
                    doubleLabel = a.optJSONObject("double")?.optString("label"),
                    canPassDouble = a.optBoolean("canPassDouble"),
                    chooseLock = a.optBoolean("chooseLock"),
                    legal = a.optJSONArray("legal").objects().mapNotNull { Card.from(it) },
                    canSawa = a.optBoolean("canSawa"),
                    canWaraq = a.optBoolean("canWaraq"),
                    waraqDecision = a.optBoolean("waraqDecision"),
                    canProject = a.optBoolean("canProject"),
                    declareKinds = a.optJSONArray("declareKinds")?.let { arr -> (0 until arr.length()).map { arr.optString(it) } } ?: emptyList(),
                    canShowProject = a.optBoolean("canShowProject"),
                    qaidTargets = a.optJSONArray("qaidTargets")?.let { arr -> (0 until arr.length()).map { arr.optInt(it) } } ?: emptyList(),
                ),
                hokmBidKey = hokmBid?.let { "${it.optInt("seat")}${it.optString("suit")}" },
                secondHokmSeat = g.optIntOrNull("secondHokmSeat"),
                dealing = g.optBoolean("dealing"),
                pendingBuy = g.optJSONObject("pendingBuy")?.let { it.optInt("seat") to it.optString("kind") },
                sawaHands = g.optJSONObject("sawaReveal")?.optJSONArray("hands")?.let { hs ->
                    (0 until hs.length()).map { i -> hs.optJSONArray(i).objects().mapNotNull { Card.from(it) } }
                },
            )
        }

        private fun played(arr: JSONArray?) = arr.objects().mapNotNull { p -> Card.from(p.optJSONObject("card"))?.let { PlayedCard(p.optInt("seat"), it) } }

        private fun parseRecord(r: JSONObject) = HandRecord(
            match = r.optInt("match", 1),
            projects = r.optJSONArray("projects")?.ints(),
            teams = r.optJSONArray("teams").mapIndexed { a, i -> a.optString(i) },
            contract = r.optString("contract"),
            level = r.optInt("level", 1),
            gahwa = r.optBoolean("gahwa"),
            buyer = r.optString("buyer"),
            buyerTeam = r.optInt("buyerTeam"),
            abnat = r.optJSONArray("abnat").ints(),
            points = r.optJSONArray("points").ints(),
            buyerFailed = r.optBoolean("buyerFailed"),
            kaboot = r.optIntOrNull("kaboot"),
        )
    }
}

// ───── مساعدات JSON ─────
fun JSONObject.optIntOrNull(key: String): Int? = if (has(key) && !isNull(key)) optInt(key) else null
fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) optString(key) else null
fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }
fun JSONArray?.ints(): List<Int> = if (this == null) emptyList() else (0 until length()).map { optInt(it) }
fun <T> JSONArray?.mapIndexed(f: (JSONArray, Int) -> T): List<T> = if (this == null) emptyList() else (0 until length()).map { f(this, it) }
