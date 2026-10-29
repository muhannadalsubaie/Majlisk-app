package com.majlisk.app.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Friend
import com.majlisk.app.data.HubState
import com.majlisk.app.data.Social
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** الأصدقاء: تبويب للقائمة مع حالة الاتصال، وتبويب للطلبات الواردة، وتبويب للمحظورين */
@Composable
fun FriendsScreen(hub: HubState, navigate: (Route) -> Unit) {
    var tab by remember { mutableStateOf(0) }
    var friends by remember { mutableStateOf<List<Friend>?>(null) }
    var bans by remember { mutableStateOf<List<Friend>?>(null) }
    var message by remember { mutableStateOf("") }
    var adding by remember { mutableStateOf(false) }
    var toRemove by remember { mutableStateOf<Friend?>(null) }
    var refreshKey by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    val say: (String) -> Unit = { message = it; Announcer.announce(it) }

    // تحديث القائمة عند أي تغيير في المركز، وكل 20 ثانية لحالة الاتصال
    LaunchedEffect(hub.friends.size, refreshKey) {
        while (true) {
            friends = runCatching { Social.listFriends().friends }.getOrDefault(friends ?: emptyList())
            delay(20_000)
        }
    }
    LaunchedEffect(tab) { if (tab == 2) bans = runCatching { Social.listBans() }.getOrDefault(emptyList()) }

    Screen {
        TopBar("الأصدقاء", onBack = { navigate(Route.Menu) }) {
            SecondaryButton("إضافة صديق", { adding = true })
        }
        if (message.isNotEmpty()) Text(message, color = Palette.goldSoft, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        TabRow(selectedTabIndex = tab, containerColor = Palette.green800, contentColor = Palette.text) {
            Tab(tab == 0, { tab = 0 }, text = { Text("الأصدقاء${friends?.let { " (${it.size})" } ?: ""}") })
            Tab(tab == 1, { tab = 1 }, text = { Text("طلبات الصداقة${if (hub.requests.isNotEmpty()) " ${hub.requests.size}" else ""}") })
            Tab(tab == 2, { tab = 2 }, text = { Text("المحظورون") })
        }
        when (tab) {
            0 -> {
                if (friends == null) Body("جارٍ التحميل…")
                else if (friends!!.isEmpty()) Note("لا يوجد أصدقاء بعد — اضغط \"إضافة صديق\" في الأعلى وأضفه باسم المستخدم.")
                friends?.sortedByDescending { it.online }?.forEach { f ->
                    ItemRow {
                        Text("${if (f.online) "🟢" else "⚪"} ${f.username}، ${if (f.online) "متصل" else "غير متصل"}", color = Palette.text, modifier = Modifier.weight(1f))
                        SecondaryButton("حذف", { toRemove = f }, description = "حذف ${f.username} من الأصدقاء")
                    }
                }
            }
            1 -> {
                if (hub.requests.isEmpty()) Note("لا توجد طلبات صداقة.")
                hub.requests.forEach { r ->
                    ItemRow {
                        Text(r.username, color = Palette.text, modifier = Modifier.weight(1f))
                        SecondaryButton("قبول", {
                            scope.launch { runCatching { Social.respondFriend(r.uid, true) }.onSuccess { say("أصبحت أنت و${r.username} أصدقاء"); refreshKey++ }.onFailure { say(Social.error(it)) } }
                        }, description = "قبول طلب ${r.username}")
                        SecondaryButton("رفض", {
                            scope.launch { runCatching { Social.respondFriend(r.uid, false) }.onSuccess { say("رُفض طلب ${r.username}") }.onFailure { say(Social.error(it)) } }
                        }, description = "رفض طلب ${r.username}")
                    }
                }
            }
            else -> {
                Note("من حظرتهم لا يستطيعون دخول أي طاولة تملكها.")
                if (bans == null) Body("جارٍ التحميل…")
                else if (bans!!.isEmpty()) Note("لا يوجد محظورون.")
                bans?.forEach { b ->
                    ItemRow {
                        Text(b.username, color = Palette.text, modifier = Modifier.weight(1f))
                        SecondaryButton("رفع الحظر", {
                            scope.launch {
                                runCatching { Social.unban(b.uid) }
                                    .onSuccess { bans = bans?.filter { it.uid != b.uid }; Announcer.announce("رُفع الحظر عن ${b.username}") }
                                    .onFailure { Announcer.announce(Social.error(it)) }
                            }
                        }, description = "رفع الحظر عن ${b.username}")
                    }
                }
            }
        }
    }

    if (adding) {
        var name by remember { mutableStateOf("") }
        var busy by remember { mutableStateOf(false) }
        MajliskDialog("إضافة صديق", { adding = false }) {
            Field("اسم المستخدم", name, { name = it })
            PrimaryButton("إرسال طلب صداقة", {
                busy = true
                scope.launch {
                    runCatching { Social.requestFriend(name.trim()) }
                        .onSuccess { became -> say(if (became) "أصبحت أنت و${name.trim()} أصدقاء" else "أُرسل طلب الصداقة إلى ${name.trim()}"); adding = false; refreshKey++ }
                        .onFailure { say(Social.error(it)) }
                    busy = false
                }
            }, enabled = !busy && name.isNotBlank())
            SecondaryButton("إلغاء", { adding = false }, fill = true)
        }
    }
    toRemove?.let { f ->
        ConfirmDialog("حذف صديق", "هل تريد حذف ${f.username} من أصدقائك؟", "حذف", danger = true, onConfirm = {
            toRemove = null
            scope.launch { runCatching { Social.removeFriend(f.uid) }; refreshKey++ }
        }, onCancel = { toRemove = null })
    }
}
