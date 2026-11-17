package com.majlisk.app.table

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Sounds
import com.majlisk.app.data.TableConnection
import com.majlisk.app.i18n.Text
import com.majlisk.app.model.MALLAK_BOARD
import com.majlisk.app.model.MALLAK_GROUP_COLORS
import com.majlisk.app.model.MALLAK_PLAYER_COLORS
import com.majlisk.app.model.MALLAK_PLAYER_COLOR_NAMES
import com.majlisk.app.model.MallakView
import com.majlisk.app.model.TableView
import com.majlisk.app.net.jsonOf
import com.majlisk.app.ui.MajliskDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.SecondaryButton
import com.majlisk.app.ui.SmallButton
import com.majlisk.app.ui.SwitchRow
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// ═════════════ ملّاك: لوحة ثلاثية الأبعاد (رسم خفيف بدون محرك) + أزرار وقوائم لقارئ الشاشة ═════════════

private fun mallakAct(conn: TableConnection, type: String, vararg extra: Pair<String, Any?>) =
    conn.send(jsonOf("type" to "mallak", "action" to jsonOf("type" to type, *extra)))

// ───── رياضيات الثلاثي الأبعاد ─────

private data class V3(val x: Float, val y: Float, val z: Float) {
    operator fun plus(o: V3) = V3(x + o.x, y + o.y, z + o.z)
    operator fun minus(o: V3) = V3(x - o.x, y - o.y, z - o.z)
    operator fun times(k: Float) = V3(x * k, y * k, z * k)
    fun dot(o: V3) = x * o.x + y * o.y + z * o.z
    fun cross(o: V3) = V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    fun norm(): V3 { val l = sqrt(dot(this)); return if (l == 0f) this else this * (1f / l) }
}

/** الكاميرا تدور حول وسط اللوحة: yaw حول المحور العمودي، وpitch زاوية النظر من فوق */
private class Cam(yaw: Float, pitch: Float, val size: Size) {
    private val dist = 19f
    val eye = V3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
    private val f = (V3(0f, 0f, 0f) - eye).norm()
    private val r = f.cross(V3(0f, 1f, 0f)).norm()
    private val u = r.cross(f)
    private val focal = size.minDimension * 0.98f
    private val c = Offset(size.width / 2, size.height * 0.4f)
    fun depth(p: V3) = (p - eye).dot(f)
    fun scale(p: V3) = focal / max(0.5f, depth(p))
    fun project(p: V3): Offset {
        val d = p - eye
        val z = max(0.5f, d.dot(f))
        return Offset(c.x + d.dot(r) / z * focal, c.y - d.dot(u) / z * focal)
    }
    /** الوجه يواجه الكاميرا؟ */
    fun facing(center: V3, normal: V3) = normal.dot(eye - center) > 0
}

/** نقطة على سطح اللوحة: (u أفقي، v للأمام)، y ارتفاع */
private fun bp(u: Float, v: Float, y: Float = 0f) = V3(u, y, v)

/** حدود الخانة على اللوحة (u0..u1، v0..v1) والجهة: 0 تحت، 1 يسار، 2 فوق، 3 يمين، -1 زاوية */
private data class Cell(val u0: Float, val u1: Float, val v0: Float, val v1: Float, val side: Int) {
    val cu get() = (u0 + u1) / 2
    val cv get() = (v0 + v1) / 2
}

private fun cell(i: Int): Cell = when {
    i == 0 -> Cell(4.5f, 6.5f, 4.5f, 6.5f, -1)
    i < 10 -> { val c = 5f - i; Cell(c - 0.5f, c + 0.5f, 4.5f, 6.5f, 0) }
    i == 10 -> Cell(-6.5f, -4.5f, 4.5f, 6.5f, -1)
    i < 20 -> { val c = 5f - (i - 10); Cell(-6.5f, -4.5f, c - 0.5f, c + 0.5f, 1) }
    i == 20 -> Cell(-6.5f, -4.5f, -6.5f, -4.5f, -1)
    i < 30 -> { val c = -5f + (i - 20); Cell(c - 0.5f, c + 0.5f, -6.5f, -4.5f, 2) }
    i == 30 -> Cell(4.5f, 6.5f, -6.5f, -4.5f, -1)
    else -> { val c = -5f + (i - 30); Cell(4.5f, 6.5f, c - 0.5f, c + 0.5f, 3) }
}

/** شريط لون المجموعة (على الحافة الداخلية للخانة) */
private fun band(c: Cell): Cell = when (c.side) {
    0 -> c.copy(v1 = c.v0 + 0.45f)
    1 -> c.copy(u0 = c.u1 - 0.45f)
    2 -> c.copy(v0 = c.v1 - 0.45f)
    3 -> c.copy(u1 = c.u0 + 0.45f)
    else -> c
}

/** علامة المالك (على الحافة الخارجية) */
private fun ownerStrip(c: Cell): Cell = when (c.side) {
    0 -> c.copy(v0 = c.v1 - 0.18f)
    1 -> c.copy(u1 = c.u0 + 0.18f)
    2 -> c.copy(v1 = c.v0 + 0.18f)
    3 -> c.copy(u0 = c.u1 - 0.18f)
    else -> c
}

/** مكان الحجر في الخانة (بعيد عن شريط اللون)، وكل لاعب له مكان صغير */
private fun pawnSpot(i: Int, slot: Int): Pair<Float, Float> {
    val c = cell(i)
    val (bu, bv) = when (c.side) { 0 -> 0f to 0.25f; 1 -> -0.25f to 0f; 2 -> 0f to -0.25f; 3 -> 0.25f to 0f; else -> 0f to 0.4f }
    val span = if (c.side < 0) 0.42f else 0.22f
    val du = ((slot % 3) - 1) * span
    val dv = ((slot / 3) - 0.5f) * span * 1.4f
    // الخانات الجانبية: نقلب الصفوف على طولها
    return if (c.side == 1 || c.side == 3) (c.cu + bu + dv) to (c.cv + bv + du) else (c.cu + bu + du) to (c.cv + bv + dv)
}

/** مكان اسم الخانة (k=0) وسعرها (k=1): بعيد عن شريط اللون، والسعر تحت الاسم */
private fun textSpot(i: Int, k: Int): Pair<Float, Float> {
    val c = cell(i)
    val (ou, ov) = when (c.side) { 0 -> 0f to 0.22f; 1 -> -0.22f to 0f; 2 -> 0f to -0.22f; else -> 0.22f to 0f }
    val u = c.cu + ou; val v = c.cv + ov
    return if (c.side == 1 || c.side == 3) u to v + (if (k == 1) 0.24f else -0.14f) else u to v + (if (k == 1) 0.38f else -0.2f)
}

private fun DrawScope.quad(cam: Cam, c: Cell, y: Float, color: Color) {
    val p = Path().apply {
        val a = cam.project(bp(c.u0, c.v0, y)); moveTo(a.x, a.y)
        val b = cam.project(bp(c.u1, c.v0, y)); lineTo(b.x, b.y)
        val d = cam.project(bp(c.u1, c.v1, y)); lineTo(d.x, d.y)
        val e = cam.project(bp(c.u0, c.v1, y)); lineTo(e.x, e.y)
        close()
    }
    drawPath(p, color)
}

private fun shade(c: Color, k: Float) = Color(c.red * k, c.green * k, c.blue * k, c.alpha)

/** صندوق ثلاثي (بيت أو برج): الوجوه المواجهة للكاميرا بس، مع إضاءة بسيطة */
private fun DrawScope.box(cam: Cam, u: Float, v: Float, w: Float, h: Float, d: Float, color: Color) {
    val x0 = u - w / 2; val x1 = u + w / 2; val z0 = v - d / 2; val z1 = v + d / 2
    val faces = listOf(
        Triple(listOf(V3(x0, h, z0), V3(x1, h, z0), V3(x1, h, z1), V3(x0, h, z1)), V3(0f, 1f, 0f), 1f),
        Triple(listOf(V3(x0, 0f, z1), V3(x1, 0f, z1), V3(x1, h, z1), V3(x0, h, z1)), V3(0f, 0f, 1f), 0.8f),
        Triple(listOf(V3(x0, 0f, z0), V3(x1, 0f, z0), V3(x1, h, z0), V3(x0, h, z0)), V3(0f, 0f, -1f), 0.65f),
        Triple(listOf(V3(x1, 0f, z0), V3(x1, 0f, z1), V3(x1, h, z1), V3(x1, h, z0)), V3(1f, 0f, 0f), 0.72f),
        Triple(listOf(V3(x0, 0f, z0), V3(x0, 0f, z1), V3(x0, h, z1), V3(x0, h, z0)), V3(-1f, 0f, 0f), 0.72f),
    )
    for ((pts, n, k) in faces) {
        val center = V3(pts.sumOf { it.x.toDouble() }.toFloat() / 4, pts.sumOf { it.y.toDouble() }.toFloat() / 4, pts.sumOf { it.z.toDouble() }.toFloat() / 4)
        if (!cam.facing(center, n)) continue
        val path = Path()
        pts.forEachIndexed { idx, p -> val s = cam.project(p); if (idx == 0) path.moveTo(s.x, s.y) else path.lineTo(s.x, s.y) }
        path.close()
        drawPath(path, shade(color, k))
        drawPath(path, Color.Black.copy(alpha = 0.25f), style = Stroke(1f))
    }
}

/** حجر اللاعب: ظل وقاعدة ورأس كروي بلمعة (حجمه حسب بعده عن الكاميرا) */
private fun DrawScope.pawn(cam: Cam, u: Float, v: Float, lift: Float, color: Color) {
    val base = cam.project(bp(u, v, 0f))
    val s = cam.scale(bp(u, v, 0f)) * 0.2f
    drawOval(Color.Black.copy(alpha = 0.35f * (1f - lift * 0.4f)), Offset(base.x - s, base.y - s * 0.35f), Size(s * 2, s * 0.7f))
    val top = cam.project(bp(u, v, 0.35f + lift * 0.6f))
    val dark = shade(color, 0.5f)
    val light = Color(color.red + (1 - color.red) * 0.6f, color.green + (1 - color.green) * 0.6f, color.blue + (1 - color.blue) * 0.6f)
    val body = Path().apply {
        val b = cam.project(bp(u, v, lift * 0.6f))
        moveTo(b.x - s * 0.8f, b.y); lineTo(b.x + s * 0.8f, b.y)
        lineTo(top.x + s * 0.35f, top.y + s * 0.4f); lineTo(top.x - s * 0.35f, top.y + s * 0.4f); close()
    }
    drawPath(body, Brush.horizontalGradient(listOf(light, color, dark), top.x - s, top.x + s))
    drawCircle(Brush.radialGradient(listOf(light, color, dark), Offset(top.x - s * 0.25f, top.y - s * 0.3f), s * 0.9f), s * 0.62f, top)
    drawCircle(Color.White.copy(alpha = 0.7f), s * 0.14f, Offset(top.x - s * 0.22f, top.y - s * 0.25f))
}

// ───── النرد الثلاثي ─────

/** الوجه اللي فوق لكل رقم (دوران المكعب): 1 فوق، 6 تحت، 2 قدام، 5 ورا، 3 يمين، 4 يسار */
private fun rotX(p: V3, a: Float) = V3(p.x, p.y * cos(a) - p.z * sin(a), p.y * sin(a) + p.z * cos(a))
private fun rotY(p: V3, a: Float) = V3(p.x * cos(a) + p.z * sin(a), p.y, -p.x * sin(a) + p.z * cos(a))
private fun rotZ(p: V3, a: Float) = V3(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a), p.z)
private fun faceUp(p: V3, value: Int): V3 = when (value) {
    6 -> rotX(p, PI.toFloat())
    2 -> rotX(p, -PI.toFloat() / 2)
    5 -> rotX(p, PI.toFloat() / 2)
    3 -> rotZ(p, PI.toFloat() / 2)
    4 -> rotZ(p, -PI.toFloat() / 2)
    else -> p
}
private val PIPS = mapOf(
    1 to listOf(0f to 0f), 2 to listOf(-1f to -1f, 1f to 1f), 3 to listOf(-1f to -1f, 0f to 0f, 1f to 1f),
    4 to listOf(-1f to -1f, 1f to -1f, -1f to 1f, 1f to 1f), 5 to listOf(-1f to -1f, 1f to -1f, 0f to 0f, -1f to 1f, 1f to 1f),
    6 to listOf(-1f to -1f, 1f to -1f, -1f to 0f, 1f to 0f, -1f to 1f, 1f to 1f),
)

private fun DrawScope.die(cam: Cam, cx: Float, cz: Float, value: Int, spin: Float, yaw: Float) {
    val h = 0.45f
    // (الرقم، العمودي، محوري الوجه)
    val faces = listOf(
        Triple(1, V3(0f, 1f, 0f), V3(1f, 0f, 0f) to V3(0f, 0f, 1f)),
        Triple(6, V3(0f, -1f, 0f), V3(1f, 0f, 0f) to V3(0f, 0f, 1f)),
        Triple(2, V3(0f, 0f, 1f), V3(1f, 0f, 0f) to V3(0f, 1f, 0f)),
        Triple(5, V3(0f, 0f, -1f), V3(1f, 0f, 0f) to V3(0f, 1f, 0f)),
        Triple(3, V3(1f, 0f, 0f), V3(0f, 0f, 1f) to V3(0f, 1f, 0f)),
        Triple(4, V3(-1f, 0f, 0f), V3(0f, 0f, 1f) to V3(0f, 1f, 0f)),
    )
    val center = V3(cx, h + 0.05f + spin * 0.8f, cz)
    val tf = { p: V3 -> center + rotY(rotX(faceUp(p, value), spin * 9f), yaw + spin * 7f) }
    val tn = { p: V3 -> rotY(rotX(faceUp(p, value), spin * 9f), yaw + spin * 7f) }
    // نرسم الوجوه المواجهة (من الأبعد للأقرب)
    faces.map { (n, normal, axes) -> Triple(n, normal, axes) }
        .filter { (_, normal, _) -> cam.facing(tf(normal * h), tn(normal)) }
        .sortedByDescending { (_, normal, _) -> cam.depth(tf(normal * h)) }
        .forEach { (n, normal, axes) ->
            val (a, b) = axes
            val corners = listOf(-1f to -1f, 1f to -1f, 1f to 1f, -1f to 1f).map { (x, y) -> tf(normal * h + a * (x * h) + b * (y * h)) }
            val path = Path()
            corners.forEachIndexed { k, p -> val s = cam.project(p); if (k == 0) path.moveTo(s.x, s.y) else path.lineTo(s.x, s.y) }
            path.close()
            val light = 0.75f + 0.25f * max(0f, tn(normal).y)
            drawPath(path, Color(0xFFF7F3E8).copy(red = 0.97f * light, green = 0.95f * light, blue = 0.91f * light))
            drawPath(path, Color(0x55000000), style = Stroke(1.2f))
            for ((x, y) in PIPS[n].orEmpty()) {
                val p = tf(normal * (h * 1.001f) + a * (x * h * 0.5f) + b * (y * h * 0.5f))
                drawCircle(Color(0xFF1B1B1B), cam.scale(p) * h * 0.13f, cam.project(p))
            }
        }
}

// ───── رسم اللوحة كاملة ─────

private class Hop(val seat: Int, val path: List<Int>, val startAt: Long, val stepMs: Long) {
    val end get() = startAt + stepMs * (path.size - 1).coerceAtLeast(1)
}

private val textPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { textAlign = android.graphics.Paint.Align.CENTER }

private fun DrawScope.label(cam: Cam, u: Float, v: Float, text: String, worldSize: Float, color: Color, bold: Boolean = false, maxWidth: Float = Float.MAX_VALUE) {
    val p = bp(u, v, 0.02f)
    var px = cam.scale(p) * worldSize
    if (px < 7f) return
    textPaint.color = color.toArgb()
    textPaint.isFakeBoldText = bold
    textPaint.textSize = px
    var lines = listOf(text)
    var w = textPaint.measureText(text)
    // أعرض من الخانة: نقسمه سطرين (عند المسافة اللي تعطي أقصر سطر)
    if (w > maxWidth && text.contains(' ')) {
        val words = text.split(' ')
        val best = (1 until words.size).map { k -> listOf(words.take(k).joinToString(" "), words.drop(k).joinToString(" ")) }
            .minByOrNull { pair -> pair.maxOf { textPaint.measureText(it) } }!!
        lines = best; w = best.maxOf { textPaint.measureText(it) }
    }
    if (w > maxWidth) { px *= maxWidth / w; if (px < 6f) return; textPaint.textSize = px }
    val s = cam.project(p)
    lines.forEachIndexed { k, line -> drawContext.canvas.nativeCanvas.drawText(line, s.x, s.y + px / 3 + (k - (lines.size - 1) / 2f) * px * 1.05f, textPaint) }
}

private fun DrawScope.drawMallak(m: MallakView, yaw: Float, pitch: Float, hops: Map<Int, Hop>, now: Long, diceSpin: Float) {
    val cam = Cam(yaw, pitch, size)
    // القاعدة: صندوق اللوحة (جوانب أغمق)
    box(cam, 0f, 0f, 13.4f, 0.0001f, 13.4f, Color(0xFF6B4A2B))
    val sideColor = Color(0xFF3E2A17)
    run {
        val h = -0.45f
        val sides = listOf(
            listOf(bp(-6.7f, 6.7f), bp(6.7f, 6.7f), bp(6.7f, 6.7f, h), bp(-6.7f, 6.7f, h)) to V3(0f, 0f, 1f),
            listOf(bp(-6.7f, -6.7f), bp(6.7f, -6.7f), bp(6.7f, -6.7f, h), bp(-6.7f, -6.7f, h)) to V3(0f, 0f, -1f),
            listOf(bp(6.7f, -6.7f), bp(6.7f, 6.7f), bp(6.7f, 6.7f, h), bp(6.7f, -6.7f, h)) to V3(1f, 0f, 0f),
            listOf(bp(-6.7f, -6.7f), bp(-6.7f, 6.7f), bp(-6.7f, 6.7f, h), bp(-6.7f, -6.7f, h)) to V3(-1f, 0f, 0f),
        )
        for ((pts, n) in sides) {
            val c = V3(pts.map { it.x }.average().toFloat(), h / 2, pts.map { it.z }.average().toFloat())
            if (!cam.facing(c, n)) continue
            val path = Path(); pts.forEachIndexed { k, p -> val s = cam.project(p); if (k == 0) path.moveTo(s.x, s.y) else path.lineTo(s.x, s.y) }; path.close()
            drawPath(path, sideColor)
        }
    }
    quad(cam, Cell(-6.5f, 6.5f, -6.5f, 6.5f, -1), 0.001f, Color(0xFFE9F1E2))
    // الوسط: لون أغمق واسم اللعبة
    quad(cam, Cell(-4.5f, 4.5f, -4.5f, 4.5f, -1), 0.002f, Color(0xFF1F5E43))
    label(cam, 0f, -1.6f, com.majlisk.app.i18n.tr("تاجر العقار"), 0.8f, Color(0xFFF5D67B), bold = true)
    // الخانات
    for (i in 0 until 40) {
        val c = cell(i)
        val sq = MALLAK_BOARD[i]
        quad(cam, c, 0.003f, if (c.side < 0) Color(0xFFF3ECD8) else Color(0xFFFBF7EC))
        val o = m.owner.getOrNull(i)
        if (sq.kind == "city") quad(cam, band(c), 0.004f, Color(MALLAK_GROUP_COLORS[sq.group]))
        if (o != null) quad(cam, ownerStrip(c), 0.004f, Color(MALLAK_PLAYER_COLORS[o % 6]))
        if (m.mortgaged.getOrNull(i) == true) quad(cam, c, 0.005f, Color(0x88808080))
        // حدود الخانة
        val pts = listOf(bp(c.u0, c.v0, 0.006f), bp(c.u1, c.v0, 0.006f), bp(c.u1, c.v1, 0.006f), bp(c.u0, c.v1, 0.006f)).map(cam::project)
        val border = Path().apply { moveTo(pts[0].x, pts[0].y); pts.drop(1).forEach { lineTo(it.x, it.y) }; close() }
        drawPath(border, Color(0x55203020), style = Stroke(1f))
        // الاسم والسعر
        val (lu, lv) = if (c.side < 0) c.cu to c.cv - 0.45f else textSpot(i, 0)
        val width = cam.scale(bp(c.cu, c.cv)) * (if (c.side < 0) 1.9f else if (c.side == 1 || c.side == 3) 1.45f else 0.92f)
        val icon = when (sq.kind) { "chance" -> "؟ "; "chest" -> "📦 "; "station" -> "✈ "; "utility" -> "⚡ "; "tax" -> "💰 "; "jail" -> "🔒 "; "goToJail" -> "👮 "; "rest" -> "☕ "; "go" -> "➜ "; else -> "" }
        label(cam, lu, lv, icon + com.majlisk.app.i18n.tr(sq.name), if (c.side < 0) 0.3f else 0.2f, Color(0xFF1D2B22), bold = c.side < 0, maxWidth = width)
        if (sq.price > 0 && o == null) {
            val (pu, pv) = if (c.side < 0) c.cu to c.cv + 0.3f else textSpot(i, 1)
            label(cam, pu, pv, "${sq.price}", 0.17f, Color(0xFF55605A), maxWidth = width)
        }
    }
    // البيوت والأبراج على شريط اللون
    for (i in 0 until 40) {
        val n = m.houses.getOrNull(i) ?: 0
        if (n == 0) continue
        val b = band(cell(i))
        if (n == 5) { box(cam, b.cu, b.cv, 0.38f, 0.55f, 0.32f, Color(0xFFC62828)); continue }
        for (k in 0 until n) {
            val t = (k - (n - 1) / 2f) * 0.22f
            val (u, v) = if (cell(i).side == 1 || cell(i).side == 3) b.cu to b.cv + t else b.cu + t to b.cv
            box(cam, u, v, 0.17f, 0.2f, 0.17f, Color(0xFF2E7D32))
        }
    }
    // الأحجار (الأبعد أول)
    val pawns = m.seats.filter { m.players.getOrNull(it)?.bankrupt == false }.map { seat ->
        val p = m.players[seat]!!
        val hop = hops[seat]
        var lift = 0f
        val slot = m.seats.indexOf(seat)
        val (u, v) = if (hop != null && now < hop.end && hop.path.size > 1) {
            val t = ((now - hop.startAt).toFloat() / hop.stepMs).coerceIn(0f, (hop.path.size - 1).toFloat())
            val k = min(t.toInt(), hop.path.size - 2)
            val f = t - k
            if (t > 0f) lift = sin(PI.toFloat() * f) * 0.6f
            val a = pawnSpot(hop.path[k], slot); val b = pawnSpot(hop.path[k + 1], slot)
            (a.first + (b.first - a.first) * f) to (a.second + (b.second - a.second) * f)
        } else pawnSpot(p.pos, slot)
        Triple(seat, Triple(u, v, lift), cam.depth(bp(u, v)))
    }.sortedByDescending { it.third }
    for ((seat, pos, _) in pawns) pawn(cam, pos.first, pos.second, pos.third, Color(MALLAK_PLAYER_COLORS[seat % 6]))
    // النرد في الوسط
    m.dice?.let { (a, b) ->
        die(cam, -0.75f, 0.9f, a, diceSpin, 0.35f)
        die(cam, 0.75f, 0.9f, b, diceSpin * 0.9f, -0.3f)
    }
}

/** أي خانة تحت اللمسة (للمس الخانة وقراءة تفاصيلها) */
private fun hitSquare(at: Offset, size: Size, yaw: Float, pitch: Float): Int? {
    val cam = Cam(yaw, pitch, size)
    for (i in 0 until 40) {
        val c = cell(i)
        val pts = listOf(bp(c.u0, c.v0), bp(c.u1, c.v0), bp(c.u1, c.v1), bp(c.u0, c.v1)).map(cam::project)
        var inside = false
        var j = pts.size - 1
        for (k in pts.indices) {
            val a = pts[k]; val b = pts[j]
            if ((a.y > at.y) != (b.y > at.y) && at.x < (b.x - a.x) * (at.y - a.y) / (b.y - a.y) + a.x) inside = !inside
            j = k
        }
        if (inside) return i
    }
    return null
}

// ───── الشاشة ─────

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MallakBoard(v: TableView, m: MallakView, conn: TableConnection, isOwner: Boolean) {
    val mySeat = v.mySeat
    val names = v.seats.mapIndexed { i, s -> s?.username ?: "المقعد ${i + 1}" }
    val reader = Announcer.readerOn
    var yaw by remember { mutableStateOf(0f) }
    var pitch by remember { mutableStateOf(0.98f) }
    // حركة الحجر خانة خانة (نفس توقيت صوت الخطوات)
    val hops = remember { mutableStateMapOf<Int, Hop>() }
    var clock by remember { mutableStateOf(System.nanoTime() / 1_000_000) }
    var seenMove by remember { mutableStateOf(m.moveSeq) }
    var seenRoll by remember { mutableStateOf(m.rollSeq) }
    var rollAt by remember { mutableStateOf(0L) }
    LaunchedEffect(m.rollSeq, m.moveSeq) {
        val now = System.nanoTime() / 1_000_000
        val rolledNow = m.rollSeq != seenRoll
        if (rolledNow) { seenRoll = m.rollSeq; rollAt = now }
        if (m.moveSeq != seenMove) {
            seenMove = m.moveSeq
            if (m.moveKind != "jail" && m.moveSeat >= 0) {
                val fwd = (m.moveTo - m.moveFrom + 40) % 40
                val back = m.moveKind == "card" && fwd > 20
                val n = if (back) 40 - fwd else fwd
                val path = (0..n).map { k -> ((if (back) m.moveFrom - k else m.moveFrom + k) % 40 + 40) % 40 }
                // المشي بنفس مهلة الخادم: 13 خطوة كحد (المشوار الطويل من البطاقة أسرع)
                val stepMs = if (n > 13) 2860L / n else (Sounds.STEP_GAP * 1000).toLong()
                hops[m.moveSeat] = Hop(m.moveSeat, path, now + if (rolledNow) 550L else 0L, stepMs)
            }
        }
    }
    val animating = hops.isNotEmpty() || clock - rollAt < 700
    LaunchedEffect(animating, hops.size, rollAt) {
        while (true) {
            withFrameNanos { clock = it / 1_000_000 }
            hops.entries.filter { clock >= it.value.end }.map { it.key }.forEach { hops.remove(it) }
            if (hops.isEmpty() && clock - rollAt >= 700) break
        }
    }
    val diceSpin = ((700 - (clock - rollAt)).coerceIn(0, 700) / 700f).let { it * it }

    var info by remember { mutableStateOf<Int?>(null) }
    var listOpen by remember { mutableStateOf(false) }
    var logOpen by remember { mutableStateOf(false) }
    var manageOpen by remember { mutableStateOf(false) }
    var tradeOpen by remember { mutableStateOf(false) }
    val me = mySeat?.let { m.playersUi.firstOrNull { p -> p.seat == it } }

    // سحب بإصبعين (قارئ الشاشة): فوق = الدور ومكانك، تحت = قائمة اللوحة، يسار = فلوسك وأملاكك، يمين = ارمِ النرد
    Column(
        Modifier.fillMaxWidth().twoFingerSwipes {
            when (it) {
                SwipeDir.Up -> Announcer.announceNow("${m.turnText}. ${m.hereText}")
                SwipeDir.Down -> listOpen = true
                SwipeDir.Left -> Announcer.announceNow(me?.text ?: m.turnText)
                SwipeDir.Right -> if (m.actions.any { a -> a.type == "roll" }) mallakAct(conn, "roll") else Announcer.announceNow(if (m.myTurn) m.prompt.ifEmpty { m.turnText } else m.turnText)
            }
        },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // اللاعبون: لون الحجر والاسم والفلوس (يتنقل بينهم قارئ الشاشة)
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            m.playersUi.forEach { p ->
                val turn = (p.seat == m.turn && m.phase != "over")
                Row(
                    Modifier.background(if (turn) Color(0x55D4AF37) else Color(0x33000000), RoundedCornerShape(12.dp))
                        .border(2.dp, if (turn) Palette.gold else Color.Transparent, RoundedCornerShape(12.dp))
                        .padding(horizontal = 8.dp, vertical = 5.dp)
                        .semantics(mergeDescendants = true) { contentDescription = com.majlisk.app.i18n.tr("${p.text}، ${MALLAK_PLAYER_COLOR_NAMES[p.seat % 6]}${if (turn) "، عليه الدور" else ""}") },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Box(Modifier.size(12.dp).background(Color(MALLAK_PLAYER_COLORS[p.seat % 6]), RoundedCornerShape(6.dp)))
                    Column {
                        Text("${names.getOrElse(p.seat) { "" }}${if (p.seat == mySeat) " (أنت)" else ""}", color = if (p.bankrupt) Palette.textDim else Palette.text, fontSize = 13.sp, fontWeight = if (turn) FontWeight.Bold else FontWeight.Normal)
                        Text(if (p.bankrupt) "مفلس" else "${p.cash} ريال${if (p.inJail) " 🔒" else ""}", color = Palette.goldSoft, fontSize = 12.sp)
                    }
                    TurnClock(v, p.seat, turn)
                }
            }
        }
        // الحالة: الدور، ونص قرارك، والمزاد/التفاوض/البطاقة
        Column(Modifier.fillMaxWidth().background(Color(0x33000000), RoundedCornerShape(12.dp)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(m.turnText, color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            if (m.myTurn && m.prompt.isNotEmpty()) Text(m.prompt, color = Palette.text, fontSize = 14.sp)
            if (m.auctionText.isNotEmpty()) Text(m.auctionText, color = Palette.text, fontSize = 14.sp)
            if (m.tradeText.isNotEmpty()) Text(m.tradeText, color = Palette.text, fontSize = 14.sp)
            if (m.cardText.isNotEmpty() && m.phase != "over") Text("🃏 ${m.cardText}", color = Palette.textDim, fontSize = 13.sp)
        }
        // اللوحة: للعين (اللمس يقرأ الخانة، والسحب يدوّر اللوحة)، وقارئ الشاشة يستخدم القائمة والإيماءات
        val latestYaw = rememberUpdatedState(yaw); val latestPitch = rememberUpdatedState(pitch)
        Box(Modifier.fillMaxWidth().clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
            Canvas(
                Modifier.widthIn(max = 560.dp).fillMaxWidth().aspectRatio(1f)
                    .pointerInput(reader) {
                        if (!reader) detectDragGestures { change, drag ->
                            change.consume()
                            yaw += drag.x * 0.008f
                            pitch = (pitch - drag.y * 0.005f).coerceIn(0.55f, 1.45f)
                        }
                    }
                    .pointerInput(reader) {
                        if (!reader) detectTapGestures(
                            onDoubleTap = { yaw = 0f; pitch = 0.98f },
                            onTap = { at -> hitSquare(at, Size(size.width.toFloat(), size.height.toFloat()), latestYaw.value, latestPitch.value)?.let { info = it } },
                        )
                    },
            ) { drawMallak(m, yaw, pitch, hops, clock, diceSpin) }
        }
        // أزرار القرار الحين
        if (m.actions.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            m.actions.forEach { a ->
                val primary = a.type in setOf("roll", "buy", "accept", "endTurn") || (a.type == "bid" && a == m.actions.first())
                SmallButton(a.label, {
                    if (a.type == "bid") mallakAct(conn, "bid", "amount" to a.amount) else mallakAct(conn, a.type)
                }, primary = primary)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (mySeat != null && m.phase != "over") SmallButton("عقاراتي", { manageOpen = true })
            if (m.canTrade) SmallButton("تفاوض", { tradeOpen = true })
            SmallButton("اللوحة", { listOpen = true }, description = "قائمة خانات اللوحة")
            SmallButton("السجل", { logOpen = true })
        }
        if (m.phase == "over") {
            Text(if (m.winner == mySeat) "🎉 فزت!" else "فاز ${names.getOrElse(m.winner ?: 0) { "" }}", color = Palette.goldSoft,
                fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            if (isOwner) PrimaryButton("لعبة جديدة", { conn.send("start") })
        }
    }

    info?.let { i ->
        MajliskDialog(MALLAK_BOARD[i].name, { info = null }) {
            Text(m.squares.getOrElse(i) { "" }, color = Palette.text)
            SecondaryButton("إغلاق", { info = null }, fill = true)
        }
    }
    if (listOpen) {
        MajliskDialog("خانات اللوحة", { listOpen = false }) {
            m.squares.forEach { Text(it, color = Palette.text, fontSize = 15.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp)) }
            SecondaryButton("إغلاق", { listOpen = false }, fill = true)
        }
    }
    if (logOpen) {
        MajliskDialog("سجل اللعبة", { logOpen = false }) {
            if (m.log.isEmpty()) Note("ما فيه شي بعد")
            m.log.takeLast(80).reversed().forEach { Text(it, color = Palette.text, fontSize = 14.sp, modifier = Modifier.fillMaxWidth()) }
            SecondaryButton("إغلاق", { logOpen = false }, fill = true)
        }
    }
    if (manageOpen) {
        MajliskDialog("عقاراتي", { manageOpen = false }) {
            me?.let { Note("معك ${it.cash} ريال") }
            if (m.myProps.isEmpty()) Note("ما تملك عقارات")
            m.myProps.forEach { p ->
                Text("${p.name}${if (p.houses == 5) "، برج" else if (p.houses > 0) "، ${p.houses} بيوت" else ""}${if (p.mortgaged) "، مرهون" else ""}",
                    color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (p.build) SmallButton(if (p.houses == 4) "ابنِ برج" else "ابنِ بيت", { mallakAct(conn, "build", "square" to p.square) }, primary = true, description = "ابنِ في ${p.name}")
                    if (p.sell) SmallButton("بِع بيت", { mallakAct(conn, "sell", "square" to p.square) }, description = "بِع بيت في ${p.name}")
                    if (p.mortgage) SmallButton("ارهن", { mallakAct(conn, "mortgage", "square" to p.square) }, description = "ارهن ${p.name}")
                    if (p.unmortgage) SmallButton("فك الرهن", { mallakAct(conn, "unmortgage", "square" to p.square) }, description = "فك رهن ${p.name}")
                }
            }
            SecondaryButton("إغلاق", { manageOpen = false }, fill = true)
        }
    }
    if (tradeOpen && mySeat != null) MallakTradeDialog(m, mySeat, names, conn) { tradeOpen = false }
}

/** التفاوض: تختار اللاعب، وش تعطيه (عقارات وفلوس)، ووش تبي منه */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MallakTradeDialog(m: MallakView, me: Int, names: List<String>, conn: TableConnection, close: () -> Unit) {
    val others = m.alive.filter { it != me }
    var to by remember { mutableStateOf(others.firstOrNull()) }
    var give by remember { mutableStateOf(setOf<Int>()) }
    var get by remember { mutableStateOf(setOf<Int>()) }
    var giveCash by remember { mutableStateOf("") }
    var getCash by remember { mutableStateOf("") }
    // مجموعة فيها بيوت: ما تنتبادل (لازم تنباع البيوت أول)
    val tradable = { i: Int -> MALLAK_BOARD[i].kind != "city" || (0 until 40).none { j -> MALLAK_BOARD[j].kind == "city" && MALLAK_BOARD[j].group == MALLAK_BOARD[i].group && (m.houses.getOrNull(j) ?: 0) > 0 } }
    MajliskDialog("تفاوض", close) {
        Text("مع مين؟", color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            others.forEach { s -> SmallButton(names.getOrElse(s) { "" }, { to = s; get = emptySet() }, primary = to == s, description = "${names.getOrElse(s) { "" }}${if (to == s) "، محدد" else ""}") }
        }
        Text("تعطيه", color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        (0 until 40).filter { m.owner.getOrNull(it) == me && tradable(it) }.forEach { i ->
            SwitchRow(MALLAK_BOARD[i].name + if (m.mortgaged.getOrNull(i) == true) " (مرهون)" else "", i in give, { on -> give = if (on) give + i else give - i })
        }
        OutlinedTextField(giveCash, { giveCash = it.filter(Char::isDigit).take(6) }, label = { Text("فلوس تعطيه") }, singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number), modifier = Modifier.fillMaxWidth())
        to?.let { t ->
            Text("تبي منه", color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            (0 until 40).filter { m.owner.getOrNull(it) == t && tradable(it) }.forEach { i ->
                SwitchRow(MALLAK_BOARD[i].name + if (m.mortgaged.getOrNull(i) == true) " (مرهون)" else "", i in get, { on -> get = if (on) get + i else get - i })
            }
            OutlinedTextField(getCash, { getCash = it.filter(Char::isDigit).take(6) }, label = { Text("فلوس تبيها منه") }, singleLine = true,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number), modifier = Modifier.fillMaxWidth())
        }
        val gc = giveCash.toIntOrNull() ?: 0
        val tc = getCash.toIntOrNull() ?: 0
        PrimaryButton("أرسل العرض", {
            val t = to ?: return@PrimaryButton
            mallakAct(conn, "propose", "offer" to jsonOf(
                "to" to t, "give" to org.json.JSONArray(give.toList()), "get" to org.json.JSONArray(get.toList()),
                "giveCash" to gc, "getCash" to tc, "giveCards" to 0, "getCards" to 0,
            ))
            close()
        }, enabled = to != null && (give.isNotEmpty() || get.isNotEmpty() || gc > 0 || tc > 0))
        SecondaryButton("إلغاء", close, fill = true)
    }
}

/** أصوات ملّاك ونص قرارك (حتى والتطبيق في الخلفية) */
class MallakSounds {
    private var prev: MallakView? = null
    private var wasMyTurn = false
    private var lastPrompt: String? = null

    fun update(v: TableView) {
        val m = v.mallak ?: run { prev = null; wasMyTurn = false; lastPrompt = null; return }
        val p = prev
        prev = m
        if (p != null) {
            val rolled = m.rollSeq != p.rollSeq
            if (rolled) Sounds.dice()
            if (m.moveSeq != p.moveSeq) {
                if (m.moveKind == "jail") Sounds.jail()
                else {
                    val fwd = (m.moveTo - m.moveFrom + 40) % 40
                    val n = if (m.moveKind == "card" && fwd > 20) 40 - fwd else fwd
                    Sounds.steps(min(13, n), at = (if (rolled) 0.55 else 0.0) + Sounds.STEP_GAP)
                }
            }
            if (m.cardSeq != p.cardSeq) Sounds.drawCard()
            if (m.houses.sum() > p.houses.sum()) Sounds.build()
            val cashChanged = m.seats.any { s -> m.players.getOrNull(s)?.cash != p.players.getOrNull(s)?.cash }
            if (cashChanged || m.owner != p.owner) Sounds.coins()
            if (m.phase == "over" && p.phase != "over" && v.mySeat != null) {
                val won = m.winner == v.mySeat
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ Sounds.matchEnd(won) }, 900)
            }
        }
        if (m.myTurn && !wasMyTurn) Sounds.turn(Announcer.readerOn)
        // نص القرار (يكمّل الإعلان): مرة لكل تغيّر
        if (m.myTurn && m.prompt.isNotEmpty() && (m.prompt != lastPrompt || !wasMyTurn)) Announcer.announce(m.prompt)
        lastPrompt = if (m.myTurn) m.prompt else null
        wasMyTurn = m.myTurn
    }
}
