package com.majlisk.app.ui

import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Hub
import com.majlisk.app.data.Online
import com.majlisk.app.data.OnlinePlayer
import com.majlisk.app.data.Social
import kotlinx.coroutines.launch

/** تحت اسمك في الشاشة الرئيسية: «المتصلون: ١٢» (يتحدث على طول)، والضغط يفتح قائمتهم */
@Composable
fun OnlineLine() {
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
    if (open) OnlineDialog { open = false }
}

/** أسماء كل المتصلين في التطبيق: الضغط على الاسم يفتح ملفه (وتقدر تضيفه صديق) */
@Composable
private fun OnlineDialog(onClose: () -> Unit) {
    val list by Online.list.collectAsState()
    val count by Online.count.collectAsState()
    var player by remember { mutableStateOf<OnlinePlayer?>(null) }
    LaunchedEffect(Unit) { Online.requestList() }
    MajliskDialog(if (count != null) "المتصلون الآن ($count)" else "المتصلون الآن", onClose) {
        val l = list
        when {
            l == null -> Body("جارٍ التحميل…")
            l.isEmpty() -> Body("ما فيه أحد متصل الحين")
            else -> LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(l, key = { it.uid }) { p ->
                    ItemRow(Modifier.clickable(role = Role.Button, onClickLabel = "فتح ملفه") { player = p }
                        .semantics(mergeDescendants = true) { contentDescription = if (p.me) "${p.username}، أنت" else p.username }) {
                        Avatar(p.uid, p.username, 36.dp)
                        Text(if (p.me) "${p.username} (أنت)" else p.username, color = Palette.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        SecondaryButton("تحديث القائمة", { Online.requestList() }, fill = true)
        SecondaryButton("إغلاق", onClose, fill = true)
    }
    player?.let { p -> PlayerCard(p) { player = null } }
}

/** ملف لاعب: صورته واسمه، وإضافته صديق (أو قبول طلبه لو هو اللي طلبك) */
@Composable
private fun PlayerCard(p: OnlinePlayer, onClose: () -> Unit) {
    val hub by Hub.state.collectAsState()
    val scope = rememberCoroutineScope()
    var sent by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val friend = hub.friends.any { it.uid == p.uid }
    val asked = hub.requests.any { it.uid == p.uid }
    MajliskDialog(p.username, onClose) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Avatar(p.uid, p.username, 110.dp) }
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Body(when { p.me -> "هذا أنت"; friend -> "صديقك، متصل الآن"; else -> "متصل الآن" })
        }
        when {
            p.me || friend -> {}
            asked -> PrimaryButton("قبول طلب الصداقة", {
                busy = true
                scope.launch {
                    runCatching { Social.respondFriend(p.uid, true) }
                        .onSuccess { Announcer.announce("أصبحت أنت و${p.username} أصدقاء") }
                        .onFailure { Announcer.announce(Social.error(it)) }
                    busy = false
                }
            }, enabled = !busy)
            sent -> Body("أُرسل طلب الصداقة")
            else -> PrimaryButton("إضافة صديق", {
                busy = true
                scope.launch {
                    runCatching { Social.requestFriend(p.username) }
                        .onSuccess { sent = true; Announcer.announce(if (it) "أصبحت أنت و${p.username} أصدقاء" else "أُرسل طلب الصداقة إلى ${p.username}") }
                        .onFailure { Announcer.announce(Social.error(it)) }
                    busy = false
                }
            }, enabled = !busy)
        }
        SecondaryButton("رجوع", onClose, fill = true)
    }
}
