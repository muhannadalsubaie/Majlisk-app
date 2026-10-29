package com.majlisk.app.table

import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
import com.majlisk.app.a11y.Announcer
import kotlin.math.abs

enum class SwipeDir { Left, Right, Up, Down }

/** اتجاه السحب: Left = من اليمين لليسار، Up = من تحت لفوق (نفس قواعد التطبيق الحالي) */
fun swipeDir(dx: Float, dy: Float, min: Float): SwipeDir? = when {
    abs(dx) >= min && abs(dy) < abs(dx) * 0.6f -> if (dx < 0) SwipeDir.Left else SwipeDir.Right
    abs(dy) >= min && abs(dx) < abs(dy) * 0.6f -> if (dy < 0) SwipeDir.Up else SwipeDir.Down
    else -> null
}

/**
 * إيماءات القراءة السريعة بإصبعين. مع TalkBack: النظام يستهلك إيماءات الإصبع الواحد،
 * ويمرر سحب الإصبعين للتطبيق كإصبع واحد في المنتصف، فأي سحب يصلنا وقتها هو سحب بإصبعين.
 * نراقب اللمس فقط دون أن نستهلكه، فالأزرار تعمل كالمعتاد.
 */
@Composable
fun Modifier.twoFingerSwipes(onSwipe: (SwipeDir) -> Unit): Modifier {
    val min = with(LocalDensity.current) { 40f * density }
    // آخر نسخة من القراءات (حالة اللعب الحالية)، لا النسخة وقت أول رسم للشاشة
    val latest = rememberUpdatedState(onSwipe)
    return this.pointerInput(Unit) {
        awaitPointerEventScope {
            var start: Offset? = null
            var last = Offset.Zero
            var startTime = 0L
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val down = event.changes.filter { it.pressed }
                val ok = down.size == 2 || (down.size == 1 && Announcer.readerOn)
                if (ok) {
                    val mid = Offset(down.map { it.position.x }.average().toFloat(), down.map { it.position.y }.average().toFloat())
                    if (start == null) { start = mid; startTime = System.currentTimeMillis() }
                    last = mid
                } else if (down.size > 2) {
                    start = null
                } else if (down.isEmpty()) {
                    val s = start
                    start = null
                    if (s != null && System.currentTimeMillis() - startTime < 1200) {
                        swipeDir(last.x - s.x, last.y - s.y, min)?.let { latest.value(it) }
                    }
                }
            }
        }
    }
}
