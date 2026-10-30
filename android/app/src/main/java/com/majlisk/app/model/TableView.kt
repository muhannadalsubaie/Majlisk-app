package com.majlisk.app.model

import org.json.JSONArray
import org.json.JSONObject

/** حالة الطاولة كما يرسلها الخادم لكل شخص (shared/table.ts → viewFor) */
data class SeatInfo(val username: String, val isBot: Boolean, val away: Boolean)
data class Person(val uid: String, val username: String)
data class VoiceMember(val uid: String, val username: String, val sessionId: String, val muted: Boolean, val mic: Boolean, val blocked: Boolean)
data class PlayedCard(val seat: Int, val card: Card)
data class Contract(val mode: String, val trump: String?, val buyer: Int, val qabaTo: Int)
data class Doubling(val level: Int, val gahwa: Boolean, val locked: Boolean)
data class Declared(val seat: Int, val kinds: List<String>, val cards: List<String>?, val cancelled: Boolean)
data class LastHand(val points: List<Int>, val kaboot: Int?)

data class GameActions(
    val bids: List<Bid>,
    val doubleLabel: String?,
    val canPassDouble: Boolean,
    val chooseLock: Boolean,
    val legal: List<Card>,
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
) {
    val myTurn: Boolean
        get() = actions.bids.isNotEmpty() || actions.doubleLabel != null || actions.canPassDouble || actions.chooseLock || actions.legal.isNotEmpty()
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
    /** لعبة غير البلوت بدأت (الدومينو والجاكارو واللودو تأتي في المرحلة الثانية) */
    val otherGame: Boolean,
    val history: List<HandRecord>,
) {
    val hasGame: Boolean get() = game != null || otherGame
    val playing: Boolean get() = (game != null && game.phase != "matchOver") || otherGame

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
            voice = o.optJSONArray("voice").objects().map {
                VoiceMember(it.optString("uid"), it.optString("username"), it.optString("sessionId"), it.optBoolean("muted"), it.optBoolean("mic"), it.optBoolean("blocked"))
            },
            voiceBlocked = o.optJSONArray("voiceBlocked").mapIndexed { a, i -> a.optString(i) },
            game = o.optJSONObject("game")?.let(::parseGame),
            kind = o.optString("kind", "baloot"),
            variant = o.optString("variant", "classic"),
            otherGame = listOf("domino", "jackaroo", "ludo").any { o.optJSONObject(it) != null },
            history = o.optJSONArray("history").objects().map(::parseRecord),
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
                doubling = Doubling(d.optInt("level", 1), d.optBoolean("gahwa"), d.optBoolean("locked")),
                trick = played(g.optJSONArray("trick")),
                lastTrick = g.optJSONObject("lastTrick")?.let { played(it.optJSONArray("cards")) },
                trickNo = g.optInt("trickNo"),
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
                    )
                },
                actions = GameActions(
                    bids = a.optJSONArray("bids").objects().map { Bid(it.optString("type"), it.optStringOrNull("suit"), it) },
                    doubleLabel = a.optJSONObject("double")?.optString("label"),
                    canPassDouble = a.optBoolean("canPassDouble"),
                    chooseLock = a.optBoolean("chooseLock"),
                    legal = a.optJSONArray("legal").objects().mapNotNull { Card.from(it) },
                ),
                hokmBidKey = hokmBid?.let { "${it.optInt("seat")}${it.optString("suit")}" },
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
