import SwiftUI

// ألعاب الورق الجديدة (طرنيب، تريكس، كنكان، شايب): الخادم يرسل لكل لاعب «وش يشوف» بس —
// أوراقه وأزرار حركاته المسموحة ونصوص قارئ الشاشة — والتطبيق يرسم ويرسل الحركة كما هي.

struct CardFace: Hashable {
    let id: Int, r: String, s: String
    init(_ o: JSON?) { id = o?.int("id") ?? 0; r = o?.str("r") ?? ""; s = o?.str("s") ?? "" }
    var red: Bool { s == "H" || s == "D" }
    var joker: Bool { r == "JK" }
    var symbol: String { ["S": "♠", "H": "♥", "D": "♦", "C": "♣"][s] ?? "" }
    var short: String { joker ? "★" : r }
}

struct CardsView {
    struct Seat { let seat: Int, name: String, count: Int, note: String, turn: Bool }
    struct Pile { let id: String, title: String, text: String, cards: [CardFace] }
    struct HandCard { let face: CardFace, label: String, legal: Bool }
    struct Button { let id: String, label: String, primary: Bool, needsSelection: Bool }

    let game: String
    let over: Bool
    let myTurn: Bool
    let prompt: String
    let status: String
    let scores: [(String, Int)]
    let seats: [Seat]
    let center: [(Int, CardFace)]
    let piles: [Pile]
    let hand: [HandCard]
    let select: Bool
    let buttons: [Button]
    let readUp: String, readDown: String, readLeft: String, readRight: String

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
        center = u.objs("center").map { ($0.int("seat"), CardFace($0.obj("card"))) }
        piles = u.objs("piles").map { p in Pile(id: p.str("id"), title: p.str("title"), text: p.str("text"), cards: p.objs("cards").map { CardFace($0) }) }
        hand = u.objs("hand").map { HandCard(face: CardFace($0), label: $0.str("label"), legal: $0.bool("legal")) }
        select = u.bool("select")
        buttons = u.objs("buttons").map { Button(id: $0.str("id"), label: $0.str("label"), primary: $0.bool("primary"), needsSelection: $0.bool("needsSelection")) }
        readUp = reads.str("up"); readDown = reads.str("down"); readLeft = reads.str("left"); readRight = reads.str("right")
    }
}

/// ورقة مرسومة: رقمها ونوعها (الأحمر للهاص والديمن)، والجوكر نجمة
struct CardsFace: View {
    let c: CardFace
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
            // اللاعبين
            HStack(spacing: 6) {
                ForEach(c.seats, id: \.seat) { s in
                    let me = s.seat == v.mySeat
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            Text(trSpoken(me ? "أنت" : s.name)).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.text).lineLimit(1)
                            TurnClock(v: v, seat: s.seat, turn: s.turn)
                        }
                        Text(verbatim: "🂠 \(s.count)").font(.system(size: 12)).foregroundColor(Palette.textDim)
                        Text(trSpoken(s.note.isEmpty ? " " : s.note)).font(.system(size: 11)).foregroundColor(Palette.goldSoft).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58).padding(4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.13)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenText("\(me ? "أنت" : s.name)، \(s.count) \(s.count == 1 ? "ورقة" : "أوراق")\(s.note.isEmpty ? "" : "، \(s.note)")"))
                }
            }
            // الأرض: الأكلة الحالية (أو آخر المكب في الكنكان) — مكان ثابت
            HStack(spacing: 6) {
                ForEach(Array(c.center.enumerated()), id: \.offset) { _, p in
                    VStack(spacing: 1) {
                        CardsFace(c: p.1, w: 46, h: 66)
                        Text(trSpoken(p.0 < 0 ? "المكب" : c.seats.first { $0.seat == p.0 }?.name ?? "")).font(.system(size: 10)).foregroundColor(Palette.textDim).lineLimit(1).frame(width: 56)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.06, green: 0.23, blue: 0.16)))
            .accessibilityElement(children: .ignore).accessibilityLabel(spokenText(c.readLeft))
            // المجموعات: تنزيلات الكنكان، صفوف التركس (تنضغط في الكنكان للصق المحدد عليها)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(c.piles, id: \.id) { p in
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
