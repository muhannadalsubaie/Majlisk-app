package com.majlisk.app.table

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Friend
import com.majlisk.app.data.Social
import com.majlisk.app.data.TableConnection
import com.majlisk.app.model.TableView
import com.majlisk.app.ui.Body
import com.majlisk.app.ui.DangerButton
import com.majlisk.app.ui.ItemRow
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import com.majlisk.app.ui.SectionTitle
import com.majlisk.app.ui.SmallButton
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private sealed interface SeatPanel {
    data class Invite(val seat: Int) : SeatPanel
    data class Add(val seat: Int) : SeatPanel
    data class Change(val seat: Int) : SeatPanel
}

/** اسم الجالس في مقعد مع وسومه (أنت، روبوت) */
fun occupantLabel(v: TableView, i: Int): String {
    val s = v.seats.getOrNull(i) ?: return "فارغ"
    val tags = listOfNotNull(if (i == v.mySeat) "أنت" else null, if (s.isBot) "روبوت" else null)
    return s.username + if (tags.isNotEmpty()) " (${tags.joinToString("، ")})" else ""
}

/**
 * المقاعد قبل بدء المباراة، مقسّمة بالفريقين.
 * مالك الطاولة: يدعو صديقاً لمقعد فارغ، أو "إضافة لاعب" (أحد الموجودين أو روبوت)،
 * ويغيّر من يجلس في كل مقعد، ويُخلي أي مقعد.
 */
@Composable
fun SeatsLobby(v: TableView, uid: String, conn: TableConnection) {
    val isOwner = v.ownerUid == uid
    var panel by remember { mutableStateOf<SeatPanel?>(null) }

    SectionTitle("المقاعد")
    listOf("الفريق الأول" to listOf(0, 2), "الفريق الثاني" to listOf(1, 3)).forEach { (title, seats) ->
        Text(title, color = Palette.goldSoft)
        seats.forEach { i ->
            ItemRow {
                Text("المقعد ${i + 1}: ${occupantLabel(v, i)}", color = Palette.text, modifier = Modifier.weight(1f))
                if (isOwner) {
                    if (v.seats.getOrNull(i) == null) {
                        SmallButton("دعوة صديق", { panel = SeatPanel.Invite(i) }, description = "دعوة صديق للمقعد ${i + 1}")
                        SmallButton("إضافة لاعب", { panel = SeatPanel.Add(i) }, description = "إضافة لاعب في المقعد ${i + 1}")
                    } else {
                        SmallButton("تغيير", { panel = SeatPanel.Change(i) }, description = "تغيير المقعد ${i + 1}")
                    }
                }
            }
        }
    }
    if (v.spectators.isNotEmpty()) {
        Note("المشاهدون: " + v.spectators.joinToString("، ") { if (it.uid == uid) "${it.username} (أنت)" else it.username })
    }
    if (isOwner) PrimaryButton("بدء المباراة", { conn.send("start") }, enabled = v.seats.size == 4 && v.seats.all { it != null })
    else Body("بانتظار مالك الطاولة لبدء المباراة")

    // كل الموجودين الذين يمكن وضعهم في مقعد: الجالسون في مقاعد أخرى والمشاهدون
    fun candidates(seat: Int): List<Pair<String, String>> =
        (0..3).filter { it != seat && v.seats.getOrNull(it) != null }.map { v.seatUids.getOrElse(it) { "" } to "${occupantLabel(v, it)} — من المقعد ${it + 1}" } +
            v.spectators.map { it.uid to "${it.username}${if (it.uid == uid) " (أنت)" else ""} — مشاهد" }

    when (val p = panel) {
        is SeatPanel.Invite -> InviteFriendsDialog(v.id, seat = p.seat, title = "دعوة صديق للمقعد ${p.seat + 1}") { panel = null }
        is SeatPanel.Add -> MajliskDialog("إضافة لاعب في المقعد ${p.seat + 1}", { panel = null }) {
            val list = candidates(p.seat).filter { it.first.isNotEmpty() }
            list.forEach { (u, label) -> SecondaryButton(label, { conn.send("replace", "seat" to p.seat, "uid" to u); panel = null }, fill = true) }
            if (list.isEmpty()) Body("لا يوجد أحد آخر في الطاولة.")
            PrimaryButton("إضافة روبوت (1 🪙)", { conn.send("addBot", "seat" to p.seat); panel = null }, description = "إضافة روبوت، عملة واحدة")
            SecondaryButton("رجوع", { panel = null }, fill = true)
        }
        is SeatPanel.Change -> MajliskDialog("المقعد ${p.seat + 1}: ${occupantLabel(v, p.seat)}", { panel = null }) {
            val list = candidates(p.seat).filter { it.first.isNotEmpty() }
            list.forEach { (u, label) -> SecondaryButton(label, { conn.send("replace", "seat" to p.seat, "uid" to u); panel = null }, fill = true) }
            if (list.isEmpty()) Body("لا يوجد أحد آخر في الطاولة.")
            val seatInfo = v.seats.getOrNull(p.seat)
            DangerButton(
                when { seatInfo?.isBot == true -> "إزالة الروبوت"; p.seat == v.mySeat -> "أخلِ مقعدي وأصبح مشاهداً"; else -> "إخلاء المقعد (يصبح مشاهداً)" },
                { conn.send("vacate", "seat" to p.seat); panel = null },
            )
            SecondaryButton("رجوع", { panel = null }, fill = true)
        }
        null -> Unit
    }
}

/** قائمة الأصدقاء مع حالة الاتصال (تُحدَّث كل 10 ثوانٍ) وزر دعوة للمتصلين */
@Composable
fun InviteFriendsDialog(tableId: String, seat: Int?, title: String, onClose: () -> Unit) {
    var friends by remember { mutableStateOf<List<Friend>?>(null) }
    var busy by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        while (true) {
            friends = runCatching { Social.listFriends().friends }.getOrDefault(friends ?: emptyList())
            delay(10_000)
        }
    }
    MajliskDialog(title, onClose) {
        if (friends == null) Body("جارٍ التحميل…")
        else if (friends!!.isEmpty()) Body("لا يوجد أصدقاء بعد. أضفهم من شاشة الأصدقاء، أو أضف روبوتاً.")
        friends?.sortedByDescending { it.online }?.forEach { f ->
            ItemRow {
                Text("${f.username}، ${if (f.online) "متصل" else "غير متصل"}", color = Palette.text, modifier = Modifier.weight(1f))
                if (f.online) SmallButton("دعوة", {
                    busy = f.uid
                    scope.launch {
                        runCatching { Social.inviteFriend(tableId, f.uid, seat) }
                            .onSuccess {
                                Announcer.announce(if (seat != null) "أُرسلت الدعوة إلى ${f.username} للمقعد ${seat + 1}" else "أُرسلت الدعوة إلى ${f.username}")
                                if (seat != null) onClose()
                            }
                            .onFailure { Announcer.announce(Social.error(it)) }
                        busy = ""
                    }
                }, enabled = busy != f.uid, description = "دعوة ${f.username}")
            }
        }
        SecondaryButton("رجوع", onClose, fill = true)
    }
}
