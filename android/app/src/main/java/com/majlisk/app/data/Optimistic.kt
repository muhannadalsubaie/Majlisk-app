package com.majlisk.app.data

import com.majlisk.app.model.Card
import com.majlisk.app.model.JackarooCard
import com.majlisk.app.model.PlayedCard
import com.majlisk.app.model.TableView
import com.majlisk.app.model.Tile
import org.json.JSONObject

/**
 * اللعب الفوري: لما تلعب ورقة أو قطعة تطلع من يدك على طول (والبلوت تنحط في الأرض) مع صوتها،
 * بدون انتظار رد الخادم. الخادم يتأكد بعدها: لو قبلها توصل حالته وتكمّل، ولو رفضها ترجع الورقة ليدك.
 *
 * يرجع دالة تطبّق الحركة على أي حالة (null لو الحركة ما تنطبق عليها: انلعبت فعلاً أو ما عادت مسموحة).
 * null من البداية لو هالحركة ما لها لعب فوري (المزايدة، النرد، ...).
 */
object Optimistic {
    fun patch(view: TableView, msg: JSONObject): ((TableView) -> TableView?)? {
        val seat = view.mySeat ?: return null
        val action = msg.optJSONObject("action") ?: return null
        if (action.optString("type") != "play") return null
        return when (msg.optString("type")) {
            "action" -> {
                val c = action.optJSONObject("card") ?: return null
                val card = Card(c.optString("suit"), c.optString("rank"))
                val f = { v: TableView ->
                    val g = v.game
                    if (g == null || g.phase != "playing" || card !in g.myHand || card !in g.actions.legal || g.trick.size >= 4) null
                    else v.copy(game = g.copy(
                        myHand = g.myHand - card,
                        trick = g.trick + PlayedCard(seat, card),
                        handCounts = g.handCounts.mapIndexed { i, n -> if (i == seat) (n - 1).coerceAtLeast(0) else n },
                        actions = g.actions.copy(legal = emptyList(), canSawa = false),
                    ))
                }
                // صوتها يطلع من مقارنة الحالات (GameSoundTracker): الحالة الفورية فيها الورقة في الأرض
                f.takeIf { it(view) != null }
            }
            "domino" -> {
                val t = action.optJSONObject("tile") ?: return null
                val tile = Tile(t.optInt("a"), t.optInt("b"))
                val f = { v: TableView ->
                    val d = v.domino
                    if (d == null || !d.myTurn || d.hand.none { it.tile == tile && it.legal }) null
                    else v.copy(domino = d.copy(
                        hand = d.hand.filterNot { it.tile == tile },
                        handCounts = d.handCounts.mapIndexed { i, n -> if (i == seat) (n - 1).coerceAtLeast(0) else n },
                        myTurn = false, canDraw = false, canPass = false, prompt = "",
                    ))
                }
                f.takeIf { it(view) != null }?.also { Sounds.dominoTile(); Sounds.markLocal("domino") }
            }
            "jackaroo" -> {
                val c = action.optJSONObject("card") ?: return null
                val card = JackarooCard(c.optString("rank"), c.optString("suit"))
                val f = { v: TableView ->
                    val j = v.jackaroo
                    val i = j?.hand?.indexOfFirst { it.card == card && it.usable } ?: -1
                    if (j == null || !j.myTurn || i < 0) null
                    else v.copy(jackaroo = j.copy(
                        hand = j.hand.filterIndexed { k, _ -> k != i },
                        handCounts = j.handCounts.mapIndexed { k, n -> if (k == seat) (n - 1).coerceAtLeast(0) else n },
                        myTurn = false, prompt = "",
                    ))
                }
                f.takeIf { it(view) != null }?.also { Sounds.jackarooCard(); Sounds.markLocal("jackaroo") }
            }
            else -> null
        }
    }
}
