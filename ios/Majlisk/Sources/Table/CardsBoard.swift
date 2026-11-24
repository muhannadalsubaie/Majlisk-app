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
    struct Pile { let id: String, title: String, text: String, cards: [CardsCard] }
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
    let piles: [Pile]
    let hand: [HandCard]
    let select: Bool
    let buttons: [Button]
    let readUp: String, readDown: String, readLeft: String, readRight: String
    /// أصوات آخر حركة من الخادم: رقمها يتغير مع كل حركة فيها صوت، وfxWin مقاعد الفائزين لما تخلص المباراة
    let fxN: Int?
    let fxKeys: [String]
    let fxWin: [Int]?

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
        piles = u.objs("piles").map { p in Pile(id: p.str("id"), title: p.str("title"), text: p.str("text"), cards: p.objs("cards").map { CardsCard($0) }) }
        hand = u.objs("hand").map { HandCard(face: CardsCard($0), label: $0.str("label"), legal: $0.bool("legal")) }
        select = u.bool("select")
        buttons = u.objs("buttons").map { Button(id: $0.str("id"), label: $0.str("label"), primary: $0.bool("primary"), needsSelection: $0.bool("needsSelection")) }
        readUp = reads.str("up"); readDown = reads.str("down"); readLeft = reads.str("left"); readRight = reads.str("right")
        let fx = c.obj("fx")
        fxN = fx?.intOrNil("n")
        fxKeys = fx?.strs("keys") ?? []
        fxWin = fx?["win"] == nil ? nil : fx?.ints("win")
    }
}

/// ورقة مرسومة: رقمها ونوعها (الأحمر للهاص والديمن)، والجوكر نجمة
struct CardsFace: View {
    let c: CardsCard
    let w: CGFloat, h: CGFloat
    var dim = false
    var body: some View {
        Text(verbatim: "\(c.short)\(c.symbol)")
            .font(.system(size: w * 0.36, weight: .bold))
            .foregroundColor(c.joker ? Color(red: 0.42, green: 0.25, blue: 0.71) : c.red ? Color(red: 0.78, green: 0.16, blue: 0.16) : Color(white: 0.1))
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: w, height: h)
            .background(dim ? Color(red: 0.81, green: 0.79, blue: 0.73) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.73, green: 0.71, blue: 0.65), lineWidth: 1))
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

    private func send(_ a: JSON) {
        if UIAccessibility.isVoiceOverRunning { Announcer.interruptNextEvents() }
        conn.send(["type": "cards", "action": a])
    }
    private func press(_ id: String, _ needs: Bool) {
        if needs && selected.isEmpty { Announcer.announceNow("حدد أوراق أول"); return }
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
            let top: CardsView.Seat? = others.count == 1 ? others[0] : others.count == 3 ? others[1] : nil
            let side1: CardsView.Seat? = others.count >= 2 ? others[0] : nil
            let side2: CardsView.Seat? = others.count == 2 ? others[1] : others.count == 3 ? others[2] : nil
            let stack = c.piles.first { $0.id == "stack" }
            VStack(spacing: 6) {
                ZStack { if let top { CardsSeatTag(v: v, s: top) } }.frame(minHeight: 92)
                HStack(spacing: 6) {
                    ZStack { if let side1 { CardsSeatTag(v: v, s: side1) } }.frame(width: 76)
                    // وسط الطاولة: الأكلة الحالية، أو كومة الأزواج المرمية فوق بعض (الشايب)
                    ZStack {
                        RoundedRectangle(cornerRadius: 70).fill(Color(red: 0.06, green: 0.23, blue: 0.16))
                        RoundedRectangle(cornerRadius: 70).stroke(Color(red: 0.42, green: 0.29, blue: 0.17), lineWidth: 3)
                        if let stack {
                            ForEach(Array(stack.cards.enumerated()), id: \.offset) { i, f in
                                CardsFace(c: f, w: 40, h: 58)
                                    .rotationEffect(.degrees(Double((i * 37) % 30 - 15)))
                                    .offset(x: CGFloat((i * 53) % 24 - 12), y: CGFloat((i * 29) % 16 - 8))
                            }
                        } else {
                            HStack(spacing: 4) {
                                ForEach(Array(c.center.enumerated()), id: \.offset) { _, p in
                                    VStack(spacing: 1) {
                                        CardsFace(c: p.1, w: 40, h: 58)
                                        Text(trSpoken(p.0 < 0 ? "الأرض" : c.seats.first { $0.seat == p.0 }?.name ?? "")).font(.system(size: 10)).foregroundColor(Palette.textDim).lineLimit(1).frame(width: 50)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenText(stack.map { "\($0.title): \($0.text)" } ?? c.readLeft))
                    ZStack { if let side2 { CardsSeatTag(v: v, s: side2) } }.frame(width: 76)
                }
                // المشاهد: أول لاعب تحت الطاولة
                if myIdx == nil, let first = c.seats.first { CardsSeatTag(v: v, s: first) }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 24).fill(RadialGradient(colors: [Color(red: 0.11, green: 0.30, blue: 0.22).opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 260)))
            // المجموعات: تنزيلات الكنكان، صفوف التركس (تنضغط في الكنكان للصق المحدد عليها)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(c.piles.filter { $0.id != "stack" }, id: \.id) { p in
                        let canLay = c.select && c.myTurn && p.id.hasPrefix("meld:")
                        HStack(spacing: 3) {
                            Text(trSpoken(p.title)).font(.system(size: 12)).foregroundColor(Palette.goldSoft).lineLimit(1).frame(width: 70, alignment: .leading)
                            ForEach(Array(p.cards.enumerated()), id: \.offset) { _, f in CardsFace(c: f, w: 24, h: 34) }
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
            .frame(maxHeight: .infinity)
            // الأزرار: مكان محجوز دايماً
            WrapLayout(spacing: 6) {
                ForEach(c.buttons, id: \.id) { b in
                    SmallButton(b.label, primary: b.primary) { press(b.id, b.needsSelection) }
                }
                if c.over && isOwner { SmallButton("لعبة جديدة", primary: true) { conn.send("start") } }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            Text(trSpoken(c.select && !selected.isEmpty ? "محدد \(selected.count)" : " ")).font(.system(size: 12)).foregroundColor(Palette.goldSoft).accessibilityHidden(true)
            // أوراقك: كل ورقة مربوطة بمكانها في اليد (مثل البلوت) فالمؤشر ما يقفز بعد ما تلعب
            WrapLayout(spacing: 4) {
                ForEach(c.hand.enumerated().map { CardsSlot(id: $0.offset, h: $0.element) }) { slot in
                    let h = slot.h
                    let sel = selected.contains(h.face.id)
                    Button {
                        if c.select { if sel { selected.remove(h.face.id) } else { selected.insert(h.face.id) }; Announcer.announceNow(sel ? "شلت التحديد" : "محددة") }
                        else if !c.myTurn { Announcer.announceNow("ليس دورك") }
                        else if !h.legal { Sounds.shared.illegal() }
                        else { if UIAccessibility.isVoiceOverRunning { playedPos = slot.id }; send(["op": "card", "id": h.face.id]) }
                    } label: {
                        CardsFace(c: h.face, w: 40, h: 58, dim: c.myTurn && !c.select && !h.legal)
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(sel ? Palette.gold : (h.legal && !c.select ? Palette.gold.opacity(0.6) : .clear), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spokenText(h.label + (sel ? "، محددة" : "")))
                    .accessibilityFocused($slotFocus, equals: slot.id)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .top)
        }
        .onChange(of: c.hand.count) { n in
            guard let p = playedPos else { return }
            playedPos = nil
            if p >= n && n > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { slotFocus = n - 1 } }
            let ids = Set(c.hand.map { $0.face.id })
            selected = selected.filter { ids.contains($0) }
        }
        // أصوات الحركات (توزيع، ورقة، أكلة، سحب، تنزيل…): مرة لكل حركة، وأول ما تفتح الطاولة ما نشغل القديم
        .onChange(of: c.fxN) { _ in
            let won: Bool? = c.fxWin.flatMap { w in v.mySeat.flatMap { $0 >= 0 ? w.contains($0) : nil } }
            Sounds.shared.cardsFx(c.fxKeys, won: won)
        }
        // جاك الدور: نغمة الدور، وVoiceOver يقول وش المطلوب
        .onChange(of: c.myTurn) { mine in
            guard mine else { return }
            Sounds.shared.turn(soft: Announcer.readerOn)
            if !c.prompt.isEmpty && UIAccessibility.isVoiceOverRunning {
                let p = c.prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Announcer.announce(p) }
            }
        }
        .onAppear { Gestures.shared.set("cards") { read($0) } }
        .onDisappear { Gestures.shared.clear("cards") }
    }
}
