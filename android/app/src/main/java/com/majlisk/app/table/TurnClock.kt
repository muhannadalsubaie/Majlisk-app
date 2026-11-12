package com.majlisk.app.table

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.model.TableView
import com.majlisk.app.ui.Palette
import kotlinx.coroutines.delay

/** خيارات مؤقت الدور اللي يختارها المالك لما يبدأ المباراة (٠ = بدون وقت) */
val TURN_LIMITS = listOf(0, 10, 20, 30, 40, 50, 60)
fun turnLimitLabel(s: Int) = if (s == 0) "بدون وقت" else "$s ثانية"

/**
 * ساعة جنب اسم اللي عليه الدور: تعد تنازلياً لو المالك اختار وقت، وبدون رقم لو ما فيه وقت.
 * لك أنت: قارئ الشاشة يقول «باقي ٥ ثواني» قبل ما يلعب عنك الروبوت
 */
@Composable
fun TurnClock(v: TableView, seat: Int, turn: Boolean) {
    if (!turn) return
    val deadline = if (v.clockLimit > 0 && v.clockSeat == seat) v.clockDeadline else null
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(deadline) {
        var warned = false
        while (deadline != null) {
            now = System.currentTimeMillis()
            val left = deadline - now
            if (!warned && seat == v.mySeat && left in 1..5_000) { warned = true; Announcer.announce("باقي ٥ ثواني") }
            if (left <= 0) break
            delay(250)
        }
    }
    val secs = deadline?.let { ((it - now + 999) / 1000).coerceAtLeast(0) }
    Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("⏱", fontSize = 13.sp)
        if (secs != null) Text("$secs", color = if (secs <= 5) Palette.goldSoft else Palette.text, fontSize = 13.sp, fontWeight = FontWeight.Bold)
    }
}
