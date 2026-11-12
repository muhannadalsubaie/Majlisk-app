package com.majlisk.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Hub
import com.majlisk.app.data.Online
import com.majlisk.app.data.OnlinePlayer
import com.majlisk.app.data.Social
import com.majlisk.app.data.Tables
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** تحت اسمك في الشاشة الرئيسية: «المتصلون: ١٢» (يتحدث على طول)، والضغط يفتح قائمتهم */
@Composable
fun OnlineLine(openTable: (String) -> Unit) {
    val count by Online.count.collectAsState()
    var open by remember { mutableStateOf(false) }
    val n = count
    Text(
        if (n == null) "المتصلون: …" else "المتصلون: $n",
        color = Palette.goldSoft, fontSize = 14.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier
            .clickable(role = Role.Button, onClickLabel = "عرض المتصلين") { open = true }
            .semantics { contentDescription = if (n == null) "المتصلون، جارٍ التحميل" else "المتصلون الآن $n" },
    )
    if (open) OnlineDialog({ open = false }, openTable)
}

/** وين اللاعب: «بلوت، طاولة عامة» أو «في الرئيسية» */
private fun placeText(p: OnlinePlayer): String =
    if (p.tableId == null) "في الرئيسية"
    else listOf(p.tableGame, if (p.tablePrivate) "طاولة خاصة" else "طاولة عامة").filter { it.isNotEmpty() }.joinToString("، ")

/**
 * الدخول لطاولة لاعب (نفس قائمة الأصدقاء): العامة تدخلها على طول، والخاصة ترسل طلب انضمام
 * لصاحبها وننتظر رده (قبول = ندخل)
 */
private fun joinTableOf(p: OnlinePlayer, scope: CoroutineScope, openTable: (String) -> Unit, done: () -> Unit) {
    val id = p.tableId ?: run { Announcer.announce("${p.username} مو على طاولة الحين"); done(); return }
    scope.launch {
        try {
            if (p.tablePrivate) {
                var (st, mins) = Tables.requestJoin(id)
                if (st == "pending") Announcer.announce("أُرسل طلب الانضمام إلى طاولة ${p.username}، ننتظر موافقة صاحبها")
                var n = 0
                while (st == "pending" && n < 155) {
                    delay(2000)
                    runCatching { Tables.joinRequestStatus(id) }.getOrNull()?.let { st = it.first; mins = it.second }
                    n++
                }
                when (st) {
                    "accepted" -> { Tables.join(id); openTable(id) }
                    "rejected" -> Announcer.announce("رُفض طلب الانضمام، تقدر تحاول بعد ${minutesText(mins)}")
                    "waiting" -> Announcer.announce("عندك طلب انضمام معلّق لهالطاولة، تقدر ترسل طلب جديد بعد ${minutesText(mins)}")
                    else -> Announcer.announce("انتهى طلب الانضمام بدون رد")
                }
            } else {
                Tables.join(id)
                openTable(id)
            }
        } catch (e: Exception) {
            Announcer.announce(Tables.error(e, if (p.tablePrivate) "تعذّر إرسال طلب الانضمام" else "تعذّر الانضمام"))
        } finally { done() }
    }
}

/**
 * كل المتصلين: صورة واسم ووين هو (اللعبة، وعامة أو خاصة)، وجنبه «إضافة صديق».
 * الضغط يفتح ملفه، والضغط المطوّل يدخلك طاولته (العامة على طول، والخاصة بطلب انضمام)
 */
@Composable
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
private fun OnlineDialog(onClose: () -> Unit, openTable: (String) -> Unit) {
    val list by Online.list.collectAsState()
    val count by Online.count.collectAsState()
    val hub by Hub.state.collectAsState()
    val scope = rememberCoroutineScope()
    var player by remember { mutableStateOf<OnlinePlayer?>(null) }
    val sent = remember { mutableStateListOf<String>() }
    var joining by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { Online.requestList() }
    val enter = { p: OnlinePlayer -> if (!joining) { joining = true; joinTableOf(p, scope, { onClose(); openTable(it) }) { joining = false } } }
    val addFriend = { p: OnlinePlayer ->
        scope.launch {
            runCatching { Social.requestFriend(p.username) }
                .onSuccess { sent += p.uid; Announcer.announce(if (it) "أصبحت أنت و${p.username} أصدقاء" else "أُرسل طلب الصداقة إلى ${p.username}") }
                .onFailure { Announcer.announce(Social.error(it)) }
        }
        Unit
    }
    val acceptFriend = { p: OnlinePlayer ->
        scope.launch {
            runCatching { Social.respondFriend(p.uid, true) }
                .onSuccess { Announcer.announce("أصبحت أنت و${p.username} أصدقاء") }
                .onFailure { Announcer.announce(Social.error(it)) }
        }
        Unit
    }
    MajliskDialog(if (count != null) "المتصلون الآن ($count)" else "المتصلون الآن", onClose) {
        val l = list
        when {
            l == null -> Body("جارٍ التحميل…")
            l.isEmpty() -> Body("ما فيه أحد متصل الحين")
            else -> LazyColumn(Modifier.fillMaxWidth().heightIn(max = 440.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(l, key = { it.uid }) { p ->
                    val friend = hub.friends.any { it.uid == p.uid }
                    val asked = hub.requests.any { it.uid == p.uid }
                    val place = placeText(p)
                    val relation = when { p.me -> "أنت"; friend -> "صديقك"; p.uid in sent -> "أُرسل طلب الصداقة"; else -> null }
                    ItemRow(
                        Modifier.combinedClickable(
                            onClickLabel = "فتح ملفه", onClick = { player = p },
                            onLongClickLabel = if (p.tableId != null && !p.me) (if (p.tablePrivate) "طلب انضمام لطاولته" else "دخول طاولته") else null,
                            onLongClick = { if (!p.me) enter(p) },
                        ).semantics(mergeDescendants = true) {
                            contentDescription = listOfNotNull(p.username, place, relation).joinToString("، ")
                            // قارئ الشاشة: الإضافة والدخول كإجراءات على السطر
                            customActions = buildList {
                                if (!p.me && !friend && p.uid !in sent) add(CustomAccessibilityAction(if (asked) "قبول طلب الصداقة" else "إضافة صديق") { if (asked) acceptFriend(p) else addFriend(p); true })
                                if (!p.me && p.tableId != null) add(CustomAccessibilityAction(if (p.tablePrivate) "طلب انضمام لطاولته" else "دخول طاولته") { enter(p); true })
                            }
                        },
                    ) {
                        Avatar(p.uid, p.username, 38.dp)
                        Column(Modifier.weight(1f)) {
                            Text(if (p.me) "${p.username} (أنت)" else p.username, color = Palette.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text(place, color = Palette.textDim, fontSize = 13.sp)
                        }
                        when {
                            p.me -> {}
                            friend -> Text("صديقك", color = Palette.goldSoft, fontSize = 13.sp)
                            p.uid in sent -> Text("أُرسل", color = Palette.textDim, fontSize = 13.sp)
                            asked -> SmallButton("قبول", { acceptFriend(p) }, primary = true, description = "قبول طلب صداقة ${p.username}")
                            else -> SmallButton("إضافة صديق", { addFriend(p) }, description = "إضافة ${p.username} صديق")
                        }
                    }
                }
            }
        }
        SecondaryButton("تحديث القائمة", { Online.requestList() }, fill = true)
        SecondaryButton("إغلاق", onClose, fill = true)
    }
    player?.let { p ->
        val friend = hub.friends.any { it.uid == p.uid }
        val asked = hub.requests.any { it.uid == p.uid }
        MajliskDialog(p.username, { player = null }) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Avatar(p.uid, p.username, 110.dp) }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Body(if (p.me) "هذا أنت" else "${if (friend) "صديقك، " else ""}متصل، ${placeText(p)}")
            }
            if (!p.me && p.tableId != null) PrimaryButton(if (p.tablePrivate) "طلب انضمام" else "دخول طاولته", { player = null; enter(p) }, enabled = !joining)
            if (!p.me && !friend && p.uid !in sent) {
                if (asked) SecondaryButton("قبول طلب الصداقة", { acceptFriend(p) }, fill = true)
                else SecondaryButton("إضافة صديق", { addFriend(p) }, fill = true)
            }
            SecondaryButton("رجوع", { player = null }, fill = true)
        }
    }
}
