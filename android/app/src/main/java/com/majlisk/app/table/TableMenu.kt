package com.majlisk.app.table

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Ads
import com.majlisk.app.data.Social
import com.majlisk.app.data.TableConnection
import com.majlisk.app.model.TableView
import com.majlisk.app.model.teamOf
import com.majlisk.app.ui.Body
import com.majlisk.app.ui.DangerButton
import com.majlisk.app.ui.ItemRow
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import com.majlisk.app.ui.SettingsScreen
import com.majlisk.app.ui.SwitchRow
import com.majlisk.app.voice.Voice
import kotlinx.coroutines.launch

private sealed interface Page {
    data object Main : Page
    data object Players : Page
    data object Invite : Page
    data object Settings : Page
    data object Stop : Page
    data class Replace(val seat: Int) : Page
    data class Member(val uid: String) : Page
    data class Confirm(val ban: Boolean, val uid: String) : Page
}

/** قائمة الطاولة: اللاعبون، دعوة صديق، مشاهدة إعلان، المحادثة الصوتية، الإعدادات، مغادرة */
@Composable
fun TableMenu(v: TableView, uid: String, conn: TableConnection, onLeave: () -> Unit, onClose: () -> Unit) {
    var page by remember { mutableStateOf<Page>(Page.Main) }
    val voice by Voice.state.collectAsState()
    val isOwner = v.ownerUid == uid
    val me = v.mySeat ?: 0
    val scope = rememberCoroutineScope()

    fun seatLabel(i: Int): String {
        val s = v.seats.getOrNull(i) ?: return "مقعد فارغ"
        val tags = listOfNotNull(
            if (i == v.mySeat) "أنت" else null,
            if (s.isBot) "روبوت" else null,
            if (s.away) "انقطع اتصاله" else null,
            if (v.mySeat != null && i != v.mySeat && teamOf(i) == teamOf(me)) "شريكك" else null,
        )
        return s.username + if (tags.isNotEmpty()) " (${tags.joinToString("، ")})" else ""
    }
    fun nameOf(u: String) = v.seats.getOrNull(v.seatUids.indexOf(u))?.username ?: v.spectators.find { it.uid == u }?.username
    // أي حاضر حقيقي غيرك: تضغطه فتظهر خياراته
    fun canManage(u: String?) = !u.isNullOrEmpty() && u != uid && !u.startsWith("bot-")

    when (val p = page) {
        Page.Main -> MajliskDialog("القائمة", onClose) {
            if (isOwner) {
                SwitchRow("طاولة خاصة", v.isPrivate, { conn.send("setPrivate", "isPrivate" to it) })
            } else Note(if (v.isPrivate) "طاولة خاصة: الدخول بالدعوة فقط" else "طاولة عامة")
            SecondaryButton("اللاعبون", { page = Page.Players }, fill = true)
            if (isOwner) SecondaryButton("دعوة صديق", { page = Page.Invite }, fill = true)
            SecondaryButton("مشاهدة إعلان (+2 🪙)", { Ads.watch() }, fill = true)
            SecondaryButton(
                if (voice.joined) "مغادرة المحادثة الصوتية" else "الانضمام للمحادثة الصوتية",
                { if (voice.joined) Voice.leave() else Voice.join(v.id, uid, Voice.Mode.Manual); onClose() },
                enabled = !voice.busy, fill = true,
            )
            SecondaryButton("الإعدادات", { page = Page.Settings }, fill = true)
            if (isOwner && (v.hasGame || v.seats.any { it != null })) DangerButton("إيقاف اللعبة", { page = Page.Stop })
            DangerButton("مغادرة الطاولة", onLeave)
            SecondaryButton("إغلاق القائمة", onClose, fill = true)
        }
        Page.Stop -> MajliskDialog("إيقاف اللعبة", { page = Page.Main }) {
            Body("إيقاف نهائي: تُلغى المباراة وترجع النتيجة صفر صفر، ويصبح الجميع مشاهدين والمقاعد فارغة. بعدها تختار أنت من يلعب من صفحة اللاعبين.")
            DangerButton("إيقاف اللعبة", { conn.send("stop"); onClose() })
            SecondaryButton("إلغاء", { page = Page.Main }, fill = true)
        }
        Page.Invite -> InviteFriendsDialog(v.id, seat = null, title = "دعوة صديق") { page = Page.Main }
        Page.Settings -> MajliskDialog("إعدادات", { page = Page.Main }) {
            SettingsScreen(onBack = { page = Page.Main }, embedded = true)
        }
        Page.Players -> MajliskDialog("اللاعبون", { page = Page.Main }) {
            (0..3).forEach { i ->
                val u = v.seatUids.getOrNull(i)
                val muted = if (u != null && u in v.voiceBlocked) "، مكتوم" else ""
                ItemRow {
                    if (canManage(u)) SecondaryButton(seatLabel(i) + muted, { page = Page.Member(u!!) }, modifier = Modifier.weight(1f))
                    else Text(seatLabel(i), color = Palette.text, modifier = Modifier.weight(1f))
                    val s = v.seats.getOrNull(i)
                    if (isOwner && i != v.mySeat && !canManage(u) && (s == null || s.isBot)) {
                        com.majlisk.app.ui.SmallButton("استبدال", { page = Page.Replace(i) }, description = "استبدال ${s?.username ?: "المقعد الفارغ"}")
                    }
                }
            }
            Text("المشاهدون", color = Palette.goldSoft)
            if (v.spectators.isEmpty()) Note("لا يوجد مشاهدون")
            v.spectators.forEach { s ->
                if (canManage(s.uid)) SecondaryButton("${s.username} (مشاهد)${if (s.uid in v.voiceBlocked) "، مكتوم" else ""}", { page = Page.Member(s.uid) }, fill = true)
                else Body("${s.username}${if (s.uid == uid) " (أنت)" else ""}")
            }
            SecondaryButton("رجوع", { page = Page.Main }, fill = true)
        }
        is Page.Member -> {
            val u = p.uid
            val name = nameOf(u)
            val seat = v.seatUids.indexOf(u)
            val blocked = u in v.voiceBlocked
            var friendState by remember(u) { mutableStateOf<String?>(null) }
            LaunchedEffect(u) {
                friendState = runCatching { if (Social.listFriends().friends.any { it.uid == u }) "friend" else "none" }.getOrDefault("none")
            }
            MajliskDialog(name ?: "لم يعد على الطاولة", { page = Page.Players }) {
                if (name != null) {
                    when (friendState) {
                        "friend" -> Note("صديقك")
                        "sent" -> Note("أُرسل طلب الصداقة")
                        "none" -> PrimaryButton("إضافة صديق", {
                            scope.launch {
                                runCatching { Social.requestFriend(name) }
                                    .onSuccess { friendState = "sent"; Announcer.announce(if (it) "أصبح $name صديقك" else "أُرسل طلب صداقة إلى $name") }
                                    .onFailure { Announcer.announce(Social.error(it)) }
                            }
                        })
                    }
                    if (isOwner) {
                        SecondaryButton(if (blocked) "إلغاء الكتم في المحادثة الصوتية" else "كتم في المحادثة الصوتية", {
                            conn.send("voiceBlock", "uid" to u, "blocked" to !blocked); page = Page.Players
                        }, fill = true)
                        DangerButton("طرد من الطاولة", { page = Page.Confirm(false, u) })
                        DangerButton("حظر من الطاولة", { page = Page.Confirm(true, u) })
                        if (seat >= 0 && v.seats.getOrNull(seat)?.away == true) {
                            SecondaryButton("روبوت مكانه الآن", { conn.send("botNow", "seat" to seat); page = Page.Players }, fill = true)
                        }
                        if (seat >= 0) SecondaryButton("استبداله بمشاهد", { page = Page.Replace(seat) }, fill = true)
                    }
                }
                SecondaryButton("رجوع", { page = Page.Players }, fill = true)
            }
        }
        is Page.Confirm -> {
            val name = nameOf(p.uid) ?: "هذا الشخص"
            MajliskDialog(if (p.ban) "حظر $name؟" else "طرد $name؟", { page = Page.Member(p.uid) }) {
                Body(
                    (if (p.ban) "سيخرج من الطاولة، ولن يستطيع دخول هذه الطاولة ولا أي طاولة تملكها."
                    else "سيخرج من الطاولة. يستطيع دخول أي طاولة أخرى فوراً، والعودة لهذه الطاولة بعد ساعة.") +
                        if (v.playing && p.uid in v.seatUids) " يحل روبوت مكانه في اللعب." else "",
                )
                DangerButton(if (p.ban) "حظر" else "طرد", { conn.send(if (p.ban) "ban" else "kick", "uid" to p.uid); page = Page.Players })
                SecondaryButton("إلغاء", { page = Page.Member(p.uid) }, fill = true)
            }
        }
        is Page.Replace -> MajliskDialog("من يجلس مكان ${v.seats.getOrNull(p.seat)?.username ?: "المقعد الفارغ"}؟", { page = Page.Players }) {
            if (v.spectators.isEmpty()) Body("لا يوجد مشاهدون للاستبدال. ادعُ صديقاً أولاً، وبعد دخوله يظهر هنا.")
            v.spectators.forEach { s -> PrimaryButton(s.username, { conn.send("replace", "seat" to p.seat, "uid" to s.uid); page = Page.Players }) }
            SecondaryButton("رجوع", { page = Page.Players }, fill = true)
        }
    }
}
