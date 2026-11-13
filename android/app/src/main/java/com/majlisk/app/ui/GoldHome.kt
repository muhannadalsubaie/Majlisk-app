package com.majlisk.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.majlisk.app.data.Ads
import com.majlisk.app.data.Profile

/** اللعبة اللي اختارها من الواجهة الذهبية: شاشة إنشاء الطاولة تفتح عليها مباشرة */
object PendingGame { var game: String? = null }

/** طاولة مجسمة صغيرة (حافة خشب، ولباد أخضر، وورقتين) */
@Composable
private fun MiniTable(modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics { }) {
        val w = size.width; val h = size.height
        // منظور: الطرف البعيد أضيق
        fun trap(inset: Float, top: Float, bottom: Float): Path = Path().apply {
            val narrow = w * 0.16f + inset
            moveTo(narrow, top); lineTo(w - narrow, top); lineTo(w - inset, bottom); lineTo(inset, bottom); close()
        }
        drawPath(trap(w * 0.02f, h * 0.22f, h * 0.98f), Color(0x66000000)) // ظل
        drawPath(trap(0f, h * 0.10f, h * 0.88f), Brush.verticalGradient(listOf(Color(0xFFA06A32), Color(0xFF4A2D13))))
        drawPath(trap(w * 0.05f, h * 0.17f, h * 0.80f), Brush.radialGradient(listOf(Color(0xFF2FA57B), Color(0xFF0F4A37)), Offset(w / 2, h * 0.45f), w * 0.5f))
        val cw = w * 0.11f; val ch = h * 0.32f
        rotate(-10f, Offset(w * 0.45f, h * 0.5f)) {
            drawRoundRect(Color(0xFFFBFBF6), Offset(w * 0.45f - cw / 2, h * 0.32f), Size(cw, ch), CornerRadius(6f))
        }
        rotate(9f, Offset(w * 0.56f, h * 0.5f)) {
            drawRoundRect(Color(0xFFFBFBF6), Offset(w * 0.56f - cw / 2, h * 0.30f), Size(cw, ch), CornerRadius(6f))
        }
    }
}

@Composable
private fun GameCard(name: String, icon: String, featured: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.height(104.dp).shadow(10.dp, shape)
            .background(Brush.linearGradient(if (featured) listOf(Color(0xFF1F7A5A), Color(0xFF124836)) else listOf(Color(0xFF2B3A4A), Color(0xFF18212B))), shape)
            .border(1.dp, Pro.goldLight.copy(alpha = 0.22f), shape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = "طاولة $name" }
            .padding(14.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(icon, fontSize = 28.sp, modifier = Modifier.clearAndSetSemantics { })
        Text(name, color = Color(0xFFF4EFE2), fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.clearAndSetSemantics { })
    }
}

@Composable
private fun NavItem(icon: String, label: String, active: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).semantics(mergeDescendants = true) { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text(icon, fontSize = 20.sp, modifier = Modifier.clearAndSetSemantics { })
        Text(label, color = if (active) Pro.goldLight else Pro.dim, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clearAndSetSemantics { })
    }
}

/**
 * الواجهة الذهبية: الشاشة الرئيسية للمشترك في الباقة الاحترافية (تفتح على طول أول ما يفتح التطبيق)
 */
@Composable
fun GoldMenuScreen(profile: Profile?, navigate: (Route) -> Unit, openTable: (String) -> Unit) {
    var getCoins by remember { mutableStateOf(false) }
    val play = { game: String? -> PendingGame.game = game; navigate(Route.CreateTable) }
    Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Color(0xFF1B2530), Color(0xFF0B0F14)), Offset(540f, 0f), 2200f))) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // الرأس: صورتك بإطار ذهبي، واسمك، وعضو ذهبي، والرصيد
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    Modifier.clip(CircleShape).border(3.dp, Brush.sweepGradient(listOf(Pro.goldLight, Pro.goldDark, Pro.goldLight, Pro.gold, Pro.goldLight)), CircleShape).padding(3.dp)
                        .clickable(role = Role.Button) { navigate(Route.Profile) }.semantics(mergeDescendants = true) { contentDescription = "الملف الشخصي" },
                ) { Avatar(com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid, profile?.username.orEmpty(), 50.dp) }
                Column(Modifier.weight(1f)) {
                    Text(profile?.username.orEmpty(), color = Color(0xFFF4EFE2), fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.semantics { heading() })
                    Text("👑 عضو ذهبي", color = Pro.goldLight, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
                Text(
                    if (profile?.unlimited == true) "🪙 ∞" else "🪙 ${profile?.coins ?: "…"}",
                    color = Color(0xFFF4EFE2), fontSize = 15.sp, fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Brush.verticalGradient(listOf(Color(0xFF232D38), Color(0xFF141B22))))
                        .clickable(role = Role.Button) { getCoins = true }.padding(horizontal = 14.dp, vertical = 8.dp)
                        .semantics { contentDescription = "رصيدك ${profile?.coins ?: ""} عملة، الحصول على عملات" },
                )
            }
            // بطاقة «العب الآن» بطاولة مجسمة
            Box(
                Modifier.fillMaxWidth().height(220.dp).shadow(16.dp, RoundedCornerShape(26.dp))
                    .background(Brush.linearGradient(listOf(Color(0xFF23303D), Color(0xFF10161C))), RoundedCornerShape(26.dp))
                    .border(1.dp, Pro.goldLight.copy(alpha = 0.18f), RoundedCornerShape(26.dp)),
            ) {
                MiniTable(Modifier.fillMaxWidth().height(150.dp).padding(horizontal = 40.dp, vertical = 8.dp))
                Row(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("مجلسك الذهبي", color = Pro.goldLight, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                        Text("طاولتك بشكلها المميز", color = Pro.dim, fontSize = 13.sp)
                    }
                    RaisedButton("العب الآن", { play(null) }, base = Pro.gold, content = Pro.ink, minHeight = 48.dp, fontSize = 16.sp)
                }
            }
            // الألعاب
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("الألعاب", color = Color(0xFFF4EFE2), fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.weight(1f).semantics { heading() })
                Text("انضمام إلى طاولة", color = Pro.goldLight, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clickable(role = Role.Button) { navigate(Route.JoinTable) }.padding(8.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                GameCard("بلوت", "🃏", true, Modifier.weight(1f)) { play("baloot") }
                GameCard("دومينو", "🁫", false, Modifier.weight(1f)) { play("domino") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                GameCard("جاكارو", "🎯", false, Modifier.weight(1f)) { play("jackaroo") }
                GameCard("لودو", "🎲", false, Modifier.weight(1f)) { play("ludo") }
            }
            // المتصلون
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color(0xFF141B22)).border(1.dp, Pro.goldLight.copy(alpha = 0.18f), RoundedCornerShape(16.dp)).padding(14.dp)) {
                OnlineLine(openTable)
            }
            Spacer(Modifier.height(4.dp))
            // شريط التنقل
            Row(
                Modifier.fillMaxWidth().shadow(14.dp, RoundedCornerShape(24.dp))
                    .background(Brush.verticalGradient(listOf(Color(0xFF232D38), Color(0xFF141B22))), RoundedCornerShape(24.dp))
                    .padding(vertical = 6.dp),
            ) {
                NavItem("👥", "الأصدقاء", false, Modifier.weight(1f)) { navigate(Route.Friends) }
                NavItem("🎴", "الطاولات", false, Modifier.weight(1f)) { navigate(Route.JoinTable) }
                NavItem("👑", "الباقة", true, Modifier.weight(1f)) { navigate(Route.Pro) }
                NavItem("👤", "حسابي", false, Modifier.weight(1f)) { navigate(Route.Profile) }
                NavItem("⚙️", "الإعدادات", false, Modifier.weight(1f)) { navigate(Route.Settings) }
            }
        }
    }
    if (getCoins) {
        MajliskDialog("الحصول على عملات", { getCoins = false }) {
            PrimaryButton("شراء عملات", { getCoins = false; navigate(Route.Shop) })
            PrimaryButton("مشاهدة إعلان (+2 🪙)", { getCoins = false; Ads.watch() }, description = "مشاهدة إعلان للحصول على عملتين")
            SecondaryButton("إلغاء", { getCoins = false }, fill = true)
        }
    }
}
