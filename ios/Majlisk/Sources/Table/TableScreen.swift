import SwiftUI

/// كم تبقى الأكلة المكتملة ظاهرة قبل أن تذهب لصاحبها
private let TRICK_HOLD: Double = 1.5

/// هوية الدور الحالي إن كان لك (nil إن لم يكن): تتغير مع كل دور جديد لك حتى لو جاك مرتين ورا بعض
/// (أكلت الأكلة فبدأت التالية، أو رجع لك الدور في المزايدة أو الدبل)، فينقال "دورك" كل مرة
func turnKey(_ g: GameView) -> String? {
    guard g.myTurn else { return nil }
    return "\(g.phase)|\(g.bidRound)|\(g.hokmBidKey ?? "")|\(g.contract?.buyer ?? -1)|\(g.doubling.level)|\(g.trickNo)|\(g.trick.count)"
}

struct TableScreen: View {
    let tableId: String
    let uid: String
    let exit: () -> Void
    @StateObject private var conn: TableConnection
    /// الصفحة اللي تنفتح عليها القائمة (من إجراءات قارئ الشاشة على زر القائمة)
    /// القائمة مفتوحة على أي صفحة (عنصر وحده بدل قيمتين: الإجراءات كانت تفتح القائمة الرئيسية بدل الصفحة المطلوبة)
    @State private var menuSheet: TableMenuStart?
    @State private var chatOpen = false
    @ObservedObject private var chatSettings = ChatSettings.shared
    @State private var historyOpen = false
    @State private var timerOpen = false
    @State private var dominoLogOpen = false
    @State private var confirmLeave = false

    init(tableId: String, uid: String, exit: @escaping () -> Void) {
        self.tableId = tableId; self.uid = uid; self.exit = exit
        // أصوات اللعب تُشغَّل من الاتصال نفسه، فتستمر والتطبيق في الخلفية ما دمت في الطاولة
        _conn = StateObject(wrappedValue: {
            let c = TableConnection(tableId)
            c.myUid = uid
            let sounds = GameSoundTracker()
            let other = OtherGameSounds()
            c.onState = { sounds.update($0); other.update($0) }
            return c
        }())
    }

    var body: some View {
        Group {
            if let kicked = conn.kicked {
                Screen {
                    Title(kicked == "banned" ? "حظرك مالك الطاولة" : "أخرجك مالك الطاولة")
                    BodyText(kicked == "banned" ? "لا يمكنك دخول هذه الطاولة ولا أي طاولة يملكها." : "يمكنك دخول أي طاولة أخرى الآن، والعودة لهذه الطاولة بعد ساعة.")
                    MButton("العودة للقائمة الرئيسية", .primary, action: exit)
                }
            } else if conn.closed {
                Screen {
                    Title("أُغلقت الطاولة")
                    BodyText("لم يبق أحد على الطاولة، فأُغلقت تلقائياً.")
                    MButton("العودة للقائمة الرئيسية", .primary, action: exit)
                }
            } else if let v = conn.view {
                table(v)
            } else {
                Screen {
                    Title("الطاولة")
                    ProgressView().tint(Palette.gold)
                    BodyText(conn.connected ? "جارٍ التحميل…" : "جارٍ الاتصال بالطاولة…")
                    MButton("رجوع", action: exit)
                }
            }
        }
        .onAppear {
            // الشاشة لا تنطفئ ما دمت في الطاولة (انطفاؤها يقطع الاتصال والمحادثة الصوتية)
            UIApplication.shared.isIdleTimerDisabled = true
            conn.start()
            // نغمة الانضمام يسمعها المنضم نفسه أول ما يدخل الطاولة (الموجودون يسمعونها من إعلان الخادم)
            Sounds.shared.tableJoin()
            // المحادثة الصوتية ما تدخلها تلقائياً: اللي يبيها يضغط ضغطة مطولة على زر الميكروفون
        }
        .task {
            // نبضة كل ١٠ ثوانٍ: لو أُغلق التطبيق ورجعت خلال دقيقة يرجعك لنفس الطاولة
            while !Task.isCancelled {
                Prefs.lastTable = tableId
                Prefs.lastTableAt = Date().timeIntervalSince1970
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        // لا نمسح آخر طاولة هنا: إغلاق التطبيق من مبدّل التطبيقات (والمحادثة الصوتية شغالة بالخلفية)
        // يهدم الشاشات فيستدعي onDisappear. نمسحها فقط عند الخروج من الطاولة بنفسك
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; conn.stop(); Voice.shared.dispose(); Gestures.shared.handler = nil }
        .onReceive(NotificationCenter.default.publisher(for: .appForeground)) { _ in conn.reconnectNow(); Voice.shared.onForeground() }
    }

    @ViewBuilder private func table(_ v: TableView) -> some View {
        // مع VoiceOver الشاشة ما تتمرر، فسحب الأصابع الثلاث (فوق/تحت) يوصل لإيماءات اللعبة دائماً
        Screen(fill: true, lockScroll: UIAccessibility.isVoiceOverRunning) {
            HStack(spacing: 8) {
                SmallButton("القائمة") { menuSheet = .main }
                    // قارئ الشاشة: الإجراءات (سحب لفوق أو تحت) تفتح الصفحة المطلوبة على طول
                    .accessibilityActions {
                        Button("اللاعبون") { menuSheet = .players }
                        Button("الأصدقاء") { menuSheet = .friends }
                        if v.ownerUid == uid { Button("دعوة صديق") { menuSheet = .invite } }
                        Button("مغادرة الطاولة") { confirmLeave = true }
                    }
                if v.kind == "baloot" { SmallButton("السجل") { historyOpen = true } }
                // المالك المشترك في الباقة الاحترافية: يغيّر المؤقت أو يوقفه والمباراة شغالة
                if v.ownerUid == uid && v.playing && Session.shared.profile?.isPro == true { SmallButton("⏱ المؤقت") { timerOpen = true } }
                if v.domino != nil { SmallButton("السجل") { dominoLogOpen = true } }
                // اسم المالك جنب اسم الطاولة، ويتحدث أول ما يتغير المالك
                Text("طاولة \(v.title)\(v.ownerName.isEmpty ? "" : " — المالك \(v.ownerName)")").foregroundColor(Palette.textDim)
                    .frame(maxWidth: .infinity, alignment: .trailing).accessibilityAddTraits(.isHeader)
            }
            if !conn.connected { Note("انقطع الاتصال — جارٍ إعادة المحاولة…") }
            if !v.hasGame {
                SeatsLobby(v: v, uid: uid, conn: conn)
            } else if let d = v.domino {
                DominoBoard(v: v, d: d, conn: conn, isOwner: v.ownerUid == uid) { dominoLogOpen = true }
            } else if let j = v.jackaroo {
                // الجاكارو في منتصف الشاشة: مسافة فوقها مثل اللي تحتها (الطويلة تملأ الشاشة بنفسها)
                if !JK_TALL { Spacer(minLength: 0) }
                JackarooBoard(v: v, j: j, conn: conn, isOwner: v.ownerUid == uid)
            } else if let l = v.ludo {
                // اللودو في منتصف الشاشة: مسافة فوقها مثل اللي تحتها
                Spacer(minLength: 0)
                LudoBoard(v: v, l: l, conn: conn, isOwner: v.ownerUid == uid)
            } else if let g = v.game {
                BalootBoard(v: v, g: g, uid: uid, conn: conn)
            }
            Spacer(minLength: 0)
            // الدومينو: قطعك تحت فوق الميكروفون
            if let d = v.domino { DominoHand(v: v, d: d, conn: conn) }
        }
        // زر الميكروفون أسفل يسار الشاشة، ثابت دائماً حتى لو طالت الطاولة،
        // وبعد الأوراق مباشرة في ترتيب VoiceOver (الرجوع منه يعود للأوراق، لا لبداية الصفحة)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // زر الدردشة الكتابية جنب الميكروفون في نفس الصف (يختفي إن أطفأتها من الإعدادات)
            HStack(spacing: 10) {
                Spacer()
                if chatSettings.mode != .off { ChatButton(conn: conn) { conn.chatOpen = true; chatOpen = true } }
                VoiceButton(tableId: v.id, uid: uid)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        // آخر رسالة: لحظات في الزاوية اليمين تحت، بعيداً عن الطاولة والأوراق
        .overlay(alignment: .bottomLeading) {
            if chatSettings.mode != .off && !chatOpen { ChatToast(conn: conn) }
        }
        .sheet(isPresented: $chatOpen, onDismiss: { conn.chatOpen = false }) { ChatSheet(conn: conn) { chatOpen = false } }
        .sheet(isPresented: $historyOpen) { HistoryView(history: v.history) { historyOpen = false } }
        .sheet(isPresented: $timerOpen) {
            Sheet(title: "إعدادات المباراة") {
                Note("تقدر تغيّر وقت الدور أو توقفه والمباراة شغالة.")
                ForEach(TURN_LIMITS, id: \.self) { s in
                    if v.clockLimit == s { MButton("✓ \(turnLimitLabel(s))", .primary, label: "\(turnLimitLabel(s))، الحالي") { timerOpen = false } }
                    else { MButton(turnLimitLabel(s)) { timerOpen = false; conn.send("turnLimit", ["turnLimit": s]) } }
                }
                if v.game != nil { Note("🔒 إعلان المشاريع \(v.manualProjects ? "يدوي" : "تلقائي")، والقيد والقطع \(v.qaid ? "مفعّل" : "مو مفعّل"): ينضبطون قبل بداية المباراة بس.") }
            }
        }
        .sheet(isPresented: $dominoLogOpen) {
            if let d = (conn.view ?? v).domino { DominoLogView(d: d) { dominoLogOpen = false } }
        }
        // طلب انضمام لطاولتك الخاصة من صديق
        // قبول: يدخل على طول؛ تجاهل: يبقى طلبه معلّق 5 دقائق؛ رفض: ما يقدر يدخل أو يطلب نصف ساعة
        .alert(conn.joinRequest.map { "\($0.name) طلب الانضمام" } ?? "",
               isPresented: Binding(get: { conn.joinRequest != nil }, set: { if !$0 { conn.joinRequest = nil } }),
               presenting: conn.joinRequest) { r in
            Button("قبول") { conn.send(["type": "joinAnswer", "uid": r.uid, "answer": "accept", "accept": true]) }
            Button("تجاهل", role: .cancel) { conn.send(["type": "joinAnswer", "uid": r.uid, "answer": "ignore", "accept": false]) }
            Button("رفض", role: .destructive) { conn.send(["type": "joinAnswer", "uid": r.uid, "answer": "reject", "accept": false]) }
        }
        .sheet(item: $menuSheet) { start in
            TableMenu(v: conn.view ?? v, uid: uid, conn: conn, onLeave: { menuSheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmLeave = true } }, onClose: { menuSheet = nil }, start: start)
        }
        .confirm("مغادرة الطاولة", isPresented: $confirmLeave,
                 message: v.playing && v.mySeat != nil ? "المباراة جارية — سيحل روبوت مكانك. هل تريد المغادرة؟" : "هل تريد مغادرة الطاولة؟",
                 confirm: "مغادرة") {
            conn.send("leave")
            exit()
        }
    }
}

struct BalootBoard: View {
    let v: TableView
    let g: GameView
    let uid: String
    @ObservedObject var conn: TableConnection
    /// آخر أكلة انتهت مهلة عرضها (بعدها تختفي أوراقها). الحساب فوري في نفس الإطار، فما تختفي الأوراق وترجع
    @State private var releasedTrick: Int?
    /// مؤشر VoiceOver: حين يختفي العنصر اللي ضغطته (ورقة لعبتها، أو أزرار المزايدة) ينتقل لأقرب عنصر
    /// بدل ما يقفز لأعلى الشاشة، وإعلان حركتك يقطع قراءته
    /// بعد ما تضغط زر شراء/دبل: الورقة اللي يروح لها المؤشر لما تختفي الأزرار
    @State private var pendingFocus: Card?
    /// بعد ما تلعب ورقة: المؤشر ينتقل لكلمة «أوراقك» (فوق أوراقك) لما تختفي الورقة
    /// مؤشر قارئ الشاشة على مكان في يدك (مو على ورقة بعينها): المكان يبقى بعد ما تلعب
    @AccessibilityFocusState private var slotFocus: Int?
    /// مكان الورقة اللي لعبتها: لو كانت آخر ورقة في اليد (مكانها يختفي) ننقل المؤشر للي قبلها
    @State private var playedPos: Int?
    @State private var prevGame: GameView?
    @State private var lastTurn: String?

    private var mySeat: Int? { v.mySeat }
    private var me: Int { v.mySeat ?? 0 }
    private var myTeam: Int { teamOf(me) }
    private var shownTrick: [PlayedCard] {
        g.trick.isEmpty && g.trickNo > 0 && releasedTrick != g.trickNo ? (g.lastTrick ?? g.trick) : g.trick
    }
    /// قدام كل لاعب: أوراقه الباقية مكشوفة بعد «سوا» (ثانيتين قبل ما تنحسب الصكة)، وإلا أوراق مشروعه
    private func shownFaces(_ seat: Int) -> [Card] {
        if let h = g.sawaHands, seat < h.count { return h[seat] }
        return text.faces(seat)
    }
    private var text: BalootText { BalootText(view: v, g: g, shownTrick: shownTrick) }

    private func act(_ a: JSON) { conn.send(["type": "action", "action": a]) }

    private func read(_ dir: SwipeDir) -> Bool {
        // نقرأ من آخر حالة وصلت من الخادم وقت الإيماءة نفسها، فلا تُقرأ حالة قديمة
        let text = conn.view.flatMap { v in v.game.map { BalootText(view: v, g: $0, shownTrick: $0.trick) } } ?? self.text
        switch dir {
        case .left: Announcer.announceNow(text.trick())
        case .right: let c = text.contract(); if !c.isEmpty { Announcer.announceNow(c) }
        case .up: Announcer.announceNow(text.projects())
        case .down: Announcer.announceNow(text.turn())
        }
        return true
    }

    var body: some View {
        VStack(spacing: 10) {
            // النقاط: جملة واحدة كاملة لـ VoiceOver
            let us = g.scores[safe: myTeam] ?? 0
            let them = g.scores[safe: 1 - myTeam] ?? 0
            // المشاهد: بدل "لنا ولهم" أسماء كل فريق
            let usLabel = mySeat == nil ? "\(text.name(0)) و\(text.name(2))" : "لنا"
            let themLabel = mySeat == nil ? "\(text.name(1)) و\(text.name(3))" : "لهم"
            HStack(spacing: 10) {
                ScoreBox(label: usLabel, value: us, mine: mySeat != nil)
                Text("152").font(.system(size: 13)).foregroundColor(Palette.textDim)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Palette.green700, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                ScoreBox(label: themLabel, value: them, mine: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("النقاط: \(usLabel) \(us)، \(themLabel) \(them). الفوز عند 152")

            if let line = text.statusLine() { Text(line).bold().foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity) }

            // اللاعبون حول الطاولة: الشريك في الأعلى، والخصمان يميناً ويساراً، ووسط الطاولة دائرة
            GeometryReader { geo in
                let unit = geo.size.width / 4.5
                VStack(spacing: 6) {
                    PlayerTag(v: v, g: g, seat: (me + 2) % 4, faces: shownFaces((me + 2) % 4), note: seatNote(g, (me + 2) % 4), partner: mySeat != nil).frame(width: unit * 3)
                    HStack(spacing: 6) {
                        PlayerTag(v: v, g: g, seat: (me + 1) % 4, faces: shownFaces((me + 1) % 4), note: seatNote(g, (me + 1) % 4)).frame(width: unit * 0.7)
                        trickArea.frame(width: min(unit * 3.1, 360), height: min(unit * 3.1, 360))
                        PlayerTag(v: v, g: g, seat: (me + 3) % 4, faces: shownFaces((me + 3) % 4), note: seatNote(g, (me + 3) % 4)).frame(width: unit * 0.7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: min(min(UIScreen.main.bounds.width - 32, 520) / 4.5 * 3.1, 360) + 70)
            .background(RadialGradient(colors: [Palette.green700.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 220))

            if g.phase == "matchOver" && g.outcomeStatus == "won" {
                // المشاهد: اسم الفريق الفائز بس (بلا «فريقك»)
                let w = g.outcomeWinner ?? 0
                Text(mySeat == nil ? "فاز فريق \(text.name(w)) و\(text.name(w + 2))" : w == myTeam ? "🎉 فاز فريقك!" : "فاز الفريق الآخر").font(.system(size: 21, weight: .bold)).foregroundColor(Palette.goldSoft)
            }

            if g.phase == "matchOver" && v.ownerUid == uid { MButton("مباراة جديدة", .primary) { conn.send("start") } }

            // أزرار الشراء فوق الأوراق مباشرة، بمسافة بسيطة جداً
            VStack(spacing: 4) {
                // أزرار المزايدة
                if !g.actions.bids.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(g.actions.bids) { b in
                            // اللفة الثانية: "ولا" بدل "بس"
                            SmallButton(b.type == "pass" && g.bidRound == 2 ? "ولا" : b.label, primary: b.type != "pass") { toHand(); act(["type": "bid", "bid": b.raw]) }
                        }
                    }
                }
                // الدبل: الضغطة تعلن الدبل فوراً للجميع، ثم يختار صاحبه مقفل أو مفتوح
                if g.actions.doubleLabel != nil || g.actions.canPassDouble {
                    HStack(spacing: 8) {
                        // «بس» يمين و«دبل» يسار
                        if g.actions.canPassDouble { MButton("بس") { toHand(); act(["type": "doublePass"]) } }
                        if let label = g.actions.doubleLabel {
                            MButton(label, .primary) {
                                toHand()
                                act(["type": "double"])
                            }
                        }
                    }
                }
                // سوا (اختياري): كل أوراقك مضمونة تاكل، تنحسب الأكلات الباقية لفريقك وتنتهي الصكة
                // القيد والقطع: تسجيلة، وإعلان مشروع، وسوا (بعد الشراء، مكان أزرار الصن والحكم)
                if v.qaid && g.phase == "playing" && (!g.actions.qaidTargets.isEmpty || !g.actions.declareKinds.isEmpty || g.actions.canSawa) {
                    QaidButtons(v: v, g: g, act: act)
                } else if g.actions.canSawa {
                    MButton("سوا", .primary) { act(["type": "sawa"]) }
                }
                if g.actions.canShowProject { ShowProjectPanel(v: v, g: g, act: act) }
                // إعلان المشاريع يدوي (خيار الباقة الاحترافية): أعلن مشروعك قبل ما تلعب ورقتك، وإلا يروح عليك
                if g.actions.canProject && v.manualProjects {
                    MButton("أعلن مشروعك", .primary) { act(["type": "declareProject"]) }
                }
                // «ورق»: أوراقك الخمس الأولى كلها ٧ و٨ و٩ بس — يعاد التوزيع. بعد الشراء يجيك دورك: بس أو ورق
                if g.actions.waraqDecision {
                    HStack(spacing: 8) {
                        MButton("بس") { toHand(); act(["type": "waraq", "call": false]) }
                        MButton("ورق", .primary) { toHand(); act(["type": "waraq", "call": true]) }
                    }
                } else if g.actions.canWaraq {
                    MButton("ورق", .primary) { toHand(); act(["type": "waraq", "call": true]) }
                }
                if g.actions.chooseLock {
                    HStack(spacing: 8) {
                        MButton("مقفل", .primary) { toHand(); act(["type": "doubleLock", "locked": true]) }
                        MButton("مفتوح", .primary) { toHand(); act(["type": "doubleLock", "locked": false]) }
                    }
                }
                // يد اللاعب
                if let mine = mySeat {
                    if let note = seatNote(g, mine) { Text("أنت: \(note)").font(.system(size: 13)).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity) }
                    let myFaces = text.faces(mine)
                    if !myFaces.isEmpty {
                        HStack(spacing: 8) {
                            Text("مشروعك").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.goldSoft)
                            ProjectFaces(faces: myFaces)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    }
                    // أوراقك في أسفل الشاشة، أكبر قليلاً من أوراق الطاولة
                    // أوراقك مروحة على قوس كأنها في يدك: كل ورقة فوق التي على يسارها، فيبقى رمزها (في زاويتها اليسرى) ظاهراً
                    let hand = sortHand(g.myHand)
                    // كل ورقة عنصر لحالها (تتنقل بينها يمين ويسار)، بس العنصر مربوط بمكانه في اليد مو بالورقة:
                    // لما تلعب ورقة يبقى مكانها (ويصير فيه الورقة اللي جنبها) فالمؤشر ما يقفز
                    ZStack(alignment: .bottom) {
                        ForEach(0..<hand.count, id: \.self) { i in
                            let c = hand[i]
                            let k = CGFloat(i) - CGFloat(hand.count - 1) / 2
                            // التنقل بين الأوراق بالسحب يمين ويسار؛ الإجراءات للقرار بس (صن/حكم/بس، الدبل...)
                            HandCard(card: c, legal: g.actions.legal.contains(c), actions: cardActions) {
                                // إعلان لعبك (واللي بعده) يقطع قراءة الورقة
                                if UIAccessibility.isVoiceOverRunning { Announcer.interruptNextEvents(); playedPos = i }
                                act(["type": "play", "card": c.json])
                            }
                                .accessibilityFocused($slotFocus, equals: i)
                                .rotationEffect(.degrees(Double(k) * 7.5), anchor: UnitPoint(x: 0.5, y: 2.6))
                                // VoiceOver يقرأ من اليمين لليسار: هاص الأكبر أولاً
                                .accessibilitySortPriority(Double(i))
                        }
                    }
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, minHeight: 152, alignment: .bottom)
                    .environment(\.layoutDirection, .leftToRight)
                    // ترتيب الأوراق لـ VoiceOver داخل اليد فقط
                    .accessibilityElement(children: .contain)
                } else {
                    // المشاهد: اللاعب الرابع تحت (الأربعة متقابلين حول الطاولة)
                    PlayerTag(v: v, g: g, seat: 0, faces: shownFaces(0), note: seatNote(g, 0))
                }
            }
        }
        .onAppear { Gestures.shared.set("baloot") { read($0) }; prevGame = g; lastTurn = turnKey(g); releasedTrick = g.trickNo }
        .onDisappear { Gestures.shared.clear("baloot") }
        .onChange(of: conn.version) { _ in
            Gestures.shared.set("baloot") { read($0) }
            settleFocus()
            if let p = prevGame, g.trickNo != p.trickNo { holdTrick() }
            // إعلان "دورك" مرة واحدة عند بداية الدور
            // النغمة أولاً (فورية)، ثم الإعلان
            // الجرس أولاً، ثم "دورك" بعد لحظة: VoiceOver يخفض الأصوات وهو يتكلم فكان يغطي الجرس
            // صوت "دورك" المنطوق يكفي؛ VoiceOver يعلنها فقط إذا كان الصوت مطفأ (الكتم العام)
            let key = turnKey(g)
            if let key, key != lastTurn, Prefs.muted { Announcer.announce("دورك") }
            lastTurn = key
            prevGame = g
        }
    }

    /// إجراءات قارئ الشاشة على أوراقك (سحب لفوق أو لتحت والمؤشر على أي ورقة): نفس أزرار الشراء والدبل الظاهرة الحين
    private var cardActions: [(String, () -> Void)] {
        var out: [(String, () -> Void)] = []
        for b in g.actions.bids {
            out.append((b.type == "pass" && g.bidRound == 2 ? "ولا" : b.label, { act(["type": "bid", "bid": b.raw]) }))
        }
        if let label = g.actions.doubleLabel { out.append((label, { act(["type": "double"]) })) }
        if g.actions.canPassDouble { out.append(("بس", { act(["type": "doublePass"]) })) }
        if g.actions.canSawa { out.append(("سوا", { act(["type": "sawa"]) })) }
        if g.actions.canProject && v.manualProjects { out.append(("مشروع", { act(["type": "declareProject"]) })) }
        if g.actions.waraqDecision { out.append(("بس", { act(["type": "waraq", "call": false]) })) }
        if g.actions.canWaraq { out.append(("ورق", { act(["type": "waraq", "call": true]) })) }
        if g.actions.chooseLock {
            out.append(("مقفل", { act(["type": "doubleLock", "locked": true]) }))
            out.append(("مفتوح", { act(["type": "doubleLock", "locked": false]) }))
        }
        return out
    }

    /// أزرار الشراء والدبل تختفي بعد الضغط: المؤشر ينتقل لأوراقك (لا فوق ولا تحت)
    private func toHand() { if let t = sortHand(g.myHand).last { pendingFocus = t } }

    /// وصلت الحالة الجديدة
    private func settleFocus() {
        let hand = g.myHand
        // خلصت الأوراق (نهاية الجولة): ننسى مكان المؤشر في اليد. لو بقي محفوظ، أول ما تتوزع الأوراق الجديدة
        // يرجع المؤشر لنفس المكان ويقرأ الورقة، فيقطع قراءة النتيجة
        if hand.isEmpty { playedPos = nil; slotFocus = nil; return }
        // لعبت آخر ورقة في اليد: مكانها اختفى، ننقل المؤشر للمكان اللي قبله
        if let p = playedPos, hand.count < p + 1 || hand.count == 0 {
            playedPos = nil
            if hand.count > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { slotFocus = hand.count - 1 } }
        } else if playedPos != nil, prevGame.map({ $0.myHand.count != hand.count }) == true { playedPos = nil }
        // أزرار الشراء اختفت: نحط المؤشر على أوراقك
        if let t = pendingFocus, g.actions.bids.isEmpty, g.actions.doubleLabel == nil, !g.actions.canPassDouble, !g.actions.chooseLock {
            pendingFocus = nil
            guard hand.contains(t), UIAccessibility.isVoiceOverRunning else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                // إعلان اللعب التالي يقطع قراءة اسم الورقة
                Announcer.interruptNextEvents()
                slotFocus = max(g.myHand.count - 1, 0)
            }
        }
    }

    /// بعد آخر ورقة في الأكلة: نبقي الأوراق الأربع ظاهرة لحظة قبل أن تذهب لصاحبها
    private func holdTrick() {
        let n = g.trickNo
        DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD) { releasedTrick = n }
    }

    /// وسط الطاولة: الوصول له يقرأ كل الأوراق ومن لعبها، والنقر مرتين يعيد قراءتها.
    /// وفي دوّار VoiceOver (الإجراءات): القراءات الثلاث
    private var trickArea: some View {
        ZStack {
            // طاولة ثلاثية الأبعاد: إطار ومفرش (المشترك يختار الشكل والألوان)
            let shape = Look.tableShape(Look.shape)
            shape.fill(RadialGradient(colors: Look.rim, center: .center, startRadius: 0, endRadius: 160))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
            shape.fill(RadialGradient(colors: Look.felt, center: .center, startRadius: 0, endRadius: 150))
                .padding(10)
            shape.stroke(Palette.gold.opacity(0.33), lineWidth: 1).padding(10)
            if (g.phase == "bidding" || g.phase == "doubling" || g.phase == "waraq"), let q = g.qaba {
                VStack(spacing: 4) {
                    Text("ورقة الأرض").font(.system(size: 14)).foregroundColor(Palette.textDim)
                    TableCard(card: q)
                }
                .offset(y: -4)
            }
            // الأوراق تتكدّس فوق بعض، كل ورقة مزاحة ومائلة قليلاً باتجاه من رماها (نفس قيم التطبيق الحالي)
            ForEach(shownTrick, id: \.seat) { p in
                let rel = (p.seat - me + 4) % 4
                let place: (CGFloat, CGFloat, Double) = rel == 0 ? (0, 38, 3) : rel == 1 ? (36, 0, 9) : rel == 2 ? (0, -38, -4) : (-36, 0, -9)
                TableCard(card: p.card)
                    .rotationEffect(.degrees(place.2))
                    .offset(x: place.0, y: place.1)
                    .transition(.asymmetric(insertion: .offset(x: place.0 * 1.5, y: place.1 * 1.5).combined(with: .opacity).combined(with: .scale(scale: 0.85)), removal: .opacity))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        // مع VoiceOver: الورقة تظهر على طول بدون حركة (المؤشر ما ينتظر الحركة)
        .animation(Announcer.readerOn ? nil : .easeOut(duration: 0.35), value: shownTrick.count)
        // مائلة كأنك جالس عليها
        .rotation3DEffect(.degrees(40), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("وسط الطاولة: \(text.trick())")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { _ = read(.left) }
        // النقر مرتين يعيد قراءة أوراق الطاولة؛ باقي القراءات بالإيماءات (الإجراءات للشراء والمايك والقائمة بس)
        .accessibilityAction { _ = read(.left) }
    }


}

/// أصوات اللعب: تُستدعى مع كل حالة تصل من الخادم (لا من الشاشة)، فتشتغل والتطبيق في الخلفية.
/// نقارن الحالة الجديدة بالسابقة لنعرف ما حدث.
final class GameSoundTracker {
    private var prev: GameView?
    private var lastTurn: String?
    private var lastBidTurn: String?
    private var lastDoubleTurn: String?

    func update(_ v: TableView) {
        guard let g = v.game else { prev = nil; lastTurn = nil; return }
        let p = prev
        prev = g
        if let p {
            gameSounds(prev: p, g: g, mySeat: v.mySeat)
            // «سوا»: انتهى كشف الأوراق، تتجمع وتنحسب الصكة
            if p.sawaHands != nil && g.sawaHands == nil { Sounds.shared.collect() }
            // اكتملت الأكلة: صوت سحبها قبل أن تذهب لصاحبها
            if g.trickNo == p.trickNo + 1, g.lastTrick != nil, g.trick.isEmpty {
                // نفس لحظة انسحاب الأوراق (تختفي بعد TRICK_HOLD بالضبط)
                DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD) { Sounds.shared.collect() }
            }
        }
        // نغمة الدور (فورية، قبل إعلان "دورك")
        let key = turnKey(g)
        if let key, key != lastTurn { Sounds.shared.turn(soft: Announcer.readerOn) }
        lastTurn = key
        // أثناء الشراء: VoiceOver يقول «دور فلان» لما ينتقل الدور لغيرك (ودورك يقوله التعليق الصوتي).
        // شراء فلان (حكم/صن) ما يعيد «دور فلان» له: نعلن بس لما ينتقل الدور لشخص ثاني
        // بعد التوزيع: «دور فلان» ينتظر لين تخلص مهلة التوزيع (فتنسمع ورقة الأرض كاملة)
        let bidTurn: String? = g.phase == "bidding" && !g.dealing && g.turn != v.mySeat ? "\(g.bidRound)|\(g.turn)" : nil
        if let bidTurn, bidTurn != lastBidTurn {
            let who = v.seat(g.turn)?.username ?? "مقعد \(g.turn + 1)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { Announcer.announce("دور \(who)") }
        }
        lastBidTurn = bidTurn
        // قرار الدبل: «دور فلان» ثم خياراته (بس أو دبل/ثري/فور/قهوة)
        let deciders = g.phase == "doubling" ? g.doubling.deciders : []
        let dblTurn: String? = deciders.isEmpty ? nil : "\(g.doubling.level)|\(deciders)"
        if let dblTurn, dblTurn != lastDoubleTurn {
            let label = g.doubling.label
            let text: String
            if let me = v.mySeat, deciders.contains(me) { text = "دورك، بس أو \(label)" }
            else {
                let names = deciders.map { v.seat($0)?.username ?? "مقعد \($0 + 1)" }
                text = "دور \(names.joined(separator: " و"))، \(names.count > 1 ? "يختارون" : "يختار") بس أو \(label)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { Announcer.announce(text) }
        }
        lastDoubleTurn = dblTurn
    }

    private func gameSounds(prev: GameView, g: GameView, mySeat: Int?) {
        let s = Sounds.shared
        let total = { (x: GameView) in x.handCounts.reduce(0, +) }
        if total(g) > total(prev) { s.deal(newHand: total(g) - total(prev) > 12) }
        // الكل قال بس في اللفتين: إعادة توزيع (نفس عدد الأوراق) بصوت التوزيع مثل بداية الجولة
        else if g.phase == "bidding" && g.bidRound == 1 && (prev.bidRound == 2 || prev.dealer != g.dealer) && prev.phase == "bidding" { s.deal(newHand: true) }
        // الورقة الجديدة: آخر ورقة في الأكلة الحالية، أو الرابعة إن اكتملت الأكلة للتو
        var played: (Card, Card)?
        if g.trickNo == prev.trickNo && g.trick.count > prev.trick.count { played = (g.trick.last!.card, g.trick.first!.card) }
        else if g.trickNo == prev.trickNo + 1, let lt = g.lastTrick, lt.count == 4 { played = (lt[3].card, lt[0].card) }
        if let p = played {
            let (card, lead) = p
            let trump = g.contract?.mode == "hokm" ? g.contract?.trump : nil
            // أي ورقة حكم في الحكم (قطع أو أول ورقة في الأرض): صوت الحكم
            _ = lead
            if let trump, card.suit == trump { s.cut() } else { s.card() }
        }
        // إعلان المشروع (اللفة الأولى): صوت كل مشروع
        if g.declared.count > prev.declared.count { s.project(g.declared.dropFirst(prev.declared.count).flatMap(\.kinds)) }
        // كشف أوراق المشروع (اللفة الثانية)
        if g.declared.filter({ !$0.faces.isEmpty }).count > prev.declared.filter({ !$0.faces.isEmpty }).count { s.projectReveal() }
        if g.balootSeat != nil && prev.balootSeat == nil { s.baloot() }
        // نهاية الصكة (بعد صوت سحب الأكلة الأخيرة)، ثم نهاية المباراة
        if let r = g.lastHand, prev.lastHand == nil {
            let team = mySeat.map(teamOf)
            var result = "neutral"
            if let team {
                let mine = r.points[safe: team] ?? 0, theirs = r.points[safe: 1 - team] ?? 0
                result = mine > theirs ? "win" : mine < theirs ? "lose" : "neutral"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD + 0.2) { s.handEnd(result, kaboot: r.kaboot != nil) }
            if g.outcomeStatus == "won", let team {
                let won = g.outcomeWinner == team
                DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD + 1.6) { s.matchEnd(won: won) }
            }
        }
        // المزايدة والدبل: أصوات منطوقة يرسلها الخادم مع الإعلان (Sounds.voices)
    }
}

private struct ScoreBox: View {
    let label: String
    let value: Int
    let mine: Bool
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.textDim)
            Text("\(value)").font(.system(size: 30, weight: .bold)).foregroundColor(Palette.gold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Palette.green700, Palette.green800], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(mine ? Palette.gold : Palette.green700, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
    }
}

/// تحت اسم اللاعب قبل توزيع بقية الورق: «الموزع»، ونوع ما اشتراه (حكم، صن، أشكل).
/// أول ما تتوزع بقية الأوراق تختفي كلها.
func seatNote(_ g: GameView, _ seat: Int) -> String? {
    guard g.phase == "bidding" || g.phase == "doubling" else { return nil }
    var parts: [String] = []
    if g.dealer == seat { parts.append("الموزع") }
    if let c = g.contract {
        if c.buyer == seat {
            // الحكم الثاني: بعد ما يحدد اللون ينكتب نوعه
            if c.mode == "hokm" && (g.bidRound == 2 || g.secondHokmSeat == seat) { parts.append("حكم ثاني \(SUIT_NAMES[c.trump ?? ""] ?? "")") }
            else { parts.append(c.mode == "hokm" ? "اشترى حكم" : c.qabaTo != c.buyer ? "اشترى أشكل" : "اشترى صن") }
        }
    } else if g.secondHokmSeat == seat {
        // الحكم الثاني قبل ما يحدد اللون
        parts.append("حكم ثاني")
    } else if let k = g.hokmBidKey?.first, Int(String(k)) == seat {
        parts.append("اشترى حكم")
    }
    return parts.isEmpty ? nil : parts.joined(separator: "، ")
}

private struct PlayerTag: View {
    let v: TableView
    let g: GameView
    let seat: Int
    var faces: [Card] = []
    var note: String? = nil
    var partner = false
    var body: some View {
        let s = v.seat(seat)
        let turn = g.turn == seat && g.phase != "matchOver"
        let label = (s?.username ?? "مقعد \(seat + 1)") + (s?.isBot == true ? " (روبوت)" : "") + (s?.away == true ? " (انقطع الاتصال)" : "") + (partner ? " (شريكك)" : "")
        VStack(spacing: 4) {
            Avatar(uid: v.seatUid(seat), name: s?.username ?? "", size: 34)
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                TurnClock(v: v, seat: seat, turn: turn)
            }
            if let note { Text(note).font(.system(size: 12)).foregroundColor(Palette.goldSoft).multilineTextAlignment(.center) }
            if !faces.isEmpty { ProjectFaces(faces: faces, maxWidth: partner ? 200 : 62).padding(.top, 2) }
        }
            .padding(.horizontal, 4).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(turn ? Palette.gold.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(turn ? Palette.gold : .clear, lineWidth: 1))
    }
}

/// أوراق المشروع مكشوفة قدام صاحبه طوال اللفة الثانية (للعرض فقط — قارئ الشاشة يسمعها من الإعلان)
private struct ProjectFaces: View {
    let faces: [Card]
    /// أقصى عرض متاح (أسماء اللاعبين على الجنب ضيقة)
    var maxWidth: CGFloat = 200
    var body: some View {
        // تحت اسم صاحبه: الأوراق مروحة مثل اليد (كل ورقة فوق اللي على يسارها، فيبان رمزها في زاويتها)
        let n = faces.count
        let w: CGFloat = maxWidth < 100 ? 30 : 36, h: CGFloat = w * 1.45
        let step: CGFloat = n > 1 ? min(w * 0.5, max(9, (maxWidth - w - 12) / CGFloat(n - 1))) : 0
        ZStack(alignment: .bottom) {
            ForEach(0..<n, id: \.self) { i in
                let k = CGFloat(i) - CGFloat(n - 1) / 2
                TableCard(card: faces[i], width: w, height: h)
                    .rotationEffect(.degrees(Double(k) * 7), anchor: UnitPoint(x: 0.5, y: 2.4))
                    .offset(x: k * step)
            }
        }
        .frame(width: w + step * CGFloat(max(n - 1, 0)) + 14, height: h + 10, alignment: .bottom)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// ورقة بحجم أوراق الطاولة: خلفية بيضاء وزوايا وظل
private struct TableCard: View {
    let card: Card
    var width: CGFloat = 58
    var height: CGFloat = 84
    var body: some View {
        // سُمك الورقة: حافة رمادية تحتها، وظل أعمق
        CardFace(card: card)
            .frame(width: width, height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Look.edge, lineWidth: Look.pro && Look.shared.cardEdge > 0 ? 2 : 0.5))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.73, green: 0.71, blue: 0.65)).offset(y: 1.5))
            .shadow(color: .black.opacity(0.7), radius: 6, y: 4)
    }
}

/// ورقة في اليد: تبقى قابلة للتركيز حتى وهي غير مسموحة، فلا يقفز مؤشر VoiceOver حين ينتهي دورك
/// ورقة في اليد. لا نعلن "غير متاحة" كحالة (تغيّرها لحظة انتهاء دورك قد يعيد قراءة الورقة المحددة).
/// الاسم والنوع (زر) ثابتين دائماً: تغييرهما وهي محددة كان يخلي VoiceOver يقول «زر» فجأة،
/// وتفريغ الاسم كان يشيلها من قائمة العناصر فيقفز المؤشر لوسط الشاشة.
private struct HandCard: View {
    let card: Card
    let legal: Bool
    /// الشراء والدبل كإجراءات على الورقة (للمكفوفين: ما يحتاجون يروحون للأزرار)
    var actions: [(String, () -> Void)] = []
    /// سحب لفوق/تحت على الورقة (وقت اللعب): ينقلك للورقة اللي بعدها/قبلها
    var step: ((AccessibilityAdjustmentDirection) -> Void)? = nil
    let play: () -> Void
    var body: some View {
        TableCard(card: card, width: 80, height: 116)
            // المسموح لعبها بإطار ذهبي فقط، فيبقى شكل المروحة واحداً
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(legal ? Palette.goldSoft : .clear, lineWidth: 3))
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tap() }
            .accessibilityActions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, a in Button(a.0) { a.1() } }
            }
            .modifier(StepAdjust(step: step))
    }

    private func tap() {
        if legal { play() } else { Sounds.shared.illegal(); Announcer.announceNow("غير متاحة") }
    }
}

/// صفوف تلتف للسطر التالي وتتوسط (للأوراق وأزرار المزايدة)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows: [CGFloat] = [0], heights: [CGFloat] = [0]
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if rows[rows.count - 1] > 0 && rows[rows.count - 1] + spacing + sz.width > width { rows.append(0); heights.append(0) }
            rows[rows.count - 1] += (rows[rows.count - 1] > 0 ? spacing : 0) + sz.width
            heights[heights.count - 1] = max(heights[heights.count - 1], sz.height)
        }
        return CGSize(width: proposal.width ?? (rows.max() ?? 0), height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lines: [[LayoutSubviews.Element]] = [[]]
        var lineWidth: CGFloat = 0
        for v in subviews {
            let w = v.sizeThatFits(.unspecified).width
            if !lines[lines.count - 1].isEmpty && lineWidth + spacing + w > bounds.width { lines.append([]); lineWidth = 0 }
            lineWidth += (lines[lines.count - 1].isEmpty ? 0 : spacing) + w
            lines[lines.count - 1].append(v)
        }
        var y = bounds.minY
        for line in lines {
            let sizes = line.map { $0.sizeThatFits(.unspecified) }
            let total = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1))
            let h = sizes.map(\.height).max() ?? 0
            // من اليمين لليسار (الاتجاه العربي)، والسطر في المنتصف
            var x = bounds.midX + total / 2
            for (v, sz) in zip(line, sizes) {
                x -= sz.width
                v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x -= spacing
            }
            y += h + spacing
        }
    }
}


/// سحب لفوق/تحت على الورقة بس لما يكون فيه خطوة (وقت اللعب)؛ وقت القرار السحب يروح للإجراءات
private struct StepAdjust: ViewModifier {
    let step: ((AccessibilityAdjustmentDirection) -> Void)?
    func body(content: Content) -> some View {
        if let step { content.accessibilityAdjustableAction(step) } else { content }
    }
}

private let PROJECT_KIND_NAMES = ["sira": "سرا", "fifty": "خمسين", "hundred": "مية", "fourHundred": "أربعمية"]
private let QAID_OPTIONS: [(String, String)] = [
    ("noRaise", "ما طلع بالحكم"), ("noTrump", "ما دق بالحكم"), ("revoke", "قاطع"),
    ("lockedLead", "تربيع بحكم مقفل"), ("badProject", "مشروع غلط"), ("badSawa", "سوا غلط"),
]

/// القيد والقطع: أزرار تسجيلة، وإعلان مشروع، وسوا
private struct QaidButtons: View {
    let v: TableView
    let g: GameView
    let act: (JSON) -> Void
    @State private var qaidOpen = false
    @State private var target: Int?
    @State private var projectOpen = false
    var body: some View {
        HStack(spacing: 8) {
            if !g.actions.qaidTargets.isEmpty { MButton("تسجيلة", .primary) { target = nil; qaidOpen = true } }
            if !g.actions.declareKinds.isEmpty { MButton("إعلان مشروع", .primary) { projectOpen = true } }
            if g.actions.canSawa { MButton("سوا", .primary) { act(["type": "sawa"]) } }
        }
        .sheet(isPresented: $qaidOpen) {
            if let t = target {
                Sheet(title: "تسجيلة على \(v.seat(t)?.username ?? "")") {
                    ForEach(QAID_OPTIONS.filter { $0.0 != "badSawa" || v.sawaOn }, id: \.0) { kind, name in
                        MButton(name, .primary) { qaidOpen = false; act(["type": "qaid", "target": t, "kind": kind]) }
                    }
                    MButton("رجوع") { target = nil }
                }
            } else {
                Sheet(title: "تسجيلة على مين؟") {
                    ForEach(g.actions.qaidTargets, id: \.self) { s in
                        MButton(v.seat(s)?.username ?? "لاعب", .primary) { target = s }
                    }
                    MButton("إلغاء") { qaidOpen = false }
                }
            }
        }
        .sheet(isPresented: $projectOpen) {
            Sheet(title: "نوع مشروعك") {
                ForEach(g.actions.declareKinds, id: \.self) { k in
                    MButton(PROJECT_KIND_NAMES[k] ?? k, .primary) { projectOpen = false; act(["type": "declareKind", "kind": k]) }
                }
                Note("في اللفة اللي بعدها تختار أوراق مشروعك وتفرشها.")
                MButton("إلغاء") { projectOpen = false }
            }
        }
    }
}

/// القيد والقطع: فرش المشروع يدوي — أول ضغطة تفتح اختيار الأوراق (وتقدر تلعب بدون ما تفرش)،
/// وبعد ما تحدد تضغط «فرش المشروع» مرة ثانية فينكشف للكل
private struct ShowProjectPanel: View {
    let v: TableView
    let g: GameView
    let act: (JSON) -> Void
    @State private var choosing = false
    @State private var picked: Set<Card> = []
    private var cards: [Card] {
        // أوراقك الحين، ومعها الورقة اللي لعبتها في اللفة الأولى (ممكن تكون من المشروع)
        var out = g.myHand
        if let mine = g.lastTrick?.first(where: { $0.seat == v.mySeat })?.card, !out.contains(mine) { out.append(mine) }
        return out
    }
    var body: some View {
        if !choosing {
            MButton("فرش المشروع", .primary) { choosing = true }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("حدد أوراق مشروعك، وبعدها اضغط فرش المشروع").bold().foregroundColor(Palette.gold).accessibilityAddTraits(.isHeader)
                FlowLayout(spacing: 6) {
                    ForEach(cards, id: \.self) { c in
                        let on = picked.contains(c)
                        SmallButton(on ? "✓ \(c.label)" : c.label, primary: on, label: on ? "\(c.label)، محددة" : c.label) {
                            if on { picked.remove(c) } else { picked.insert(c) }
                        }
                    }
                }
                MButton("فرش المشروع", .primary, enabled: picked.count >= 3) {
                    act(["type": "showProject", "cards": picked.map { $0.json }])
                    picked = []; choosing = false
                }
                MButton("إلغاء") { choosing = false; picked = [] }
            }
            .padding(10)
            .background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold, lineWidth: 1))
        }
    }
}
