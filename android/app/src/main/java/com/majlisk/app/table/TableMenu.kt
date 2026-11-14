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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Ads
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
import com.majlisk.app.ui.SettingsScreen
import com.majlisk.app.ui.SwitchRow
import com.majlisk.app.voice.Voice
import kotlinx.coroutines.launch

private sealed interface Page {
    data object Main : Page
    data object Players : Page
    data object Invite : Page
    data object Friends : Page
    data object Settings : Page
    data object Stop : Page
    data object ChangeGame : Page
    data class Replace(val seat: Int) : Page
    data class Member(val uid: String) : Page
    data class Confirm(val ban: Boolean, val uid: String) : Page
}

/** صفحة تنفتح عليها القائمة مباشرة (من إجراءات قارئ الشاشة على زر القائمة) */
enum class TableMenuStart { Main, Players, Invite, Friends }

/** قائمة الطاولة: اللاعبون، دعوة صديق، مشاهدة إعلان، المحادثة الصوتية، الإعدادات، مغادرة */
@Composable
fun TableMenu(v: TableView, uid: String, conn: TableConnection, onLeave: () -> Unit, onClose: () -> Unit, start: TableMenuStart = TableMenuStart.Main) {
    var page by remember {
        mutableStateOf<Page>(when (start) {
            TableMenuStart.Main -> Page.Main
            TableMenuStart.Players -> Page.Players
            TableMenuStart.Invite -> Page.Invite
            TableMenuStart.Friends -> Page.Friends
        })
    }
    val voice by Voice.state.collectAsState()
    val isOwner = v.ownerUid == uid
    val scope = rememberCoroutineScope()

    /** بجانب اسم كل لاعب (غير الروبوت): في المحادثة الصوتية أو خارجها */
    fun voiceTag(u: String?): String =
        if (u.isNullOrEmpty()) "" else if (v.voice.any { it.uid == u }) "، في المحادثة الصوتية" else "، خارج المحادثة الصوتية"
    fun seatLabel(i: Int): String {
        val s = v.seats.getOrNull(i) ?: return "مقعد فارغ"
        // قائمة اللاعبين: الاسم (ومعه حالة المحادثة الصوتية)؛ الروبوت يتوضح، واللي انقطع اتصاله
        return s.username + (if (s.isBot) "، روبوت" else "") + (if (s.away) "، انقطع اتصاله" else "")
    }
    fun nameOf(u: String) = v.seats.getOrNull(v.seatUids.indexOf(u))?.username ?: v.spectators.find { it.uid == u }?.username
    // أي حاضر حقيقي غيرك: تضغطه فتظهر خياراته
    fun canManage(u: String?) = !u.isNullOrEmpty() && u != uid && !u.startsWith("bot-")

    when (val p = page) {
        Page.Main -> MajliskDialog("القائمة", onClose) {
            if (isOwner) {
                SwitchRow("طاولة خاصة", v.isPrivate, { conn.send("setPrivate", "isPrivate" to it) })
            } else Note(if (v.isPrivate) "طاولة خاصة: الدخول بالدعوة فقط" else "طاولة عامة")
            // المشترك: إخفاء ظهوره من هنا بعد
            if (com.majlisk.app.data.Session.profile.collectAsState().value?.isPro == true) com.majlisk.app.ui.HideOnlineSwitch()
            SecondaryButton("اللاعبون", { page = Page.Players }, fill = true)
            if (isOwner) SecondaryButton("دعوة صديق", { page = Page.Invite }, fill = true)
            SecondaryButton("الأصدقاء", { page = Page.Friends }, fill = true)
            SecondaryButton("مشاهدة إعلان (+2 🪙)", { Ads.watch() }, fill = true)
            SecondaryButton(
                if (voice.joined) "مغادرة المحادثة الصوتية" else "الانضمام للمحادثة الصوتية",
                { if (voice.joined) Voice.leave() else Voice.join(v.id, uid, Voice.Mode.Manual); onClose() },
                enabled = !voice.busy, fill = true,
            )
            SecondaryButton("الإعدادات", { page = Page.Settings }, fill = true)
            if (isOwner) SecondaryButton("تغيير اللعبة", { page = Page.ChangeGame }, fill = true)
            if (isOwner && (v.hasGame || v.seats.any { it != null })) DangerButton("إيقاف اللعبة", { page = Page.Stop })
            DangerButton("مغادرة الطاولة", onLeave)
            SecondaryButton("إغلاق القائمة", onClose, fill = true)
        }
        Page.Stop -> MajliskDialog("إيقاف اللعبة", { page = Page.Main }) {
            Body("إيقاف نهائي: تُلغى المباراة وترجع النتيجة صفر صفر، ويصبح الجميع مشاهدين والمقاعد فارغة. بعدها تختار أنت من يلعب من صفحة اللاعبين.")
            DangerButton("إيقاف اللعبة", { conn.send("stop"); onClose() })
            SecondaryButton("إلغاء", { page = Page.Main }, fill = true)
        }
        // المالك يغيّر لعبة الطاولة: تنتهي اللعبة الحالية، ويبقى الكل في أماكنهم للعبة الجديدة
        Page.ChangeGame -> MajliskDialog("تغيير اللعبة", { page = Page.Main }) {
            Body("الحالية: ${com.majlisk.app.data.gameTitle(v.kind, "classic")}. لو غيّرتها تنتهي اللعبة الحالية، ويبقى الكل في أماكنهم للعبة الجديدة. خيارات اللعبة (فردي أو فرق، عادي أو كومبلكس، نهاية المباراة) تختارها من صفحة المقاعد.")
            // اسم اللعبة بس
            listOf("baloot", "domino", "jackaroo", "ludo").filter { it != v.kind }.forEach { k ->
                PrimaryButton(com.majlisk.app.data.gameTitle(k, "classic"), { conn.send("changeGame", "kind" to k); onClose() })
            }
            SecondaryButton("رجوع", { page = Page.Main }, fill = true)
        }
        Page.Invite -> InviteFriendsDialog(v.id, seat = null, title = "دعوة صديق") { page = Page.Main }
        // قائمة الأصدقاء كاملة (الأصدقاء، الطلبات، المحظورون) من داخل الطاولة، بملء الشاشة
        Page.Friends -> androidx.compose.ui.window.Dialog(
            onDismissRequest = { page = Page.Main },
            properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        ) {
            val hub by com.majlisk.app.data.Hub.state.collectAsState()
            // دخول طاولة صديق من هنا: تطلع من طاولتك وتنتقل لطاولته على طول
            com.majlisk.app.ui.FriendsScreen(hub, navigate = { page = Page.Main }, openTable = { id ->
                if (id != v.id) {
                    conn.send("leave")
                    com.majlisk.app.push.Push.switchTable.value = id
                }
                onClose()
            })
        }
        Page.Settings -> MajliskDialog("إعدادات", { page = Page.Main }) {
            SettingsScreen(onBack = { page = Page.Main }, embedded = true)
        }
        Page.Players -> MajliskDialog("اللاعبون", { page = Page.Main }) {
            (0..3).forEach { i ->
                val u = v.seatUids.getOrNull(i)
                val muted = if (u != null && u in v.voiceBlocked) "، مكتوم" else ""
                val s = v.seats.getOrNull(i)
                // انقطع اتصاله: ما نكتب حالة المحادثة
                val vt = if (s == null || s.isBot || s.away) "" else voiceTag(u)
                ItemRow {
                    if (canManage(u)) SecondaryButton(seatLabel(i) + vt + muted, { page = Page.Member(u!!) }, modifier = Modifier.weight(1f))
                    else Text(seatLabel(i) + vt, color = Palette.text, modifier = Modifier.weight(1f))
                    // المالك يستبدل المقعد الفاضي أو الروبوت، أو نفسه (حتى أثناء اللعب: يصير مشاهد ويبقى المالك)
                    if (isOwner && !canManage(u) && (s == null || s.isBot || i == v.mySeat)) {
                        com.majlisk.app.ui.SmallButton("استبدال", { page = Page.Replace(i) },
                            description = if (i == v.mySeat) "استبدال نفسك بمشاهد" else "استبدال ${s?.username ?: "المقعد الفارغ"}")
                    }
                }
            }
            Text("المشاهدون", color = Palette.goldSoft)
            if (v.spectators.isEmpty()) Note("لا يوجد مشاهدون")
            v.spectators.forEach { s ->
                if (canManage(s.uid)) SecondaryButton("${s.username}${voiceTag(s.uid)}${if (s.uid in v.voiceBlocked) "، مكتوم" else ""}", { page = Page.Member(s.uid) }, fill = true)
                else Body("${s.username}${voiceTag(s.uid)}")
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
                        SecondaryButton("تعيينه مالكاً للطاولة", { conn.send("setOwner", "uid" to u); onClose() }, fill = true)
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
                    else "سيخرج من الطاولة. يستطيع دخول أي طاولة أخرى فوراً، والعودة لهذه الطاولة بعد ساعة، أو قبلها لو أرسلت له دعوة.") +
                        if (v.playing && p.uid in v.seatUids) " يحل روبوت مكانه في اللعب." else "",
                )
                DangerButton(if (p.ban) "حظر" else "طرد", { conn.send(if (p.ban) "ban" else "kick", "uid" to p.uid); page = Page.Players })
                SecondaryButton("إلغاء", { page = Page.Member(p.uid) }, fill = true)
            }
        }
        is Page.Replace -> MajliskDialog("من يجلس مكان ${v.seats.getOrNull(p.seat)?.username ?: "المقعد الفارغ"}؟", { page = Page.Players }) {
            v.spectators.forEach { s -> PrimaryButton(s.username, { conn.send("replace", "seat" to p.seat, "uid" to s.uid); page = Page.Players }) }
            // روبوت مكانه (حتى أثناء اللعب: ياخذ أوراق المقعد)
            if (v.seats.getOrNull(p.seat)?.isBot != true)
                PrimaryButton("روبوت (1 🪙)", { conn.send("replace", "seat" to p.seat, "uid" to "bot"); page = Page.Players }, description = "روبوت، عملة واحدة")
            if (v.spectators.isEmpty()) Note("ما فيه مشاهدين. تقدر تحط روبوت، أو تدعو صديق وبعد ما يدخل يطلع هنا.")
            SecondaryButton("رجوع", { page = Page.Players }, fill = true)
        }
    }
}
