import SwiftUI

// الدومينو والجاكارو واللودو على طاولة مجلسك (نفس فكرة النسخة السابقة):
// الحالة والحركات المسموحة ونصوصها من الخادم، والتطبيق يرسم اللوحة ويعرض الأزرار ويرسل الحركة.
// لـ VoiceOver: كل قطعة/ورقة/خيار زر بنص واضح، ولمس اللوحة في نص الشاشة ما يقرأ شي (القراءة بالإيماءات)، وحركات الجميع يعلنها الخادم.
// الإيماءات: سحب بثلاث أصابع، ولكل لعبة اتجاهاتها (تحت عند كل لوحة).

/// حجم لوحة اللودو والجاكارو: يتكيّف مع طول شاشة الجوال (من الصغير مثل SE للكبير)،
/// فتكفي الطاولة كلها صفحة وحدة بلا تمرير
private func boardSide(_ full: CGFloat) -> CGFloat {
    min(full, max(170, UIScreen.main.bounds.height - 550))
}
/// قطع الدومينو على الطاولة: أصغر شوي في الجوالات القصيرة
private var dominoUnit: CGFloat { UIScreen.main.bounds.height < 740 ? 15 : 18 }

/// في الآيفون فوق/تحت يوصلان من VoiceOver مقلوبين في ألعاب اللوحة (الدومينو والجاكارو واللودو)
/// مقارنة بالبلوت، فنعدّلهما هنا لتطابق الاتجاهات المكتوبة (من فوق لتحت، ومن تحت لفوق)
private func flipVertical(_ d: SwipeDir) -> SwipeDir {
    switch d { case .up: return .down; case .down: return .up; default: return d }
}

private func seatNames(_ v: TableView) -> [String] { (0..<4).map { v.seat($0)?.username ?? "المقعد \($0 + 1)" } }

/// مربع نقاط (مثل البلوت)
private struct ScoreTile: View {
    let label: String, value: String, mine: Bool
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 14)).foregroundColor(Palette.textDim).multilineTextAlignment(.center)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundColor(Palette.gold)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(mine ? Palette.gold : Palette.green700, lineWidth: 1))
    }
}

/// سطر لاعب: إطار ذهبي على من عليه الدور، ونقطة بلونه
private struct PlayerLine: View {
    let text: String, turn: Bool
    var color: Color? = nil
    var spoken: String? = nil
    /// نرد صغير بآخر رمية (لودو)
    var roll: Int? = nil
    /// الصورة الشخصية: (uid، الاسم)
    var avatar: (String?, String)? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let color { Circle().fill(color).frame(width: 12, height: 12) }
            if let avatar { Avatar(uid: avatar.0, name: avatar.1, size: 30) }
            Text(text).font(.system(size: 15, weight: turn ? .bold : .regular)).foregroundColor(Palette.text)
            Spacer(minLength: 0)
            if let roll { DiceView(value: roll, color: color ?? Palette.gold, size: 26) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(turn ? Palette.gold.opacity(0.08) : .clear).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(turn ? Palette.gold : .clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
    }
}

/// صف يلتف (للقطع والأوراق)
private struct Wrap<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell
    var body: some View {
        if #available(iOS 16.0, *) {
            WrapLayout(spacing: spacing) { ForEach(items) { cell($0) } }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: spacing)], spacing: spacing) { ForEach(items) { cell($0) } }
        }
    }
}

@available(iOS 16.0, *)
private struct WrapLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // نوزّع كل سطر في المنتصف
        var rows: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > bounds.width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((v, s)); x += s.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let w = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(row.count - 1, 0))
            let h = row.map(\.1.height).max() ?? 0
            // من اليمين لليسار
            var cx = bounds.maxX - (bounds.width - w) / 2
            for (v, s) in row {
                cx -= s.width
                v.place(at: CGPoint(x: cx, y: y + (h - s.height) / 2), proposal: ProposedViewSize(s))
                cx -= spacing
            }
            y += h + spacing
        }
    }
}

// ═════════════ الدومينو ═════════════

private let PIPS: [Int: [(CGFloat, CGFloat)]] = [
    0: [], 1: [(0.5, 0.5)], 2: [(0.25, 0.25), (0.75, 0.75)], 3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
    6: [(0.25, 0.2), (0.75, 0.2), (0.25, 0.5), (0.75, 0.5), (0.25, 0.8), (0.75, 0.8)],
]

/// قطعة دومينو للعين: عمودية (a فوق) أو أفقية (a يمين)
private struct DominoTileView: View {
    let t: Tile
    let vertical: Bool
    var unit: CGFloat = 22
    var dim = false
    var body: some View {
        let w = vertical ? unit : unit * 2, h = vertical ? unit * 2 : unit
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.18
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
            ctx.fill(rect, with: .color(dim ? Color(red: 0.81, green: 0.79, blue: 0.73) : Color(red: 0.98, green: 0.97, blue: 0.93)))
            ctx.stroke(rect, with: .color(Color(red: 0.62, green: 0.6, blue: 0.53)), lineWidth: 1)
            var line = Path()
            if vertical { line.move(to: CGPoint(x: size.width * 0.12, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width * 0.88, y: size.height / 2)) }
            else { line.move(to: CGPoint(x: size.width / 2, y: size.height * 0.12)); line.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.88)) }
            ctx.stroke(line, with: .color(Color(white: 0.2)), lineWidth: 1.5)
            let half = vertical ? CGSize(width: size.width, height: size.height / 2) : CGSize(width: size.width / 2, height: size.height)
            let pr = min(half.width, half.height) * 0.1
            func pips(_ n: Int, _ o: CGPoint) {
                for (x, y) in PIPS[n] ?? [] {
                    let c = CGPoint(x: o.x + x * half.width, y: o.y + y * half.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)), with: .color(Color(white: 0.1)))
                }
            }
            if vertical { pips(t.a, .zero); pips(t.b, CGPoint(x: 0, y: half.height)) }
            else { pips(t.a, CGPoint(x: half.width, y: 0)); pips(t.b, .zero) }
        }
        .frame(width: w, height: h)
        .accessibilityHidden(true)
    }
}

/// نعرض القطعة بحيث يلاصق رقمها المطابق جارتها في الخط (نفس النسخة السابقة)
private func orient(_ p: PlacedTile) -> Tile {
    if p.side == "first" { return p.tile }
    let inner = p.tile.a == p.outer ? p.tile.b : p.tile.a
    return p.side == "right" ? Tile(a: inner, b: p.outer) : Tile(a: p.outer, b: inner)
}

private struct LineItem: Identifiable { let id: Int; let p: PlacedTile }

/// نص الدور في الدومينو: "دورك" أو "دور فلان"
private func dominoTurnText(_ v: TableView, _ d: DominoView) -> String {
    if d.phase == "chooseStarter" {
        if d.chooser == v.mySeat { return "دورك: اختر من يبدأ، أنت أو شريكك" }
        let names = seatNames(v)
        return "\(names[min(d.chooser ?? 0, 3)]) يختار من يبدأ"
    }
    if d.phase == "matchOver" { return "انتهت المباراة" }
    if d.phase != "playing" { return "انتهت الصكة، الصكة التالية بعد لحظات" }
    if d.turn == v.mySeat { return "دورك" }
    let names = seatNames(v)
    return "دور \(d.turn < names.count ? names[d.turn] : "")"
}

/// جلا (تمرير): لما ما عندك قطعة تصلح
private func dominoJala(_ conn: TableConnection, _ d: DominoView) {
    if !d.myTurn { Announcer.announceNow("ليس دورك") }
    else if d.canPass { conn.send(["type": "domino", "action": ["type": "pass"]]) }
    else if d.canDraw { Announcer.announceNow("ما تقدر تجلي، اسحب من البنك") }
    else { Announcer.announceNow("ما تقدر تجلي، عندك قطعة تصلح") }
}

/// أعلى طاولة الدومينو: النقاط، اللاعبون، وخط اللعب.
/// سحب بثلاث أصابع: من اليمين لليسار = الطرفان، من تحت لفوق = الدور عند مين، من اليسار لليمين = سجل الجولات، من فوق لتحت = جلا
struct DominoBoard: View {
    let v: TableView
    let d: DominoView
    let conn: TableConnection
    let isOwner: Bool
    let openLog: () -> Void

    var body: some View {
        let names = seatNames(v)
        let mySeat = v.mySeat
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(d.scores.enumerated()), id: \.offset) { side, n in
                    ScoreTile(label: side < d.sideNames.count ? d.sideNames[side] : "", value: "\(n)", mine: side == d.mySide)
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(d.scoreText)
            ForEach(0..<min(d.players, 4), id: \.self) { seat in
                if seat != mySeat {
                    let partner = mySeat != nil && d.players == 4 && seat == (mySeat! + 2) % 4
                    PlayerLine(text: "\(names[seat])\(partner ? " (شريكك)" : "")، \(seat < d.handCounts.count ? d.handCounts[seat] : 0) قطع",
                               turn: d.turn == seat && d.phase == "playing", avatar: (v.seatUid(seat), names[seat]))
                }
            }
            // الطاولة: للعين فقط، لمسها ما يقرأ شي (الطرفان بالإيماءة)
            Group {
                Group {
                    if d.line.isEmpty { Text("الطاولة فارغة").foregroundColor(Palette.textDim).frame(maxWidth: .infinity) }
                    else {
                        Wrap(items: d.line.enumerated().map { LineItem(id: $0.offset, p: $0.element) }, spacing: 3) { item in
                            DominoTileView(t: orient(item.p), vertical: item.p.tile.isDouble, unit: dominoUnit)
                        }
                    }
                }
                .padding(10).frame(maxWidth: .infinity)
                .background(Color(red: 0.08, green: 0.31, blue: 0.21)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.gold.opacity(0.33), lineWidth: 1))
            }
            .accessibilityHidden(true)
            if let e = d.ends {
                Text("يمين \(e.right) — يسار \(e.left)\(d.boneyard > 0 ? " — في البنك \(d.boneyard)" : "")")
                    .foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            if d.phase != "playing" {
                Text(dominoTurnText(v, d))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity)
            }
            if d.phase == "matchOver" && isOwner { MButton("مباراة جديدة", .primary) { conn.send("start") } }
            if mySeat == nil { Note("أنت تشاهد هذه الطاولة.") }
        }
        .onAppear { Gestures.shared.handler = { read($0) } }
    }

    private func read(_ raw: SwipeDir) -> Bool {
        let dir = flipVertical(raw)
        // آخر حالة وصلت وقت الإيماءة نفسها
        let cur = conn.view?.domino ?? d
        let view = conn.view ?? v
        switch dir {
        case .left: Announcer.announceNow(cur.endsText)
        case .up: Announcer.announceNow(dominoTurnText(view, cur))
        case .right: openLog()
        case .down: dominoJala(conn, cur)
        }
        return true
    }
}

/// قطعك في أسفل الشاشة فوق الميكروفون، ومعها زر جلا (وسحب من البنك إن وجد)
struct DominoHand: View {
    let v: TableView
    let d: DominoView
    let conn: TableConnection
    @State private var chooseSide: DominoHandTile?

    private func act(_ a: JSON) { conn.send(["type": "domino", "action": a]) }

    var body: some View {
        if v.mySeat != nil {
            VStack(spacing: 8) {
                // فاز فريقك بالصكة: تختار من يبدأ (أنت أو شريكك)
                if !d.starterOptions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(d.starterOptions.enumerated()), id: \.offset) { _, o in
                            MButton(o.text, .primary) { act(["type": "starter", "starter": o.seat]) }
                        }
                    }
                }
                if d.myTurn && (d.canDraw || d.canPass) {
                    HStack(spacing: 8) {
                        if d.canDraw { MButton("سحب من البنك", .primary) { act(["type": "draw"]) } }
                        if d.canPass { MButton("جلا", .primary) { dominoJala(conn, d) } }
                    }
                }
                Text("قطعك").font(.system(size: 1)).foregroundColor(.clear).accessibilityAddTraits(.isHeader)
                Wrap(items: d.hand, spacing: 8) { h in
                    Button {
                        if !d.myTurn { Announcer.announceNow("ليس دورك") }
                        else if !h.legal { Announcer.announceNow(h.label) }
                        else if h.askSide { chooseSide = h }
                        else { act(["type": "play", "tile": h.tile.json]) }
                    } label: {
                        DominoTileView(t: h.tile, vertical: true, unit: 24, dim: d.myTurn && !h.legal)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(h.legal ? Palette.gold : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(h.label)
                }
            }
            .sheet(item: $chooseSide) { h in
                Sheet(title: "أين تلعب القطعة؟") {
                    if let e = d.ends {
                        MButton("اليمين (على \(e.right))", .primary) { chooseSide = nil; act(["type": "play", "tile": h.tile.json, "side": "right"]) }
                        MButton("اليسار (على \(e.left))", .primary) { chooseSide = nil; act(["type": "play", "tile": h.tile.json, "side": "left"]) }
                    }
                    MButton("إلغاء") { chooseSide = nil }
                }
            }
        }
    }
}

/// سجل الدومينو: حركات كل جولة بالترتيب، تتنقل بين الجولات (يبدأ من الجولة الحالية)
struct DominoLogView: View {
    let d: DominoView
    let close: () -> Void
    @State private var page: Int

    init(d: DominoView, close: @escaping () -> Void) {
        self.d = d; self.close = close
        _page = State(initialValue: max(d.log.count - 1, 0))
    }

    var body: some View {
        let entry = page < d.log.count ? d.log[page] : nil
        let current = page == d.log.count - 1
        Sheet(title: entry.map { "سجل الجولة \($0.hand)\(current ? " (الحالية)" : "")" } ?? "السجل") {
            let lines = entry?.lines ?? []
            if lines.isEmpty { Note(entry == nil ? "ما فيه حركات بعد." : "ما انلعبت حجار في هذه الجولة بعد.") }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 16)).foregroundColor(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                if page > 0 { MButton("الجولة السابقة") { page -= 1 } }
                if page < d.log.count - 1 { MButton("الجولة التالية") { page += 1 } }
            }
            MButton("إغلاق", .primary, action: close)
        }
    }
}

// ═════════════ الجاكارو ═════════════

private let JK_COLORS: [Color] = [Color(red: 0.83, green: 0.69, blue: 0.22), Color(red: 0.75, green: 0.22, blue: 0.17), Color(red: 0.18, green: 0.53, blue: 0.87), Color(red: 0.15, green: 0.68, blue: 0.38)]
private let JK_COLOR_NAMES = ["الذهبي", "الأحمر", "الأزرق", "الأخضر"]

struct JackarooBoard: View {
    let v: TableView
    let j: JackarooView
    let conn: TableConnection
    let isOwner: Bool
    @State private var picked: JackarooHandCard?
    /// أماكن الأحجار: تفتح بسحبة من فوق لتحت
    @State private var posOpen = false

    private func act(_ a: JSON) { conn.send(["type": "jackaroo", "action": a]) }
    private func short(_ label: String) -> String { label.components(separatedBy: "،").first ?? label }

    var body: some View {
        let names = seatNames(v)
        let mySeat = v.mySeat
        let myTeam = (mySeat ?? 0) % 2
        let usLabel = mySeat == nil ? "فريق \(names[0])" : "فريقك"
        let themLabel = mySeat == nil ? "فريق \(names[1])" : "الخصم"
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ScoreTile(label: usLabel, value: "\(j.safeCount(myTeam))/8", mine: true)
                ScoreTile(label: themLabel, value: "\(j.safeCount(1 - myTeam))/8", mine: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("في منطقة الأمان: \(usLabel) \(j.safeCount(myTeam)) من 8، \(themLabel) \(j.safeCount(1 - myTeam)) من 8")
            // اللوحة: للعين فقط، لمسها ما يقرأ شي (أماكن الأحجار بالإيماءات)
            Group {
                ZStack {
                    Canvas { ctx, size in drawJackaroo(ctx, size, j, mySeat ?? 0) }
                    // أوراق اللفة الحالية في وسط الطاولة (تنمسح مع كل لفة جديدة)
                    HStack(spacing: -10) {
                        ForEach(Array(j.centerCards.enumerated()), id: \.offset) { i, c in
                            Text("\(c.rank)\(c.symbol)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(c.red ? Color(red: 0.78, green: 0.16, blue: 0.16) : Color(white: 0.1))
                                .frame(width: 40, height: 58)
                                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.73, green: 0.71, blue: 0.65), lineWidth: 1))
                                .rotationEffect(.degrees(Double(i) * 8 - Double(j.centerCards.count - 1) * 4))
                        }
                    }
                    .accessibilityHidden(true)
                }
                .aspectRatio(1, contentMode: .fit).frame(maxWidth: boardSide(340))
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            // اللاعبون: كل اثنين في صف، فتكفي الطاولة صفحة وحدة
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(0..<4, id: \.self) { seat in
                let partner = mySeat != nil && seat == (mySeat! + 2) % 4
                let n = names[seat]
                let cards = seat < j.handCounts.count ? j.handCounts[seat] : 0
                PlayerLine(text: "\(seat == mySeat ? "\(n) (أنت)" : n)\(partner ? " (شريكك)" : "")، \(cards) أوراق",
                           turn: j.turn == seat && j.phase == "playing", color: JK_COLORS[seat],
                           spoken: "\(seat == mySeat ? "أنت" : n)\(partner ? "، شريكك" : "")، \(JK_COLOR_NAMES[seat])، \(cards) أوراق", avatar: (v.seatUid(seat), n))
            }
            }
            if j.phase == "over" {
                let w = j.winnerTeam ?? 0
                Text(mySeat == nil ? "فاز فريق \(names[w]) و\(names[w + 2])" : w == myTeam ? "🎉 فاز فريقك!" : "فاز الفريق الآخر")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity)
                if isOwner { MButton("لعبة جديدة", .primary) { conn.send("start") } }
            }
            if mySeat != nil {
                Text("أوراقك\(j.burning ? "، اختر ورقة لحرقها" : "")").font(.system(size: 1)).foregroundColor(.clear).accessibilityAddTraits(.isHeader)
                if j.burning { Text("لا لعب صالح: اختر ورقة لحرقها").foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity).accessibilityHidden(true) }
                Wrap(items: j.hand, spacing: 8) { h in
                    Button {
                        if !j.myTurn { Announcer.announceNow("ليس دورك") }
                        else if j.burning { act(["type": "burn", "card": h.card.json]) }
                        else if h.moves.isEmpty { Announcer.announceNow("\(short(h.label)) لا تصلح الآن") }
                        else if h.moves.count == 1 { act(["type": "play", "card": h.card.json, "move": h.moves[0].move]) }
                        else { picked = h }
                    } label: {
                        Text("\(h.card.rank)\(h.card.symbol)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(h.card.red ? Color(red: 0.78, green: 0.16, blue: 0.16) : Color(white: 0.1))
                            .frame(width: 58, height: 84)
                            .background(j.myTurn && !h.usable ? Color(red: 0.81, green: 0.79, blue: 0.73) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(h.usable ? Palette.gold : Color(red: 0.73, green: 0.71, blue: 0.65), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(h.label)
                }
            } else { Note("أنت تشاهد هذه الطاولة.") }
        }
        .onAppear { Gestures.shared.handler = { read($0) } }
        .sheet(isPresented: $posOpen) {
            let cur = conn.view?.jackaroo ?? j
            let me = (conn.view ?? v).mySeat
            Sheet(title: "أماكن الأحجار") {
                ForEach(Array(jackarooPositions(cur, mySeat: me).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 8) {
                        Circle().fill(p.color < JK_COLORS.count ? JK_COLORS[p.color] : Palette.gold).frame(width: 12, height: 12)
                        Text("\(p.title)، \(p.color < JK_COLOR_NAMES.count ? JK_COLOR_NAMES[p.color] : "")").bold().foregroundColor(Palette.goldSoft)
                    }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    ForEach(Array(p.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 16)).foregroundColor(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                MButton("إغلاق", .primary) { posOpen = false }
            }
        }
        .sheet(item: $picked) { h in
            Sheet(title: "\(short(h.label)): اختر الحركة") {
                ForEach(h.moves) { m in
                    MButton(m.text, .primary) { picked = nil; act(["type": "play", "card": h.card.json, "move": m.move]) }
                }
                MButton("إلغاء") { picked = nil }
            }
        }
    }

    /// سحب بثلاث أصابع: من اليمين لليسار = اللوحة كاملة، من اليسار لليمين = أحجارك،
    /// من تحت لفوق = الدور عند مين، من فوق لتحت = قائمة أماكن الأحجار (أحجارك أولاً ثم كل لاعب)
    private func read(_ raw: SwipeDir) -> Bool {
        let dir = flipVertical(raw)
        let cur = conn.view?.jackaroo ?? j
        switch dir {
        case .left: Announcer.announceNow(cur.boardText)
        case .right: Announcer.announceNow(cur.mineText)
        case .up: Announcer.announceNow(jackarooTurnText(conn.view ?? v, cur))
        case .down: posOpen = true
        }
        return true
    }
}

/// الدور عند مين في الجاكارو
func jackarooTurnText(_ v: TableView, _ j: JackarooView) -> String {
    let names = seatNames(v)
    if j.phase == "over" {
        let w = j.winnerTeam ?? 0
        if let me = v.mySeat { return w == me % 2 ? "انتهت اللعبة، فاز فريقك" : "انتهت اللعبة، فاز الفريق الآخر" }
        return "انتهت اللعبة، فاز فريق \(names[w]) و\(names[w + 2])"
    }
    if j.turn == v.mySeat { return j.burning ? "دورك، ما عندك لعب صالح، احرق ورقة" : "دورك" }
    return "الدور عند \(j.turn < names.count ? names[j.turn] : "")"
}

/// "أحجار فلان: 1 في البيت، 2 على المسار، باقي له…" → العنوان وسطر لكل حجر
/// (الفاصل بين الأحجار فاصلة بعدها رقم الحجر، لأن وصف المكان نفسه فيه فواصل)
private func splitMarbles(_ text: String) -> (title: String, lines: [String]) {
    guard let colon = text.range(of: ": ") else { return (text, []) }
    let title = String(text[..<colon.lowerBound])
    let body = String(text[colon.upperBound...])
    var lines: [String] = [], cur = ""
    let chars = Array(body)
    var i = 0
    while i < chars.count {
        if chars[i] == "،", i + 2 < chars.count, chars[i + 1] == " ", chars[i + 2].isNumber, !cur.isEmpty {
            lines.append("حجر \(cur)"); cur = ""; i += 2; continue
        }
        cur.append(chars[i]); i += 1
    }
    if !cur.isEmpty { lines.append("حجر \(cur)") }
    return (title, lines)
}

/// أماكن الأحجار: أحجارك أولاً (أو أحجار شريكك لو تلعب بها)، ثم باقي اللاعبين بترتيب اللعب
func jackarooPositions(_ j: JackarooView, mySeat: Int?) -> [(title: String, color: Int, lines: [String])] {
    let all = j.boardText.components(separatedBy: ". ")
    var out: [(title: String, color: Int, lines: [String])] = []
    let start = mySeat ?? 0
    if let me = mySeat {
        let m = splitMarbles(j.mineText)
        // تلعب بأحجار شريكك بعد ما خلصت أحجارك
        out.append((m.title, m.title.hasPrefix("أحجارك") ? me : (me + 2) % 4, m.lines))
    }
    for k in 0..<4 {
        let seat = (start + k) % 4
        if seat == mySeat || seat >= all.count { continue }
        let p = splitMarbles(all[seat])
        out.append((p.title, seat, p.lines))
    }
    return out
}

/// رسم لوحة الجاكارو (نفس رسم النسخة السابقة): المسار دائرة، ولكل لاعب قاعدة ومنطقة أمان وبيت
private func drawJackaroo(_ ctx: GraphicsContext, _ size: CGSize, _ j: JackarooView, _ bottom: Int) {
    let k = min(size.width, size.height) / 320
    let L = j.segment * 4
    let c: CGFloat = 160, R: CGFloat = 130
    func start(_ o: Int) -> Int { o * j.segment }
    let base = start(bottom)
    func at(_ pos: CGFloat, _ r: CGFloat = R) -> CGPoint {
        let a = Double.pi / 2 + 2 * Double.pi * Double(pos - CGFloat(base)) / Double(L)
        return CGPoint(x: (c + r * CGFloat(cos(a))) * k, y: (c + r * CGFloat(sin(a))) * k)
    }
    func dot(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
    ctx.fill(dot(CGPoint(x: c * k, y: c * k), (R + 30) * k), with: .color(Color(red: 0.04, green: 0.14, blue: 0.11)))
    ctx.stroke(dot(CGPoint(x: c * k, y: c * k), (R + 30) * k), with: .color(Palette.gold.opacity(0.2)), lineWidth: 1)
    for p in 0..<L {
        let owner = (0...3).first { start($0) == p }
        ctx.fill(dot(at(CGFloat(p)), (owner != nil ? 6 : 3.5) * k), with: .color(owner.map { JK_COLORS[$0] } ?? Color.white.opacity(0.2)))
        // رقم الخانة (ثابت للجميع، نفس الرقم اللي ينقال في الإعلان) داخل الدائرة جنب كل نقطة
        ctx.draw(Text("\(p)").font(.system(size: 6.5 * k, weight: .semibold)).foregroundColor(Color.white.opacity(0.75)), at: at(CGFloat(p), R - 12))
    }
    for o in 0...3 {
        for s in 0..<4 { ctx.stroke(dot(at(CGFloat(start(o) - 1), R - 16 - CGFloat(s) * 14), 5 * k), with: .color(JK_COLORS[o]), lineWidth: 1.5 * k) }
        let row = o < j.marbles.count ? j.marbles[o] : []
        for (i, m) in row.enumerated() {
            let p: CGPoint
            switch m.zone {
            case "track": p = at(CGFloat(m.pos))
            case "safe": p = at(CGFloat(start(o) - 1), R - 16 - CGFloat(m.pos) * 14)
            default: p = at(CGFloat(start(o)) + 3 + CGFloat(i) * 1.6, R + 18)
            }
            ctx.fill(dot(p, 7 * k), with: .color(JK_COLORS[o].opacity(m.zone == "home" ? 0.55 : 1)))
            ctx.stroke(dot(p, 7 * k), with: .color(Color.black.opacity(0.67)), lineWidth: 1.5 * k)
        }
    }
}

// ═════════════ لودو ═════════════

// ترتيب الألوان مع ترتيب اللعب: أحمر ← أزرق ← أصفر ← أخضر (الفرق: أحمر+أصفر ضد أزرق+أخضر)
private let LUDO_COLORS: [Color] = [Color(red: 0.85, green: 0.27, blue: 0.23), Color(red: 0.18, green: 0.5, blue: 0.85), Color(red: 0.9, green: 0.71, blue: 0.13), Color(red: 0.18, green: 0.65, blue: 0.38)]
private let LUDO_COLOR_NAMES = ["الأحمر", "الأزرق", "الأصفر", "الأخضر"]

struct LudoBoard: View {
    let v: TableView
    let l: LudoView
    let conn: TableConnection
    let isOwner: Bool
    /// آخر رمية لكل لاعب (نرد صغير جنب اسمه)، نتذكرها من الحالات اللي توصل
    @State private var rolls: [Int: Int] = [:]
    @State private var rollTicks: [Int: Int] = [:]
    @State private var prevPhase: String?
    @State private var prevTurn: Int?
    @State private var prevLast: String?
    /// السجل: يفتح بسحبة إصبعين من فوق لتحت (بدون زر)
    @State private var logOpen = false

    private func act(_ a: JSON) { conn.send(["type": "ludo", "action": a]) }

    /// زاوية لون اللاعب بعد تدوير اللوحة: (فوق؟، يسار؟)
    private func corner(_ o: Int, _ mySeat: Int?) -> (top: Bool, left: Bool) {
        let turns = (3 - (mySeat ?? 0) + 4) % 4
        var p: (CGFloat, CGFloat) = (YARDS[o].0 + 2.5, YARDS[o].1 + 2.5)
        for _ in 0..<turns { p = (p.1, 14 - p.0) }
        return (p.0 < 7, p.1 < 7)
    }

    /// عند كل لون: صورة اللاعب الدائرية واسمه، وجنبها النرد بآخر رقم رماه (يتدحرج أول ما يرمي)
    @ViewBuilder private func label(_ o: Int, names: [String], mySeat: Int?, partner: Int) -> some View {
        let n = o < names.count ? names[o] : ""
        let turn = l.turn == o && l.phase != "over"
        let left = corner(o, mySeat).left
        let dice = DiceView(value: rolls[o], color: LUDO_COLORS[o], size: 40)
            .rotationEffect(.degrees(Double(rollTicks[o] ?? 0) * 360))
            .animation(.easeOut(duration: 0.45), value: rollTicks[o] ?? 0)
        HStack(spacing: 8) {
            // النرد جهة اللوحة: لاعب اليسار نرده يمين صورته، ولاعب اليمين يسارها
            if !left { dice }
            VStack(spacing: 2) {
                Avatar(uid: v.seatUid(o), name: n, size: 52)
                    .padding(3)
                    .overlay(Circle().stroke(turn ? Palette.gold : LUDO_COLORS[o], lineWidth: 3))
                Text("\(n)\(o == mySeat ? " (أنت)" : l.teams && o == partner ? " (شريكك)" : "")")
                    .font(.system(size: 13, weight: turn ? .bold : .regular)).foregroundColor(Palette.text).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("وصل \(l.home(o))/4").font(.system(size: 11)).foregroundColor(Palette.textDim)
            }
            if left { dice }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o == mySeat ? "أنت" : n)\(l.teams && o == partner ? "، شريكك" : "")، \(LUDO_COLOR_NAMES[o])، وصل \(l.home(o)) من 4\(rolls[o].map { "، آخر رمية \($0)" } ?? "")\(turn ? "، عليه الدور" : "")")
    }

    @ViewBuilder private func cornerRow(top: Bool, names: [String], mySeat: Int?, partner: Int) -> some View {
        let here = l.seats.filter { corner($0, mySeat).top == top }
        if !here.isEmpty {
            HStack {
                if let o = here.first(where: { corner($0, mySeat).left }) { label(o, names: names, mySeat: mySeat, partner: partner) }
                Spacer(minLength: 4)
                if let o = here.first(where: { !corner($0, mySeat).left }) { label(o, names: names, mySeat: mySeat, partner: partner) }
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
        }
    }

    /// رمية جديدة: نحدّث نرد صاحبها ونزيد عدّاده فيتدحرج
    private func noteRoll() {
        if l.phase == "move", let d = l.dice, prevPhase != "move" || prevTurn != l.turn {
            rolls[l.turn] = d; rollTicks[l.turn, default: 0] += 1
        } else if let s = l.lastSeat, let r = l.lastRoll, l.lastSig != prevLast, prevPhase != "move", prevPhase != nil {
            rolls[s] = r; rollTicks[s, default: 0] += 1
        } else if let s = l.lastSeat, let r = l.lastRoll, rolls[s] == nil { rolls[s] = r }
        prevPhase = l.phase; prevTurn = l.turn; prevLast = l.lastSig
    }

    var body: some View {
        let names = seatNames(v)
        let mySeat = v.mySeat
        let partner = mySeat == nil ? -1 : (mySeat! + 2) % 4
        VStack(spacing: 10) {
            // اسم كل لاعب عند زاوية لونه في اللوحة، وجنبه نرد بآخر رقم جاه
            cornerRow(top: true, names: names, mySeat: mySeat, partner: partner)
            // اللوحة: للعين فقط، لمسها ما يقرأ شي (أماكن الأحجار بالإيماءات)
            Canvas { ctx, size in
                drawLudo(ctx, size, l, mySeat ?? 0, l.myTurn && l.phase == "move" ? l.options.map { (l.movableOwner, $0.token) } : [])
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: boardSide(360))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            cornerRow(top: false, names: names, mySeat: mySeat, partner: partner)
            if l.phase == "over" {
                let w = l.winner ?? 0
                let won = l.winner != nil && mySeat != nil && (l.teams ? l.winner == mySeat! % 2 : l.winner == mySeat)
                Text(won ? "🎉 فزت!" : l.teams ? "فاز فريق \(names[w]) و\(names[(w + 2) % 4])" : "فاز \(w < names.count ? names[w] : "")")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity)
                if isOwner { MButton("لعبة جديدة", .primary) { conn.send("start") } }
            } else {
                HStack(spacing: 12) {
                    DiceView(value: l.phase == "move" ? l.dice : l.lastRoll, color: l.turn < 4 ? LUDO_COLORS[l.turn] : Palette.gold)
                    if l.myTurn && l.phase == "roll" { MButton("ارمِ النرد", .primary, fill: false) { act(["type": "roll"]) } }
                    if !l.myTurn { Text("دور \(l.turn < names.count ? names[l.turn] : "")").foregroundColor(Palette.textDim).accessibilityHidden(true) }
                }
                .frame(maxWidth: .infinity)
            }
            if l.myTurn && l.phase == "move" && l.options.count > 1 {
                Text("رميت \(l.dice ?? 0): اختر الحجر").font(.system(size: 1)).foregroundColor(.clear).accessibilityAddTraits(.isHeader)
                ForEach(l.options) { o in MButton(o.text) { act(["type": "move", "token": o.token]) } }
            }
            if mySeat == nil { Note("أنت تشاهد هذه الطاولة.") }
        }
        .onAppear { Gestures.shared.handler = { read($0) }; noteRoll() }
        .onChange(of: l.moveSig) { _ in noteRoll() }
        .sheet(isPresented: $logOpen) {
            let cur = conn.view?.ludo ?? l
            // قائمة فيها كل لاعب وأحجاره في أي خانة، تتنقل فيها
            Sheet(title: "أماكن الأحجار") {
                ForEach(Array(cur.positions.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 8) {
                        Circle().fill(p.color < LUDO_COLORS.count ? LUDO_COLORS[p.color] : Palette.gold).frame(width: 12, height: 12)
                        Text("\(p.name)، \(p.color < LUDO_COLOR_NAMES.count ? LUDO_COLOR_NAMES[p.color] : "")").bold().foregroundColor(Palette.goldSoft)
                    }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    ForEach(Array(p.tokens.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 16)).foregroundColor(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                MButton("إغلاق", .primary) { logOpen = false }
            }
        }
    }

    /// سحب بثلاث أصابع: من فوق لتحت = أماكن الأحجار، من تحت لفوق = الدور عند مين،
    /// من اليمين لليسار = آخر رمية نرد، من اليسار لليمين = ترمي النرد مباشرة
    private func read(_ raw: SwipeDir) -> Bool {
        let dir = flipVertical(raw)
        let cur = conn.view?.ludo ?? l
        switch dir {
        case .down: logOpen = true
        case .up: Announcer.announceNow(cur.turnText)
        case .left: Announcer.announceNow(cur.diceText)
        case .right:
            if cur.canRoll { act(["type": "roll"]) }
            else { Announcer.announceNow(cur.myTurn ? "اختر الحجر أولاً" : cur.turnText) }
        }
        return true
    }
}

/// النرد: نقاط للعين، والرقم يُعلن صوتياً
private struct DiceView: View {
    let value: Int?
    let color: Color
    var size: CGFloat = 54
    var body: some View {
        let spots: [Int: [Int]] = [1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8]]
        Canvas { ctx, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5), cornerRadius: size.width * 0.19)
            ctx.fill(rect, with: .color(.white))
            ctx.stroke(rect, with: .color(color), lineWidth: max(1.5, size.width * 0.055))
            for i in value.flatMap({ spots[$0] }) ?? [] {
                let x = (CGFloat(i % 3) + 0.5) / 3 * size.width, y = (CGFloat(i / 3) + 0.5) / 3 * size.height
                let r = size.width * 0.08
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.1)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// رسم اللوحة (15×15) — نفس خانات النسخة السابقة
private typealias Cell = (CGFloat, CGFloat)
private let TRACK_CELLS: [Cell] = {
    var c: [Cell] = []
    for x in [1, 2, 3, 4, 5] { c.append((6, CGFloat(x))) }
    for x in [5, 4, 3, 2, 1, 0] { c.append((CGFloat(x), 6)) }
    c.append((0, 7))
    for x in [0, 1, 2, 3, 4, 5] { c.append((CGFloat(x), 8)) }
    for x in [9, 10, 11, 12, 13, 14] { c.append((6, CGFloat(x))) }
    c.append((7, 14))
    for x in [14, 13, 12, 11, 10, 9] { c.append((8, CGFloat(x))) }
    for x in [9, 10, 11, 12, 13, 14] { c.append((CGFloat(x), 8)) }
    c.append((14, 7))
    for x in [14, 13, 12, 11, 10, 9] { c.append((CGFloat(x), 6)) }
    for x in [5, 4, 3, 2, 1, 0] { c.append((8, CGFloat(x))) }
    c.append((7, 0)); c.append((6, 0))
    return c
}()
private let HOME_CELLS: [[Cell]] = [
    [1, 2, 3, 4, 5].map { (7, CGFloat($0)) },
    [1, 2, 3, 4, 5].map { (CGFloat($0), 7) },
    [13, 12, 11, 10, 9].map { (7, CGFloat($0)) },
    [13, 12, 11, 10, 9].map { (CGFloat($0), 7) },
]
private let YARDS: [Cell] = [(0, 0), (0, 9), (9, 9), (9, 0)]
private let YARD_SPOTS: [Cell] = [(1.5, 1.5), (1.5, 3.5), (3.5, 1.5), (3.5, 3.5)]
private let CENTER_SPOT: [Cell] = [(7, 6.25), (6.25, 7), (7, 7.75), (7.75, 7)]

private func drawLudo(_ ctx: GraphicsContext, _ size: CGSize, _ l: LudoView, _ bottom: Int, _ movable: [(Int, Int)]) {
    let U = min(size.width, size.height) / 15
    // ندير اللوحة حتى يكون بيت صاحب الجهاز أسفل اليسار
    let turns = (3 - bottom + 4) % 4
    func rot(_ cell: Cell) -> Cell { var p = cell; for _ in 0..<turns { p = (p.1, 14 - p.0) }; return p }
    func xy(_ cell: Cell) -> CGPoint { let (r, c) = rot(cell); return CGPoint(x: c * U + U / 2, y: r * U + U / 2) }
    func circle(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
    let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: CGSize(width: 15 * U, height: 15 * U)), cornerRadius: U * 0.6), with: .color(Color(red: 0.04, green: 0.14, blue: 0.11)))
    for (o, y) in YARDS.enumerated() {
        let a = rot(y), b = rot((y.0 + 5, y.1 + 5))
        let x0 = min(a.1, b.1) * U, y0 = min(a.0, b.0) * U
        ctx.fill(Path(roundedRect: CGRect(x: x0 + 1, y: y0 + 1, width: 6 * U - 2, height: 6 * U - 2), cornerRadius: U * 0.45),
                 with: .color(LUDO_COLORS[o].opacity(l.seats.contains(o) ? 0.9 : 0.25)))
        ctx.fill(Path(roundedRect: CGRect(x: x0 + U, y: y0 + U, width: 4 * U, height: 4 * U), cornerRadius: U * 0.35), with: .color(paper))
    }
    for (i, cell) in TRACK_CELLS.enumerated() {
        let p = xy(cell)
        let start = LudoView.STARTS.firstIndex(of: i)
        let r = CGRect(x: p.x - U / 2 + 0.5, y: p.y - U / 2 + 0.5, width: U - 1, height: U - 1)
        ctx.fill(Path(r), with: .color(start.map { LUDO_COLORS[$0] } ?? paper))
        ctx.stroke(Path(r), with: .color(Color(red: 0.05, green: 0.17, blue: 0.13).opacity(0.33)), lineWidth: 1)
        if LudoView.SAFE.contains(i) && start == nil { ctx.fill(starPath(p, U * 0.32), with: .color(Color(red: 0.05, green: 0.17, blue: 0.13).opacity(0.6))) }
        // رقم الخانة ثابت للجميع من 1 إلى 52 (نفس الأرقام اللي ينطقها الإعلان لكل اللاعبين)
        let num = i + 1
        ctx.draw(Text("\(num)").font(.system(size: U * 0.42, weight: .semibold))
            .foregroundColor(start != nil ? .white : Color(red: 0.05, green: 0.17, blue: 0.13).opacity(0.8)), at: p)
    }
    for (o, cells) in HOME_CELLS.enumerated() {
        for cell in cells { let p = xy(cell); ctx.fill(Path(CGRect(x: p.x - U / 2 + 0.5, y: p.y - U / 2 + 0.5, width: U - 1, height: U - 1)), with: .color(LUDO_COLORS[o])) }
    }
    // الوسط: أربعة مثلثات، كل مثلث بلون صاحبه جهة ممره
    let c0 = xy((6, 6)), c2 = xy((8, 8))
    let L = min(c0.x, c2.x) - U / 2, T = min(c0.y, c2.y) - U / 2, R = L + 3 * U, B = T + 3 * U
    let M = CGPoint(x: (L + R) / 2, y: (T + B) / 2)
    for o in 0...3 {
        let e = xy(HOME_CELLS[o][4])
        let pts: [CGPoint] = e.x < L ? [CGPoint(x: L, y: T), CGPoint(x: L, y: B)] : e.x > R ? [CGPoint(x: R, y: T), CGPoint(x: R, y: B)]
            : e.y < T ? [CGPoint(x: L, y: T), CGPoint(x: R, y: T)] : [CGPoint(x: L, y: B), CGPoint(x: R, y: B)]
        var path = Path(); path.move(to: pts[0]); path.addLine(to: pts[1]); path.addLine(to: M); path.closeSubpath()
        ctx.fill(path, with: .color(LUDO_COLORS[o]))
    }
    // الأحجار (أكثر من حجر في خانة: تُزاح قليلاً)
    var seen: [String: Int] = [:]
    for o in l.seats {
        let row = o < l.tokens.count ? l.tokens[o] : []
        for (i, p) in row.enumerated() {
            let cell: Cell
            if p == -1 { cell = (YARDS[o].0 + YARD_SPOTS[i].0 - 0.5, YARDS[o].1 + YARD_SPOTS[i].1 - 0.5) }
            else if p == LudoView.FINISH { cell = CENTER_SPOT[o] }
            // ممر المنزل 6 خانات: الخمس الملوّنة، والسادسة عند حافة الوسط
            else if p > LudoView.LAST_TRACK && p - LudoView.LAST_TRACK - 1 < 5 { cell = HOME_CELLS[o][p - LudoView.LAST_TRACK - 1] }
            else if p > LudoView.LAST_TRACK { cell = ((HOME_CELLS[o][4].0 + CENTER_SPOT[o].0) / 2, (HOME_CELLS[o][4].1 + CENTER_SPOT[o].1) / 2) }
            else { cell = TRACK_CELLS[LudoView.absPos(o, p)] }
            let pt = xy(cell)
            let key = "\(Int(pt.x)),\(Int(pt.y))"
            let n = seen[key] ?? 0
            seen[key] = n + 1
            let q = CGPoint(x: pt.x + CGFloat(n) * U * 0.18, y: pt.y - CGFloat(n) * U * 0.18)
            if movable.contains(where: { $0.0 == o && $0.1 == i }) { ctx.stroke(circle(q, U * 0.5), with: .color(Palette.gold), lineWidth: U * 0.14) }
            let r = p == LudoView.FINISH ? U * 0.23 : U * 0.36
            ctx.fill(circle(q, r), with: .color(LUDO_COLORS[o]))
            ctx.stroke(circle(q, r), with: .color(Color(red: 0.05, green: 0.17, blue: 0.13)), lineWidth: U * 0.09)
            if p != LudoView.FINISH { ctx.fill(circle(q, U * 0.14), with: .color(Color.white.opacity(0.67))) }
        }
    }
}

private func starPath(_ c: CGPoint, _ r: CGFloat) -> Path {
    var p = Path()
    for k in 0..<10 {
        let rr = k % 2 == 0 ? r : r * 0.45
        let a = -Double.pi / 2 + Double(k) * Double.pi / 5
        let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// ═════════════ الأصوات والإعلانات ═════════════

/// أصوات الدومينو والجاكارو واللودو ونص "دورك" (حتى والتطبيق في الخلفية)
final class OtherGameSounds {
    private var sig: String?
    private var wasMyTurn = false
    private var lastPrompt: String?
    private var phase: String?
    private var deal: Int?
    private var ludoLast: String?
    private var ludoTurn: Int?

    func update(_ v: TableView) {
        let d = v.domino, j = v.jackaroo, l = v.ludo
        guard let newSig = d?.moveSig ?? j?.moveSig ?? l?.moveSig else {
            sig = nil; wasMyTurn = false; lastPrompt = nil; phase = nil; deal = nil; ludoLast = nil; ludoTurn = nil; return
        }
        let first = sig == nil
        let changed = sig != newSig
        sig = newSig
        let s = Sounds.shared
        if changed {
            if let d {
                // الدومينو: صوت خلط القطع مع كل توزيع، وطقة القطعة لما تنلعب أو تنسحب
                if (first && d.line.isEmpty && d.phase == "playing") || (phase != nil && phase != "playing" && d.phase == "playing") { s.dominoShuffle() }
                else if !first && (d.lastKind == "play" || d.lastKind == "draw") { s.dominoTile() }
            } else if let j {
                // الجاكارو: توزيع الورق، وصوت الورقة، ونقرة لكل خطوة يمشيها الحجر
                if (first && !j.hasMove) || (!first && deal != nil && deal != j.dealNo) { s.deal(newHand: true) }
                if !first && j.hasMove { s.jackarooCard(); if j.lastSteps > 0 { s.steps(j.lastSteps, at: 0.25) } }
            } else if let l, !first {
                // لودو: صوت النرد مع كل رمية، ونقرة لكل خطوة يمشيها الحجر
                let newTurnRoll = l.phase == "move" && (phase != "move" || ludoTurn != l.turn)
                let moveChanged = l.lastSig != ludoLast && l.lastSig != "null"
                let rolledNow = newTurnRoll || (moveChanged && phase != "move")
                if rolledNow { s.dice() }
                if moveChanged && l.moved { s.steps(l.lastSteps, at: rolledNow && !newTurnRoll ? 0.6 : 0) }
            }
        }
        phase = d?.phase ?? j?.phase ?? l?.phase
        deal = j?.dealNo
        ludoLast = l?.lastSig
        ludoTurn = l?.turn
        let myTurn = d?.myTurn ?? j?.myTurn ?? l?.myTurn ?? false
        let prompt = d?.prompt ?? j?.prompt ?? l?.prompt ?? ""
        if myTurn && !wasMyTurn { s.turn(soft: Announcer.readerOn) }
        // نص الدور (مع الطرفين في الدومينو، أو "اختر الحجر" في لودو): مرة لكل تغيّر
        if myTurn && !prompt.isEmpty && changed && (prompt != lastPrompt || !wasMyTurn) { Announcer.announce(prompt) }
        lastPrompt = myTurn ? prompt : nil
        wasMyTurn = myTurn
    }
}
