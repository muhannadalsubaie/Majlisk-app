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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
            .clearAndSetSemantics { contentDescription = label; role = Role.Button; onClick { onOpen(); true } }
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
@Composable
fun ChatDialog(conn: TableConnection, onClose: () -> Unit) {
    val messages by conn.chat.collectAsState()
    var text by remember { mutableStateOf("") }
    MajliskDialog("الدردشة", onClose) {
        if (messages.isEmpty()) Note("ما فيه رسائل بعد.")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            messages.forEach { m ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.mine) Arrangement.End else Arrangement.Start) {
                    Column(
                        Modifier.widthIn(max = 300.dp)
                            .background(if (m.mine) androidx.compose.ui.graphics.Color(0xFF3B5E2E) else Palette.green700, RoundedCornerShape(12.dp))
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                            .semantics(mergeDescendants = true) { contentDescription = "${if (m.mine) "أنت" else m.name}: ${m.text}" },
                    ) {
                        Text(if (m.mine) "أنت" else m.name, color = Palette.goldSoft, fontSize = 12.sp)
                        Text(m.text, color = Palette.text, fontSize = 15.sp)
                    }
                }
            }
        }
        Field("اكتب رسالة…", text, { text = it.take(200) })
        PrimaryButton("إرسال", { conn.sendChat(text); text = "" }, enabled = text.isNotBlank())
        SecondaryButton("إغلاق", onClose, fill = true)
    }
}
