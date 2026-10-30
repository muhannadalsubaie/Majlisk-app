package com.majlisk.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.ripple
import androidx.compose.runtime.getValue
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/** شاشة كاملة قابلة للتمرير بخلفية التطبيق */
@Composable
fun Screen(modifier: Modifier = Modifier, scroll: Boolean = true, fill: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    // خلفية بعمق: أفتح قليلاً في الوسط وأغمق عند الأطراف
    Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Palette.green800, Palette.green900), radius = 1400f))) {
        // fill: المحتوى يملأ طول الشاشة على الأقل، فيقدر Spacer(weight) يدفع ما بعده لأسفلها
        if (fill) {
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
                val inner = if (scroll) Modifier.verticalScroll(rememberScrollState()) else Modifier
                Column(
                    Modifier.fillMaxWidth().then(inner).heightIn(min = maxHeight).padding(horizontal = 16.dp, vertical = 12.dp).then(modifier),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    content = content,
                )
            }
        } else {
            val m = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 12.dp)
            Column(
                (if (scroll) m.verticalScroll(rememberScrollState()) else m).then(modifier),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                content = content,
            )
        }
    }
}

/** عنوان يقرؤه قارئ الشاشة كعنوان، ويأخذ التركيز عند فتح الشاشة */
@Composable
fun Title(text: String, modifier: Modifier = Modifier, focus: Boolean = true) {
    val req = remember { FocusRequester() }
    Text(
        text,
        style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
        color = Palette.gold,
        modifier = modifier.semantics { heading() }.focusRequester(req),
    )
    if (focus) LaunchedEffect(text) { runCatching { req.requestFocus() } }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = androidx.compose.material3.MaterialTheme.typography.titleLarge, color = Palette.gold, modifier = Modifier.semantics { heading() })
}

/** شريط أعلى الشاشة: العنوان، وزر الرجوع في نهاية الصف */
@Composable
fun TopBar(title: String, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.weight(1f)) { Title(title) }
        actions()
        if (onBack != null) BackButton(onBack)
    }
}

/**
 * زر بارز ثلاثي الأبعاد: تدرّج لوني من الأعلى للأسفل وظل تحته، وينضغط للداخل عند اللمس.
 * كل أزرار التطبيق تُبنى منه، فتغيير شكلها يكون هنا فقط.
 */
@Composable
fun RaisedButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    base: Color = Palette.gold,
    content: Color = Palette.green900,
    border: Color? = null,
    enabled: Boolean = true,
    description: String? = null,
    minHeight: Dp = 52.dp,
    padding: PaddingValues = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
    fontSize: TextUnit = 18.sp,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier
            .heightIn(min = minHeight)
            .graphicsLayer {
                val k = if (pressed) 0.96f else 1f
                scaleX = k; scaleY = k
                translationY = if (pressed) 2.dp.toPx() else 0f
                alpha = if (enabled) 1f else 0.5f
            }
            .shadow(if (pressed || !enabled) 1.dp else 6.dp, shape, ambientColor = Color.Black, spotColor = Color.Black)
            .background(Brush.verticalGradient(listOf(lerp(base, Color.White, 0.22f), base, lerp(base, Color.Black, 0.18f))), shape)
            .then(if (border != null) Modifier.border(1.dp, border, shape) else Modifier)
            .clickable(interaction, ripple(), enabled = enabled, role = Role.Button, onClick = onClick)
            .describe(description)
            .padding(padding),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = content, fontSize = fontSize, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, description: String? = null) =
    RaisedButton(text, onClick, modifier.fillMaxWidth(), enabled = enabled, description = description)

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, description: String? = null, fill: Boolean = false) =
    RaisedButton(
        text, onClick, if (fill) modifier.fillMaxWidth() else modifier,
        base = Palette.green700, content = Palette.text, border = Palette.gold, enabled = enabled, description = description, minHeight = 48.dp,
    )

/** زر الرجوع: صغير في كل الشاشات والقوائم (مع مساحة لمس كافية) */
@Composable
fun BackButton(onClick: () -> Unit, text: String = "رجوع") =
    RaisedButton(
        text, onClick, base = Palette.green700, content = Palette.text, border = Palette.gold,
        minHeight = 40.dp, padding = PaddingValues(horizontal = 14.dp, vertical = 6.dp), fontSize = 14.sp,
    )

/** زر صغير (المزايدة، وأزرار صفوف المقاعد) */
@Composable
fun SmallButton(text: String, onClick: () -> Unit, primary: Boolean = false, enabled: Boolean = true, description: String? = null) =
    RaisedButton(
        text, onClick, Modifier.widthIn(min = 64.dp),
        base = if (primary) Palette.gold else Palette.green700,
        content = if (primary) Palette.green900 else Palette.text,
        border = if (primary) null else Palette.gold,
        enabled = enabled, description = description,
        minHeight = 44.dp, padding = PaddingValues(horizontal = 14.dp, vertical = 8.dp), fontSize = 15.sp,
    )

@Composable
fun DangerButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, fill: Boolean = true) =
    RaisedButton(text, onClick, if (fill) modifier.fillMaxWidth() else modifier, base = Palette.danger, content = Color.White, minHeight = 48.dp)

/** وصف مختلف عن النص الظاهر (مثل "دعوة صديق للمقعد 2") */
fun Modifier.describe(description: String?): Modifier =
    if (description == null) this else this.semantics(mergeDescendants = true) { contentDescription = description }

@Composable
fun Note(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Palette.textDim, fontSize = 14.sp, modifier = modifier)
}

@Composable
fun Body(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Palette.text, style = androidx.compose.material3.MaterialTheme.typography.bodyLarge, modifier = modifier)
}

/** مفتاح تشغيل/إيقاف بعنوان ووصف: الصف كله عنصر واحد لقارئ الشاشة */
@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit, description: String? = null) {
    Column(
        Modifier.fillMaxWidth()
            .background(Palette.green800, RoundedCornerShape(14.dp))
            .border(1.dp, if (checked) Palette.gold else Palette.green700, RoundedCornerShape(14.dp))
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .semantics(mergeDescendants = true) { stateDescription = if (checked) "مفعّل" else "متوقف" }
            .heightIn(min = 56.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = Palette.text, style = androidx.compose.material3.MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Switch(
                checked = checked, onCheckedChange = null,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Palette.green900, checkedTrackColor = Palette.gold, checkedBorderColor = Palette.gold,
                    uncheckedThumbColor = Palette.textDim, uncheckedTrackColor = Palette.green700, uncheckedBorderColor = Palette.green700,
                ),
            )
        }
    }
}

/** صف بعنصر ونص على اليمين وأزرار على اليسار */
@Composable
fun ItemRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).background(Palette.green800, RoundedCornerShape(14.dp)).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** نافذة منبثقة بعنوان: قارئ الشاشة يبقى داخلها حتى تُغلق */
@Composable
fun MajliskDialog(title: String, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier.padding(16.dp).widthIn(max = 420.dp).fillMaxWidth()
                .background(Palette.green800, RoundedCornerShape(14.dp))
                .border(1.dp, Palette.gold, RoundedCornerShape(14.dp))
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, color = Palette.gold, fontSize = 21.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, modifier = Modifier.semantics { heading() })
            content()
        }
    }
}

@Composable
fun ConfirmDialog(title: String, message: String, confirm: String, danger: Boolean = false, onConfirm: () -> Unit, onCancel: () -> Unit) {
    MajliskDialog(title, onCancel) {
        Body(message)
        if (danger) DangerButton(confirm, onConfirm) else PrimaryButton(confirm, onConfirm)
        SecondaryButton("إلغاء", onCancel, fill = true)
    }
}
