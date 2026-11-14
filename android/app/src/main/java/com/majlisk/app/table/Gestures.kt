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

/** معالج الإيماءات الحالي: اللوحة المعروضة تسجّل قراءاتها، وشاشة الطاولة كلها تلتقط السحب */
object TableGestures {
    @Volatile var handler: ((SwipeDir) -> Unit)? = null
    /** كم نافذة مفتوحة فوق الطاولة (القائمة، اللاعبون، الأصدقاء...): وقتها إيماءات اللعبة واقفة */
    @Volatile var openDialogs = 0
}

/**
 * لوحة اللعبة تسجّل قراءاتها للإيماءات (آخر نسخة دائماً)، وتنمسح لما تختفي اللوحة
 * (تغيير اللعبة أو الرجوع للمقاعد) فما تنقرأ لعبة سابقة أبداً.
 */
@Composable
fun Modifier.twoFingerSwipes(onSwipe: (SwipeDir) -> Unit): Modifier {
    val latest = rememberUpdatedState(onSwipe)
    androidx.compose.runtime.DisposableEffect(Unit) {
        val h: (SwipeDir) -> Unit = { latest.value(it) }
        TableGestures.handler = h
        onDispose { if (TableGestures.handler === h) TableGestures.handler = null }
    }
    return this
}

/**
 * إيماءات القراءة السريعة بإصبعين، في أي مكان في شاشة الطاولة. مع TalkBack: النظام يستهلك إيماءات
 * الإصبع الواحد، ويمرر سحب الإصبعين للتطبيق كإصبع واحد في المنتصف، فأي سحب يصلنا وقتها هو سحب بإصبعين.
 * نراقب اللمس فقط دون أن نستهلكه، فالأزرار تعمل كالمعتاد.
 */
@Composable
fun Modifier.tableGestureArea(): Modifier {
    val min = with(LocalDensity.current) { 30f * density }
    return this.pointerInput(Unit) {
        awaitPointerEventScope {
            var start: Offset? = null
            var last = Offset.Zero
            var startTime = 0L
            var prevCount = 0
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val down = event.changes.filter { it.pressed }
                val ok = down.size == 2 || (down.size == 1 && Announcer.readerOn)
                if (ok) {
                    val mid = Offset(down.map { it.position.x }.average().toFloat(), down.map { it.position.y }.average().toFloat())
                    // بداية اللمس، أو نزل الإصبع الثاني بعد الأول: نبدأ القياس من منتصف الأصابع الحالية
                    if (start == null || down.size > prevCount) { start = mid; startTime = System.currentTimeMillis() }
                    last = mid
                } else if (down.size > 2) {
                    start = null
                } else if (down.isEmpty()) {
                    val s = start
                    val end = last
                    start = null
                    if (s != null && System.currentTimeMillis() - startTime < 1500) {
                        if (TableGestures.openDialogs == 0) swipeDir(end.x - s.x, end.y - s.y, min)?.let { TableGestures.handler?.invoke(it) }
                    }
                }
                prevCount = down.size
            }
        }
    }
}
