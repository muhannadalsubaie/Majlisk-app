package com.majlisk.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * ألوان التصميم المؤقت (الأخضر الغامق والذهبي، مثل التطبيق الحالي).
 * كل ألوان التطبيق وخطوطه من هنا فقط، فتغيير التصميم لاحقاً يكون في هذا الملف.
 */
object Palette {
    val green900 = Color(0xFF0D2B20)
    val green800 = Color(0xFF133A2B)
    val green700 = Color(0xFF1B4D39)
    val gold = Color(0xFFD4AF37)
    val goldSoft = Color(0xFFE8CF7A)
    val text = Color(0xFFF3EFE2)
    val textDim = Color(0xFFB9C4BD)
    val danger = Color(0xFFC0392B)
    val online = Color(0xFF7FD48F)
}

@Composable
fun MajliskTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Palette.gold,
            onPrimary = Palette.green900,
            secondary = Palette.green700,
            onSecondary = Palette.text,
            background = Palette.green900,
            onBackground = Palette.text,
            surface = Palette.green800,
            onSurface = Palette.text,
            error = Palette.danger,
        ),
        typography = Typography(
            headlineMedium = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold),
            titleLarge = TextStyle(fontSize = 21.sp, fontWeight = FontWeight.Bold),
            titleMedium = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold),
            bodyLarge = TextStyle(fontSize = 18.sp),
            bodyMedium = TextStyle(fontSize = 16.sp),
            labelLarge = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold),
        ),
        content = content,
    )
}
