package com.majlisk.app.table

import kotlin.math.roundToInt
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.key
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.majlisk.app.a11y.Announcer
import com.majlisk.app.data.Sounds
import com.majlisk.app.data.TableConnection
import com.majlisk.app.data.gameTitle
import com.majlisk.app.model.Bid
import com.majlisk.app.model.Card
import com.majlisk.app.model.GameView
import com.majlisk.app.model.PlayedCard
import com.majlisk.app.model.TableView
import com.majlisk.app.model.sortHand
import com.majlisk.app.model.teamOf
import com.majlisk.app.net.jsonOf
import com.majlisk.app.ui.Body
import com.majlisk.app.ui.ConfirmDialog
import com.majlisk.app.ui.Note
import com.majlisk.app.ui.Palette
import com.majlisk.app.ui.PrimaryButton
import com.majlisk.app.ui.Screen
import com.majlisk.app.ui.SecondaryButton
import com.majlisk.app.ui.Title
import com.majlisk.app.voice.Voice
import com.majlisk.app.voice.VoiceButton
import kotlinx.coroutines.delay

/** كم تبقى الأكلة المكتملة ظاهرة قبل أن تذهب لصاحبها */
private const val TRICK_HOLD_MS = 1500L
/** كم يبقى اسم الورقة اللي انتقل لها المؤشر بعد حركتك مخفياً (حتى تُقرأ إعلانات اللعب) */

@Composable
fun TableScreen(tableId: String, uid: String, exit: () -> Unit) {
    // أصوات اللعب تُشغَّل من الاتصال نفسه، فتستمر والتطبيق في الخلفية ما دمت في الطاولة
    val conn = remember(tableId) { TableConnection(tableId).also { c -> val s = GameSoundTracker(); val o = OtherGameSounds(); c.onState = { v -> s.update(v); o.update(v) }; c.myUid = uid; c.start() } }
    DisposableEffect(conn) { onDispose { conn.stop(); Voice.dispose() } }
    // الشاشة لا تنطفئ ما دمت في الطاولة (انطفاؤها يقطع الاتصال والمحادثة الصوتية)
    val window = (androidx.compose.ui.platform.LocalContext.current as? android.app.Activity)?.window
    DisposableEffect(window) {
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    // العودة للتطبيق (بعد مكالمة أو تطبيق آخر): نعيد الاتصال فوراً
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) { conn.reconnectNow(); Voice.onResume() } }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }

    // نحفظ أنك في هذه الطاولة (كل 10 ثوانٍ): إن أُغلق التطبيق وفُتح خلال دقيقة يرجعك لها
    LaunchedEffect(tableId) {
        while (true) {
            com.majlisk.app.data.Prefs.lastTable = tableId
            com.majlisk.app.data.Prefs.lastTableAt = System.currentTimeMillis()
            kotlinx.coroutines.delay(10_000)
        }
    }
    val view by conn.view.collectAsState()
    val connected by conn.connected.collectAsState()
    val closed by conn.closed.collectAsState()
    val kicked by conn.kicked.collectAsState()
    val joinRequest by conn.joinRequest.collectAsState()
    var menuOpen by remember { mutableStateOf(false) }
    /** الصفحة اللي تنفتح عليها القائمة (من إجراءات قارئ الشاشة على زر القائمة) */
    var menuStart by remember { mutableStateOf(TableMenuStart.Main) }
    var historyOpen by remember { mutableStateOf(false) }
    var dominoLogOpen by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    var chatOpen by remember { mutableStateOf(false) }
    val chatMode by com.majlisk.app.data.ChatSettings.mode.collectAsState()

    // زر الرجوع في الجهاز يفتح قائمة الطاولة (ومنها المغادرة) بدل الخروج المفاجئ
    BackHandler(enabled = kicked == null && !closed) { menuOpen = true }

    if (kicked != null) {
        Screen {
            Title(if (kicked == "banned") "حظرك مالك الطاولة" else "أخرجك مالك الطاولة")
            Body(if (kicked == "banned") "لا يمكنك دخول هذه الطاولة ولا أي طاولة يملكها." else "يمكنك دخول أي طاولة أخرى الآن، والعودة لهذه الطاولة بعد ساعة.")
            PrimaryButton("العودة للقائمة الرئيسية", exit)
        }
        return
    }
    if (closed) {
        Screen {
            Title("أُغلقت الطاولة")
            Body("لم يبق أحد على الطاولة، فأُغلقت تلقائياً.")
            PrimaryButton("العودة للقائمة الرئيسية", exit)
        }
        return
    }
    val v = view
    if (v == null) {
        Screen {
            Title("الطاولة")
            CircularProgressIndicator(color = Palette.gold)
            Body(if (connected) "جارٍ التحميل…" else "جارٍ الاتصال بالطاولة…")
            SecondaryButton("رجوع", exit)
        }
        return
    }

    // كل من يدخل الطاولة ينضم للمحادثة الصوتية مستمعاً، وميكروفونه مقفل حتى يفتحه بنفسه
    // نغمة الانضمام يسمعها المنضم نفسه أول ما تفتح الطاولة (الموجودون يسمعونها من إعلان الخادم)
    LaunchedEffect(tableId) { Sounds.tableJoin(); Voice.join(tableId, uid, Voice.Mode.Auto) }
    // متابعة المنضمين للمحادثة الصوتية صارت في اتصال الطاولة نفسه (تشتغل والتطبيق في الخلفية)

    val leave = { conn.send("leave"); exit() }

    // إيماءات اللعبة تشتغل في أي مكان في شاشة الطاولة
    Box(Modifier.fillMaxSize().tableGestureArea()) {
        Screen(fill = true) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                // قارئ الشاشة: الإجراءات تفتح الصفحة المطلوبة على طول (بدون ما تدخل القائمة)
                // الإجراءات على الزر نفسه (كانت على غلاف حوله، فيصير عنصر فاضي ما يفتح القائمة)
                com.majlisk.app.ui.BackButton({ menuStart = TableMenuStart.Main; menuOpen = true }, "القائمة", Modifier.semantics {
                    customActions = listOfNotNull(
                        CustomAccessibilityAction("اللاعبون") { menuStart = TableMenuStart.Players; menuOpen = true; true },
                        CustomAccessibilityAction("الأصدقاء") { menuStart = TableMenuStart.Friends; menuOpen = true; true },
                        if (v.ownerUid == uid) CustomAccessibilityAction("دعوة صديق") { menuStart = TableMenuStart.Invite; menuOpen = true; true } else null,
                        CustomAccessibilityAction("مغادرة الطاولة") { confirmLeave = true; true },
                    )
                })
                if (v.kind == "baloot") com.majlisk.app.ui.BackButton({ historyOpen = true }, "السجل")
                if (v.domino != null) com.majlisk.app.ui.BackButton({ dominoLogOpen = true }, "السجل")
                Text(
                    // اسم المالك جنب اسم الطاولة، ويتحدث أول ما يتغير المالك
                    "طاولة ${if (v.kind == "domino") "دومينو ${v.optTarget}" else gameTitle(v.kind, v.variant)}${if (v.ownerName.isNotEmpty()) " — المالك ${v.ownerName}" else ""}",
                    color = Palette.textDim,
                    modifier = Modifier.weight(1f).semantics { heading() },
                    textAlign = TextAlign.End,
                )
            }
            if (!connected) Note("انقطع الاتصال — جارٍ إعادة المحاولة…")

            // اللودو والجاكارو في منتصف الشاشة: مسافة فوقها مثل اللي تحتها
            // (الجاكارو الطويلة تملأ المساحة كلها بنفسها)
            val jkTall = JK_TALL && v.jackaroo != null
            if (v.hasGame && v.domino == null && (v.jackaroo != null || v.ludo != null) && !jkTall) Spacer(Modifier.weight(1f))
            when {
                !v.hasGame -> SeatsLobby(v, uid, conn)
                // الدومينو: الطاولة تملأ المساحة الباقية بالضبط (صفحة وحدة بدون تمرير)
                v.domino != null -> DominoBoard(v, v.domino, conn, v.ownerUid == uid, Modifier.weight(1f)) { dominoLogOpen = true }
                v.jackaroo != null -> JackarooBoard(v, v.jackaroo, conn, v.ownerUid == uid, if (jkTall) Modifier.weight(1f) else Modifier)
                v.ludo != null -> LudoBoard(v, v.ludo, conn, v.ownerUid == uid)
                v.game != null -> BalootBoard(v, v.game, uid, conn)
            }
            // زر الميكروفون أسفل يسار الشاشة، بعد الأوراق مباشرة في ترتيب قارئ الشاشة
            // (الرجوع منه يعود للأوراق، لا لبداية الصفحة)
            // للمشاهد (بلا أوراق) يبقى الزر في أسفل الشاشة
            if (v.domino == null && !jkTall) Spacer(Modifier.weight(1f))
            // الدومينو: قطعك تحت فوق الميكروفون
            v.domino?.let { DominoHand(v, it, conn) { dominoLogOpen = true } }
            // زر الدردشة الكتابية جنب الميكروفون في نفس الصف (يختفي إن أطفأتها من الإعدادات)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                if (chatMode != com.majlisk.app.data.ChatMode.OFF) ChatButton(conn) { chatOpen = true; conn.chatOpen = true }
                VoiceButton(v.id, uid)
            }
        }
        // آخر رسالة: لحظات في الزاوية اليمين تحت، بعيداً عن الطاولة والأوراق
        if (chatMode != com.majlisk.app.data.ChatMode.OFF && !chatOpen) ChatToast(conn, Modifier.align(Alignment.BottomStart))
    }
    if (chatOpen) ChatDialog(conn) { chatOpen = false; conn.chatOpen = false }

    if (historyOpen) HistoryDialog(v.history) { historyOpen = false }
    if (dominoLogOpen && v.domino != null) DominoLogDialog(v.domino) { dominoLogOpen = false }
    // طلب انضمام لطاولتك الخاصة من صديق
    joinRequest?.let { (rid, rname) ->
        val answer = { a: String -> conn.send(jsonOf("type" to "joinAnswer", "uid" to rid, "answer" to a, "accept" to (a == "accept"))); conn.joinRequest.value = null }
        // نافذة في منتصف الشاشة (بنفس شكل التطبيق): فلان طلب الانضمام
        // قبول: يدخل على طول؛ تجاهل: يبقى طلبه معلّق 5 دقائق؛ رفض: ما يقدر يدخل أو يطلب نصف ساعة
        com.majlisk.app.ui.MajliskDialog("$rname طلب الانضمام", { answer("ignore") }) {
            com.majlisk.app.ui.PrimaryButton("قبول", { answer("accept") })
            com.majlisk.app.ui.SecondaryButton("تجاهل", { answer("ignore") }, fill = true)
            com.majlisk.app.ui.DangerButton("رفض", { answer("reject") })
        }
    }
    if (menuOpen && !confirmLeave) TableMenu(v, uid, conn, onLeave = { confirmLeave = true }, onClose = { menuOpen = false }, start = menuStart)
    if (confirmLeave) {
        ConfirmDialog(
            "مغادرة الطاولة",
            if (v.playing && v.mySeat != null) "المباراة جارية — سيحل روبوت مكانك. هل تريد المغادرة؟" else "هل تريد مغادرة الطاولة؟",
            "مغادرة",
            onConfirm = { confirmLeave = false; leave() },
            onCancel = { confirmLeave = false; menuOpen = false },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BalootBoard(v: TableView, g: GameView, uid: String, conn: TableConnection) {
    val mySeat = v.mySeat
    val me = mySeat ?: 0
    val myTeam = teamOf(me)
    val isOwner = v.ownerUid == uid
    val act: (org.json.JSONObject) -> Unit = { conn.send(jsonOf("type" to "action", "action" to it)) }

    // بعد آخر ورقة في الأكلة: نبقي الأوراق الأربع ظاهرة لحظة قبل أن تذهب لصاحبها
    // الحساب فوري في نفس الإطار (بدون انتظار تأثير جانبي)، فما تختفي أوراق الأكلة وترجع
    var releasedTrick by remember { mutableStateOf(g.trickNo) }
    LaunchedEffect(g.trickNo) {
        val n = g.trickNo
        delay(TRICK_HOLD_MS)
        releasedTrick = n
    }
    val shownTrick: List<PlayedCard> = if (g.trick.isEmpty() && g.trickNo > 0 && releasedTrick != g.trickNo) (g.lastTrick ?: g.trick) else g.trick
    val text = BalootText(v, g, shownTrick)

    // إعلان "دورك" عند بداية كل دور (حتى لو جاك الدور مرتين ورا بعض، مثل لما تاكل الأكلة)
    var lastTurn by remember { mutableStateOf<String?>(null) }
    val turnNow = turnKey(g)
    LaunchedEffect(turnNow) {
        val starts = turnNow != null && turnNow != lastTurn
        lastTurn = turnNow
        // الجرس أولاً، ثم "دورك" بعد لحظة: قارئ الشاشة يخفض الأصوات وهو يتكلم فكان يغطي الجرس
        // صوت "دورك" المنطوق يكفي؛ قارئ الشاشة يعلنها فقط إذا كان الصوت مطفأ (الكتم العام)
        if (starts && com.majlisk.app.data.Prefs.muted) Announcer.announce("دورك")
    }

    val reads = mapOf(
        SwipeDir.Left to { Announcer.announceNow(text.trick()) },
        SwipeDir.Right to { val c = text.contract(); if (c.isNotEmpty()) Announcer.announceNow(c) },
        // من تحت لفوق = الدور عند مين (مثل باقي الألعاب)، ومن فوق لتحت = المشاريع
        SwipeDir.Up to { Announcer.announceNow(text.turn()) },
        SwipeDir.Down to { Announcer.announceNow(text.projects()) },
    )

    Column(Modifier.fillMaxWidth().twoFingerSwipes { reads[it]?.invoke() }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // النقاط: جملة واحدة كاملة لقارئ الشاشة
        val us = g.scores.getOrElse(myTeam) { 0 }
        val them = g.scores.getOrElse(1 - myTeam) { 0 }
        // المشاهد: بدل "لنا ولهم" أسماء كل فريق
        val teamName = { t: Int -> "${text.name(t)} و${text.name(t + 2)}" }
        val usLabel = if (mySeat == null) teamName(0) else "لنا"
        val themLabel = if (mySeat == null) teamName(1) else "لهم"
        Row(
            Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min)
                .semantics(mergeDescendants = true) { contentDescription = "النقاط: $usLabel $us، $themLabel $them. الفوز عند 152" },
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
        ) {
            ScoreBox(usLabel, us, mine = mySeat != null, modifier = Modifier.weight(1f).fillMaxHeight())
            Text("152", color = Palette.textDim, fontSize = 13.sp,
                modifier = Modifier.dashedPill().padding(horizontal = 10.dp, vertical = 4.dp))
            ScoreBox(themLabel, them, mine = false, modifier = Modifier.weight(1f).fillMaxHeight())
        }
        text.statusLine()?.let { Text(it, color = Palette.goldSoft, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }

        // اللاعبون حول الطاولة: الشريك في الأعلى، والخصمان يميناً ويساراً، ووسط الطاولة دائرة
        val seatOf = { r: Int -> (me + r) % 4 }
        Column(
            Modifier.fillMaxWidth()
                .background(androidx.compose.ui.graphics.Brush.radialGradient(listOf(Color(0x661B4D39), Color.Transparent)), RoundedCornerShape(24.dp))
                .padding(vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.weight(0.8f))
                PlayerTag(v, g, seatOf(2), faces = g.sawaHands?.getOrNull(seatOf(2)) ?: text.faces(seatOf(2)), note = seatNote(g, seatOf(2)), partner = mySeat != null, modifier = Modifier.weight(3f))
                Box(Modifier.weight(0.8f))
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PlayerTag(v, g, seatOf(1), faces = g.sawaHands?.getOrNull(seatOf(1)) ?: text.faces(seatOf(1)), note = seatNote(g, seatOf(1)), modifier = Modifier.weight(0.8f))
                Box(Modifier.weight(3f), contentAlignment = Alignment.Center) { TrickArea(v, g, shownTrick, me, text, reads) }
                PlayerTag(v, g, seatOf(3), faces = g.sawaHands?.getOrNull(seatOf(3)) ?: text.faces(seatOf(3)), note = seatNote(g, seatOf(3)), modifier = Modifier.weight(0.8f))
            }
        }

        if (g.phase == "matchOver" && g.outcomeStatus == "won") {
            // المشاهد: اسم الفريق الفائز بس (بلا «فريقك»)
            Text(if (mySeat == null) "فاز فريق ${teamName(g.outcomeWinner ?: 0)}" else if (g.outcomeWinner == myTeam) "🎉 فاز فريقك!" else "فاز الفريق الآخر", color = Palette.goldSoft,
                style = MaterialTheme.typography.titleLarge, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }

        if (g.phase == "matchOver" && isOwner) PrimaryButton("مباراة جديدة", { conn.send("start") })

        // مؤشر قارئ الشاشة: بعد ما تلعب ورقة ينتقل لكلمة «أوراقك»، وأزرار الشراء لما تختفي ينتقل لأوراقك
        val hand = if (mySeat != null) sortHand(g.myHand) else emptyList()
        // كل ورقة عنصر لحالها (تتنقل بينها يمين ويسار)، بس العنصر مربوط بمكانه في اليد مو بالورقة:
        // لما تلعب ورقة يبقى مكانها (ويصير فيه الورقة اللي جنبها) فالمؤشر ما يقفز
        val slotFocus = remember { mutableMapOf<Int, FocusRequester>() }
        val focusSlot: (Int) -> Unit = { i ->
            slotFocus[i]?.let { fr -> if (Announcer.readerOn) { Announcer.interruptNextEvents(); runCatching { fr.requestFocus() } } }
        }
        val focusCard: (Card?) -> Unit = { c -> if (c != null) focusSlot(hand.size - 1) }
        // لعبت آخر ورقة في اليد (مكانها يختفي): المؤشر للمكان اللي قبله
        var playedPos by remember { mutableStateOf<Int?>(null) }
        LaunchedEffect(hand.size) {
            val p = playedPos ?: return@LaunchedEffect
            playedPos = null
            if (p >= hand.size && hand.isNotEmpty()) { delay(50); focusSlot(hand.size - 1) }
        }
        // بعد ما تضغط زر شراء/دبل يختفي: المؤشر يروح لأوراقك (ما ينط فوق ولا تحت)
        // pending: (null، الورقة اللي يروح لها المؤشر)
        var pending by remember { mutableStateOf<Pair<String?, String>?>(null) }
        LaunchedEffect(hand.map(::cardKey), g.actions.bids.size, g.actions.doubleLabel, g.actions.chooseLock) {
            val p = pending ?: return@LaunchedEffect
            if (p.first != null && hand.any { cardKey(it) == p.first }) return@LaunchedEffect
            pending = null
            delay(60)
            focusCard(hand.firstOrNull { cardKey(it) == p.second })
        }
        val toHand = { hand.lastOrNull()?.let { pending = null to cardKey(it) }; Unit }
        // إجراءات قارئ الشاشة على أوراقك (والمؤشر على أي ورقة): نفس أزرار الشراء والدبل الظاهرة الحين
        val cardActions = buildList {
            g.actions.bids.forEach { b -> add((if (b.type == "pass" && g.bidRound == 2) "ولا" else b.label) to { act(jsonOf("type" to "bid", "bid" to b.raw)) }) }
            g.actions.doubleLabel?.let { add(it to { act(jsonOf("type" to "double")) }) }
            if (g.actions.canPassDouble) add("بس" to { act(jsonOf("type" to "doublePass")) })
            if (g.actions.canSawa) add("سوا" to { act(jsonOf("type" to "sawa")) })
            if (g.actions.waraqDecision) add("بس" to { act(jsonOf("type" to "waraq", "call" to false)) })
            if (g.actions.canWaraq) add("ورق" to { act(jsonOf("type" to "waraq", "call" to true)) })
            if (g.actions.chooseLock) {
                add("مقفل" to { act(jsonOf("type" to "doubleLock", "locked" to true)) })
                add("مفتوح" to { act(jsonOf("type" to "doubleLock", "locked" to false)) })
            }
        }
        // أزرار الشراء فوق الأوراق مباشرة، بمسافة بسيطة جداً
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // أزرار المزايدة
            if (g.actions.bids.isNotEmpty()) {
                FlowRow(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    g.actions.bids.forEach { b ->
                        // اللفة الثانية: "ولا" بدل "بس"
                        com.majlisk.app.ui.SmallButton(if (b.type == "pass" && g.bidRound == 2) "ولا" else b.label, { toHand(); act(jsonOf("type" to "bid", "bid" to b.raw)) }, primary = b.type != "pass")
                    }
                }
            }
            // الدبل: الضغطة تعلن الدبل فوراً للجميع، ثم يختار صاحبه مقفل أو مفتوح
            if (g.actions.doubleLabel != null || g.actions.canPassDouble) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // «بس» يمين و«دبل» يسار
                    if (g.actions.canPassDouble) SecondaryButton("بس", { toHand(); act(jsonOf("type" to "doublePass")) }, modifier = Modifier.weight(1f), fill = true)
                    g.actions.doubleLabel?.let { label ->
                        PrimaryButton(label, {
                            toHand()
                            act(jsonOf("type" to "double"))
                        }, modifier = Modifier.weight(1f))
                    }
                }
            }
            // سوا (اختياري): كل أوراقك مضمونة تاكل، تنحسب الأكلات الباقية لفريقك وتنتهي الصكة
            if (g.actions.canSawa) PrimaryButton("سوا", { act(jsonOf("type" to "sawa")) })
            // «ورق»: أوراقك الخمس الأولى كلها ٧ و٨ و٩ بس — يعاد التوزيع. بعد الشراء يجيك دورك: بس أو ورق
            if (g.actions.waraqDecision) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SecondaryButton("بس", { toHand(); act(jsonOf("type" to "waraq", "call" to false)) }, modifier = Modifier.weight(1f), fill = true)
                    PrimaryButton("ورق", { toHand(); act(jsonOf("type" to "waraq", "call" to true)) }, modifier = Modifier.weight(1f))
                }
            } else if (g.actions.canWaraq) PrimaryButton("ورق", { toHand(); act(jsonOf("type" to "waraq", "call" to true)) })
            if (g.actions.chooseLock) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton("مقفل", { toHand(); act(jsonOf("type" to "doubleLock", "locked" to true)) }, modifier = Modifier.weight(1f))
                    PrimaryButton("مفتوح", { toHand(); act(jsonOf("type" to "doubleLock", "locked" to false)) }, modifier = Modifier.weight(1f))
                }
            }
        // يد اللاعب
        if (mySeat != null) {
            seatNote(g, mySeat)?.let { Text("أنت: $it", color = Palette.goldSoft, fontSize = 13.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }
            text.faces(mySeat).takeIf { it.isNotEmpty() }?.let { mine ->
                Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    Text("مشروعك", color = Palette.goldSoft, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    ProjectFaces(mine)
                }
            }
            // أوراقك مروحة على قوس كأنها في يدك: كل ورقة فوق التي على يسارها، فيبقى رمزها (في زاويتها اليسرى) ظاهراً
            // ترتيب الأوراق لقارئ الشاشة داخل اليد فقط (لا يختلط بباقي عناصر الشاشة)
            Box(Modifier.fillMaxWidth().height(152.dp).padding(top = 4.dp).semantics { isTraversalGroup = true }) {
                hand.forEachIndexed { i, c ->
                    // مربوط بالمكان (i) مو بالورقة
                    androidx.compose.runtime.key(i) {
                        val k = i - (hand.size - 1) / 2f
                        val fr = remember { FocusRequester() }
                        androidx.compose.runtime.DisposableEffect(Unit) {
                            slotFocus[i] = fr
                            onDispose { if (slotFocus[i] === fr) slotFocus.remove(i) }
                        }
                        HandCard(
                            c, legal = g.actions.legal.contains(c), fanAngle = k * 7.5f, actions = cardActions,
                            // قارئ الشاشة يقرأ من اليمين لليسار: هاص الأكبر أولاً
                            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 4.dp).size(80.dp, 116.dp).focusRequester(fr)
                                .semantics { traversalIndex = (hand.size - i).toFloat() },
                        ) {
                            if (Announcer.readerOn) { Announcer.interruptNextEvents(); playedPos = i }
                            act(jsonOf("type" to "play", "card" to c.toJson()))
                        }
                    }
                }
            }
        }
        // المشاهد: اللاعب الرابع تحت (الأربعة متقابلين حول الطاولة)
        if (mySeat == null) PlayerTag(v, g, seatOf(0), faces = g.sawaHands?.getOrNull(seatOf(0)) ?: text.faces(seatOf(0)), note = seatNote(g, seatOf(0)), modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun ScoreBox(label: String, value: Int, mine: Boolean, modifier: Modifier) {
    Column(
        modifier.shadow(6.dp, RoundedCornerShape(14.dp))
            .background(Brush.verticalGradient(listOf(Palette.green700, Palette.green800)), RoundedCornerShape(14.dp))
            .border(1.dp, if (mine) Palette.gold else Palette.green700, RoundedCornerShape(14.dp))
            .padding(horizontal = 4.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text(label, color = Palette.textDim, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text("$value", color = Palette.gold, fontWeight = FontWeight.Bold, fontSize = 30.sp, lineHeight = 30.sp)
    }
}

/** حد متقطع حول هدف النقاط */
private fun Modifier.dashedPill(): Modifier = drawBehind {
    drawRoundRect(
        color = Palette.green700, cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2),
        style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(6f, 4f))),
    )
}

/**
 * تحت اسم اللاعب قبل توزيع بقية الورق: «الموزع»، ونوع ما اشتراه (حكم، صن، أشكل).
 * أول ما تتوزع بقية الأوراق تختفي كلها.
 */
private fun seatNote(g: GameView, seat: Int): String? {
    if (g.phase != "bidding" && g.phase != "doubling") return null
    val parts = mutableListOf<String>()
    if (g.dealer == seat) parts += "الموزع"
    val c = g.contract
    when {
        c != null && c.buyer == seat -> parts += when {
            // الحكم الثاني: بعد ما يحدد اللون ينكتب نوعه
            c.mode == "hokm" && (g.bidRound == 2 || g.secondHokmSeat == seat) -> "حكم ثاني ${com.majlisk.app.model.SUIT_NAMES[c.trump].orEmpty()}"
            c.mode == "hokm" -> "اشترى حكم"
            c.qabaTo != c.buyer -> "اشترى أشكل"
            else -> "اشترى صن"
        }
        // الحكم الثاني قبل ما يحدد اللون
        c == null && g.secondHokmSeat == seat -> parts += "حكم ثاني"
        c == null && g.hokmBidKey?.firstOrNull()?.digitToIntOrNull() == seat -> parts += "اشترى حكم"
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString("، ")
}

@Composable
private fun PlayerTag(v: TableView, g: GameView, seat: Int, faces: List<Card> = emptyList(), partner: Boolean = false, note: String? = null, modifier: Modifier = Modifier) {
    val s = v.seats.getOrNull(seat)
    val turn = g.turn == seat && g.phase != "matchOver"
    val label = buildString {
        append(s?.username ?: "مقعد ${seat + 1}")
        if (s?.isBot == true) append(" (روبوت)")
        if (s?.away == true) append(" (انقطع الاتصال)")
        if (partner) append(" (شريكك)")
    }
    Column(
        modifier
            .border(1.dp, if (turn) Palette.gold else Color.Transparent, RoundedCornerShape(14.dp))
            .background(if (turn) Color(0x14D4AF37) else Color.Transparent, RoundedCornerShape(14.dp))
            .padding(horizontal = 4.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        com.majlisk.app.ui.Avatar(v.seatUids.getOrNull(seat), s?.username.orEmpty(), 34.dp)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, color = Palette.text, fontWeight = FontWeight.Bold, fontSize = 14.sp, textAlign = TextAlign.Center)
            TurnClock(v, seat, turn)
        }
        if (note != null) Text(note, color = Palette.goldSoft, fontSize = 12.sp, textAlign = TextAlign.Center)
        if (faces.isNotEmpty()) ProjectFaces(faces, if (partner) 200f else 62f)
    }
}

/** أوراق المشروع مكشوفة قدام صاحبه طوال اللفة الثانية (للعرض فقط — قارئ الشاشة يسمعها من الإعلان) */
@Composable
private fun ProjectFaces(faces: List<Card>, maxWidth: Float = 200f) {
    // تحت اسم صاحبه: الأوراق مروحة مثل اليد (كل ورقة فوق اللي على يسارها، فيبان رمزها في زاويتها)
    val n = faces.size
    val w = if (maxWidth < 100f) 30f else 36f; val h = w * 1.45f
    val step = if (n > 1) minOf(w * 0.5f, maxOf(9f, (maxWidth - w - 12f) / (n - 1))) else 0f
    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalLayoutDirection provides androidx.compose.ui.unit.LayoutDirection.Ltr) {
        Box(
            Modifier.clearAndSetSemantics { }.size((w + step * maxOf(n - 1, 0) + 14f).dp, (h + 10f).dp),
            contentAlignment = Alignment.BottomCenter,
        ) {
            faces.forEachIndexed { i, c ->
                val k = i - (n - 1) / 2f
                CardFaceBox(c, Modifier.size(w.dp, h.dp)
                    .absoluteOffset(x = (k * step).dp)
                    .graphicsLayer {
                        rotationZ = k * 7f
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 2.4f)
                    })
            }
        }
    }
}

/**
 * وسط الطاولة: الأوراق تتكدّس فوق بعض، كل ورقة مزاحة ومائلة قليلاً باتجاه من رماها، والأخيرة في الأعلى.
 * الوصول لها يقرأ كل الأوراق ومن لعبها، والنقر مرتين يعيد قراءتها، وفي قائمة إجراءات TalkBack القراءات الأربع.
 */
@Composable
private fun TrickArea(v: TableView, g: GameView, shownTrick: List<PlayedCard>, me: Int, text: BalootText, reads: Map<SwipeDir, () -> Unit>) {
    // طاولة ثلاثية الأبعاد: مائلة كأنك جالس عليها، بإطار خشب ومفرش أخضر
    Box(
        Modifier.widthIn(max = 300.dp).fillMaxWidth().aspectRatio(1f)
            .graphicsLayer { rotationX = 40f; cameraDistance = 12f * density }
            .shadow(14.dp, androidx.compose.foundation.shape.CircleShape)
            .background(Brush.radialGradient(listOf(Color(0xFF8A5A2B), Color(0xFF5C3A1A), Color(0xFF3B2410))), androidx.compose.foundation.shape.CircleShape)
            .padding(10.dp)
            .clip(androidx.compose.foundation.shape.CircleShape)
            .background(Brush.radialGradient(listOf(Color(0xFF1E6B4A), Color(0xFF145036), Color(0xFF0B241B))))
            .border(1.dp, Color(0x55D4AF37), androidx.compose.foundation.shape.CircleShape)
            .clickable { reads.getValue(SwipeDir.Left)() }
            .semantics(mergeDescendants = true) {
                contentDescription = "وسط الطاولة: ${text.trick()}"
                // النقر مرتين يعيد قراءة أوراق الطاولة؛ باقي القراءات بالإيماءات (الإجراءات للشراء والمايك والقائمة بس)
            },
        contentAlignment = Alignment.Center,
    ) {
        if ((g.phase == "bidding" || g.phase == "doubling" || g.phase == "waraq") && g.qaba != null) {
            Column(Modifier.absoluteOffset(y = 6.dp - 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("ورقة الأرض", color = Palette.textDim, fontSize = 14.sp)
                CardFaceBox(g.qaba)
            }
        }
        shownTrick.forEach { p ->
            // الإزاحة والميل والجهة: نفس قيم التطبيق الحالي (يمين الشاشة = اللاعب التالي)
            val (dx, dy, rot) = when ((p.seat - me + 4) % 4) {
                0 -> Triple(0, 38, 3f)
                1 -> Triple(36, 0, 9f)
                2 -> Triple(0, -38, -4f)
                else -> Triple(-36, 0, -9f)
            }
            key(g.trickNo, p.seat) {
                val anim = remember { androidx.compose.animation.core.Animatable(0f) }
                LaunchedEffect(Unit) { anim.animateTo(1f, androidx.compose.animation.core.tween(350)) }
                val f = 1f - anim.value
                Box(
                    Modifier.absoluteOffset((dx + dx * 1.5f * f).dp, (dy + dy * 1.5f * f).dp)
                        .graphicsLayer { rotationZ = rot; alpha = anim.value; scaleX = 0.85f + 0.15f * anim.value; scaleY = scaleX },
                ) { CardFaceBox(p.card) }
            }
        }
    }
}

/** ورقة بحجم أوراق الطاولة: خلفية بيضاء وزوايا وظل */
@Composable
private fun CardFaceBox(card: Card, modifier: Modifier = Modifier.size(58.dp, 84.dp)) {
    // سُمك الورقة: حافة رمادية تحتها، وظل أعمق
    Box(modifier.shadow(8.dp, RoundedCornerShape(6.dp))) {
        Box(Modifier.matchParentSize().absoluteOffset(y = 1.5.dp).background(Color(0xFFB9B4A6), RoundedCornerShape(6.dp)))
        CardFace(card, Modifier.matchParentSize().clip(RoundedCornerShape(6.dp)).background(Color.White).border(0.5.dp, Color(0xFFCFC9B8), RoundedCornerShape(6.dp)))
    }
}

/**
 * ورقة في اليد: تبقى قابلة للتركيز حتى وهي غير مسموحة، فلا يقفز مؤشر قارئ الشاشة حين ينتهي دورك.
 * لا نعلن "غير متاحة" كحالة: تغيّرها لحظة انتهاء دورك كان يجعل قارئ الشاشة يعيد قراءة الورقة المحددة.
 */
@Composable
private fun HandCard(card: Card, legal: Boolean, fanAngle: Float, modifier: Modifier, actions: List<Pair<String, () -> Unit>> = emptyList(), onPlay: () -> Unit) {
    val tap = { if (legal) onPlay() else { Sounds.illegal(); Announcer.announceNow("غير متاحة") } }
    Box(
        modifier
            // مكانها في المروحة (تدور حول نقطة تحت اليد)، والمسموح لعبها بإطار ذهبي فقط فيبقى شكل المروحة واحداً
            .graphicsLayer {
                rotationZ = fanAngle
                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 2.6f)
            }
            .then(if (legal) Modifier.border(3.dp, Palette.goldSoft, RoundedCornerShape(6.dp)) else Modifier)
            .focusable()
            // اسم الورقة دائماً (ما نفرّغه أبداً: كان يُقرأ "فاضي" أو "مسافة")
            .clickable { tap() }.semantics(mergeDescendants = true) {
                contentDescription = card.label
                role = Role.Button
                onClick { tap(); true }
                // الشراء والدبل كإجراءات على الورقة (للمكفوفين: ما يحتاجون يروحون للأزرار)
                if (actions.isNotEmpty()) customActions = actions.map { (label, run) -> CustomAccessibilityAction(label) { run(); true } }
            },
    ) { CardFaceBox(card, Modifier.fillMaxSize()) }
}

/**
 * هوية الدور الحالي إن كان لك (null إن لم يكن): تتغير مع كل دور جديد لك حتى لو جاك مرتين ورا بعض
 * (أكلت الأكلة فبدأت التالية، أو رجع لك الدور في المزايدة أو الدبل)، فينقال "دورك" كل مرة
 */
fun turnKey(g: GameView): String? = if (!g.myTurn) null else
    listOf(g.phase, g.bidRound, g.hokmBidKey, g.contract?.buyer, g.doubling.level, g.trickNo, g.trick.size).joinToString("|")

private fun cardKey(c: Card) = "${c.suit}${c.rank}"


/**
 * أصوات اللعب: تُستدعى مع كل حالة تصل من الخادم (لا من الشاشة)، فتشتغل والتطبيق في الخلفية.
 * نقارن الحالة الجديدة بالسابقة لنعرف ما حدث.
 */
class GameSoundTracker {
    private var prev: GameView? = null
    private var lastTurn: String? = null
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private var lastBidTurn: String? = null
    private var lastDoubleTurn: String? = null

    fun update(v: TableView) {
        val g = v.game ?: run { prev = null; lastTurn = null; return }
        val p = prev
        prev = g
        if (p != null) {
            gameSounds(p, g, v.mySeat)
            // اكتملت الأكلة: صوت سحبها قبل أن تذهب لصاحبها
            if (g.trickNo == p.trickNo + 1 && g.lastTrick != null && g.trick.isEmpty()) main.postDelayed({ Sounds.collect() }, TRICK_HOLD_MS) // نفس لحظة انسحاب الأوراق
            // «سوا»: انتهى كشف الأوراق، تتجمع وتنحسب الصكة
            if (p.sawaHands != null && g.sawaHands == null) Sounds.collect()
        }
        // نغمة الدور (فورية، قبل إعلان "دورك")
        val key = turnKey(g)
        if (key != null && key != lastTurn) Sounds.turn(Announcer.readerOn)
        lastTurn = key
        // أثناء المزايدة: قارئ الشاشة يقول «دور فلان» لما ينتقل الدور لغيرك (ودورك يقوله التعليق الصوتي)
        // بعد التوزيع: «دور فلان» ينتظر لين تخلص مهلة التوزيع (فتنسمع ورقة الأرض كاملة)
        val bidTurn = if (g.phase == "bidding" && !g.dealing && g.turn != v.mySeat) "${g.phase}|${g.bidRound}|${g.turn}" else null
        if (bidTurn != null && bidTurn != lastBidTurn) {
            val who = v.seats.getOrNull(g.turn)?.username ?: "مقعد ${g.turn + 1}"
            main.postDelayed({ Announcer.announce("دور $who") }, 700)
        }
        lastBidTurn = bidTurn
        // قرار الدبل: «دور فلان» ثم خياراته (بس أو دبل/ثري/فور/قهوة)
        val deciders = if (g.phase == "doubling") g.doubling.deciders else emptyList()
        val dblTurn = if (deciders.isEmpty()) null else "${g.doubling.level}|$deciders"
        if (dblTurn != null && dblTurn != lastDoubleTurn) {
            val label = g.doubling.label
            val me = v.mySeat
            val text = if (me != null && me in deciders) "دورك، بس أو $label" else {
                val names = deciders.map { v.seats.getOrNull(it)?.username ?: "مقعد ${it + 1}" }
                "دور ${names.joinToString(" و")}، ${if (names.size > 1) "يختارون" else "يختار"} بس أو $label"
            }
            main.postDelayed({ Announcer.announce(text) }, 700)
        }
        lastDoubleTurn = dblTurn
    }
}

private fun gameSounds(prev: GameView, g: GameView, mySeat: Int?) {
    val total = { x: GameView -> x.handCounts.sum() }
    if (total(g) > total(prev)) Sounds.deal(total(g) - total(prev) > 12)
    // الكل قال بس في اللفتين: إعادة توزيع (نفس عدد الأوراق) بصوت التوزيع مثل بداية الجولة
    else if (g.phase == "bidding" && g.bidRound == 1 && prev.phase == "bidding" && (prev.bidRound == 2 || prev.dealer != g.dealer)) Sounds.deal(true)
    // الورقة الجديدة: آخر ورقة في الأكلة الحالية، أو الرابعة إن اكتملت الأكلة للتو
    val played: Pair<Card, Card>? = when {
        g.trickNo == prev.trickNo && g.trick.size > prev.trick.size -> g.trick.last().card to g.trick.first().card
        g.trickNo == prev.trickNo + 1 && g.lastTrick != null && g.lastTrick.size == 4 -> g.lastTrick[3].card to g.lastTrick[0].card
        else -> null
    }
    if (played != null) {
        val trump = g.contract?.takeIf { it.mode == "hokm" }?.trump
        // أي ورقة حكم في الحكم (قطع أو أول ورقة في الأرض): صوت الحكم
        if (trump != null && played.first.suit == trump) Sounds.cut() else Sounds.card()
    }
    // إعلان المشروع (اللفة الأولى): صوت كل مشروع
    if (g.declared.size > prev.declared.size) Sounds.project(g.declared.drop(prev.declared.size).flatMap { it.kinds })
    // كشف أوراق المشروع (اللفة الثانية)
    if (g.declared.count { it.faces.isNotEmpty() } > prev.declared.count { it.faces.isNotEmpty() }) Sounds.projectReveal()
    if (g.balootSeat != null && prev.balootSeat == null) Sounds.baloot()
    // نهاية الصكة (بعد صوت سحب الأكلة الأخيرة)، ثم نهاية المباراة
    val r = g.lastHand
    if (r != null && prev.lastHand == null) {
        val team = mySeat?.let { teamOf(it) }
        val result = if (team == null) "neutral" else {
            val mine = r.points.getOrElse(team) { 0 }; val theirs = r.points.getOrElse(1 - team) { 0 }
            if (mine > theirs) "win" else if (mine < theirs) "lose" else "neutral"
        }
        val h = android.os.Handler(android.os.Looper.getMainLooper())
        h.postDelayed({ Sounds.handEnd(result, r.kaboot != null) }, TRICK_HOLD_MS + 200)
        if (g.outcomeStatus == "won" && team != null) h.postDelayed({ Sounds.matchEnd(g.outcomeWinner == team) }, TRICK_HOLD_MS + 1600)
    }
    // المزايدة والدبل: أصوات منطوقة يرسلها الخادم مع الإعلان (Sounds.voices)
}
