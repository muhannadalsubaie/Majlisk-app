import SwiftUI

// ألعاب الورق الجديدة (طرنيب، تريكس، كنكان، شايب): الخادم يرسل لكل لاعب «وش يشوف» بس —
// أوراقه وأزرار حركاته المسموحة ونصوص قارئ الشاشة — والتطبيق يرسم ويرسل الحركة كما هي.

struct CardsCard: Hashable {
    let id: Int, r: String, s: String
    init(_ o: JSON?) { id = o?.int("id") ?? 0; r = o?.str("r") ?? ""; s = o?.str("s") ?? "" }
    var red: Bool { s == "H" || s == "D" }
    var joker: Bool { r == "JK" }
    var symbol: String { ["S": "♠", "H": "♥", "D": "♦", "C": "♣"][s] ?? "" }
    var short: String { joker ? "★" : r }
}

struct CardsView {
    struct Seat { let seat: Int, name: String, count: Int, note: String, turn: Bool }
    struct Pile { let id: String, title: String, text: String, cards: [CardsCard], group: String }
    struct HandCard { let face: CardsCard, label: String, legal: Bool }
    struct Button { let id: String, label: String, primary: Bool, needsSelection: Bool }

    let game: String
    let over: Bool
    let myTurn: Bool
    let prompt: String
    let status: String
    let scores: [(String, Int)]
    let seats: [Seat]
    let center: [(Int, CardsCard)]
    /// الأكلة اكتملت: تنعرض لحظة وتنشال
    let centerDone: Bool
    let piles: [Pile]
    let hand: [HandCard]
    let select: Bool
    let buttons: [Button]
    let readUp: String, readDown: String, readLeft: String, readRight: String
    /// أصوات آخر حركة من الخادم: رقمها يتغير مع كل حركة فيها صوت، وfxWin مقاعد الفائزين لما تخلص المباراة
    let fxN: Int?
    let fxKeys: [String]
    let fxWin: [Int]?
    let fxBy: Int?
    /// لوحة اللعبة على الطاولة (عقد التريكس، سحب وأرض الكنكان)
    let board: CardsBoardInfo?

    init(_ c: JSON) {
        let u = c.obj("ui") ?? [:]
        let reads = u.obj("reads") ?? [:]
        game = c.str("game")
        over = c.bool("over")
        myTurn = u.bool("myTurn")
        prompt = u.str("prompt")
        status = u.str("status")
        scores = u.objs("scores").map { ($0.str("name"), $0.int("value")) }
        seats = u.objs("seats").map { Seat(seat: $0.int("seat"), name: $0.str("name"), count: $0.int("count"), note: $0.str("note"), turn: $0.bool("turn")) }
        center = u.objs("center").map { ($0.int("seat"), CardsCard($0.obj("card"))) }
        centerDone = u.bool("centerDone")
        piles = u.objs("piles").map { p in Pile(id: p.str("id"), title: p.str("title"), text: p.str("text"), cards: p.objs("cards").map { CardsCard($0) }, group: p.str("group")) }
        board = u.obj("board").map { CardsBoardInfo($0) }
        hand = u.objs("hand").map { HandCard(face: CardsCard($0), label: $0.str("label"), legal: $0.bool("legal")) }
        select = u.bool("select")
        buttons = u.objs("buttons").map { Button(id: $0.str("id"), label: $0.str("label"), primary: $0.bool("primary"), needsSelection: $0.bool("needsSelection")) }
        readUp = reads.str("up"); readDown = reads.str("down"); readLeft = reads.str("left"); readRight = reads.str("right")
        let fx = c.obj("fx")
        fxN = fx?.intOrNil("n")
        fxKeys = fx?.strs("keys") ?? []
        fxWin = fx?["win"] == nil ? nil : fx?.ints("win")
        fxBy = fx?.intOrNil("by")
    }
}

/// ورقة مرسومة: رقمها ونوعها (الأحمر للهاص والديمن)، والجوكر نجمة
struct CardsFace: View {
    let c: CardsCard
    let w: CGFloat, h: CGFloat
    var dim = false
    /// المحددة (الكونكان والشايب): خلفية ذهبية فاتحة وعلامة ✓، تبان واضحة بدون قارئ الشاشة
    var selected = false
    var body: some View {
        Text(verbatim: "\(c.short)\(c.symbol)")
            .font(.system(size: w * 0.36, weight: .bold))
            .foregroundColor(c.joker ? Color(red: 0.42, green: 0.25, blue: 0.71) : c.red ? Color(red: 0.78, green: 0.16, blue: 0.16) : Color(white: 0.1))
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: w, height: h)
            .background(selected ? Color(red: 0.96, green: 0.89, blue: 0.63) : dim ? Color(red: 0.81, green: 0.79, blue: 0.73) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.73, green: 0.71, blue: 0.65), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if selected { Text(verbatim: "✓").font(.system(size: w * 0.28, weight: .bold)).foregroundColor(Color(red: 0.11, green: 0.37, blue: 0.13)).padding(.trailing, 2) }
            }
            .accessibilityHidden(true)
    }
}

/// لاعب حول الطاولة: صورته (ومؤقت الدور حولها)، واسمه، وكم ورقة معه، وملاحظته
private struct CardsSeatTag: View {
    let v: TableView
    let s: CardsView.Seat
    var body: some View {
        let me = s.seat == v.mySeat
        VStack(spacing: 1) {
            TurnAvatar(v: v, seat: s.seat, turn: s.turn, uid: v.seatUid(s.seat), name: s.name, size: 44)
            Text(trSpoken(me ? "أنت" : s.name)).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text).lineLimit(1)
            Text(verbatim: "🂠 \(s.count)").font(.system(size: 11)).foregroundColor(Palette.textDim)
            Text(trSpoken(s.note.isEmpty ? " " : s.note)).font(.system(size: 11)).foregroundColor(Palette.goldSoft).lineLimit(1)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText("\(me ? "أنت" : s.name)، \(s.count) \(s.count == 1 ? "ورقة" : "أوراق")\(s.note.isEmpty ? "" : "، \(s.note)")\(s.turn ? "، عليه الدور" : "")"))
    }
}

private struct CardsSlot: Identifiable { let id: Int; let h: CardsView.HandCard }

/// لوحة ألعاب الورق الجديدة: نفس الشكل للأربع، والخادم يحدد المحتوى.
/// كل جزء له مكان محجوز (الحالة، النقاط، اللاعبين، الأرض، الأزرار، الأوراق) فالشاشة ما تتحرك.
struct CardsBoard: View {
    let v: TableView
    let c: CardsView
    @ObservedObject var conn: TableConnection
    let isOwner: Bool
    /// الكنكان: الأوراق المحددة
    @State private var selected: Set<Int> = []
    @AccessibilityFocusState private var slotFocus: Int?
    @State private var playedPos: Int?
    /// مكان اليد ثابت طول اللعبة: أكثر عدد سطور وصلت له، وحجم الورقة (يصغر بس لو احتاج، وما يرجع يكبر)
    @State private var keptRows = 1
    @State private var slotW: CGFloat = HAND_SLOTS[0]
    @State private var handWidth: CGFloat = 0
    /// سحبت ورقة (الكونكان والشايب): قارئ الشاشة يقول وش الورقة اللي جتك (الخادم يقول للكل «سحب ورقة» بس)
    @State private var drawAt: Date?
    @State private var drawFromPile = false
    @State private var prevIds: Set<Int> = []
    /// الأكلة المكتملة: تبقى لحظة (تشوف آخر ورقة) وتنشال مع صوت الأخذ، بدل ما تنتظر أول ورقة في الأكلة الجاية
    @State private var doneHidden = false
    private var doneKey: String { c.centerDone ? c.center.map { "\($0.0):\($0.1.id)" }.joined(separator: ",") : "" }

    private func send(_ a: JSON) {
        if UIAccessibility.isVoiceOverRunning { Announcer.interruptNextEvents() }
        conn.send(["type": "cards", "action": a])
    }
    /// مجموعة أوراق من نفس النوع (أو نفس الرقم في الشايب)
    private struct HandGroup: Identifiable { let id: Int; var slots: [CardsSlot] }
    private var handGroups: [HandGroup] {
        var out: [HandGroup] = []
        let key = { (h: CardsView.HandCard) in c.game == "shayeb" ? h.face.r : h.face.s }
        for (i, h) in c.hand.enumerated() {
            if let last = out.last?.slots.last, key(last.h) == key(h) { out[out.count - 1].slots.append(CardsSlot(id: i, h: h)) }
            else { out.append(HandGroup(id: i, slots: [CardsSlot(id: i, h: h)])) }
        }
        return out
    }
    /// سطور اليد بعرض الشاشة وحجم الورقة الحالي (بدون تراكب، والمجموعة ما تنقسم إلا لو أطول من سطر)
    private var handRows: [[HandGroup]] {
        let groups = handGroups
        return packHand(groups, sizes: groups.map { $0.slots.count }, avail: handWidth, slot: slotW) { g, r in
            HandGroup(id: g.slots[r.lowerBound].id, slots: Array(g.slots[r]))
        }
    }
    /// يحدّث حجم الورقة وعدد السطور المحجوزة (يكبر المكان بس، وما يصغر لين تنتهي اللعبة)
    private func planHand() {
        guard handWidth > 0 else { return }
        let sizes = handGroups.map { $0.slots.count }
        // الكونكان: ورقة زيادة لما تسحب، فنحجز مكانها من البداية
        let planned = c.hand.count + (c.game == "konkan" ? 1 : 0)
        let fit = HAND_SLOTS.filter { $0 <= slotW }.first { handRowsCount(sizes, planned: planned, avail: handWidth, slot: $0) <= 3 } ?? HAND_SLOTS[HAND_SLOTS.count - 1]
        if fit < slotW { slotW = fit }
        keptRows = max(keptRows, handRowsCount(sizes, planned: planned, avail: handWidth, slot: slotW))
    }
    /// ورقة في يدك: مربوطة بمكانها (المؤشر ما يقفز بعد ما تلعب)
    @ViewBuilder private func handCard(_ slot: CardsSlot) -> some View {
        let h = slot.h
            let sel = selected.contains(h.face.id)
            Button {
                if c.select { if sel { selected.remove(h.face.id) } else { selected.insert(h.face.id) }; Announcer.announceNow(sel ? "شلت التحديد" : "محددة") }
                else if !c.myTurn { Announcer.announceNow("ليس دورك") }
                else if !h.legal { Sounds.shared.illegal() }
                else { if UIAccessibility.isVoiceOverRunning { playedPos = slot.id }; Sounds.shared.cardsFx([(c.board?.rows ?? []).isEmpty ? "c-card" : "c-row"], won: nil); Sounds.shared.markLocal("cards"); send(["op": "card", "id": h.face.id]) }
            } label: {
                CardsFace(c: h.face, w: slotW - 4, h: slotW * 1.4 - 4, dim: c.myTurn && !c.select && !h.legal, selected: sel)
                    .padding(2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(sel ? Palette.gold : (h.legal && !c.select ? Palette.gold.opacity(0.6) : .clear), lineWidth: sel ? 3 : 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenText(h.label + (sel ? "، محددة" : "")))
            // الأزرار والسحب كإجراءات على الورقة (مثل الشراء في البلوت): الكفيف ما يحتاج يروح للأزرار
            .accessibilityActions {
                if let d = c.board?.draw { ForEach(0..<d.count, id: \.self) { k in Button(tr("اسحب كرت \(k + 1)")) { press("draw:\(k)", false) } } }
                ForEach(shownButtons, id: \.id) { b in Button(tr(b.label)) { press(b.id, b.needsSelection) } }
            }
            .accessibilityFocused($slotFocus, equals: slot.id)
    }
    /// الأزرار الظاهرة: أوراق السحب في الشايب ترسم مقلوبة فوق بدل الأزرار
    private var shownButtons: [CardsView.Button] { c.buttons.filter { !(c.board?.draw != nil && $0.id.hasPrefix("draw:")) } }
    private func press(_ id: String, _ needs: Bool) {
        if needs && selected.isEmpty { Announcer.announceNow("حدد أوراق أول"); return }
        if id.hasPrefix("draw:") { drawAt = Date(); drawFromPile = id == "draw:pile" }
        var a: JSON = ["op": "button", "id": id]
        if needs || id.hasPrefix("pile:") { a["cards"] = Array(selected); selected = [] }
        send(a)
    }
    private func read(_ raw: SwipeDir) -> Bool {
        let cur = conn.view?.cards ?? c
        switch raw {
        case .up: Announcer.announceNow(cur.readDown)
        case .down: Announcer.announceNow(cur.readUp)
        case .left: Announcer.announceNow(cur.readLeft)
        case .right: Announcer.announceNow(cur.readRight)
        }
        return true
    }

    var body: some View {
        VStack(spacing: 6) {
            // الحالة: سطر واحد ثابت
            Text(trSpoken(c.status.isEmpty ? " " : c.status)).font(.system(size: 14, weight: .bold)).foregroundColor(Palette.goldSoft)
                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            // النقاط
            HStack(spacing: 6) {
                ForEach(Array(c.scores.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: 0) {
                        Text(trSpoken(s.0)).font(.system(size: 11)).foregroundColor(Palette.textDim).lineLimit(1)
                        Text(verbatim: "\(s.1)").font(.system(size: 18, weight: .bold)).foregroundColor(Palette.gold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.09, green: 0.24, blue: 0.17)))
                    .accessibilityElement(children: .ignore).accessibilityLabel(spokenText("\(s.0) \(s.1)"))
                }
            }
            .frame(minHeight: 34)
            // الطاولة مثل البلوت: اللاعبين حولها (اللي بعدك على جنب، واللي قدامك فوق) ووسطها الأرض
            let myIdx = c.seats.firstIndex { $0.seat == v.mySeat }
            let n = c.seats.count
            let others: [CardsView.Seat] = myIdx.map { m in (1..<max(n, 1)).map { c.seats[(m + $0) % n] } } ?? Array(c.seats.dropFirst())
            // 4 لاعبين أو أقل: واحد فوق واثنين على الجنبين. أكثر (الكنكان والشايب حتى 7): أول واحد وآخر واحد على الجنبين، والباقي صف فوق
            let many = others.count > 3
            let top: CardsView.Seat? = others.count == 1 ? others[0] : others.count == 3 ? others[1] : nil
            let side1: CardsView.Seat? = others.count >= 2 ? others[0] : nil
            let side2: CardsView.Seat? = many ? others.last : others.count == 2 ? others[1] : others.count == 3 ? others[2] : nil
            let topRow: [CardsView.Seat] = many ? Array(others[1..<(others.count - 1)]) : (top.map { [$0] } ?? [])
            let stack = c.piles.first { $0.id == "stack" }
            // فيه مجموعات تحت الطاولة (تنزيلات الكنكان): الطاولة أصغر عشان تبان كلها
            // الكنكان: مكان التنزيلات محجوز من أول اللعبة (والطاولة بحجمها الصغير)، فلما تزيد التنزيلات ما تنزل الطاولة ولا تتحرك
            let hasRows = c.game == "konkan" || c.piles.contains { $0.id != "stack" }
            // المشاهد ما عنده أوراق ولا أزرار: ما نحجز لها مكان
            let watcher = myIdx == nil
            // رأس اللوحة: اسم العقد بلونه، ووش تتجنب، وعقود المملكة
            if let b = c.board { CardsBoardHeader(b: b) }
            // الشايب: أوراق اللي تسحب منه مقلوبة فوق الطاولة
            if let d = c.board?.draw { ShayebDrawRow(d: d) { i in press("draw:\(i)", false) }.id("draw-\(d.seat)-\(d.count)") }
            CardsTableArea(v: v, c: c, top: top, topRow: topRow, side1: side1, side2: side2, stack: stack, hasRows: hasRows, watcher: watcher,
                           shownCenter: c.centerDone && doneHidden ? [] : c.center, press: press)
            // المجموعات: تنزيلات الكنكان، صفوف التركس (تنضغط في الكنكان للصق المحدد عليها)
            ScrollView {
                VStack(spacing: 4) {
                    let shownPiles = c.piles.filter { $0.id != "stack" }
                    ForEach(Array(shownPiles.enumerated()), id: \.element.id) { k, p in
                        let canLay = c.select && c.myTurn && p.id.hasPrefix("meld:")
                        // الكنكان: تنزيلات كل لاعب تحت اسمه
                        if !p.group.isEmpty && (k == 0 || shownPiles[k - 1].group != p.group) {
                            Text(trSpoken(p.group)).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.gold).frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
                        }
                        HStack(spacing: 3) {
                            Text(trSpoken(p.title)).font(.system(size: 12)).foregroundColor(Palette.goldSoft).lineLimit(1).frame(width: 56, alignment: .leading)
                            // صف طويل (التركس يوصل 13 ورقة): الأوراق فوق بعض شوي عشان يبان الصف كامل
                            HStack(spacing: p.cards.count > 8 ? -8 : 3) {
                                ForEach(Array(p.cards.enumerated()), id: \.offset) { _, f in CardsFace(c: f, w: 24, h: 34) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.09)))
                        .contentShape(Rectangle())
                        .onTapGesture { if canLay { press("pile:\(p.id)", true) } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spokenText("\(p.title)، \(p.text)\(canLay ? "، اضغط للصق الأوراق المحددة" : "")"))
                        .accessibilityAddTraits(canLay ? .isButton : [])
                    }
                }
            }
            // التنزيلات تتمرر داخل مكانها (ما تكبر وتدفع الطاولة): ارتفاع ثابت في الكنكان
            .frame(minHeight: hasRows ? 120 : 0, idealHeight: hasRows ? 150 : 0, maxHeight: c.game == "konkan" ? 170 : .infinity)
            .layoutPriority(-1)
            // الكنكان: شريط الفتح (مجموع تنزيلك من الـ51)
            if let pr = c.board?.progress { KonkanProgress(p: pr) }
            // الأزرار: مكان محجوز دايماً
            WrapLayout(spacing: 6) {
                // أوراق السحب في الشايب ترسم مقلوبة فوق، ما تطلع أزرار
                ForEach(shownButtons, id: \.id) { b in
                    SmallButton(b.label, primary: b.primary) { press(b.id, b.needsSelection) }
                }
                if c.over && isOwner { NewMatchButton(label: "لعبة جديدة", v: v, conn: conn, small: true) }
            }
            .frame(maxWidth: .infinity, minHeight: watcher && !(c.over && isOwner) ? 0 : 44)
            if !watcher { Text(trSpoken(c.select && !selected.isEmpty ? "محدد \(selected.count)" : " ")).font(.system(size: 12)).foregroundColor(Palette.goldSoft).accessibilityHidden(true) }
            // أوراقك: كل ورقة مربوطة بمكانها في اليد (مثل البلوت) فالمؤشر ما يقفز بعد ما تلعب
            // اليد: الأوراق جنب بعض بدون تراكب (كل ورقة تنضغط بسهولة)، وكل مجموعة (نوع، أو رقم في الشايب) مع بعض.
            // لو ما كفّى السطر تنزل لسطر تحته. المكان ثابت طول اللعبة فالشاشة ما تطلع وتنزل
            let rows = handRows
            VStack(spacing: HAND_ROW_GAP) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, rowGroups in
                    HStack(spacing: HAND_GROUP_GAP) {
                        ForEach(rowGroups) { g in
                            HStack(spacing: HAND_CARD_GAP) { ForEach(g.slots) { slot in handCard(slot) } }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: watcher && c.hand.isEmpty ? 0 : slotW * 1.4 * CGFloat(keptRows) + HAND_ROW_GAP * CGFloat(keptRows - 1), alignment: .top)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { handWidth = g.size.width; planHand() }
                    .onChange(of: g.size.width) { w in handWidth = w; planHand() }
            })
            .onChange(of: c.hand.count) { _ in planHand() }
            .onChange(of: c.hand.map { $0.face.id }) { ids in
                let added = Set(ids).subtracting(prevIds)
                prevIds = Set(ids)
                if let t = drawAt, Date().timeIntervalSince(t) < 8, added.count == 1, let h = c.hand.first(where: { added.contains($0.face.id) }) {
                    drawAt = nil
                    Announcer.announce("\(drawFromPile ? "أخذت" : "سحبت") \(h.label)")
                }
            }
            .onAppear { prevIds = Set(c.hand.map { $0.face.id }) }
            .onChange(of: c.game) { _ in keptRows = 1; slotW = HAND_SLOTS[0]; planHand() }
        }
        .onChange(of: c.hand.count) { n in
            guard let p = playedPos else { return }
            playedPos = nil
            if p >= n && n > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { slotFocus = n - 1 } }
            let ids = Set(c.hand.map { $0.face.id })
            selected = selected.filter { ids.contains($0) }
        }
        // أصوات الحركات (توزيع، ورقة، أكلة، سحب، تنزيل…): مرة لكل حركة، وأول ما تفتح الطاولة ما نشغل القديم
        // الأصوات والدور: كل اللي نحتاجه يجي مع القيمة الجديدة نفسها. داخل onChange القيم الثانية من الواجهة
        // ممكن تكون حق التحديث اللي قبله (كان يطلع صوت الحركة اللي قبل: تسحب ما يطلع شي، وترمي يطلع صوت السحب)
        .onChange(of: FxEvent(c)) { ev in
            guard ev.n != nil else { return }
            let won: Bool? = ev.win.flatMap { w in v.mySeat.flatMap { $0 >= 0 ? w.contains($0) : nil } }
            // ورقتك: صوتها اشتغل وقت الضغط، فما نعيده لما يوصل رد الخادم
            var keys = ev.keys
            if let me = v.mySeat, ev.by == me, Sounds.shared.consumeLocal("cards"), let f = keys.first, f == "c-card" || f == "c-row" || f == "c-draw" { keys.removeFirst() }
            Sounds.shared.cardsFx(keys, won: won)
        }
        // جاك الدور: نغمة الدور، وVoiceOver يقول وش المطلوب
        .onChange(of: TurnEvent(mine: c.myTurn, prompt: c.prompt)) { t in
            guard t.mine else { return }
            Sounds.shared.turn(soft: Announcer.readerOn)
            if !t.prompt.isEmpty && UIAccessibility.isVoiceOverRunning {
                let p = t.prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Announcer.announce(p) }
            }
        }
        .onChange(of: doneKey) { key in
            doneHidden = false
            guard !key.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { if doneKey == key { doneHidden = true } }
        }
        .onAppear { Gestures.shared.set("cards") { read($0) } }
        .onDisappear { Gestures.shared.clear("cards") }
    }
}


/// الطاولة: اللاعبين حولها ووسطها حسب اللعبة — الأكلة (وفوقها الأوراق الخطرة وعداد العقد)، أو صفوف التركس بعرض الشاشة،
/// أو السحب والأرض (الكنكان)، أو كومة الأزواج (الشايب)
private struct CardsTableArea: View {
    let v: TableView
    let c: CardsView
    let top: CardsView.Seat?, topRow: [CardsView.Seat], side1: CardsView.Seat?, side2: CardsView.Seat?
    let stack: CardsView.Pile?
    let hasRows: Bool, watcher: Bool
    let shownCenter: [(Int, CardsCard)]
    let press: (String, Bool) -> Void

    private var felt: Color { Color(red: 0.06, green: 0.23, blue: 0.16) }
    private var rim: Color { Color(red: 0.42, green: 0.29, blue: 0.17) }

    var body: some View {
        VStack(spacing: 6) {
            if let rows = c.board?.rows, !rows.isEmpty {
                // التركس: اللاعبين في صف واحد فوق، والطاولة كلها بعرض الشاشة لصفوف الأنواع الأربعة
                HStack(spacing: 0) {
                    ForEach([side1, top, side2].compactMap { $0 }, id: \.seat) { s in CardsSeatTag(v: v, s: s).frame(maxWidth: .infinity) }
                }
                TrixRows(rows: rows)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 22).fill(felt))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(rim, lineWidth: 3))
            } else {
                HStack(spacing: 0) {
                    ForEach(topRow, id: \.seat) { s in CardsSeatTag(v: v, s: s).frame(maxWidth: .infinity) }
                }
                .frame(minHeight: hasRows ? 0 : 92)
                HStack(spacing: 6) {
                    ZStack { if let side1 { CardsSeatTag(v: v, s: side1) } }.frame(width: 76)
                    middle
                    ZStack { if let side2 { CardsSeatTag(v: v, s: side2) } }.frame(width: 76)
                }
            }
            // المشاهد: أول لاعب تحت الطاولة
            if watcher, let first = c.seats.first { CardsSeatTag(v: v, s: first) }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 24).fill(RadialGradient(colors: [Color(red: 0.11, green: 0.30, blue: 0.22).opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 260)))
    }

    @ViewBuilder private var middle: some View {
        let b = c.board
        let heaps = b?.stock != nil || b?.discard != nil
        let marks = b?.marks ?? []
        let h: CGFloat = !marks.isEmpty ? 176 : hasRows ? 112 : 150
        let oval = ZStack {
            RoundedRectangle(cornerRadius: 70).fill(felt)
            RoundedRectangle(cornerRadius: 70).stroke(rim, lineWidth: 3)
            if let stack {
                ForEach(Array(stack.cards.enumerated()), id: \.offset) { i, f in
                    CardsFace(c: f, w: 40, h: 58)
                        .rotationEffect(.degrees(Double((i * 37) % 30 - 15)))
                        .offset(x: CGFloat((i * 53) % 24 - 12), y: CGFloat((i * 29) % 16 - 8))
                }
            } else if heaps {
                KonkanHeaps(stock: b?.stock, discard: b?.discard, onStock: { press("draw:stock", false) }, onDiscard: { press("draw:pile", false) })
            } else {
                VStack(spacing: 4) {
                    if let b, !marks.isEmpty { CardsMarksRow(b: b) }
                    HStack(spacing: 4) {
                        ForEach(Array(shownCenter.enumerated()), id: \.offset) { _, p in
                            VStack(spacing: 1) {
                                CardsFace(c: p.1, w: 40, h: 58)
                                Text(trSpoken(p.0 < 0 ? "الأرض" : c.seats.first { $0.seat == p.0 }?.name ?? "")).font(.system(size: 10)).foregroundColor(Palette.textDim).lineLimit(1).frame(width: 50)
                            }
                        }
                    }
                    .frame(minHeight: 70)
                    if let counter = b?.counter, !counter.isEmpty {
                        Text(trSpoken(counter)).font(.system(size: 11, weight: .bold)).foregroundColor(boardTone(b?.tone ?? "")).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: h, maxHeight: h)
        if heaps {
            oval
        } else {
            oval
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText(stack.map { "\($0.title): \($0.text)" } ?? [c.readLeft, b?.read ?? ""].filter { !$0.isEmpty }.joined(separator: ". ")))
        }
    }
}


/// صوت حركة من الخادم كقيمة وحدة (رقمها وأصواتها والفائزين واللي سواها)
private struct FxEvent: Equatable {
    let n: Int?, keys: [String], win: [Int]?, by: Int?
    init(_ c: CardsView) { n = c.fxN; keys = c.fxKeys; win = c.fxWin; by = c.fxBy }
    static func == (a: FxEvent, b: FxEvent) -> Bool { a.n == b.n }
}
/// جاك الدور: يتغير لما يبدأ دورك (وما ينعاد لو تغير نص الطلب وأنت في نفس الدور)
private struct TurnEvent: Equatable {
    let mine: Bool, prompt: String
    static func == (a: TurnEvent, b: TurnEvent) -> Bool { a.mine == b.mine }
}

/// عرض خانة الورقة في اليد (من الأكبر للأصغر): يصغر لين تدخل اليد في ٣ أسطر
private let HAND_SLOTS: [CGFloat] = [46, 42, 38, 34]
private let HAND_CARD_GAP: CGFloat = 4
private let HAND_GROUP_GAP: CGFloat = 12
private let HAND_ROW_GAP: CGFloat = 4

/// مجموعات اليد في أسطر بدون تراكب: المجموعة كاملة في سطر لو تكفّى، وإلا تنزل لسطر جديد،
/// والمجموعة الأطول من سطر كامل تنقسم
private func packHand<G>(_ groups: [G], sizes: [Int], avail: CGFloat, slot: CGFloat, split: (G, Range<Int>) -> G) -> [[G]] {
    guard avail > 0 else { return groups.isEmpty ? [] : [groups] }
    func width(_ n: Int) -> CGFloat { slot * CGFloat(n) + HAND_CARD_GAP * CGFloat(max(n - 1, 0)) }
    let cap = max(1, Int((avail + HAND_CARD_GAP) / (slot + HAND_CARD_GAP)))
    var rows: [[G]] = []
    var used: CGFloat = 0
    for (g, n) in zip(groups, sizes) {
        var from = 0
        while from < n {
            let rest = n - from
            let inRow = !(rows.last?.isEmpty ?? true)
            let start = inRow ? used + HAND_GROUP_GAP : 0
            if inRow && start + width(rest) <= avail {
                rows[rows.count - 1].append(split(g, from..<n)); used = start + width(rest); from = n
            } else if rest <= cap || !inRow {
                let take = min(rest, cap)
                rows.append([split(g, from..<(from + take))]); used = width(take); from += take
            } else {
                // أطول من سطر كامل: يكمل في السطر الحالي لو فيه مكان لورقتين أو أكثر، والباقي ينزل
                let room = Int((avail - start + HAND_CARD_GAP) / (slot + HAND_CARD_GAP))
                if room >= 2 { rows[rows.count - 1].append(split(g, from..<(from + room))); used = start + width(room); from += room }
                else { let take = min(rest, cap); rows.append([split(g, from..<(from + take))]); used = width(take); from += take }
            }
        }
    }
    return rows
}

/// كم سطر تحتاج اليد (ومعها ورقة زيادة متوقعة لو planned أكبر من الموجود: أسوأ حالة مجموعة لحالها)
private func handRowsCount(_ sizes: [Int], planned: Int, avail: CGFloat, slot: CGFloat) -> Int {
    let extra = max(0, planned - sizes.reduce(0, +))
    let all = sizes + (extra > 0 ? [extra] : [])
    return max(1, packHand(all, sizes: all, avail: avail, slot: slot) { n, _ in n }.count)
}
