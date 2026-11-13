package com.majlisk.app.table

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.MajliskApp
import com.majlisk.app.model.Card

/** صور الأوراق (SVG-cards لديفيد بيلو، رخصة LGPL-2.1 — مذكورة في الإعدادات). للعين فقط: الاسم يُقرأ نصاً */
object CardImages {
    private val cache = HashMap<String, ImageBitmap?>()

    fun get(card: Card): ImageBitmap? = cache.getOrPut(card.asset) {
        runCatching { MajliskApp.instance.assets.open(card.asset).use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
    }
}

private fun symbol(suit: String) = when (suit) { "S" -> "♠"; "H" -> "♥"; "D" -> "♦"; else -> "♣" }
private fun isRed(suit: String) = suit == "H" || suit == "D"

/**
 * وجه الورقة: الصور الكلاسيكية، أو (للمشترك) شكل من أشكال الوجه المرسومة:
 * 1 خط كبير واضح، 2 ذهبي، 3 ليلي.
 */
@Composable
fun CardFace(card: Card, modifier: Modifier = Modifier) {
    val style = com.majlisk.app.data.Look.face
    if (style == 0) {
        val bmp = CardImages.get(card) ?: return
        Image(bmp, contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit)
        return
    }
    val red = isRed(card.suit)
    val (bg, ink, frame) = when (style) {
        2 -> Triple(Brush.verticalGradient(listOf(Color(0xFFFFF8E1), Color(0xFFF1E3BC))), if (red) Color(0xFFB0302A) else Color(0xFF2A1E05), Color(0xFFD9B45A))
        3 -> Triple(Brush.verticalGradient(listOf(Color(0xFF1F2A35), Color(0xFF0B0F14))), if (red) Color(0xFFFF7A7A) else Color(0xFFF1DDA0), Color(0xFFD9B45A))
        else -> Triple(Brush.verticalGradient(listOf(Color.White, Color.White)), if (red) Color(0xFFC62828) else Color(0xFF111111), Color.Transparent)
    }
    BoxWithConstraints(modifier.background(bg)) {
        val w = maxWidth.value
        Box(Modifier.fillMaxSize().padding((w * 0.06f).dp).border(if (frame == Color.Transparent) 0.dp else 1.dp, frame, RoundedCornerShape((w * 0.06f).dp)))
        if (style == 1) {
            // خط كبير: الرقم والرمز كبار في النص (أوضح للنظر)
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center) {
                Text(card.rank, color = ink, fontSize = (w * 0.42f).sp, fontWeight = FontWeight.ExtraBold, lineHeight = (w * 0.44f).sp)
                Text(symbol(card.suit), color = ink, fontSize = (w * 0.46f).sp, lineHeight = (w * 0.48f).sp)
            }
        } else {
            // الرقم والرمز في الزاوية اليسرى دائماً (حتى والتطبيق عربي): يبين والورق فوق بعض في يدك
            Column(Modifier.align(androidx.compose.ui.AbsoluteAlignment.TopLeft).absolutePadding(left = (w * 0.1f).dp, top = (w * 0.08f).dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(card.rank, color = ink, fontSize = (w * 0.26f).sp, fontWeight = FontWeight.ExtraBold, lineHeight = (w * 0.28f).sp)
                Text(symbol(card.suit), color = ink, fontSize = (w * 0.22f).sp, lineHeight = (w * 0.24f).sp)
            }
            Text(symbol(card.suit), color = ink, fontSize = (w * 0.52f).sp, modifier = Modifier.align(Alignment.Center).padding(top = (w * 0.18f).dp))
        }
    }
}
