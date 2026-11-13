package com.majlisk.app.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

/** خيار شكل: اسم يُقرأ، وألوانه */
data class LookOption(val name: String, val colors: List<Color>)

/**
 * تخصيص الشكل (الباقة الاحترافية): يتحفظ في الجوال، ويطلع للمشترك بس — غيره يشوف الشكل العادي (الخيار الأول).
 * كل لعبة تقرأ ألوانها من هنا.
 */
object Look {
    // ألوان المفرش: [وسط، منتصف، حافة]
    val FELTS = listOf(
        LookOption("أخضر زمردي", listOf(Color(0xFF1E6B4A), Color(0xFF145036), Color(0xFF0B241B))),
        LookOption("أزرق ليلي", listOf(Color(0xFF3A68AC), Color(0xFF1F3B66), Color(0xFF0E1C33))),
        LookOption("عنابي", listOf(Color(0xFFA52A3A), Color(0xFF6A1420), Color(0xFF3A0C13))),
        LookOption("بنفسجي", listOf(Color(0xFF7A4FB0), Color(0xFF4A2D70), Color(0xFF2A1746))),
        LookOption("رمادي فحمي", listOf(Color(0xFF4A525C), Color(0xFF2B3036), Color(0xFF15181C))),
        LookOption("رملي", listOf(Color(0xFFD9C08A), Color(0xFFB09460), Color(0xFF8A6F3A))),
    )
    /** شكل طاولة البلوت */
    val SHAPES = listOf("دائرية", "مستطيلة", "ثمانية", "مربعة")
    /** حافة الطاولة: [فاتح، وسط، غامق] */
    val RIMS = listOf(
        LookOption("خشب", listOf(Color(0xFF8A5A2B), Color(0xFF5C3A1A), Color(0xFF3B2410))),
        LookOption("ذهب", listOf(Color(0xFFF1DDA0), Color(0xFFD9B45A), Color(0xFF8A6A22))),
        LookOption("رخام", listOf(Color(0xFFF2F0EA), Color(0xFFC8C4BA), Color(0xFF8E8A80))),
        LookOption("أسود", listOf(Color(0xFF3A3F46), Color(0xFF22262B), Color(0xFF0B0F14))),
    )
    /** إطار الورق: لون حافة الورقة */
    val CARD_EDGES = listOf(
        LookOption("كلاسيكي", listOf(Color(0xFFCFC9B8))),
        LookOption("ذهبي", listOf(Color(0xFFD9B45A))),
        LookOption("عنابي", listOf(Color(0xFF7A1F2B))),
        LookOption("أزرق", listOf(Color(0xFF2B4C7E))),
    )
    /** وجه الورق (البلوت) */
    val FACES = listOf("كلاسيكي", "خط كبير", "ذهبي", "ليلي")
    /** أحجار الدومينو: [الوجه، النقاط، الحافة] */
    val TILES = listOf(
        LookOption("عاجي", listOf(Color(0xFFFAF7EE), Color(0xFF1A1A1A), Color(0xFF9E9886))),
        LookOption("أسود بنقط ذهبية", listOf(Color(0xFF2A2E33), Color(0xFFF1DDA0), Color(0xFF0B0F14))),
        LookOption("ذهبي", listOf(Color(0xFFF1DDA0), Color(0xFF2A1E05), Color(0xFF8A6A22))),
        LookOption("أزرق", listOf(Color(0xFF3A68AC), Color(0xFFFFFFFF), Color(0xFF1B3157))),
    )
    val SIZES = listOf("صغير" to 0.85f, "وسط" to 1f, "كبير" to 1.15f)
    /** لوحة الجاكارو: [اللوحة، الحافة، الصينية] */
    val JK_BOARDS = listOf(
        LookOption("أسود وخشب", listOf(Color(0xFF1C1C1E), Color(0xFF0B0B0C), Color(0xFFE4C48F))),
        LookOption("خشب وزمرد", listOf(Color(0xFF7A4A22), Color(0xFF4A2D13), Color(0xFF2FA57B))),
        LookOption("ليلي وذهب", listOf(Color(0xFF1F3B66), Color(0xFF0E1C33), Color(0xFFD9B45A))),
    )
    /** نرد اللودو: [الوجه، النقاط] */
    val DICE = listOf(
        LookOption("عاجي", listOf(Color.White, Color(0xFF1A1A1A))),
        LookOption("ذهبي", listOf(Color(0xFFF1DDA0), Color(0xFF2A1E05))),
        LookOption("أسود", listOf(Color(0xFF2A2E33), Color(0xFFF1DDA0))),
        LookOption("ياقوتي", listOf(Color(0xFFC8394B), Color.White)),
    )

    private fun saved(key: String) = Prefs.lookGet(key)
    var balootFelt by mutableIntStateOf(saved("balootFelt"))
    var balootShape by mutableIntStateOf(saved("balootShape"))
    var balootRim by mutableIntStateOf(saved("balootRim"))
    var cardEdge by mutableIntStateOf(saved("cardEdge"))
    var cardFace by mutableIntStateOf(saved("cardFace"))
    var dominoFelt by mutableIntStateOf(saved("dominoFelt"))
    var dominoRim by mutableIntStateOf(saved("dominoRim"))
    var dominoTile by mutableIntStateOf(saved("dominoTile"))
    var dominoSize by mutableIntStateOf(saved("dominoSize").let { if (it == 0 && !Prefs.lookHas("dominoSize")) 1 else it })
    var jkBoard by mutableIntStateOf(saved("jkBoard"))
    var ludoDice by mutableIntStateOf(saved("ludoDice"))

    fun save() {
        mapOf("balootFelt" to balootFelt, "balootShape" to balootShape, "balootRim" to balootRim, "cardEdge" to cardEdge, "cardFace" to cardFace,
            "dominoFelt" to dominoFelt, "dominoRim" to dominoRim, "dominoTile" to dominoTile, "dominoSize" to dominoSize,
            "jkBoard" to jkBoard, "ludoDice" to ludoDice).forEach { (k, v) -> Prefs.lookSet(k, v) }
    }

    /** المشترك يشوف اختياره، وغيره الشكل العادي */
    private val pro get() = Session.profile.value?.isPro == true
    private fun <T> pick(list: List<T>, i: Int): T = if (pro) list.getOrElse(i) { list[0] } else list[0]

    val felt get() = pick(FELTS, balootFelt).colors
    val shape get() = if (pro) balootShape else 0
    val rim get() = pick(RIMS, balootRim).colors
    val edge get() = pick(CARD_EDGES, cardEdge).colors[0]
    val face get() = if (pro) cardFace.coerceIn(0, FACES.lastIndex) else 0
    val dFelt get() = pick(FELTS, dominoFelt).colors
    val dRim get() = pick(RIMS, dominoRim).colors
    val tile get() = pick(TILES, dominoTile).colors
    val tileScale get() = if (pro) SIZES.getOrElse(dominoSize) { SIZES[1] }.second else 1f
    val jk get() = pick(JK_BOARDS, jkBoard).colors
    val dice get() = pick(DICE, ludoDice).colors
}
