package com.majlisk.app.table

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.fillMaxWidth
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

    // خيارات اللعبة فوق المقاعد: المالك يغيّرها، والباقين يشوفونها بس
    val choice: @Composable (String, String, Boolean, (Boolean) -> Unit) -> Unit = { a, b, second, send ->
        androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
            listOf(false, true).forEach { isB ->
                val on = isB == second
                val name = if (isB) b else a
                SmallButton(name, { if (isOwner && !on) send(isB) }, primary = on, enabled = isOwner || on, description = "$name${if (on) "، محدد" else ""}")
            }
        }
    }
    if (v.kind == "ludo" || v.kind == "domino") choice("فردي", "فرق", v.optTeams) { conn.send("setOptions", "teams" to it) }
    if (v.kind == "jackaroo") choice("عادي", "كومبلكس", v.optComplex) { conn.send("setOptions", "complex" to it) }
    if (v.kind == "domino") {
        if (isOwner) {
            var target by remember(v.optTarget) { mutableStateOf(v.optTarget.toString()) }
            androidx.compose.foundation.layout.Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
                androidx.compose.material3.OutlinedTextField(
                    value = target, onValueChange = { target = it.filter(Char::isDigit).take(4) },
                    label = { Text("نهاية المباراة") }, singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
                SmallButton("حفظ", { target.toIntOrNull()?.let { conn.send("setOptions", "target" to it) } }, primary = true, description = "حفظ نهاية المباراة")
            }
        } else Note("نهاية المباراة: ${v.optTarget}")
    }

    SectionTitle("المقاعد")
    listOf("الفريق الأول" to listOf(0, 2), "الفريق الثاني" to listOf(1, 3)).forEach { (title, seats) ->
        Text(title, color = Palette.goldSoft)
        seats.forEach { i ->
            ItemRow {
                v.seats.getOrNull(i)?.let { com.majlisk.app.ui.Avatar(v.seatUids.getOrNull(i), it.username, 32.dp) }
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
    val seated = v.seats.count { it != null }
    // «بدء المباراة» يفتح نافذة إعدادات المباراة: فيها وقت كل دور (قائمة منسدلة) وأي إعدادات تنضاف بعدين، ثم «ابدأ»
    if (isOwner) {
        var limit by remember { mutableStateOf(0) }
        var open by remember { mutableStateOf(false) }
        var setup by remember { mutableStateOf(false) }
        // خيارات الباقة الاحترافية (البلوت، والمالك مشترك): تنضبط قبل البداية بس
        val pro = com.majlisk.app.data.Session.profile.collectAsState().value?.isPro == true
        var manual by remember { mutableStateOf(false) }
        var qaid by remember { mutableStateOf(false) }
        var sawa by remember { mutableStateOf(true) }
        PrimaryButton("بدء المباراة", { setup = true }, enabled = seated in v.startCounts)
        if (setup) MajliskDialog("إعدادات المباراة", { setup = false }) {
        androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth()) {
            SecondaryButton("وقت كل دور: ${turnLimitLabel(limit)} ▾", { open = true }, fill = true, description = "وقت كل دور، ${turnLimitLabel(limit)}، قائمة")
            androidx.compose.material3.DropdownMenu(open, { open = false }, containerColor = Palette.green800) {
                TURN_LIMITS.forEach { s ->
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text(if (s == limit) "✓ ${turnLimitLabel(s)}" else turnLimitLabel(s), color = Palette.text, fontSize = 17.sp) },
                        onClick = { limit = s; open = false },
                    )
                }
            }
        }
        Note("لو خلص وقت اللاعب، الروبوت يلعب عنه أفضل حركة.")
        if (v.kind == "baloot") {
            if (pro) {
                com.majlisk.app.ui.SwitchRow("إعلان المشاريع يدوي", manual, { manual = it }, description = "كل لاعب يعلن مشروعه بنفسه قبل ورقته الأولى")
                com.majlisk.app.ui.SwitchRow("القيد والقطع", qaid, { qaid = it }, description = "اللعب حر، واللي يغلط يتسجّل عليه بزر تسجيلة")
                com.majlisk.app.ui.SwitchRow("زر سوا", sawa, { sawa = it }, description = "زر سوا يطلع للكل، ولو توقفه ما يطلع لأحد في هالمباراة")
                Note("🔒 هذي الخيارات تنضبط قبل بداية المباراة بس. بعد ما تبدأ يتغير المؤقت فقط.")
            } else if (com.majlisk.app.data.Session.profile.collectAsState().value?.proAccess == true)
                Note("👑 إعلان المشاريع يدوي، والقيد والقطع، وتغيير المؤقت أثناء اللعب: للمشتركين في الباقة الاحترافية.")
        }
        PrimaryButton("ابدأ", { setup = false; conn.send("start", "turnLimit" to limit, "manualProjects" to (pro && manual), "qaid" to (pro && qaid), "sawa" to (!pro || sawa)) }, enabled = seated in v.startCounts)
        SecondaryButton("إلغاء", { setup = false }, fill = true)
        }
    } else Body("بانتظار مالك الطاولة لبدء المباراة")

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
        // الأصدقاء اللي موجودين في نفس الطاولة (جالسين أو يتفرجون) ما يطلعون في الدعوة
        val outside = friends?.filter { it.tableId != tableId }
        if (friends == null) Body("جارٍ التحميل…")
        else if (friends!!.isEmpty()) Body("لا يوجد أصدقاء بعد. أضفهم من شاشة الأصدقاء، أو أضف روبوتاً.")
        else if (outside!!.isEmpty()) Body("كل أصدقائك موجودين في الطاولة.")
        outside?.sortedByDescending { it.online }?.forEach { f ->
            ItemRow {
                Text("${f.username}، ${if (f.online) "متصل" else "غير متصل"}", color = Palette.text, modifier = Modifier.weight(1f))
                // غير المتصل تصله الدعوة إشعار على جواله
                SmallButton("دعوة", {
                    busy = f.uid
                    scope.launch {
                        runCatching { Social.inviteFriend(tableId, f.uid, seat) }
                            .onSuccess {
                                // الخادم يعلن للكل «فلان أرسل دعوة إلى فلان» (وتنكتب في الدردشة)، فما نكررها هنا
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
