package com.majlisk.app.table

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import com.majlisk.app.i18n.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.data.ChatMessage
import com.majlisk.app.data.TableConnection
import com.majlisk.app.ui.Field
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import kotlinx.coroutines.delay

/** زر الدردشة الكتابية (فوق الميكروفون): عليه عدد الرسائل غير المقروءة */
@Composable
fun ChatButton(conn: TableConnection, onOpen: () -> Unit) {
    val unread by conn.unread.collectAsState()
    val label = if (unread > 0) "الدردشة، $unread رسائل جديدة" else "الدردشة"
    Text(
        if (unread > 0) "💬 الدردشة ($unread)" else "💬 الدردشة",
        color = Palette.green900, fontSize = 13.sp,
        modifier = Modifier.widthIn(max = 200.dp).heightIn(min = 40.dp)
            .background(Palette.gold, RoundedCornerShape(20.dp))
            .clickable(onClick = onOpen)
            .clearAndSetSemantics { contentDescription = com.majlisk.app.i18n.tr(label); role = Role.Button; onClick { onOpen(); true } }
            .padding(horizontal = 12.dp, vertical = 10.dp),
    )
}

/** آخر رسالة وصلت: تظهر ٥ ثوانٍ في الزاوية (قارئ الشاشة يقرؤها من الإعلان، فلا نكررها هنا) */
@Composable
fun ChatToast(conn: TableConnection, modifier: Modifier) {
    val toast by conn.toast.collectAsState()
    var shown by remember { mutableStateOf<ChatMessage?>(null) }
    LaunchedEffect(toast) {
        shown = toast
        if (toast != null) { delay(5000); shown = null }
    }
    val m = shown ?: return
    Box(modifier.navigationBarsPadding().padding(12.dp)) {
        Text(
            "${m.name}: ${m.text}",
            color = Palette.text, fontSize = 13.sp, maxLines = 3,
            modifier = Modifier.widthIn(max = 170.dp)
                .background(androidx.compose.ui.graphics.Color(0xCC000000), RoundedCornerShape(12.dp))
                .border(1.dp, Palette.gold, RoundedCornerShape(12.dp))
                .padding(horizontal = 10.dp, vertical = 6.dp)
                .clearAndSetSemantics { },
        )
    }
}

/** نافذة الدردشة: الرسائل، وخانة الكتابة وزر الإرسال */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ChatDialog(conn: TableConnection, onClose: () -> Unit) {
    val messages by conn.chat.collectAsState()
    var text by remember { mutableStateOf("") }
    // أول ما تنفتح: تنزل لآخر الرسائل، ومؤشر قارئ الشاشة يروح لخانة الكتابة (بعد أحدث رسالة على طول) بدون لوحة المفاتيح
    val inputFocus = remember { androidx.compose.ui.focus.FocusRequester() }
    val bring = remember { androidx.compose.foundation.relocation.BringIntoViewRequester() }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) {
        delay(250)
        runCatching { bring.bringIntoView() }
        // المؤشر على الخانة بدون ما تطلع لوحة المفاتيح (تضغط ضغطتين على الخانة إذا تبغى تكتب)
        if (com.majlisk.app.a11y.Announcer.readerOn) {
            runCatching { inputFocus.requestFocus() }
            delay(60)
            keyboard?.hide()
        }
    }
    MajliskDialog("الدردشة", onClose) {
        if (messages.isEmpty()) Note("ما فيه رسائل بعد.")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            messages.forEach { m ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
                    Column(
                        Modifier.widthIn(max = 300.dp)
                            .background(if (m.mine) androidx.compose.ui.graphics.Color(0xFF3B5E2E) else Palette.green700, RoundedCornerShape(12.dp))
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                            .clearAndSetSemantics { contentDescription = com.majlisk.app.i18n.tr("${if (m.mine) "أنت" else m.name}: ${m.text}") },
                    ) {
                        Text(if (m.mine) "أنت" else m.name, color = Palette.goldSoft, fontSize = 12.sp)
                        Text(m.text, color = Palette.text, fontSize = 15.sp)
                    }
                }
            }
        }
        // زر الإرسال في الكيبورد يرسل على طول
        androidx.compose.material3.OutlinedTextField(
            value = text, onValueChange = { text = it.take(200) },
            placeholder = { Text("اكتب رسالة…", color = Palette.textDim, fontSize = 14.sp) },
            singleLine = true,
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 15.sp, color = Palette.text),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Send),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSend = { if (text.isNotBlank()) { conn.sendChat(text); text = "" } }),
            colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700, cursorColor = Palette.gold),
            modifier = Modifier.fillMaxWidth().focusRequester(inputFocus).bringIntoViewRequester(bring)
                .semantics { contentDescription = com.majlisk.app.i18n.tr("اكتب رسالة") },
        )
        PrimaryButton("إرسال", { conn.sendChat(text); text = "" }, enabled = text.isNotBlank())
        SecondaryButton("إغلاق", onClose, fill = true)
    }
}

/**
 * الدردشة تحت الطاولة: فوق مربع صغير بآخر الرسائل (ارتفاعه محدود، ما يوصل للأوراق، ويتمرر)،
 * وتحته خانة الكتابة وزر الإرسال جنب الميكروفون. تكتب وتضغط إرسال وتنرسل على طول
 */
@Composable
fun ChatBar(conn: TableConnection, mic: @Composable () -> Unit) {
    val messages by conn.chat.collectAsState()
    var text by remember { mutableStateOf("") }
    // الرسائل ظاهرة دائماً: ما فيه «غير مقروءة»
    androidx.compose.runtime.DisposableEffect(Unit) {
        conn.chatOpen = true
        onDispose { conn.chatOpen = false }
    }
    val send = { if (text.isNotBlank()) { conn.sendChat(text); text = "" } }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (messages.isNotEmpty()) {
            val list = androidx.compose.foundation.lazy.rememberLazyListState()
            LaunchedEffect(messages.size) { list.animateScrollToItem(messages.size - 1) }
            androidx.compose.foundation.lazy.LazyColumn(
                state = list,
                modifier = Modifier.fillMaxWidth().heightIn(max = 96.dp)
                    .background(androidx.compose.ui.graphics.Color(0x99000000), RoundedCornerShape(12.dp))
                    .border(1.dp, Palette.green700, RoundedCornerShape(12.dp))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                items(messages.size) { i ->
                    val m = messages[i]
                    Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = com.majlisk.app.i18n.tr("${if (m.mine) "أنت" else m.name}: ${m.text}") }) {
                        Text("${if (m.mine) "أنت" else m.name}: ", color = Palette.goldSoft, fontSize = 13.sp)
                        Text(m.text, color = Palette.text, fontSize = 13.sp)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.OutlinedTextField(
                value = text, onValueChange = { text = it.take(200) },
                placeholder = { Text("اكتب رسالة…", color = Palette.textDim, fontSize = 14.sp) },
                singleLine = true,
                textStyle = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, color = Palette.text),
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Send),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSend = { send() }),
                shape = RoundedCornerShape(22.dp),
                colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Palette.gold, unfocusedBorderColor = Palette.green700,
                    focusedContainerColor = Palette.green800, unfocusedContainerColor = Palette.green800, cursorColor = Palette.gold,
                ),
                modifier = Modifier.weight(1f).heightIn(min = 48.dp)
                    .semantics { contentDescription = com.majlisk.app.i18n.tr("اكتب رسالة") },
            )
            // زر الإرسال (مكان زر الدردشة)
            Text(
                "إرسال ➤", color = Palette.green900, fontSize = 13.sp,
                modifier = Modifier.heightIn(min = 44.dp)
                    .background(if (text.isNotBlank()) Palette.gold else Palette.goldSoft.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
                    .clickable { send() }
                    .clearAndSetSemantics { contentDescription = com.majlisk.app.i18n.tr("إرسال"); role = Role.Button; onClick { send(); true } }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
            )
            mic()
        }
    }
}
