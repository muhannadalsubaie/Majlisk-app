package com.majlisk.app.table

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import com.majlisk.app.MajliskApp
import com.majlisk.app.model.Card

/** صور الأوراق (SVG-cards لديفيد بيلو، رخصة LGPL-2.1 — مذكورة في الإعدادات). للعين فقط: الاسم يُقرأ نصاً */
object CardImages {
    private val cache = HashMap<String, ImageBitmap?>()

    fun get(card: Card): ImageBitmap? = cache.getOrPut(card.asset) {
        runCatching { MajliskApp.instance.assets.open(card.asset).use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
    }
}

@Composable
fun CardFace(card: Card, modifier: Modifier = Modifier) {
    val bmp = CardImages.get(card) ?: return
    Image(bmp, contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit)
}
