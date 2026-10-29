package com.majlisk.app.ui

import androidx.compose.foundation.background
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
fun Screen(modifier: Modifier = Modifier, scroll: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Palette.green900)) {
        val m = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 12.dp)
        Column(
            (if (scroll) m.verticalScroll(rememberScrollState()) else m).then(modifier),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
    }
}

/** عنوان يقرؤه قارئ الشاشة كعنوان، ويأخذ التركيز عند فتح الشاشة */
@Composable
fun Title(text: String, modifier: Modifier = Modifier, focus: Boolean = true) {
    val req = remember { FocusRequester() }
    Text(
        text,
        style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
        color = Palette.text,
        modifier = modifier.semantics { heading() }.focusRequester(req),
    )
    if (focus) LaunchedEffect(text) { runCatching { req.requestFocus() } }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = androidx.compose.material3.MaterialTheme.typography.titleLarge, color = Palette.goldSoft, modifier = Modifier.semantics { heading() })
}

/** شريط أعلى الشاشة: العنوان، وزر الرجوع في نهاية الصف */
@Composable
fun TopBar(title: String, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.weight(1f)) { Title(title) }
        actions()
        if (onBack != null) SecondaryButton("رجوع", onBack)
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, description: String? = null) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth().heightIn(min = 52.dp).describe(description),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Palette.gold, contentColor = Palette.green900),
    ) { Text(text, style = androidx.compose.material3.MaterialTheme.typography.labelLarge) }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, description: String? = null, fill: Boolean = false) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = (if (fill) modifier.fillMaxWidth() else modifier).heightIn(min = 48.dp).describe(description),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Palette.green700, contentColor = Palette.text),
    ) { Text(text, style = androidx.compose.material3.MaterialTheme.typography.labelLarge) }
}

@Composable
fun DangerButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, fill: Boolean = true) {
    Button(
        onClick = onClick,
        modifier = (if (fill) modifier.fillMaxWidth() else modifier).heightIn(min = 48.dp),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Palette.danger, contentColor = Palette.text),
    ) { Text(text, style = androidx.compose.material3.MaterialTheme.typography.labelLarge) }
}

/** وصف مختلف عن النص الظاهر (مثل "دعوة صديق للمقعد 2") */
fun Modifier.describe(description: String?): Modifier =
    if (description == null) this else this.semantics(mergeDescendants = true) { contentDescription = description }

@Composable
fun Note(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Palette.textDim, style = androidx.compose.material3.MaterialTheme.typography.bodyMedium, modifier = modifier)
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
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .semantics(mergeDescendants = true) { stateDescription = if (checked) "مفعّل" else "متوقف" }
            .padding(vertical = 6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = Palette.text, style = androidx.compose.material3.MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Switch(
                checked = checked, onCheckedChange = null,
                colors = SwitchDefaults.colors(checkedThumbColor = Palette.green900, checkedTrackColor = Palette.gold),
            )
        }
        if (description != null) Note(description)
    }
}

/** صف بعنصر ونص على اليمين وأزرار على اليسار */
@Composable
fun ItemRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.fillMaxWidth().background(Palette.green800, RoundedCornerShape(12.dp)).padding(10.dp),
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
            Modifier.padding(16.dp).fillMaxWidth()
                .background(Palette.green800, RoundedCornerShape(18.dp))
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Title(title)
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
