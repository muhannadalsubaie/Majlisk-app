package com.majlisk.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.majlisk.app.MainActivity
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Billing
import com.majlisk.app.data.Hub
import com.majlisk.app.data.Prefs
import com.majlisk.app.net.Api
import com.majlisk.app.data.Session
import com.majlisk.app.data.Social
import com.majlisk.app.table.TableScreen
import kotlinx.coroutines.launch

enum class Route { Splash, Auth, Menu, CreateTable, JoinTable, Table, Friends, Settings, Shop, Profile, Pro, Gift, Look }

@Composable
fun AppRoot() {
    val user by Session.user.collectAsState()
    val profile by Session.profile.collectAsState()
    var screen by rememberSaveable { mutableStateOf(Route.Splash) }
    var tableId by rememberSaveable { mutableStateOf<String?>(null) }
    val hub by Hub.state.collectAsState()
    val scope = rememberCoroutineScope()
    var confirmExit by remember { mutableStateOf(false) }

    val navigate: (Route) -> Unit = { screen = it }
    val openTable: (String) -> Unit = { tableId = it; screen = Route.Table }

    // المشترك: كل صفحات التطبيق بالشكل الذهبي
    LaunchedEffect(profile?.isPro) { Palette.goldMode = profile?.isPro == true }
    // بعد تسجيل الخروج (أو حذف الحساب) من أي شاشة نعود لشاشة الدخول
    LaunchedEffect(user) {
        if (user == null && screen != Route.Splash) screen = Route.Auth
    }
    val signedIn = user != null && !profile?.username.isNullOrEmpty()
    // مركز اللاعب (الأصدقاء والدعوات)، واستكمال أي شراء دُفع ولم تُسلَّم عملاته
    LaunchedEffect(signedIn) {
        if (signedIn) { Hub.start(); Billing.recover() } else { Hub.stop(); Hub.clearLock() }
    }

    // زر الرجوع في الجهاز: يرجع للصفحة السابقة، ومن الرئيسية يسأل قبل الخروج
    BackHandler(enabled = screen != Route.Splash && screen != Route.Table) {
        when (screen) {
            Route.Menu, Route.Auth -> confirmExit = true
            else -> screen = Route.Menu
        }
    }

    // أي حساب مسجّل بلا اسم مستخدم يجب أن يختار اسماً قبل أي شاشة أخرى
    val needsUsername = user != null && profile?.loaded == true && profile?.username.isNullOrEmpty() && screen != Route.Splash
    // حساب جديد بالبريد لم يضغط رابط التحقق بعد
    var verified by remember(user?.uid) { mutableStateOf(!com.majlisk.app.data.AuthService.needsVerification(user)) }
    // الحساب مفتوح في جهاز ثاني: هالجهاز مقفول (بدون تسجيل خروج) لين ترجع تفتحه هنا
    val locked by Hub.locked.collectAsState()
    when {
        user != null && locked -> Screen {
            Title("حسابك مفتوح في جهاز ثاني")
            Body("فتحت حسابك من جهاز ثاني، فتقفل هنا. حسابك ما تسجّل خروجه.")
            PrimaryButton("استخدم حسابي هنا", { Hub.takeOver() })
            Note("أي جهاز تفتح فيه التطبيق ياخذ الحساب على طول، والجهاز الثاني يتقفل.")
        }
        user != null && !verified && screen != Route.Splash -> VerifyEmailScreen(user?.email.orEmpty()) { verified = true }
        needsUsername -> ChooseUsernameScreen()
        // المشترك: علامات التبويب ثابتة تحت، وكل تبويب يفتح فوقها (ما يفتح صفحة مستقلة)
        profile?.isPro == true && screen in GOLD_TABS -> GoldTabs(screen, navigate) {
            when (screen) {
                Route.Menu -> GoldMenuScreen(profile, navigate, openTable)
                Route.JoinTable -> JoinTableScreen(navigate, openTable)
                Route.Friends -> FriendsScreen(hub, navigate, openTable)
                Route.Settings -> SettingsScreen(onBack = { screen = Route.Menu }, embedded = false)
                Route.Profile -> ProfileScreen(profile) { screen = Route.Menu }
                Route.Pro -> ProScreen(profile, onBack = { screen = Route.Menu }, onGift = { screen = Route.Gift }, onLook = { screen = Route.Look })
                else -> LookScreen { screen = Route.Menu }
            }
        }
        else -> when (screen) {
            Route.Splash -> SplashScreen {
                if (user == null) { screen = Route.Auth; return@SplashScreen }
                // أُغلق التطبيق وأنت في طاولة قبل أقل من دقيقة: نرجعك لها إن كنت ما زلت فيها
                val last = Prefs.lastTable
                if (last != null && System.currentTimeMillis() - Prefs.lastTableAt < 60_000) {
                    scope.launch {
                        val member = runCatching { Api.get("/tables/$last/member").optBoolean("member") }.getOrDefault(false)
                        if (member) openTable(last) else screen = Route.Menu
                    }
                } else screen = Route.Menu
            }
            Route.Auth -> AuthScreen { screen = Route.Menu }
            // المشترك في الباقة الاحترافية: يفتح على الواجهة الذهبية على طول
            Route.Menu -> if (profile?.isPro == true) GoldMenuScreen(profile, navigate, openTable) else MainMenuScreen(profile, navigate, openTable)
            Route.CreateTable -> CreateTableScreen(profile, navigate, openTable)
            Route.JoinTable -> JoinTableScreen(navigate, openTable)
            Route.Friends -> FriendsScreen(hub, navigate, openTable)
            Route.Settings -> SettingsScreen(onBack = { screen = Route.Menu }, embedded = false)
            Route.Shop -> ShopScreen(profile, navigate)
            Route.Profile -> ProfileScreen(profile) { screen = Route.Menu }
            Route.Pro -> ProScreen(profile, onBack = { screen = Route.Menu }, onGift = { screen = Route.Gift }, onLook = { screen = Route.Look })
            Route.Gift -> GiftScreen { screen = Route.Pro }
            // تخصيص الشكل: للمشترك (غيره يروح لشاشة الباقة)
            Route.Look -> if (profile?.isPro == true) LookScreen { screen = Route.Menu } else ProScreen(profile, onBack = { screen = Route.Menu }, onGift = { screen = Route.Gift })
            Route.Table -> tableId?.let { id -> TableScreen(id, user?.uid.orEmpty()) { Prefs.lastTable = null; screen = Route.Menu } } ?: run { screen = Route.Menu }
        }
    }

    // بعد تسجيل الدخول: إذن الإشعارات ورمز الجهاز، عشان تصلك دعوات أصدقائك حتى والتطبيق مقفل
    LaunchedEffect(user?.uid, verified, needsUsername) {
        if (user != null && verified && !needsUsername) {
            com.majlisk.app.MainActivity.current?.requestNotifications()
            com.majlisk.app.push.Push.register()
        }
    }
    // انتقلت لطاولة صديق من داخل طاولة: نفتحها على طول
    val switchTo by com.majlisk.app.push.Push.switchTable.collectAsState()
    LaunchedEffect(switchTo) {
        val id = switchTo ?: return@LaunchedEffect
        com.majlisk.app.push.Push.switchTable.value = null
        tableId = id; screen = Route.Table
    }
    // ضغطت على إشعار دعوة: نقبلها وندخلك الطاولة مباشرة
    val pushTable by com.majlisk.app.push.Push.pendingTable.collectAsState()
    LaunchedEffect(pushTable, user?.uid, verified, needsUsername) {
        val id = pushTable ?: return@LaunchedEffect
        if (user == null || !verified || needsUsername) return@LaunchedEffect
        com.majlisk.app.push.Push.pendingTable.value = null
        runCatching { Social.respondInvite(id, true) }
            .onSuccess { Hub.dropInvite(id); openTable(id) }
            .onFailure {
                // انتهت الدعوة (أكثر من ١٠ دقائق): لو أنت أصلاً في الطاولة ندخلك، وإلا يفتح التطبيق بس بدون أي رسالة
                val member = runCatching { Api.get("/tables/$id/member").optBoolean("member") }.getOrDefault(false)
                if (member) openTable(id) else if ((it as? com.majlisk.app.net.ApiError)?.code != "no-invite") Announcer.announce(Social.error(it))
            }
    }

    // دعوة واردة لطاولة: تظهر فوق أي شاشة (إلا إن كنت في نفس الطاولة)
    val invite = hub.invites.firstOrNull { !(screen == Route.Table && tableId == it.tableId) }
    if (invite != null && !needsUsername && verified && user != null) {
        var busy by remember(invite.tableId) { mutableStateOf(false) }
        val answer: (Boolean) -> Unit = { accept ->
            busy = true
            scope.launch {
                runCatching { Social.respondInvite(invite.tableId, accept) }
                    .onSuccess { Hub.dropInvite(invite.tableId); if (accept) openTable(invite.tableId) }
                    .onFailure { Hub.dropInvite(invite.tableId); Announcer.announce(Social.error(it)) }
                busy = false
            }
        }
        MajliskDialog("دعوة لطاولة", onDismiss = { answer(false) }) {
            Body("${invite.fromName} يدعوك للعب معه في طاولته.")
            PrimaryButton("قبول", { answer(true) }, enabled = !busy)
            SecondaryButton("رفض", { answer(false) }, enabled = !busy, fill = true)
        }
    }

    // نافذة عرض الباقة الاحترافية: أول ما يفتح التطبيق على القائمة، لغير المشتركين، ومرة كل يومين بالكثير
    var offer by remember { mutableStateOf(false) }
    LaunchedEffect(screen, profile?.loaded, profile?.isPro) {
        val p = profile ?: return@LaunchedEffect
        if (screen == Route.Menu && p.loaded && p.proAccess && !p.isPro && !p.unlimited && invite == null &&
            System.currentTimeMillis() - com.majlisk.app.data.Prefs.offerShownAt > 2 * 24 * 60 * 60 * 1000L) {
            com.majlisk.app.data.Prefs.offerShownAt = System.currentTimeMillis()
            offer = true
        }
    }
    if (offer) ProOfferDialog(onSubscribe = { offer = false; screen = Route.Pro }, onDismiss = { offer = false })

    if (confirmExit) {
        ConfirmDialog(
            title = "الخروج من مجلسك", message = "هل تريد الخروج من مجلسك؟", confirm = "خروج",
            onConfirm = { confirmExit = false; MainActivity.current?.finish() },
            onCancel = { confirmExit = false },
        )
    }
}
