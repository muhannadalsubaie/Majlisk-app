package com.majlisk.app.table

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
private const val TRICK_HOLD_MS = 1200L
/** كم يبقى اسم الورقة اللي انتقل لها المؤشر بعد حركتك مخفياً (حتى تُقرأ إعلانات اللعب) */
private const val SILENT_FOCUS_MS = 4000L

@Composable
fun TableScreen(tableId: String, uid: String, exit: () -> Unit) {
    // أصوات اللعب تُشغَّل من الاتصال نفسه، فتستمر والتطبيق في الخلفية ما دمت في الطاولة
    val conn = remember(tableId) { TableConnection(tableId).also { c -> val s = GameSoundTracker(); c.onState = s::update; c.start() } }
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
    var menuOpen by remember { mutableStateOf(false) }
    var historyOpen by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }

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
    LaunchedEffect(v.voice) { Voice.sync(v.voice) }

    val leave = { conn.send("leave"); exit() }

    Box(Modifier.fillMaxSize()) {
        Screen(fill = true) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                com.majlisk.app.ui.BackButton({ menuOpen = true }, "القائمة")
                if (v.kind == "baloot") com.majlisk.app.ui.BackButton({ historyOpen = true }, "السجل")
                Text(
                    "طاولة ${gameTitle(v.kind, v.variant)}",
                    color = Palette.textDim,
                    modifier = Modifier.weight(1f).semantics { heading() },
                    textAlign = TextAlign.End,
                )
            }
            if (!connected) Note("انقطع الاتصال — جارٍ إعادة المحاولة…")

            when {
                !v.hasGame -> SeatsLobby(v, uid, conn)
                v.otherGame -> {
                    Body("هذه الطاولة ${gameTitle(v.kind, v.variant)}، وهذه اللعبة تُضاف قريباً لهذه النسخة. يمكنك البقاء في المحادثة الصوتية.")
                }
                v.game != null -> BalootBoard(v, v.game, uid, conn)
            }
            // زر الميكروفون أسفل يسار الشاشة، بعد الأوراق مباشرة في ترتيب قارئ الشاشة
            // (الرجوع منه يعود للأوراق، لا لبداية الصفحة)
            // للمشاهد (بلا أوراق) يبقى الزر في أسفل الشاشة
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { VoiceButton(v.id, uid) }
        }
    }

    if (historyOpen) HistoryDialog(v.history) { historyOpen = false }
    if (menuOpen && !confirmLeave) TableMenu(v, uid, conn, onLeave = { confirmLeave = true }, onClose = { menuOpen = false })
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
private fun BalootBoard(v: TableView, g: GameView, uid: String, conn: TableConnection) {
    val mySeat = v.mySeat
    val me = mySeat ?: 0
    val myTeam = teamOf(me)
    val isOwner = v.ownerUid == uid
    val act: (org.json.JSONObject) -> Unit = { conn.send(jsonOf("type" to "action", "action" to it)) }

    // بعد آخر ورقة في الأكلة: نبقي الأوراق الأربع ظاهرة لحظة قبل أن تذهب لصاحبها
    var heldTrick by remember { mutableStateOf<Int?>(null) }
    var lastTrickNo by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(g.trickNo) {
        val prev = lastTrickNo
        lastTrickNo = g.trickNo
        if (prev != null && g.trickNo == prev + 1 && g.lastTrick != null && g.trick.isEmpty()) {
            heldTrick = g.trickNo
            delay(TRICK_HOLD_MS)
            heldTrick = null
        }
    }
    val shownTrick: List<PlayedCard> = if (heldTrick == g.trickNo && g.trick.isEmpty() && g.lastTrick != null) g.lastTrick else g.trick
    val text = BalootText(v, g, shownTrick)

    // إعلان "دورك" مرة واحدة عند بداية الدور
    var wasMyTurn by remember { mutableStateOf(false) }
    LaunchedEffect(g.myTurn) {
        val starts = g.myTurn && !wasMyTurn
        wasMyTurn = g.myTurn
        // الجرس أولاً، ثم "دورك" بعد لحظة: قارئ الشاشة يخفض الأصوات وهو يتكلم فكان يغطي الجرس
        if (starts) { delay(700); Announcer.announce("دورك") }
    }

    val reads = mapOf(
        SwipeDir.Left to { Announcer.announceNow(text.trick()) },
        SwipeDir.Right to { Announcer.announceNow(text.contract()) },
        SwipeDir.Up to { Announcer.announceNow(text.projects()) },
        SwipeDir.Down to { Announcer.announceNow(text.turn()) },
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
                PlayerTag(v, g, seatOf(2), partner = true, modifier = Modifier.weight(3f))
                Box(Modifier.weight(0.8f))
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PlayerTag(v, g, seatOf(1), modifier = Modifier.weight(0.8f))
                Box(Modifier.weight(3f), contentAlignment = Alignment.Center) { TrickArea(v, g, shownTrick, me, text, reads) }
                PlayerTag(v, g, seatOf(3), modifier = Modifier.weight(0.8f))
            }
        }

        if (g.phase == "matchOver" && g.outcomeStatus == "won") {
            Text(if (g.outcomeWinner == myTeam) "🎉 فاز فريقك!" else "فاز الفريق الآخر", color = Palette.goldSoft,
                style = MaterialTheme.typography.titleLarge, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }

        if (g.phase == "matchOver" && isOwner) PrimaryButton("مباراة جديدة", { conn.send("start") })

        // مؤشر قارئ الشاشة: حين يختفي العنصر اللي ضغطته (ورقة لعبتها، أو أزرار المزايدة) ينتقل لأقرب ورقة
        // بدل ما يقفز لأعلى الشاشة، وبصمت: اسمها مخفي لحظات فتسمع إعلانات اللعب فقط، وتُقرأ عادي لما تحرك المؤشر
        val hand = if (mySeat != null) sortHand(g.myHand) else emptyList()
        val cardFocus = remember { mutableMapOf<String, FocusRequester>() }
        var silentKey by remember { mutableStateOf<String?>(null) }
        LaunchedEffect(silentKey) { if (silentKey != null) { delay(SILENT_FOCUS_MS); silentKey = null } }
        val focusCard: (Card?) -> Unit = { c ->
            val fr = c?.let { cardFocus[cardKey(it)] }
            if (fr != null && Announcer.readerOn) {
                silentKey = cardKey(c)
                Announcer.interruptNextEvents()
                runCatching { fr.requestFocus() }
            }
        }
        val toHand = { focusCard(hand.firstOrNull()) }
        // أزرار الشراء فوق الأوراق مباشرة، بمسافة بسيطة جداً
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // أزرار المزايدة
            if (g.actions.bids.isNotEmpty()) {
                FlowRow(
                    Modifier.fillMaxWidth().semantics { contentDescription = "المزايدة" },
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    g.actions.bids.forEach { b ->
                        com.majlisk.app.ui.SmallButton(b.label, { bidSound(b); toHand(); act(jsonOf("type" to "bid", "bid" to b.raw)) }, primary = b.type != "pass")
                    }
                }
            }
            // الدبل: الضغطة تعلن الدبل فوراً للجميع، ثم يختار صاحبه مقفل أو مفتوح
            if (g.actions.doubleLabel != null || g.actions.canPassDouble) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    g.actions.doubleLabel?.let { label ->
                        PrimaryButton(label, {
                            if (label == "قهوة") Sounds.gahwa() else Sounds.double(g.doubling.level + 1)
                            toHand()
                            act(jsonOf("type" to "double"))
                        }, modifier = Modifier.weight(1f))
                    }
                    if (g.actions.canPassDouble) SecondaryButton("بس", { toHand(); act(jsonOf("type" to "doublePass")) }, modifier = Modifier.weight(1f), fill = true)
                }
            }
            if (g.actions.chooseLock) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PrimaryButton("مقفل", { toHand(); act(jsonOf("type" to "doubleLock", "locked" to true)) }, modifier = Modifier.weight(1f))
                    PrimaryButton("مفتوح", { toHand(); act(jsonOf("type" to "doubleLock", "locked" to false)) }, modifier = Modifier.weight(1f))
                }
            }
        // يد اللاعب
        if (mySeat != null) {
            Text("أوراقك", color = Color.Transparent, modifier = Modifier.size(1.dp).semantics { heading() })
            // أوراقك مروحة على قوس كأنها في يدك: كل ورقة فوق التي على يسارها، فيبقى رمزها (في زاويتها اليسرى) ظاهراً
            Box(Modifier.fillMaxWidth().height(132.dp).padding(top = 4.dp)) {
                hand.forEachIndexed { i, c ->
                    androidx.compose.runtime.key(cardKey(c)) {
                        val k = i - (hand.size - 1) / 2f
                        val fr = remember { FocusRequester() }
                        androidx.compose.runtime.DisposableEffect(Unit) {
                            cardFocus[cardKey(c)] = fr
                            onDispose { cardFocus.remove(cardKey(c)) }
                        }
                        HandCard(
                            c, legal = g.actions.legal.contains(c), fanAngle = k * 7.5f, silent = silentKey == cardKey(c),
                            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 4.dp).size(66.dp, 96.dp).focusRequester(fr),
                        ) {
                            // الورقة اللي جنبها تأخذ المؤشر (اللي بعدها، أو اللي قبلها إن كانت الأخيرة)
                            focusCard(hand.getOrNull(i + 1) ?: hand.getOrNull(i - 1))
                            act(jsonOf("type" to "play", "card" to c.toJson()))
                        }
                    }
                }
            }
        }
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

@Composable
private fun PlayerTag(v: TableView, g: GameView, seat: Int, partner: Boolean = false, modifier: Modifier = Modifier) {
    val s = v.seats.getOrNull(seat)
    val turn = g.turn == seat && g.phase != "matchOver"
    val label = buildString {
        append(s?.username ?: "مقعد ${seat + 1}")
        if (s?.isBot == true) append(" (روبوت)")
        if (s?.away == true) append(" (انقطع الاتصال)")
        if (partner) append(" (شريكك)")
    }
    Box(
        modifier
            .border(1.dp, if (turn) Palette.gold else Color.Transparent, RoundedCornerShape(14.dp))
            .background(if (turn) Color(0x14D4AF37) else Color.Transparent, RoundedCornerShape(14.dp))
            .padding(horizontal = 4.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Palette.text, fontWeight = FontWeight.Bold, fontSize = 14.sp, textAlign = TextAlign.Center)
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
                customActions = listOf(
                    CustomAccessibilityAction("أوراق الطاولة") { reads.getValue(SwipeDir.Left)(); true },
                    CustomAccessibilityAction("نوع اللعب") { reads.getValue(SwipeDir.Right)(); true },
                    CustomAccessibilityAction("المشاريع") { reads.getValue(SwipeDir.Up)(); true },
                    CustomAccessibilityAction("دور مين") { reads.getValue(SwipeDir.Down)(); true },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        if ((g.phase == "bidding" || g.phase == "doubling") && g.qaba != null) {
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
 * silent: انتقل لها المؤشر بعد حركتك، فلا يُقرأ اسمها حتى تنتهي إعلانات اللعب.
 */
@Composable
private fun HandCard(card: Card, legal: Boolean, fanAngle: Float, silent: Boolean, modifier: Modifier, onPlay: () -> Unit) {
    val tap = { if (legal) onPlay() else Announcer.announceNow("غير متاحة") }
    Box(
        modifier
            // مكانها في المروحة (تدور حول نقطة تحت اليد)، والمسموح لعبها بإطار ذهبي فقط فيبقى شكل المروحة واحداً
            .graphicsLayer {
                rotationZ = fanAngle
                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 2.6f)
            }
            .then(if (legal) Modifier.border(3.dp, Palette.goldSoft, RoundedCornerShape(6.dp)) else Modifier)
            .focusable()
            .then(
                if (silent) Modifier.semantics(mergeDescendants = true) { contentDescription = "\u200B" }
                else Modifier.clickable { tap() }.semantics(mergeDescendants = true) {
                    contentDescription = card.label
                    role = Role.Button
                    onClick { tap(); true }
                },
            ),
    ) { CardFaceBox(card, Modifier.fillMaxSize()) }
}

private fun cardKey(c: Card) = "${c.suit}${c.rank}"

/** صاحب المزايدة يسمع صوتها فوراً عند الضغط (ولا يتكرر حين يصل التحديث من الخادم) */
private fun bidSound(b: Bid) = when (b.type) {
    "hokm" -> Sounds.hokm()
    "sun", "ashkal" -> Sounds.sun()
    "confirmHokm" -> Sounds.confirmHokm()
    "double" -> Sounds.double(2)
    else -> Unit
}

/**
 * أصوات اللعب: تُستدعى مع كل حالة تصل من الخادم (لا من الشاشة)، فتشتغل والتطبيق في الخلفية.
 * نقارن الحالة الجديدة بالسابقة لنعرف ما حدث.
 */
class GameSoundTracker {
    private var prev: GameView? = null
    private var wasMyTurn = false
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    fun update(v: TableView) {
        val g = v.game ?: run { prev = null; wasMyTurn = false; return }
        val p = prev
        prev = g
        if (p != null) {
            gameSounds(p, g, v.mySeat)
            // اكتملت الأكلة: صوت سحبها قبل أن تذهب لصاحبها
            if (g.trickNo == p.trickNo + 1 && g.lastTrick != null && g.trick.isEmpty()) main.postDelayed({ Sounds.collect() }, TRICK_HOLD_MS - 150)
        }
        // نغمة الدور (فورية، قبل إعلان "دورك")
        if (g.myTurn && !wasMyTurn) Sounds.turn(Announcer.readerOn)
        wasMyTurn = g.myTurn
    }
}

private fun gameSounds(prev: GameView, g: GameView, mySeat: Int?) {
    val total = { x: GameView -> x.handCounts.sum() }
    if (total(g) > total(prev)) Sounds.deal(total(g) - total(prev) > 12)
    // الورقة الجديدة: آخر ورقة في الأكلة الحالية، أو الرابعة إن اكتملت الأكلة للتو
    val played: Pair<Card, Card>? = when {
        g.trickNo == prev.trickNo && g.trick.size > prev.trick.size -> g.trick.last().card to g.trick.first().card
        g.trickNo == prev.trickNo + 1 && g.lastTrick != null && g.lastTrick.size == 4 -> g.lastTrick[3].card to g.lastTrick[0].card
        else -> null
    }
    if (played != null) {
        val trump = g.contract?.takeIf { it.mode == "hokm" }?.trump
        if (trump != null && played.first.suit == trump && played.second.suit != trump) Sounds.cut() else Sounds.card()
    }
    if (g.declared.size > prev.declared.size) Sounds.project(g.declared.drop(prev.declared.size).flatMap { it.kinds })
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
    // المزايدة
    if (g.hokmBidKey != null && g.hokmBidKey != prev.hokmBidKey) Sounds.hokm()
    if (g.contract != null && prev.contract == null) {
        if (g.contract.mode == "sun") Sounds.sun() else if (prev.hokmBidKey != null) Sounds.confirmHokm()
    }
    if (g.doubling.gahwa && !prev.doubling.gahwa) Sounds.gahwa()
    else if (g.doubling.level > prev.doubling.level) Sounds.double(g.doubling.level)
}
