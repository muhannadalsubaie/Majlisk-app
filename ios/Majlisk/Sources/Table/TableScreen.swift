import SwiftUI

/// كم تبقى الأكلة المكتملة ظاهرة قبل أن تذهب لصاحبها
private let TRICK_HOLD: Double = 1.2

struct TableScreen: View {
    let tableId: String
    let uid: String
    let exit: () -> Void
    @StateObject private var conn: TableConnection
    @State private var menuOpen = false
    @State private var historyOpen = false
    @State private var confirmLeave = false

    init(tableId: String, uid: String, exit: @escaping () -> Void) {
        self.tableId = tableId; self.uid = uid; self.exit = exit
        _conn = StateObject(wrappedValue: TableConnection(tableId))
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
            conn.start()
            // كل من يدخل الطاولة ينضم للمحادثة الصوتية مستمعاً، وميكروفونه مقفل حتى يفتحه بنفسه
            Voice.shared.join(tableId, uid: uid, mode: .auto)
        }
        .onDisappear { conn.stop(); Voice.shared.dispose(); Gestures.shared.handler = nil }
        .onReceive(NotificationCenter.default.publisher(for: .appForeground)) { _ in conn.reconnectNow(); Voice.shared.onForeground() }
        .onChange(of: conn.view?.voice ?? []) { list in Voice.shared.sync(list) }
    }

    @ViewBuilder private func table(_ v: TableView) -> some View {
        Screen {
            HStack(spacing: 8) {
                MButton("القائمة", fill: false) { menuOpen = true }
                if v.kind == "baloot" { MButton("السجل", fill: false) { historyOpen = true } }
                Text("طاولة \(gameTitle(v.kind, v.variant))").foregroundColor(Palette.textDim)
                    .frame(maxWidth: .infinity, alignment: .trailing).accessibilityAddTraits(.isHeader)
            }
            if !conn.connected { Note("انقطع الاتصال — جارٍ إعادة المحاولة…") }
            if !v.hasGame {
                SeatsLobby(v: v, uid: uid, conn: conn)
            } else if v.otherGame {
                BodyText("هذه الطاولة \(gameTitle(v.kind, v.variant))، وهذه اللعبة تُضاف قريباً لهذه النسخة. يمكنك البقاء في المحادثة الصوتية.")
            } else if let g = v.game {
                BalootBoard(v: v, g: g, uid: uid, conn: conn)
            }
            VoiceButton(tableId: v.id, uid: uid)
        }
        .sheet(isPresented: $historyOpen) { HistoryView(history: v.history) { historyOpen = false } }
        .sheet(isPresented: $menuOpen) {
            TableMenu(v: conn.view ?? v, uid: uid, conn: conn, onLeave: { menuOpen = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmLeave = true } }, onClose: { menuOpen = false })
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
    @State private var heldTrick: Int?
    @State private var prevGame: GameView?
    @State private var wasMyTurn = false

    private var mySeat: Int? { v.mySeat }
    private var me: Int { v.mySeat ?? 0 }
    private var myTeam: Int { teamOf(me) }
    private var shownTrick: [PlayedCard] {
        heldTrick == g.trickNo && g.trick.isEmpty && g.lastTrick != nil ? g.lastTrick! : g.trick
    }
    private var text: BalootText { BalootText(view: v, g: g, shownTrick: shownTrick) }

    private func act(_ a: JSON) { conn.send(["type": "action", "action": a]) }

    private func read(_ dir: SwipeDir) -> Bool {
        switch dir {
        case .left: Announcer.announceNow(text.trick())
        case .right: Announcer.announceNow(text.contract())
        case .up: Announcer.announceNow(text.projects())
        case .down: return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 10) {
            // النقاط: جملة واحدة كاملة لـ VoiceOver
            let us = g.scores[safe: myTeam] ?? 0
            let them = g.scores[safe: 1 - myTeam] ?? 0
            HStack {
                ScoreBox(label: "لنا", value: us)
                Spacer()
                Text("152").foregroundColor(Palette.textDim)
                Spacer()
                ScoreBox(label: "لهم", value: them)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("النقاط: لنا \(us)، لهم \(them). الفوز عند 152")

            if let line = text.statusLine() { Text(line).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity) }

            // أزرار القراءة السريعة: نفس قراءات إيماءة الثلاث أصابع، تظهر مع VoiceOver
            if Announcer.readerOn {
                HStack(spacing: 6) {
                    MButton("أوراق الطاولة") { _ = read(.left) }
                    MButton("نوع اللعب") { _ = read(.right) }
                    MButton("المشاريع") { _ = read(.up) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("قراءة سريعة")
            }

            // اللاعبون حول الطاولة: الشريك في الأعلى، والخصمان يميناً ويساراً
            PlayerTag(v: v, g: g, seat: (me + 2) % 4, partner: true)
            HStack(spacing: 4) {
                PlayerTag(v: v, g: g, seat: (me + 1) % 4).frame(maxWidth: 80)
                trickArea.frame(maxWidth: 300).aspectRatio(1, contentMode: .fit)
                PlayerTag(v: v, g: g, seat: (me + 3) % 4).frame(maxWidth: 80)
            }

            if g.phase == "matchOver" && g.outcomeStatus == "won" {
                Text(g.outcomeWinner == myTeam ? "🎉 فاز فريقك!" : "فاز الفريق الآخر").font(.system(size: 21, weight: .bold)).foregroundColor(Palette.goldSoft)
            }

            // أزرار المزايدة
            if !g.actions.bids.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(g.actions.bids) { b in
                        MButton(b.label, b.type == "pass" ? .secondary : .primary) { bidSound(b); act(["type": "bid", "bid": b.raw]) }
                    }
                }
                .accessibilityElement(children: .contain).accessibilityLabel("المزايدة")
            }
            // الدبل: الضغطة تعلن الدبل فوراً للجميع، ثم يختار صاحبه مقفل أو مفتوح
            if g.actions.doubleLabel != nil || g.actions.canPassDouble {
                HStack(spacing: 8) {
                    if let label = g.actions.doubleLabel {
                        MButton(label, .primary) {
                            if label == "قهوة" { Sounds.shared.gahwa() } else { Sounds.shared.double(g.doubling.level + 1) }
                            act(["type": "double"])
                        }
                    }
                    if g.actions.canPassDouble { MButton("تمرير") { act(["type": "doublePass"]) } }
                }
            }
            if g.actions.chooseLock {
                HStack(spacing: 8) {
                    MButton("مقفل", .primary) { act(["type": "doubleLock", "locked": true]) }
                    MButton("مفتوح", .primary) { act(["type": "doubleLock", "locked": false]) }
                }
            }
            if g.phase == "matchOver" && v.ownerUid == uid { MButton("مباراة جديدة", .primary) { conn.send("start") } }

            // يد اللاعب
            if mySeat != nil {
                Text("أوراقك").foregroundColor(Palette.textDim).accessibilityAddTraits(.isHeader).frame(maxWidth: .infinity, alignment: .leading)
                let hand = sortHand(g.myHand)
                HStack(spacing: 3) {
                    ForEach(hand, id: \.self) { c in
                        HandCard(card: c, legal: g.actions.legal.contains(c)) { act(["type": "play", "card": c.json]) }
                    }
                    // أماكن فارغة حتى لا تكبر الأوراق كثيراً حين تقل
                    ForEach(0..<max(0, 8 - hand.count), id: \.self) { _ in Color.clear.aspectRatio(0.69, contentMode: .fit) }
                }
            } else {
                Note("أنت تشاهد هذه الطاولة.")
            }
        }
        .onAppear { Gestures.shared.handler = { read($0) }; prevGame = g; wasMyTurn = g.myTurn }
        .onChange(of: conn.version) { _ in
            Gestures.shared.handler = { read($0) }
            if let prev = prevGame { gameSounds(prev: prev, g: g) }
            if let p = prevGame, g.trickNo == p.trickNo + 1, g.lastTrick != nil, g.trick.isEmpty { holdTrick() }
            // إعلان "دورك" مرة واحدة عند بداية الدور
            if g.myTurn && !wasMyTurn { Announcer.announce("دورك"); Sounds.shared.turn(soft: Announcer.readerOn) }
            wasMyTurn = g.myTurn
            prevGame = g
        }
    }

    /// بعد آخر ورقة في الأكلة: نبقي الأوراق الأربع ظاهرة لحظة قبل أن تذهب لصاحبها
    private func holdTrick() {
        let n = g.trickNo
        heldTrick = n
        DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD - 0.15) { Sounds.shared.collect() }
        DispatchQueue.main.asyncAfter(deadline: .now() + TRICK_HOLD) { if heldTrick == n { heldTrick = nil } }
    }

    /// وسط الطاولة: الوصول له يقرأ كل الأوراق ومن لعبها، والنقر مرتين يعيد قراءتها.
    /// وفي دوّار VoiceOver (الإجراءات): القراءات الثلاث
    private var trickArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Palette.green800)
            if (g.phase == "bidding" || g.phase == "doubling"), let q = g.qaba {
                VStack {
                    Text("ورقة الأرض").foregroundColor(Palette.textDim)
                    CardFace(card: q).frame(width: 70)
                }
            }
            ForEach(shownTrick, id: \.seat) { p in
                let rel = (p.seat - me + 4) % 4
                // الأوراق تنزل من جهة لاعبها (في RTL: leading = يمين الشاشة)
                let align: Alignment = rel == 0 ? .bottom : rel == 1 ? .leading : rel == 2 ? .top : .trailing
                CardFace(card: p.card).frame(width: 62).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shownTrick.isEmpty ? "وسط الطاولة: لا توجد أوراق" : "وسط الطاولة: \(text.trick())")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { _ = read(.left) }
        .accessibilityAction(named: "أوراق الطاولة") { _ = read(.left) }
        .accessibilityAction(named: "نوع اللعب") { _ = read(.right) }
        .accessibilityAction(named: "المشاريع") { _ = read(.up) }
    }

    /// صاحب المزايدة يسمع صوتها فوراً عند الضغط (ولا يتكرر حين يصل التحديث من الخادم)
    private func bidSound(_ b: Bid) {
        switch b.type {
        case "hokm": Sounds.shared.hokm()
        case "sun", "ashkal": Sounds.shared.sun()
        case "confirmHokm": Sounds.shared.confirmHokm()
        default: break
        }
    }

    private func gameSounds(prev: GameView, g: GameView) {
        let s = Sounds.shared
        let total = { (x: GameView) in x.handCounts.reduce(0, +) }
        if total(g) > total(prev) { s.deal(newHand: total(g) - total(prev) > 12) }
        // الورقة الجديدة: آخر ورقة في الأكلة الحالية، أو الرابعة إن اكتملت الأكلة للتو
        var played: (Card, Card)?
        if g.trickNo == prev.trickNo && g.trick.count > prev.trick.count { played = (g.trick.last!.card, g.trick.first!.card) }
        else if g.trickNo == prev.trickNo + 1, let lt = g.lastTrick, lt.count == 4 { played = (lt[3].card, lt[0].card) }
        if let p = played {
            let (card, lead) = p
            let trump = g.contract?.mode == "hokm" ? g.contract?.trump : nil
            if let trump, card.suit == trump && lead.suit != trump { s.cut() } else { s.card() }
        }
        if g.declared.count > prev.declared.count { s.project() }
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
        // المزايدة
        if let k = g.hokmBidKey, k != prev.hokmBidKey { s.hokm() }
        if let c = g.contract, prev.contract == nil {
            if c.mode == "sun" { s.sun() } else if prev.hokmBidKey != nil { s.confirmHokm() }
        }
        if g.doubling.gahwa && !prev.doubling.gahwa { s.gahwa() }
        else if g.doubling.level > prev.doubling.level { s.double(g.doubling.level) }
    }
}

private struct ScoreBox: View {
    let label: String
    let value: Int
    var body: some View {
        VStack {
            Text(label).foregroundColor(Palette.textDim)
            Text("\(value)").font(.system(size: 22, weight: .bold))
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlayerTag: View {
    let v: TableView
    let g: GameView
    let seat: Int
    var partner = false
    var body: some View {
        let s = v.seat(seat)
        let turn = g.turn == seat && g.phase != "matchOver"
        let label = (s?.username ?? "مقعد \(seat + 1)") + (s?.isBot == true ? " (روبوت)" : "") + (s?.away == true ? " (انقطع الاتصال)" : "") + (partner ? " (شريكك)" : "")
        Text(label)
            .multilineTextAlignment(.center)
            .font(.system(size: 15))
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(turn ? Palette.gold : .clear, lineWidth: 2))
    }
}

/// ورقة في اليد: تبقى قابلة للتركيز حتى وهي غير مسموحة، فلا يقفز مؤشر VoiceOver حين ينتهي دورك
private struct HandCard: View {
    let card: Card
    let legal: Bool
    let play: () -> Void
    var body: some View {
        CardFace(card: card)
            .aspectRatio(0.69, contentMode: .fit)
            .opacity(legal ? 1 : 0.55)
            .contentShape(Rectangle())
            .onTapGesture { if legal { play() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.label)
            .accessibilityValue(legal ? "" : "غير متاحة")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if legal { play() } }
    }
}
