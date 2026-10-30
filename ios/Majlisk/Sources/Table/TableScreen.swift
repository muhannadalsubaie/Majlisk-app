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
            // الشاشة لا تنطفئ ما دمت في الطاولة (انطفاؤها يقطع الاتصال والمحادثة الصوتية)
            UIApplication.shared.isIdleTimerDisabled = true
            conn.start()
            // نغمة الانضمام يسمعها المنضم نفسه أول ما يدخل الطاولة (الموجودون يسمعونها من إعلان الخادم)
            Sounds.shared.tableJoin()
            // كل من يدخل الطاولة ينضم للمحادثة الصوتية مستمعاً، وميكروفونه مقفل حتى يفتحه بنفسه
            Voice.shared.join(tableId, uid: uid, mode: .auto)
        }
        .task {
            // نبضة كل ١٠ ثوانٍ: لو أُغلق التطبيق ورجعت خلال دقيقة يرجعك لنفس الطاولة
            while !Task.isCancelled {
                Prefs.lastTable = tableId
                Prefs.lastTableAt = Date().timeIntervalSince1970
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .onDisappear { Prefs.lastTable = nil; UIApplication.shared.isIdleTimerDisabled = false; conn.stop(); Voice.shared.dispose(); Gestures.shared.handler = nil }
        .onReceive(NotificationCenter.default.publisher(for: .appForeground)) { _ in conn.reconnectNow(); Voice.shared.onForeground() }
        .onChange(of: conn.view?.voice ?? []) { list in Voice.shared.sync(list) }
    }

    @ViewBuilder private func table(_ v: TableView) -> some View {
        Screen(fill: true) {
            HStack(spacing: 8) {
                SmallButton("القائمة") { menuOpen = true }
                if v.kind == "baloot" { SmallButton("السجل") { historyOpen = true } }
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
            // زر الميكروفون أسفل يسار الشاشة، بعد الأوراق مباشرة في ترتيب VoiceOver
            // (الرجوع منه يعود للأوراق، لا لبداية الصفحة)
            // للمشاهد (بلا أوراق) يبقى الزر في أسفل الشاشة
            Spacer(minLength: 0)
            HStack { Spacer(); VoiceButton(tableId: v.id, uid: uid) }
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
        // نقرأ من آخر حالة وصلت من الخادم وقت الإيماءة نفسها، فلا تُقرأ حالة قديمة
        let text = conn.view.flatMap { v in v.game.map { BalootText(view: v, g: $0, shownTrick: $0.trick) } } ?? self.text
        switch dir {
        case .left: Announcer.announceNow(text.trick())
        case .right: Announcer.announceNow(text.contract())
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
                let unit = geo.size.width / 4.6
                VStack(spacing: 6) {
                    PlayerTag(v: v, g: g, seat: (me + 2) % 4, partner: true).frame(width: unit * 3)
                    HStack(spacing: 6) {
                        PlayerTag(v: v, g: g, seat: (me + 1) % 4).frame(width: unit * 0.8)
                        trickArea.frame(width: min(unit * 3, 300), height: min(unit * 3, 300))
                        PlayerTag(v: v, g: g, seat: (me + 3) % 4).frame(width: unit * 0.8)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: min(UIScreen.main.bounds.width - 32, 400) / 4.6 * 3 + 70)
            .background(RadialGradient(colors: [Palette.green700.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 220))

            if g.phase == "matchOver" && g.outcomeStatus == "won" {
                Text(g.outcomeWinner == myTeam ? "🎉 فاز فريقك!" : "فاز الفريق الآخر").font(.system(size: 21, weight: .bold)).foregroundColor(Palette.goldSoft)
            }

            if g.phase == "matchOver" && v.ownerUid == uid { MButton("مباراة جديدة", .primary) { conn.send("start") } }

            // أزرار الشراء فوق الأوراق مباشرة، بمسافة بسيطة جداً
            VStack(spacing: 4) {
                // أزرار المزايدة
                if !g.actions.bids.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(g.actions.bids) { b in
                            SmallButton(b.label, primary: b.type != "pass") { bidSound(b); act(["type": "bid", "bid": b.raw]) }
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
                        if g.actions.canPassDouble { MButton("بس") { act(["type": "doublePass"]) } }
                    }
                }
                if g.actions.chooseLock {
                    HStack(spacing: 8) {
                        MButton("مقفل", .primary) { act(["type": "doubleLock", "locked": true]) }
                        MButton("مفتوح", .primary) { act(["type": "doubleLock", "locked": false]) }
                    }
                }
                // يد اللاعب
                if mySeat != nil {
                    Text("أوراقك").font(.system(size: 1)).foregroundColor(.clear).accessibilityAddTraits(.isHeader)
                    // أوراقك في أسفل الشاشة، أكبر قليلاً من أوراق الطاولة
                    // أوراقك مروحة على قوس كأنها في يدك: كل ورقة فوق التي على يسارها، فيبقى رمزها (في زاويتها اليسرى) ظاهراً
                    let hand = sortHand(g.myHand)
                    ZStack(alignment: .bottom) {
                        ForEach(hand, id: \.self) { c in
                            let k = CGFloat(hand.firstIndex(of: c) ?? 0) - CGFloat(hand.count - 1) / 2
                            HandCard(card: c, legal: g.actions.legal.contains(c)) { act(["type": "play", "card": c.json]) }
                                .rotationEffect(.degrees(Double(k) * 7.5), anchor: UnitPoint(x: 0.5, y: 2.6))
                        }
                    }
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .bottom)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .onAppear { Gestures.shared.handler = { read($0) }; prevGame = g; wasMyTurn = g.myTurn }
        .onChange(of: conn.version) { _ in
            Gestures.shared.handler = { read($0) }
            if let prev = prevGame { gameSounds(prev: prev, g: g) }
            if let p = prevGame, g.trickNo == p.trickNo + 1, g.lastTrick != nil, g.trick.isEmpty { holdTrick() }
            // إعلان "دورك" مرة واحدة عند بداية الدور
            // النغمة أولاً (فورية)، ثم الإعلان
            if g.myTurn && !wasMyTurn { Sounds.shared.turn(soft: Announcer.readerOn); Announcer.announce("دورك") }
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
            // طاولة ثلاثية الأبعاد: إطار خشب ومفرش أخضر
            Circle().fill(RadialGradient(colors: [Color(red: 0.54, green: 0.35, blue: 0.17), Color(red: 0.36, green: 0.23, blue: 0.10), Color(red: 0.23, green: 0.14, blue: 0.06)], center: .center, startRadius: 0, endRadius: 160))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
            Circle().fill(RadialGradient(colors: [Color(red: 0.12, green: 0.42, blue: 0.29), Color(red: 0.08, green: 0.31, blue: 0.21), Color(red: 0.04, green: 0.14, blue: 0.11)], center: .center, startRadius: 0, endRadius: 150))
                .padding(10)
            Circle().stroke(Palette.gold.opacity(0.33), lineWidth: 1).padding(10)
            if (g.phase == "bidding" || g.phase == "doubling"), let q = g.qaba {
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
        .animation(.easeOut(duration: 0.35), value: shownTrick.count)
        // مائلة كأنك جالس عليها
        .rotation3DEffect(.degrees(40), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("وسط الطاولة: \(text.trick())")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { _ = read(.left) }
        .accessibilityAction(named: "أوراق الطاولة") { _ = read(.left) }
        .accessibilityAction(named: "نوع اللعب") { _ = read(.right) }
        .accessibilityAction(named: "المشاريع") { _ = read(.up) }
        .accessibilityAction(named: "دور مين") { _ = read(.down) }
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
            .font(.system(size: 14, weight: .bold))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(turn ? Palette.gold.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(turn ? Palette.gold : .clear, lineWidth: 1))
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
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.8), lineWidth: 0.5))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.73, green: 0.71, blue: 0.65)).offset(y: 1.5))
            .shadow(color: .black.opacity(0.7), radius: 6, y: 4)
    }
}

/// ورقة في اليد: تبقى قابلة للتركيز حتى وهي غير مسموحة، فلا يقفز مؤشر VoiceOver حين ينتهي دورك
private struct HandCard: View {
    let card: Card
    let legal: Bool
    let play: () -> Void
    var body: some View {
        TableCard(card: card, width: 66, height: 96)
            // المسموح لعبها بإطار ذهبي فقط، فيبقى شكل المروحة واحداً
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(legal ? Palette.goldSoft : .clear, lineWidth: 3))
            .contentShape(Rectangle())
            .onTapGesture { if legal { play() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.label)
            .accessibilityValue(legal ? "" : "غير متاحة")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if legal { play() } }
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
