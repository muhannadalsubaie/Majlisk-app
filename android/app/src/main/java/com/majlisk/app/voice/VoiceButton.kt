package com.majlisk.app.voice

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.unit.sp
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
    val toggleMute = {
        if (!s.busy) {
            // خرجت بنفسك: الضغطة العادية لا تعيدك، العودة بالضغط المطول فقط
            if (!s.joined) Announcer.announce("أنت خارج المحادثة الصوتية")
            else Voice.setMuted(!s.muted)
        }
    }
    val toggleJoin = { if (!s.busy) { if (s.joined) Voice.leave() else Voice.join(tableId, uid) } }
    // نفس ألوان زر الميكروفون في التطبيق الحالي: ذهبي مفتوح، وأخضر بإطار ذهبي مغلق، وباهت خارج المحادثة
    val bg = if (s.joined && !s.muted) Palette.gold else Palette.green700
    val fg = when { !s.joined -> Palette.textDim; s.muted -> Palette.gold; else -> Palette.green900 }
    val borderWidth = if (s.joined && s.muted) 2.dp else 1.dp
    Text(
        "🎤 $status",
        color = fg,
        fontSize = 13.sp,
        lineHeight = 17.sp,
        modifier = Modifier.widthIn(max = 200.dp).heightIn(min = 40.dp)
            .background(bg, RoundedCornerShape(20.dp))
            .border(borderWidth, Palette.gold, RoundedCornerShape(20.dp))
            .combinedClickable(onClick = toggleMute, onLongClick = toggleJoin)
            .semantics {
                contentDescription = status
                role = Role.Button
                onClick { toggleMute(); true }
                onLongClick { toggleJoin(); true }
            }
            .padding(horizontal = 12.dp, vertical = 10.dp),
    )
}
