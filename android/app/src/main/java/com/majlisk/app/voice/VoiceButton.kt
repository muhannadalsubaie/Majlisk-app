package com.majlisk.app.voice

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.ui.Palette

/**
 * زر المحادثة الصوتية — للاعبين والمشاهدين.
 * ضغطة: فتح/كتم الميكروفون. ضغطة مطولة (ومع TalkBack: نقر مرتين مع الإبقاء): انضمام/مغادرة.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun VoiceButton(tableId: String, uid: String) {
    val s by Voice.state.collectAsState()
    val status = when {
        s.busy -> "جارٍ الاتصال بالمحادثة الصوتية"
        !s.joined -> "أنت خارج المحادثة الصوتية"
        s.muted -> "الميكروفون مغلق"
        else -> "الميكروفون مفتوح"
    }
    val hint = when {
        s.busy -> ""
        !s.joined -> "اضغط مطولاً للعودة إليها"
        s.muted -> "اضغط لفتحه، أو مطولاً للخروج من المحادثة"
        else -> "اضغط لإغلاقه، أو مطولاً للخروج من المحادثة"
    }
    val toggleMute = {
        if (!s.busy) {
            // خرجت بنفسك: الضغطة العادية لا تعيدك، العودة بالضغط المطول فقط
            if (!s.joined) Announcer.announce("أنت خارج المحادثة الصوتية. اضغط مطولاً للعودة إليها")
            else Voice.setMuted(!s.muted)
        }
    }
    val toggleJoin = { if (!s.busy) { if (s.joined) Voice.leave() else Voice.join(tableId, uid) } }
    val bg = when { !s.joined -> Palette.green800; s.muted -> Palette.green700; else -> Palette.gold }
    Text(
        "🎤 $status",
        color = if (s.joined && !s.muted) Palette.green900 else Palette.text,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
            .background(bg, RoundedCornerShape(26.dp))
            .combinedClickable(onClick = toggleMute, onLongClick = toggleJoin)
            .semantics {
                contentDescription = if (hint.isNotEmpty()) "$status، $hint" else status
                role = Role.Button
                onClick(label = if (s.muted) "فتح الميكروفون" else "إغلاق الميكروفون") { toggleMute(); true }
                onLongClick(label = if (s.joined) "الخروج من المحادثة" else "العودة للمحادثة") { toggleJoin(); true }
            }
            .padding(14.dp)
            .wrapContentHeight(),
    )
}
