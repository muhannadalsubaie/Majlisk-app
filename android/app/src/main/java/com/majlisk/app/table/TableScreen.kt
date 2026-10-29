package com.majlisk.app.table

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.draw.alpha
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

@Composable
fun TableScreen(tableId: String, uid: String, exit: () -> Unit) {
    val conn = remember(tableId) { TableConnection(tableId).also { it.start() } }
    DisposableEffect(conn) { onDispose { conn.stop(); Voice.dispose() } }
    // العودة للتطبيق (بعد مكالمة أو تطبيق آخر): نعيد الاتصال فوراً
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) { conn.reconnectNow(); Voice.onResume() } }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
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
    LaunchedEffect(tableId) { Voice.join(tableId, uid, Voice.Mode.Auto) }
    LaunchedEffect(v.voice) { Voice.sync(v.voice) }

    val leave = { conn.send("leave"); exit() }

    Box(Modifier.fillMaxSize()) {
        Screen {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SecondaryButton("القائمة", { menuOpen = true })
                if (v.kind == "baloot") SecondaryButton("السجل", { historyOpen = true })
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
            VoiceButton(v.id, uid)
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
            delay(TRICK_HOLD_MS - 150)
            Sounds.collect()
            delay(150)
            heldTrick = null
        }
    }
    val shownTrick: List<PlayedCard> = if (heldTrick == g.trickNo && g.trick.isEmpty() && g.lastTrick != null) g.lastTrick else g.trick
    val text = BalootText(v, g, shownTrick)

    // إعلان "دورك" مرة واحدة عند بداية الدور
    var wasMyTurn by remember { mutableStateOf(false) }
    LaunchedEffect(g.myTurn) {
        if (g.myTurn && !wasMyTurn) { Announcer.announce("دورك"); Sounds.turn(Announcer.readerOn) }
        wasMyTurn = g.myTurn
    }

    // المؤثرات الصوتية: نقارن الحالة الجديدة بالسابقة لنعرف ما حدث
    var prevGame by remember { mutableStateOf<GameView?>(null) }
    LaunchedEffect(g) {
        val prev = prevGame
        prevGame = g
        if (prev != null) gameSounds(prev, g, mySeat)
    }

    val reads = mapOf(
        SwipeDir.Left to { Announcer.announceNow(text.trick()) },
        SwipeDir.Right to { Announcer.announceNow(text.contract()) },
        SwipeDir.Up to { Announcer.announceNow(text.projects()) },
    )

    Column(Modifier.fillMaxWidth().twoFingerSwipes { reads[it]?.invoke() }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // النقاط: جملة واحدة كاملة لقارئ الشاشة
        val us = g.scores.getOrElse(myTeam) { 0 }
        val them = g.scores.getOrElse(1 - myTeam) { 0 }
        Row(
            Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "النقاط: لنا $us، لهم $them. الفوز عند 152" },
            horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically,
        ) {
            ScoreBox("لنا", us)
            Text("152", color = Palette.textDim)
            ScoreBox("لهم", them)
        }
        text.statusLine()?.let { Text(it, color = Palette.goldSoft, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }

        // اللاعبون حول الطاولة: الشريك في الأعلى، والخصمان يميناً ويساراً
        val seatOf = { r: Int -> (me + r) % 4 }
        PlayerTag(v, g, seatOf(2), partner = true, modifier = Modifier.align(Alignment.CenterHorizontally))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PlayerTag(v, g, seatOf(1), modifier = Modifier.weight(0.8f))
            // وسط الطاولة: الوصول له يقرأ كل الأوراق ومن لعبها، والنقر مرتين يعيد قراءتها.
            // وفي قائمة إجراءات TalkBack: القراءات الثلاث
            Box(
                Modifier.weight(3f).widthIn(max = 300.dp).aspectRatio(1f)
                    .background(Palette.green800, RoundedCornerShape(18.dp))
                    .clickable { reads.getValue(SwipeDir.Left)() }
                    .semantics(mergeDescendants = true) {
                        contentDescription = if (shownTrick.isEmpty()) "وسط الطاولة: لا توجد أوراق" else "وسط الطاولة: ${text.trick()}"
                        customActions = listOf(
                            CustomAccessibilityAction("أوراق الطاولة") { reads.getValue(SwipeDir.Left)(); true },
                            CustomAccessibilityAction("نوع اللعب") { reads.getValue(SwipeDir.Right)(); true },
                            CustomAccessibilityAction("المشاريع") { reads.getValue(SwipeDir.Up)(); true },
                        )
                    },
            ) {
                if ((g.phase == "bidding" || g.phase == "doubling") && g.qaba != null) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("ورقة الأرض", color = Palette.textDim)
                        CardFace(g.qaba, Modifier.width(70.dp))
                    }
                }
                shownTrick.forEach { p ->
                    val rel = (p.seat - me + 4) % 4
                    // الأوراق تنزل من جهة لاعبها (في RTL: Start = يمين الشاشة)
                    val align = when (rel) { 0 -> Alignment.BottomCenter; 1 -> Alignment.CenterStart; 2 -> Alignment.TopCenter; else -> Alignment.CenterEnd }
                    CardFace(p.card, Modifier.align(align).padding(8.dp).width(62.dp))
                }
            }
            PlayerTag(v, g, seatOf(3), modifier = Modifier.weight(0.8f))
        }

        if (g.phase == "matchOver" && g.outcomeStatus == "won") {
            Text(if (g.outcomeWinner == myTeam) "🎉 فاز فريقك!" else "فاز الفريق الآخر", color = Palette.goldSoft,
                style = MaterialTheme.typography.titleLarge, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }

        // أزرار المزايدة
        if (g.actions.bids.isNotEmpty()) {
            FlowRow(Modifier.fillMaxWidth().semantics { contentDescription = "المزايدة" }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                g.actions.bids.forEach { b ->
                    val click = { bidSound(b); act(jsonOf("type" to "bid", "bid" to b.raw)) }
                    if (b.type == "pass") SecondaryButton(b.label, click) else BidButton(b.label, click)
                }
            }
        }
        // الدبل: الضغطة تعلن الدبل فوراً للجميع، ثم يختار صاحبه مقفل أو مفتوح
        if (g.actions.doubleLabel != null || g.actions.canPassDouble) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                g.actions.doubleLabel?.let { label ->
                    BidButton(label, {
                        if (label == "قهوة") Sounds.gahwa() else Sounds.double(g.doubling.level + 1)
                        act(jsonOf("type" to "double"))
                    })
                }
                if (g.actions.canPassDouble) SecondaryButton("تمرير", { act(jsonOf("type" to "doublePass")) })
            }
        }
        if (g.actions.chooseLock) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BidButton("مقفل", { act(jsonOf("type" to "doubleLock", "locked" to true)) })
                BidButton("مفتوح", { act(jsonOf("type" to "doubleLock", "locked" to false)) })
            }
        }
        if (g.phase == "matchOver" && isOwner) PrimaryButton("مباراة جديدة", { conn.send("start") })

        // يد اللاعب
        if (mySeat != null) {
            Text("أوراقك", color = Palette.textDim, modifier = Modifier.semantics { heading() })
            val hand = sortHand(g.myHand)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                hand.forEach { c -> HandCard(c, legal = g.actions.legal.contains(c), modifier = Modifier.weight(1f)) { act(jsonOf("type" to "play", "card" to c.toJson())) } }
                // أماكن فارغة حتى لا تكبر الأوراق كثيراً حين تقل
                repeat((8 - hand.size).coerceAtLeast(0)) { Box(Modifier.weight(1f)) }
            }
        } else {
            Note("أنت تشاهد هذه الطاولة.")
        }
    }
}

@Composable
private fun ScoreBox(label: String, value: Int) {
    Column(
        Modifier.background(Palette.green800, RoundedCornerShape(12.dp)).padding(horizontal = 18.dp, vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(label, color = Palette.textDim)
        Text("$value", color = Palette.text, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge)
    }
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
    Text(
        label,
        color = Palette.text,
        textAlign = TextAlign.Center,
        modifier = modifier
            .then(if (turn) Modifier.border(2.dp, Palette.gold, RoundedCornerShape(10.dp)) else Modifier)
            .padding(6.dp),
    )
}

@Composable
private fun BidButton(text: String, onClick: () -> Unit) = PrimaryButtonCompact(text, onClick)

@Composable
private fun PrimaryButtonCompact(text: String, onClick: () -> Unit) {
    androidx.compose.material3.Button(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = Palette.gold, contentColor = Palette.green900),
        modifier = Modifier.height(48.dp),
    ) { Text(text, style = MaterialTheme.typography.labelLarge) }
}

/** ورقة في اليد: تبقى قابلة للتركيز حتى وهي غير مسموحة، فلا يقفز مؤشر قارئ الشاشة حين ينتهي دورك */
@Composable
private fun HandCard(card: Card, legal: Boolean, modifier: Modifier, onPlay: () -> Unit) {
    Box(
        modifier
            .aspectRatio(0.69f)
            .alpha(if (legal) 1f else 0.55f)
            .clickable { if (legal) onPlay() }
            .semantics(mergeDescendants = true) {
                contentDescription = card.label
                role = Role.Button
                if (!legal) disabled()
                onClick(label = "لعب الورقة") { if (legal) onPlay(); true }
            },
    ) { CardFace(card, Modifier.fillMaxSize()) }
}

/** صاحب المزايدة يسمع صوتها فوراً عند الضغط (ولا يتكرر حين يصل التحديث من الخادم) */
private fun bidSound(b: Bid) = when (b.type) {
    "hokm" -> Sounds.hokm()
    "sun", "ashkal" -> Sounds.sun()
    "confirmHokm" -> Sounds.confirmHokm()
    else -> Unit
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
    if (g.declared.size > prev.declared.size) Sounds.project()
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
