package com.majlisk.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.border
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.runtime.CompositionLocalProvider
import com.majlisk.app.R
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.AuthService
import com.majlisk.app.data.Session
import com.majlisk.app.data.Usernames
import com.majlisk.app.net.Api
import com.majlisk.app.net.ApiError
import com.majlisk.app.net.jsonOf
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun Logo(size: Int) {
    // شعار التطبيق: زوايا دائرية وظل وإطار ذهبي خفيف (كالتطبيق الحالي)
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(22)
    Image(
        painterResource(R.drawable.logo), contentDescription = null,
        modifier = Modifier.size(size.dp)
            .shadow(12.dp, shape)
            .clip(shape)
            .border(1.dp, androidx.compose.ui.graphics.Color(0x55D4AF37), shape),
    )
}

/** شاشة البداية: ننتظر Firebase يتذكر الحساب ثم نذهب للقائمة أو الدخول */
@Composable
fun SplashScreen(done: () -> Unit) {
    LaunchedEffect(Unit) { delay(300); done() }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Logo(160)
            CircularProgressIndicator(color = Palette.gold, modifier = Modifier.semantics { })
        }
    }
}

private val AUTH_ERRORS = mapOf(
    "ERROR_INVALID_CREDENTIAL" to "البريد أو كلمة المرور غير صحيحة",
    "ERROR_WRONG_PASSWORD" to "البريد أو كلمة المرور غير صحيحة",
    "ERROR_USER_NOT_FOUND" to "البريد أو كلمة المرور غير صحيحة",
    "ERROR_INVALID_EMAIL" to "البريد الإلكتروني غير صالح",
    "ERROR_EMAIL_ALREADY_IN_USE" to "هذا البريد مسجّل مسبقاً، سجّل الدخول بدلاً من ذلك",
    "ERROR_WEAK_PASSWORD" to "كلمة المرور قصيرة — 6 أحرف على الأقل",
    "ERROR_TOO_MANY_REQUESTS" to "محاولات كثيرة، حاول بعد قليل",
    "ERROR_OPERATION_NOT_ALLOWED" to "طريقة الدخول هذه غير مفعّلة بعد",
    "ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL" to "بريد هذا الحساب مسجّل بطريقة دخول أخرى، ادخل بها",
    "cancelled" to "تم إغلاق نافذة الدخول",
    "missing-password" to "أدخل كلمة المرور",
    "network" to "تعذّر الاتصال بالإنترنت",
)

fun authMessage(e: Throwable): String {
    val code = (e as? com.google.firebase.auth.FirebaseAuthException)?.errorCode ?: (e as? ApiError)?.code ?: e.message
    if (e is com.google.firebase.FirebaseNetworkException) return AUTH_ERRORS.getValue("network")
    return AUTH_ERRORS[code] ?: Usernames.ERRORS[code] ?: "حدث خطأ، حاول مرة أخرى"
}

@Composable
fun Field(label: String, value: String, onChange: (String) -> Unit, password: Boolean = false, email: Boolean = false, ltr: Boolean = false) {
    val field = @Composable {
        OutlinedTextField(
            value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = when { password -> KeyboardType.Password; email -> KeyboardType.Email; else -> KeyboardType.Text }),
            shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = Palette.green800, unfocusedContainerColor = Palette.green800,
                focusedBorderColor = Palette.goldSoft, unfocusedBorderColor = Palette.green700,
                focusedLabelColor = Palette.goldSoft, unfocusedLabelColor = Palette.textDim,
                focusedTextColor = Palette.text, unfocusedTextColor = Palette.text, cursorColor = Palette.gold,
            ),
        )
    }
    if (ltr) CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) { field() } else field()
}

/** حقل اسم المستخدم مع فحص فوري للصيغة والتوفر (القرار النهائي في الخادم) */
@Composable
fun UsernameField(value: String, onChange: (String) -> Unit) {
    var hint by remember { mutableStateOf("اسم فريد يظهر للاعبين — حروف عربية أو إنجليزية أو أرقام أو _") }
    var color by remember { mutableStateOf(Palette.textDim) }
    LaunchedEffect(value) {
        if (value.isBlank()) { hint = "اسم فريد يظهر للاعبين — حروف عربية أو إنجليزية أو أرقام أو _"; color = Palette.textDim; return@LaunchedEffect }
        val invalid = Usernames.validate(value)
        if (invalid != null) { hint = Usernames.ERRORS.getValue(invalid); color = Palette.goldSoft; return@LaunchedEffect }
        hint = "جارٍ التحقق…"; color = Palette.textDim
        delay(450)
        runCatching { Api.postPublic("/username/available", jsonOf("username" to value)) }.onSuccess {
            if (it.optBoolean("available")) { hint = "✓ الاسم متاح"; color = Palette.online }
            else { hint = Usernames.ERRORS[it.optString("error", "taken")] ?: Usernames.ERRORS.getValue("taken"); color = Palette.goldSoft }
        }
    }
    Field("اسم المستخدم", value, onChange)
    Text(hint, color = color, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
}

@Composable
fun AuthScreen(done: () -> Unit) {
    var signup by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    fun run(block: suspend () -> Unit) {
        busy = true; error = ""
        scope.launch {
            try { block() } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                error = authMessage(e); Announcer.announce(error)
            } finally { busy = false }
        }
    }

    Screen {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Logo(120) }
        Title(if (signup) "حساب جديد" else "تسجيل الدخول")
        if (signup) UsernameField(name) { name = it }
        Field("البريد الإلكتروني", email, { email = it }, email = true, ltr = true)
        Field("كلمة المرور", password, { password = it }, password = true, ltr = true)
        if (error.isNotEmpty()) Text(error, color = Palette.goldSoft, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
        PrimaryButton(if (signup) "إنشاء الحساب (+30 🪙)" else "دخول", {
            run {
                if (signup) {
                    AuthService.signUp(name, email.trim(), password)
                    Announcer.announce("أهلاً ${name.trim()}، حصلت على 30 عملة ترحيبية")
                } else {
                    AuthService.signIn(email.trim(), password)
                    Announcer.announce("تم تسجيل الدخول")
                }
                done()
            }
        }, enabled = !busy)
        Note("بالتسجيل أنت توافق على سياسة الخصوصية.")
        SecondaryButton("سياسة الخصوصية", { AuthService.openUrl(context, "${Api.BASE.removeSuffix("/api")}/privacy.html") }, fill = true)
        SecondaryButton("الدخول بحساب Google", { run { AuthService.google(); Announcer.announce("تم تسجيل الدخول"); done() } }, enabled = !busy, fill = true)
        SecondaryButton("الدخول بحساب Apple", { run { AuthService.apple(); Announcer.announce("تم تسجيل الدخول"); done() } }, enabled = !busy, fill = true)
        SecondaryButton(if (signup) "عندي حساب — تسجيل الدخول" else "ما عندي حساب — حساب جديد", { signup = !signup; error = "" }, enabled = !busy, fill = true)
        if (!signup) SecondaryButton("نسيت كلمة المرور", {
            run {
                AuthService.resetPassword(email.trim())
                error = "أرسلنا رابط استعادة كلمة المرور إلى بريدك"
                Announcer.announce(error)
            }
        }, enabled = !busy, fill = true)
    }
}

/** يظهر لأي حساب بلا اسم مستخدم (مثل أول دخول بحساب Google) قبل الوصول للقائمة */
@Composable
fun ChooseUsernameScreen() {
    var name by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    Screen {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Logo(100) }
        Title("اختر اسم المستخدم")
        Text("هذا الاسم يظهر لكل اللاعبين ولا يمكن لأحد غيرك استخدامه.", color = Palette.textDim, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        UsernameField(name) { name = it }
        if (error.isNotEmpty()) Text(error, color = Palette.goldSoft, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
        PrimaryButton("تأكيد", {
            val invalid = Usernames.validate(name)
            if (invalid != null) { error = Usernames.ERRORS.getValue(invalid); Announcer.announce(error); return@PrimaryButton }
            busy = true; error = ""
            scope.launch {
                runCatching { Api.post("/profile/username", jsonOf("username" to name)) }
                    .onSuccess { Announcer.announce("تم حجز اسم المستخدم $name") }
                    .onFailure { error = Usernames.ERRORS[(it as? ApiError)?.code] ?: "حدث خطأ، حاول مرة أخرى"; Announcer.announce(error) }
                busy = false
            }
        }, enabled = !busy)
        SecondaryButton("تسجيل الخروج", { Session.signOut() }, enabled = !busy, fill = true)
    }
}
