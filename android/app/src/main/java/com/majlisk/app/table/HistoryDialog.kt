package com.majlisk.app.table

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.majlisk.app.model.HandRecord
import com.majlisk.app.ui.Body
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.SecondaryButton

private val LEVELS = mapOf(2 to "دبل", 3 to "ثري", 4 to "فور")

/** سجل المباراة: كل صكة بأبناطها ثم مشاريعها ثم نقاطها، كلٌّ في سطر — فقرة واحدة تُقرأ دفعة واحدة */
@Composable
fun HistoryDialog(history: List<HandRecord>, onClose: () -> Unit) {
    MajliskDialog("السجل", onClose) {
        if (history.isEmpty()) Body("لم تنتهِ أي صكة بعد")
        history.groupBy { it.match }.toSortedMap(compareByDescending { it }).forEach { (match, hands) ->
            val t0 = hands.sumOf { it.points.getOrElse(0) { 0 } }
            val t1 = hands.sumOf { it.points.getOrElse(1) { 0 } }
            val teams = hands.first().teams
            Text("المباراة $match: ${teams.getOrElse(0) { "" }} $t0، ${teams.getOrElse(1) { "" }} $t1", color = Palette.goldSoft, modifier = Modifier.semantics { heading() })
            hands.forEachIndexed { i, r ->
                val level = if (r.gahwa) "قهوة" else LEVELS[r.level].orEmpty()
                val winner = r.kaboot ?: if (r.buyerFailed) 1 - r.buyerTeam else r.buyerTeam
                val tm = { x: Int -> r.teams.getOrElse(x) { "" } }
                val projects = r.projects?.takeIf { it.getOrElse(0) { 0 } != 0 || it.getOrElse(1) { 0 } != 0 }
                    ?.let { "${tm(0)} ${it[0]}، ${tm(1)} ${it[1]}" } ?: "لا توجد"
                val lines = listOf(
                    "الصكة ${i + 1}: ${r.contract}${if (level.isNotEmpty()) " $level" else ""}${if (r.kaboot != null) "، كبوت" else ""}.",
                    "المشتري: ${r.buyer} (${tm(r.buyerTeam)}).",
                    "الأبناط: ${tm(0)} ${r.abnat.getOrElse(0) { 0 }}، ${tm(1)} ${r.abnat.getOrElse(1) { 0 }}.",
                    "المشاريع: $projects.",
                    "النقاط: ${tm(0)} ${r.points.getOrElse(0) { 0 }}، ${tm(1)} ${r.points.getOrElse(1) { 0 }}.",
                    "الخاسر: ${tm(1 - winner)}${if (r.buyerFailed && r.kaboot == null) " (خسر المشتري)" else ""}.",
                )
                Text(lines.joinToString("\n"), color = Palette.text, modifier = Modifier.fillMaxWidth().background(Palette.green900, RoundedCornerShape(10.dp)).padding(10.dp))
            }
        }
        SecondaryButton("إغلاق", onClose, fill = true)
    }
}
