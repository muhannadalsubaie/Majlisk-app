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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.focusable
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.ui.Palette

/**
 * بعد ما تلعب ورقة: مؤشر قارئ الشاشة ينتقل لزر الميكروفون بصمت (اسمه مخفي لحظات)،
 * فتسمع ورقتك وباقي اللعب بدل اسم الزر، ويُقرأ عادي لما تحرك المؤشر.
 */
object MicFocus {
    var requester: androidx.compose.ui.focus.FocusRequester? = null
    val silent = androidx.compose.runtime.mutableStateOf(false)
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    fun take() {
        val r = requester ?: return
        if (!Announcer.readerOn) return
        silent.value = true
        Announcer.interruptNextEvents()
        runCatching { r.requestFocus() }
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ silent.value = false }, 4000)
    }
}

/**
 * زر المحادثة الصوتية — للاعبين والمشاهدين.
 * ضغطة: فتح/كتم الميكروفون. ضغطة مطولة (ومع TalkBack: نقر مرتين مع الإبقاء): انضمام/مغادرة.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun VoiceButton(tableId: String, uid: String) {
    val raw by Voice.state.collectAsState()
    // أثناء إعادة الاتصال الصامتة يبقى الزر على حاله: في المحادثة والميكروفون مغلق
    val s = if (raw.reconnecting) raw.copy(joined = true, muted = true, busy = false) else raw
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
    val fr = androidx.compose.runtime.remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.runtime.DisposableEffect(Unit) {
        MicFocus.requester = fr
        onDispose { if (MicFocus.requester === fr) MicFocus.requester = null }
    }
    val silent by MicFocus.silent
    Text(
        "🎤 $status",
        color = fg,
        fontSize = 13.sp,
        lineHeight = 17.sp,
        modifier = Modifier.widthIn(max = 200.dp).heightIn(min = 40.dp)
            .background(bg, RoundedCornerShape(20.dp))
            .border(borderWidth, Palette.gold, RoundedCornerShape(20.dp))
            .focusRequester(fr)
            .focusable()
            .combinedClickable(onClick = toggleMute, onLongClick = toggleJoin)
            // صامت بعد لعب ورقة: بلا أي نص؛ وإلا حالته وإجراءاته
            .clearAndSetSemantics {
                if (!silent) {
                    contentDescription = status
                    role = Role.Button
                    onClick { toggleMute(); true }
                    onLongClick { toggleJoin(); true }
                }
            }
            .padding(horizontal = 12.dp, vertical = 10.dp),
    )
}
