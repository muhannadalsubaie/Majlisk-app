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
/// لوحة الجاكارو كبيرة: تاخذ عرض الشاشة لو فيه مكان بالطول
/// حجم لوحة الجاكارو: الطويلة تاخذ عرض الشاشة وتتمدد بالطول على المساحة الباقية (لين ١٫٦ من العرض)
private struct JkBoardSize: ViewModifier {
    let player: Bool
    func body(content: Content) -> some View {
        if JK_TALL {
            let s = UIScreen.main.bounds
            let w = s.width - 32
            // باقي الشاشة: الحواف والعنوان ومربعات اللاعبين والأزرار، وأوراقك لو كنت لاعب
            let h = min(max(s.height - (player ? 420 : 320), min(w, 260)), w * 1.6)
            content.frame(width: w, height: h)
        } else {
            content.aspectRatio(1, contentMode: .fit).frame(maxWidth: jkSide())
        }
    }
}

private func jkSide() -> CGFloat {
    min(440, max(220, UIScreen.main.bounds.height - 490))
}
/// لوحة اللودو أكبر (شلنا النرد الكبير اللي تحتها): تاخذ عرض الشاشة لو فيه مكان بالطول
private func ludoSide() -> CGFloat {
    min(440, max(200, UIScreen.main.bounds.height - 440))
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
        // المشترك يختار لون القطع
        let look = Look.tile
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.18
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
            ctx.fill(rect, with: .color(dim ? look[0].opacity(0.6) : look[0]))
            ctx.stroke(rect, with: .color(look[2]), lineWidth: 1)
            var line = Path()
            if vertical { line.move(to: CGPoint(x: size.width * 0.12, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width * 0.88, y: size.height / 2)) }
            else { line.move(to: CGPoint(x: size.width / 2, y: size.height * 0.12)); line.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.88)) }
            ctx.stroke(line, with: .color(look[1].opacity(0.8)), lineWidth: 1.5)
            let half = vertical ? CGSize(width: size.width, height: size.height / 2) : CGSize(width: size.width / 2, height: size.height)
            let pr = min(half.width, half.height) * 0.1
            func pips(_ n: Int, _ o: CGPoint) {
                for (x, y) in PIPS[n] ?? [] {
                    let c = CGPoint(x: o.x + x * half.width, y: o.y + y * half.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)), with: .color(look[1]))
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

/// لاعب على طاولة الدومينو: صورته واسمه وكم قطعة معه، بإطار ذهبي لما يكون دوره
private struct DominoSeatTag: View {
    let name: String, uid: String?, count: Int, partner: Bool, turn: Bool
    var body: some View {
        VStack(spacing: 2) {
            Avatar(uid: uid, name: name, size: 32)
            Text(name).font(.system(size: 12, weight: turn ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(count) قطع").font(.system(size: 11)).foregroundColor(Palette.textDim)
        }
        .padding(4)
        .background(turn ? Palette.gold.opacity(0.08) : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(turn ? Palette.gold : .clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)\(partner ? "، شريكك" : "")، \(count) قطع\(turn ? "، عليه الدور" : "")")
    }
}

/**
 * خط اللعب على شكل حرف U: يبدأ من فوق على اليسار وينزل، يمشي على الأسفل، ويطلع يمين لين فوق.
 * أول الخط (الطرف اليسار) فوق على اليسار، وآخره (الطرف اليمين) فوق على اليمين.
 * كل ما كثرت القطع تصغر عشان تكفي الطاولة كلها بلا صفوف.
 */
/// قطعة بمكانها على الطاولة (من فوق يسار) وكيف تنرسم
private struct DominoSpot { let rect: CGRect; let vertical: Bool; let tile: Tile }

/// خط اللعب يبدأ من الوسط: أول قطعة بالطول في منتصف الطاولة، والسلسلة تمشي يمين ويسار بخط عرضي.
/// اليمين لما يوصل حافة الطاولة يطلع لفوق ثم يرجع يسار، واليسار ينزل لتحت ثم يرجع يمين.
/// الدبل ينحط بالعرض عكس اتجاه الخط. يرجع nil لو ما كفت الطاولة بهالحجم (فنصغّر القطع).
private func dominoSpiral(_ line: [PlacedTile], _ W: CGFloat, _ H: CGFloat, _ u: CGFloat) -> [DominoSpot]? {
    if line.isEmpty { return [] }
    let f = line.firstIndex { $0.side == "first" } ?? 0
    let S = u, L = 2 * u, g: CGFloat = 2, m = u * 0.5
    let cx = W / 2, cy = H / 2
    let first = orient(line[f])
    // أول قطعة: الدبل بالطول، وغير الدبل بالعرض (الأفقية تنرسم a يمين و b يسار)
    let firstDbl = first.a == first.b
    let c0 = firstDbl ? CGRect(x: cx - S / 2, y: cy - L / 2, width: S, height: L) : CGRect(x: cx - L / 2, y: cy - S / 2, width: L, height: S)
    var out = [DominoSpot(rect: c0, vertical: firstDbl, tile: firstDbl ? Tile(a: first.a, b: first.b) : Tile(a: first.b, b: first.a))]
    func fits(_ r: CGRect) -> Bool { r.minX >= m && r.minY >= m && r.maxX <= W - m && r.maxY <= H - m }
    func run(_ tiles: [PlacedTile], _ side: Int) -> Bool {
        let turns: [(Int, Int)] = side > 0 ? [(1, 0), (0, -1), (-1, 0)] : [(-1, 0), (0, 1), (1, 0)]
        var ti = 0, d = turns[0], last = c0, c = cy
        for p in tiles {
            let t = orient(p)
            // الرقم الداخلي يلاصق القطعة اللي قبله (جهة الوسط)
            let inner = side > 0 ? t.a : t.b, outer = side > 0 ? t.b : t.a
            let dbl = t.a == t.b
            var r: CGRect
            if d.1 == 0 {
                let w = dbl ? S : L, h = dbl ? L : S
                r = CGRect(x: d.0 > 0 ? last.maxX + g : last.minX - g - w, y: c - h / 2, width: w, height: h)
            } else {
                let w = dbl ? L : S, h = dbl ? S : L
                r = CGRect(x: c - w / 2, y: d.1 > 0 ? last.maxY + g : last.minY - g - h, width: w, height: h)
            }
            if !fits(r) {
                // وصل الحافة: يلف (قطعة عمودية على آخر الخط)
                if ti + 1 >= turns.count { return false }
                switch d {
                case (1, 0): r = CGRect(x: last.maxX - S, y: last.minY - g - L, width: S, height: L)
                case (0, -1): r = CGRect(x: last.minX - g - L, y: last.minY, width: L, height: S)
                case (-1, 0): r = CGRect(x: last.minX, y: last.maxY + g, width: S, height: L)
                default: r = CGRect(x: last.maxX + g, y: last.maxY - S, width: L, height: S)
                }
                if !fits(r) { return false }
                ti += 1; d = turns[ti]
                c = d.1 != 0 ? r.minX + S / 2 : r.minY + S / 2
            }
            // الرسم: الأفقية a يمين و b يسار، العمودية a فوق و b تحت
            let tile: Tile = d.0 > 0 ? Tile(a: outer, b: inner) : d.0 < 0 ? Tile(a: inner, b: outer)
                : d.1 < 0 ? Tile(a: outer, b: inner) : Tile(a: inner, b: outer)
            out.append(DominoSpot(rect: r, vertical: r.height > r.width, tile: tile))
            last = r
        }
        return true
    }
    if !run(Array(line[(f + 1)...]), 1) { return nil }
    if !run(Array(line[..<f].reversed()), -1) { return nil }
    return out
}

private struct DominoSnake: View {
    let line: [PlacedTile]
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            // أكبر حجم يكفي كل القطع، وتصغر بس لما تكثر
            let fit: (CGFloat, [DominoSpot]) = {
                var u: CGFloat = 32 * Look.tileScale
                while u > 7 {
                    if let s = dominoSpiral(line, W, H, u) { return (u, s) }
                    u -= 0.5
                }
                return (u, dominoSpiral(line, W, H, u) ?? [])
            }()
            ZStack(alignment: .topLeading) {
                ForEach(Array(fit.1.enumerated()), id: \.offset) { _, s in
                    DominoTileView(t: s.tile, vertical: s.vertical, unit: fit.0).position(x: s.rect.midX, y: s.rect.midY)
                }
            }
            .frame(width: W, height: H)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

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

/// إيماءة الجلا (من فوق لتحت): لو فيه بنك (اللعب الفردي) تسحب لك قطعة، وإلا (الفرق) تجلي
private func dominoDrawOrJala(_ conn: TableConnection, _ d: DominoView) {
    if d.myTurn && d.canDraw { conn.send(["type": "domino", "action": ["type": "draw"]]) }
    else { dominoJala(conn, d) }
}

/// أعلى طاولة الدومينو: النقاط، اللاعبون، وخط اللعب.
/// سحب بثلاث أصابع: من اليمين لليسار = الطرفان، من تحت لفوق = الدور عند مين، من اليسار لليمين = سجل الجولات، من فوق لتحت = سحب من البنك (الفردي) أو جلا (الفرق)
struct DominoBoard: View {
    let v: TableView
    let d: DominoView
    let conn: TableConnection
    let isOwner: Bool
    let openLog: () -> Void

    var body: some View {
        let names = seatNames(v)
        let mySeat = v.mySeat
        VStack(spacing: 8) {
            // النتيجة: شريط صغير «فريقك 10 — الخصم 0» (أو نقاط كل لاعب في الفردي)
            HStack {
                ForEach(Array(d.scores.enumerated()), id: \.offset) { side, n in
                    let mine = side == d.mySide
                    Text("\(mine && d.players == 4 ? "فريقك" : (side < d.sideNames.count ? d.sideNames[side] : "")) \(n)")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(mine ? Palette.gold : Palette.text).lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36)
            .background(Color(red: 0.09, green: 0.24, blue: 0.17)).clipShape(Capsule())
            .overlay(Capsule().stroke(Color(red: 0.17, green: 0.35, blue: 0.27), lineWidth: 1))
            .accessibilityElement(children: .ignore).accessibilityLabel(d.scoreText)
            // الطاولة تملأ باقي الشاشة، واللاعبين على حوافها: اللي قدامك فوق، والباقين يمين ويسار، وأنت تحت
            let me = mySeat ?? 0
            let others = (1..<max(d.players, 2)).map { (me + $0) % d.players }
            let top: Int? = d.players == 4 ? others[1] : d.players == 2 ? others[0] : nil
            let right: Int? = d.players >= 3 ? others[0] : nil
            let left: Int? = d.players == 4 ? others[2] : d.players == 3 ? others[1] : nil
            ZStack {
                // المفرش
                // (المشترك يختار لون المفرش وحافته)
                RoundedRectangle(cornerRadius: 16).fill(RadialGradient(colors: Array(Look.dFelt.prefix(2)), center: .center, startRadius: 0, endRadius: 260))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.gold.opacity(0.4), lineWidth: 1))
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: Look.dRim, startPoint: .top, endPoint: .bottom)))
                    .padding(.vertical, 20).padding(.horizontal, 8)
                // القطع: داخل المفرش بعيد عن صور اللاعبين
                DominoSnake(line: d.line)
                    .padding(.vertical, 70).padding(.horizontal, 44)
                    .accessibilityHidden(true)
                if d.line.isEmpty { Text("الطاولة فارغة").foregroundColor(Palette.textDim) }
                VStack {
                    if let top { seatChip(top, names: names, mySeat: mySeat) }
                    Spacer(minLength: 0)
                    seatChip(mySeat ?? 0, names: names, mySeat: mySeat)
                }
                HStack {
                    if let left { seatChip(left, names: names, mySeat: mySeat).frame(width: 64) }
                    Spacer(minLength: 0)
                    if let right { seatChip(right, names: names, mySeat: mySeat).frame(width: 64) }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: dominoBoardHeight())
            if let e = d.ends {
                Text("يمين \(e.right) — يسار \(e.left)\(d.boneyard > 0 ? " — في البنك \(d.boneyard)" : "")")
                    .foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            if d.phase != "playing" {
                Text(dominoTurnText(v, d))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(Palette.goldSoft).frame(maxWidth: .infinity)
            }
            if d.phase == "matchOver" && isOwner { MButton("مباراة جديدة", .primary) { conn.send("start") } }
        }
        .onAppear { Gestures.shared.set("domino") { read($0) } }
        .onDisappear { Gestures.shared.clear("domino") }
    }

    /// لاعب على حافة الطاولة: صورته بإطار (ذهبي أعرض لما يكون دوره)، وتحته الاسم وكم قطعة
    @ViewBuilder private func seatChip(_ seat: Int, names: [String], mySeat: Int?) -> some View {
        let me = mySeat ?? 0
        let partner = mySeat != nil && d.players == 4 && seat == (me + 2) % 4
        let turn = d.turn == seat && d.phase == "playing"
        let n = seat == mySeat ? "أنت" : (seat < names.count ? names[seat] : "")
        let count = seat < d.handCounts.count ? d.handCounts[seat] : 0
        VStack(spacing: 2) {
            Avatar(uid: v.seatUid(seat), name: n, size: 32)
                .padding(3)
                .background(Circle().fill(Color(red: 0.09, green: 0.24, blue: 0.17)))
                .overlay(Circle().stroke(Palette.gold.opacity(turn ? 1 : 0.7), lineWidth: turn ? 3 : 2))
            HStack(spacing: 3) {
                Text("\(n) · \(count)").font(.system(size: 11, weight: .bold)).foregroundColor(turn ? Palette.gold : Palette.text).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color(red: 0.06, green: 0.16, blue: 0.12).opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 8))
                TurnClock(v: v, seat: seat, turn: turn)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n)\(partner ? "، شريكك" : "")، \(count) قطع\(turn ? "، عليه الدور" : "")")
    }

    /// طول الطاولة: باقي الشاشة بعد الأزرار والنتيجة وقطعك والميكروفون (صفحة وحدة بدون تمرير)
    private func dominoBoardHeight() -> CGFloat {
        let win = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let safe = (win?.safeAreaInsets.top ?? 47) + (win?.safeAreaInsets.bottom ?? 34)
        return min(max(UIScreen.main.bounds.height - safe - 400, 260), 620)
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
        case .down: dominoDrawOrJala(conn, cur)
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
                        DominoTileView(t: h.tile, vertical: true, unit: 24 * Look.tileScale, dim: d.myTurn && !h.legal)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(h.legal ? Palette.gold : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(h.label)
                }
            }
            .sheet(item: $chooseSide) { h in
                Sheet(title: "القطعة تصلح على الطرفين: وش تبي تصير الجهتين؟") {
                    if let e = d.ends {
                        // على اليمين (يطابق \(e.right)) تصير الجهتين \(e.left)، وعلى اليسار تصير \(e.right)
                        MButton("الجهتين \(e.left)", .primary) { chooseSide = nil; act(["type": "play", "tile": h.tile.json, "side": "right"]) }
                        MButton("الجهتين \(e.right)", .primary) { chooseSide = nil; act(["type": "play", "tile": h.tile.json, "side": "left"]) }
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
            // مربعات فوق اللوحة بلون كل لاعب: اسمه وكم حجر دخّل منطقة الأمان من أحجاره الأربعة (وإطار ذهبي لما يكون دوره)
            HStack(spacing: 8) {
                ForEach(j.active, id: \.self) { o in
                    let turn = j.turn == o && j.phase == "playing"
                    let who = o == mySeat ? "أنت" : names[o]
                    let color = JK_COLOR_NAMES[o].hasPrefix("ال") ? String(JK_COLOR_NAMES[o].dropFirst(2)) : JK_COLOR_NAMES[o]
                    VStack(spacing: 0) {
                        HStack(spacing: 3) {
                            Text(who).font(.system(size: 13, weight: .bold)).foregroundColor(Palette.text).lineLimit(1)
                            TurnClock(v: v, seat: o, turn: turn)
                        }
                        Text("\(j.safeOf(o))/4").font(.system(size: 22, weight: .bold)).foregroundColor(Palette.goldSoft)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 4)
                    .frame(width: 84)
                    .background((turn ? Palette.gold : JK_COLORS[o]).opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(turn ? Palette.gold : JK_COLORS[o], lineWidth: turn ? 3 : 2))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(who)، \(color)، \(j.safeOf(o)) من 4\(turn ? "، عليه الدور" : "")")
                }
            }
            .frame(maxWidth: .infinity)
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
                .modifier(JkBoardSize(player: mySeat != nil))
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            if j.phase == "over" {
                let w = j.winnerTeam ?? 0
                let wonText = !j.teams ? (j.winner != nil && j.winner == mySeat ? "🎉 فزت!" : "فاز \(names[j.winner ?? 0])")
                    : mySeat == nil ? "فاز فريق \(names[w]) و\(names[w + 2])" : w == myTeam ? "🎉 فاز فريقك!" : "فاز الفريق الآخر"
                Text(wonText)
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
                        else if h.moves.isEmpty { Sounds.shared.illegal(); Announcer.announceNow("\(short(h.label)) لا تصلح الآن") }
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
            }
        }
        .onAppear { Gestures.shared.set("jackaroo") { read($0) } }
        .onDisappear { Gestures.shared.clear("jackaroo") }
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

    /// لاعب حول اللوحة: صورته بإطار لونه، واسمه وكم ورقة معه، وإطار ذهبي لما يكون دوره
    @ViewBuilder private func seatTag(_ seat: Int?, names: [String], mySeat: Int?) -> some View {
        if let seat {
            let n = names[seat]
            let cards = seat < j.handCounts.count ? j.handCounts[seat] : 0
            let partner = j.teams && mySeat != nil && seat == (mySeat! + 2) % 4
            let turn = j.turn == seat && j.phase == "playing"
            VStack(spacing: 2) {
                Avatar(uid: v.seatUid(seat), name: n, size: 32)
                    .padding(2).overlay(Circle().stroke(JK_COLORS[seat], lineWidth: 2))
                Text(n).font(.system(size: 12, weight: turn ? .bold : .regular)).foregroundColor(Palette.text).lineLimit(1)
                Text("\(cards) أوراق").font(.system(size: 11)).foregroundColor(Palette.textDim)
            }
            .padding(4)
            .background(turn ? Palette.gold.opacity(0.08) : .clear).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(turn ? Palette.gold : .clear, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seat == mySeat ? "أنت" : n)\(partner ? "، شريكك" : "")، \(JK_COLOR_NAMES[seat])، \(cards) أوراق\(turn ? "، عليه الدور" : "")")
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
        out.append((m.title, m.title.hasPrefix("أحجارك") || !j.teams ? me : (me + 2) % 4, m.lines))
    }
    for k in 0..<4 {
        let seat = (start + k) % 4
        guard seat != mySeat, let idx = j.active.firstIndex(of: seat), idx < all.count else { continue }
        let p = splitMarbles(all[idx])
        out.append((p.title, seat, p.lines))
    }
    return out
}

/// رسم لوحة الجاكارو (نفس رسم النسخة السابقة): المسار دائرة، ولكل لاعب قاعدة ومنطقة أمان وبيت
/// مفاتيح الشكل: true = الجديد. لو ما عجبك، false يرجّع الشكل القديم كما كان بالضبط
/// (الجاكارو: اللوحة الدائرية، اللودو: أحجار مسطحة تنقل لمكانها مباشرة)
let JK_OCTAGON = true
/// الجاكارو: اللوحة الثمانية تتمدد بالطول وتملأ الشاشة (false = مربعة بحجمها القديم)
let JK_TALL = true
let LUDO_3D = true

/// لوحة الجاكارو الثمانية (مثل اللوحة الخشب): لكل لاعب ١٩ خانة على جهته، وخانة البداية عليها حلقة بلونه.
/// نقاط خانات جهة اللاعب اللي تحت (بنسبة من نص اللوحة: x، y، وجهة الرقم للخارج)، وباقي الجهات بالتدوير
private let JK_HOLES: [[CGFloat]] = [
    [0.54, 0.684, -0.068, 0.998],
    [0.4811, 0.6346, -0.642, 0.767],
    [0.4225, 0.5857, -0.641, 0.768],
    [0.3636, 0.5365, -0.671, 0.742],
    [0.3089, 0.4829, -0.596, 0.803],
    [0.2422, 0.4466, -0.368, 0.93],
    [0.168, 0.4272, -0.205, 0.979],
    [0.0925, 0.4153, -0.115, 0.993],
    [0.016, 0.4097, -0.021, 1.0],
    [-0.0605, 0.4121, 0.077, 0.997],
    [-0.1365, 0.4215, 0.165, 0.986],
    [-0.2114, 0.4373, 0.283, 0.959],
    [-0.2825, 0.4646, 0.522, 0.853],
    [-0.3393, 0.5155, 0.652, 0.758],
    [-0.3982, 0.5641, 0.632, 0.775],
    [-0.4582, 0.6125, 0.599, 0.8],
    [-0.5209, 0.656, 0.342, 0.94],
    [-0.5925, 0.6615, -0.39, 0.921],
    [-0.643, 0.6043, -0.799, 0.602]
]
private let JK_YARD_SPOTS: [(CGFloat, CGFloat)] = [(0, -0.045), (0.045, 0), (0, 0.045), (-0.045, 0)]
private let JK_SUITS = ["♠", "♣", "♦", "♥"]

/// تدوير ربع لفة مع عقارب الساعة على الشاشة، k مرات
private func jkRot(_ x: CGFloat, _ y: CGFloat, _ k: Int) -> (CGFloat, CGFloat) {
    var a = x, b = y
    for _ in 0..<(((k % 4) + 4) % 4) { (a, b) = (-b, a) }
    return (a, b)
}

private func drawJackaroo(_ ctx: GraphicsContext, _ size: CGSize, _ j: JackarooView, _ bottom: Int) {
    // لوحة غير الحجم المعتاد (١٩ خانة لكل لاعب): الرسم الدائري القديم
    guard JK_OCTAGON, j.segment == JK_HOLES.count else {
        // اللوحة الطويلة: الدائرية القديمة في النص
        var c = ctx
        c.translateBy(x: 0, y: max(0, size.height - min(size.width, size.height)) / 2)
        drawJackarooRound(c, size, j, bottom); return
    }
    // اللوحة الطويلة: العرض كامل، والطول يتمدد (لين ١٫٦ من العرض)؛ الخانات والأحجار تبقى دائرية
    let W = min(size.width, size.height)
    let half = W * 0.47
    let halfY = JK_TALL ? min(size.height, size.width * 1.6) * 0.47 : half
    let ctr = JK_TALL ? CGPoint(x: size.width / 2, y: size.height / 2) : CGPoint(x: W / 2, y: W / 2)
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ctr.x + x * half, y: ctr.y + y * halfY) }
    func rk(_ seat: Int) -> Int { (seat - bottom + 4) % 4 }
    func hole(_ seat: Int, _ i: Int) -> CGPoint { let h = JK_HOLES[i]; let (x, y) = jkRot(h[0], h[1], rk(seat)); return at(x, y) }
    func safe(_ seat: Int, _ s: Int) -> CGPoint { let d = 0.565 - 0.068 * CGFloat(s); let (x, y) = jkRot(d, d, rk(seat)); return at(x, y) }
    func yard(_ seat: Int) -> (CGFloat, CGFloat) { jkRot(0.20, 0.79, rk(seat)) }
    func dot(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
    let holeR = W * 0.015
    let woodDark = Color(red: 0.42, green: 0.29, blue: 0.13)
    let cream = Color(red: 0.91, green: 0.86, blue: 0.75)
    func drawHole(_ p: CGPoint, _ r: CGFloat? = nil, ring: Color? = nil, ringW: CGFloat? = nil) {
        let r = r ?? holeR
        ctx.fill(dot(p, r), with: .radialGradient(Gradient(colors: [Color(red: 0.91, green: 0.79, blue: 0.58), Color(red: 0.85, green: 0.71, blue: 0.49), Color(red: 0.65, green: 0.49, blue: 0.28)]),
                                                  center: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        ctx.stroke(dot(p, r), with: .color(ring ?? woodDark), lineWidth: ringW ?? W * 0.0015)
    }
    func marble(_ color: Color, _ p: CGPoint) {
        let r = W * 0.013
        ctx.fill(dot(p, r), with: .color(color))
        ctx.fill(dot(p, r), with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .clear]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 0.8))
        ctx.fill(dot(p, r), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.7)]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: r * 0.5, endRadius: r * 1.6))
    }
    func octagon(_ radius: CGFloat, stretch: CGFloat = 1) -> Path {
        var path = Path()
        for i in 0..<8 {
            let a = (22.5 + 45 * Double(i)) * Double.pi / 180
            let rr = radius / CGFloat(cos(22.5 * Double.pi / 180))
            let q = CGPoint(x: ctr.x + rr * CGFloat(cos(a)), y: ctr.y + rr * CGFloat(sin(a)) * stretch)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }
    // اللوحة الثمانية السوداء
    let board = octagon(half * 0.99, stretch: halfY / half)
    // (المشترك يختار ألوان اللوحة)
    let jkLook = Look.jk
    ctx.fill(board, with: .linearGradient(Gradient(colors: [jkLook[0], jkLook[1]]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
    ctx.stroke(board, with: .color(Palette.gold.opacity(0.5)), lineWidth: W * 0.003)
    // صينية الورق في النص
    let tray = octagon(half * 0.27)
    ctx.fill(tray, with: .radialGradient(Gradient(colors: [jkLook[2], jkLook[2].opacity(0.7)]), center: ctr, startRadius: 0, endRadius: half * 0.32))
    ctx.stroke(tray, with: .color(Color(red: 0.54, green: 0.38, blue: 0.2)), lineWidth: W * 0.003)
    let cards: [(String, String, Bool)] = [("3", "♥", true), ("2", "♠", false), ("Q", "♣", false), ("A", "♦", true), ("K", "♣", false), ("J", "♠", false), ("A", "♠", false)]
    let cw = W * 0.076, ch = W * 0.108
    for (i, card) in cards.enumerated() {
        var c2 = ctx
        let pivot = CGPoint(x: ctr.x, y: ctr.y + W * 0.04)
        c2.translateBy(x: pivot.x, y: pivot.y)
        c2.rotate(by: .degrees(-27 + Double(i) * 9))
        let rect = CGRect(x: -cw / 2, y: -W * 0.15, width: cw, height: ch)
        let col = card.2 ? Color(red: 0.75, green: 0.22, blue: 0.17) : Color(red: 0.07, green: 0.07, blue: 0.07)
        c2.fill(Path(roundedRect: rect, cornerRadius: W * 0.007), with: .color(Color(red: 0.98, green: 0.98, blue: 0.96)))
        c2.stroke(Path(roundedRect: rect, cornerRadius: W * 0.007), with: .color(Color(white: 0.73)), lineWidth: W * 0.0012)
        c2.draw(Text(card.0).font(.system(size: W * 0.02, weight: .bold)).foregroundColor(col), at: CGPoint(x: rect.minX + W * 0.016, y: rect.minY + W * 0.017))
        c2.draw(Text(card.1).font(.system(size: W * 0.018)).foregroundColor(col), at: CGPoint(x: rect.minX + W * 0.016, y: rect.minY + W * 0.038))
        if i == cards.count - 1 { c2.draw(Text(card.1).font(.system(size: W * 0.044)).foregroundColor(col), at: CGPoint(x: rect.midX, y: rect.minY + W * 0.066)) }
    }
    // جهة كل لاعب: الخانات وأرقامها (رقم ثابت للجميع، نفس الرقم في الإعلانات)، ورمز ورق، والبيت ومنطقة الأمان
    for seat in 0...3 {
        let k = rk(seat)
        let active = j.active.contains(seat)
        for (i, h) in JK_HOLES.enumerated() {
            let p = hole(seat, i)
            if i == 0 && active { ctx.stroke(dot(p, holeR * 1.4), with: .color(JK_COLORS[seat]), lineWidth: W * 0.004) }
            drawHole(p)
            let (nx, ny) = jkRot(h[2], h[3], k)
            ctx.draw(Text("\(seat * j.segment + i)").font(.system(size: W * 0.021, weight: .semibold)).foregroundColor(cream),
                     at: CGPoint(x: p.x + nx * half * 0.062, y: p.y + ny * halfY * 0.062))
        }
        let (sx, sy) = jkRot(-0.24, 0.84, k)
        ctx.draw(Text(JK_SUITS[seat]).font(.system(size: W * 0.064)).foregroundColor(cream), at: at(sx, sy))
        if !active { continue }
        for s2 in 0..<4 { drawHole(safe(seat, s2), ring: JK_COLORS[seat], ringW: W * 0.003) }
        let (yx, yy) = yard(seat)
        let yc = at(yx, yy)
        var c3 = ctx
        c3.translateBy(x: yc.x, y: yc.y)
        c3.rotate(by: .degrees(45))
        let bs = W * 0.096
        let box = Path(roundedRect: CGRect(x: -bs / 2, y: -bs / 2, width: bs, height: bs), cornerRadius: W * 0.016)
        c3.fill(box, with: .color(Color(white: 0.06)))
        c3.stroke(box, with: .color(cream.opacity(0.7)), lineWidth: W * 0.002)
        for (dx, dy) in JK_YARD_SPOTS { drawHole(CGPoint(x: yc.x + dx * half, y: yc.y + dy * half), W * 0.014) }
    }
    // الأحجار
    for o in j.active {
        let row = o < j.marbles.count ? j.marbles[o] : []
        for (i, m) in row.enumerated() {
            let p: CGPoint
            switch m.zone {
            case "track": p = hole(m.pos / j.segment, m.pos % j.segment)
            case "safe": p = safe(o, min(max(m.pos, 0), 3))
            default: let (yx, yy) = yard(o); let (dx, dy) = JK_YARD_SPOTS[i % 4]; let yc = at(yx, yy); p = CGPoint(x: yc.x + dx * half, y: yc.y + dy * half)
            }
            marble(JK_COLORS[o], p)
        }
    }
}

/// الرسم الدائري القديم (للوحة بعدد خانات مختلف)
private func drawJackarooRound(_ ctx: GraphicsContext, _ size: CGSize, _ j: JackarooView, _ bottom: Int) {
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
        let owner = (0...3).first { start($0) == p && j.active.contains($0) }
        ctx.fill(dot(at(CGFloat(p)), (owner != nil ? 6 : 3.5) * k), with: .color(owner.map { JK_COLORS[$0] } ?? Color.white.opacity(0.2)))
        // رقم الخانة (ثابت للجميع، نفس الرقم اللي ينقال في الإعلان) داخل الدائرة جنب كل نقطة
        ctx.draw(Text("\(p)").font(.system(size: 6.5 * k, weight: .semibold)).foregroundColor(Color.white.opacity(0.75)), at: at(CGFloat(p), R - 12))
    }
    for o in j.active {
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
    @State private var prevRollSeq = 0
    @State private var prevTurn: Int?
    @State private var prevLast: String?
    /// السجل: يفتح بسحبة إصبعين من فوق لتحت (بدون زر)
    @State private var logOpen = false
    /// قارئ الشاشة شغّال: يبقى كل شي زي ما هو (الإيماءة وأزرار الاختيار)
    @Environment(\.accessibilityVoiceOverEnabled) private var reader
    /// الرقم اللي اختاره (لما يكون عنده أكثر من رقم، مثل ستة وثلاثة): الحجر اللي يلمسه يمشي فيه
    @State private var pickedDie: Int?
    /// حركة الأحجار: الحجر يقفز خانة خانة لين يوصل (نفس توقيت نقرات الخطوات)، والمأكول يطير لبيته
    @State private var hops: [String: LudoHop] = [:]
    @State private var prevTokens: [[Int]]?
    @State private var prevTokPhase: String?

    private func act(_ a: JSON) { conn.send(["type": "ludo", "action": a]) }

    /// تغيّرت أماكن الأحجار: نحسب طريق كل حجر تحرك
    private func animateMoves() {
        let before = prevTokens, wasPhase = prevTokPhase
        prevTokens = l.tokens; prevTokPhase = l.phase
        guard let before, LUDO_3D else { return }
        let now = Date().timeIntervalSince1970
        hops = hops.filter { $0.value.end > now }
        // رمى وتحرك بنفس اللحظة: الحجر يبدأ بعد صوت النرد (نفس الصوت)
        let delay = wasPhase != "move" ? 0.6 : 0
        var moverEnd = now + delay
        var captured: [(Int, Int, Int)] = []
        for o in l.seats {
            let row = o < l.tokens.count ? l.tokens[o] : []
            for (i, p1) in row.enumerated() {
                guard o < before.count, i < before[o].count else { continue }
                let p0 = before[o][i]
                if p0 == p1 { continue }
                if p1 == -1 { captured.append((o, i, p0)) }
                else if p0 == -1 { let h = LudoHop(path: [ludoCell(o, i, -1), ludoCell(o, i, p1)], startAt: now + delay, step: 0.32); hops["\(o)-\(i)"] = h; moverEnd = max(moverEnd, h.end) }
                else if p1 > p0 { let h = LudoHop(path: (p0...p1).map { ludoCell(o, i, $0) }, startAt: now + delay, step: Sounds.stepGap); hops["\(o)-\(i)"] = h; moverEnd = max(moverEnd, h.end) }
            }
        }
        // المأكول: يبقى مكانه لين يوصله اللي أكله، وبعدها يطير لبيته
        for (o, i, p0) in captured { hops["\(o)-\(i)"] = LudoHop(path: [ludoCell(o, i, p0), ludoCell(o, i, -1)], startAt: moverEnd, step: 0.52) }
    }

    /// النرد اللي يطلع جنب اللاعب: آخر رمية من السيرفر مباشرة (تتحدث على طول لكل اللاعبين)، وإلا آخر رمية محفوظة له
    private func shownRoll(_ o: Int) -> Int? {
        if l.rollSeq > 0, l.rolledSeat == o, let r = l.rolledValue { return r }
        return rolls[o]
    }

    /// لمس حجر على اللوحة: يتحرك بالرقم المختار (أو أول رقم يقدر يمشيه)
    private func tapBoard(_ at: CGPoint, _ size: CGSize) {
        guard l.myTurn, l.phase == "move", !l.options.isEmpty else { return }
        let U = min(size.width, size.height) / 15
        let movable = Set(l.options.map(\.token))
        let hits = ludoTokenPoints(size, l, v.mySeat ?? 0)
            .filter { $0.owner == l.movableOwner && movable.contains($0.index) }
            .map { (t: $0, d: hypot($0.point.x - at.x, $0.point.y - at.y)) }
            .filter { $0.d < U * 0.9 }
            .sorted { $0.d < $1.d }
        guard let hit = hits.first?.t else { return }
        let opts = l.options.filter { $0.token == hit.index }
        let o = opts.first { $0.die == pickedDie } ?? opts.first!
        pickedDie = nil
        act(["type": "move", "token": o.token, "die": o.die])
    }

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
        let dice = myDice(o, mySeat: mySeat)
        HStack(spacing: 8) {
            // النرد جهة اللوحة: لاعب اليسار نرده يمين صورته، ولاعب اليمين يسارها
            if !left { dice }
            VStack(spacing: 2) {
                Avatar(uid: v.seatUid(o), name: n, size: 52)
                    .padding(3)
                    .overlay(Circle().stroke(turn ? Palette.gold : LUDO_COLORS[o], lineWidth: 3))
                HStack(spacing: 3) {
                    Text("\(n)\(o == mySeat ? " (أنت)" : l.teams && o == partner ? " (شريكك)" : "")")
                        .font(.system(size: 13, weight: turn ? .bold : .regular)).foregroundColor(Palette.text).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.black.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 8))
                    TurnClock(v: v, seat: o, turn: turn)
                }
                Text("وصل \(l.home(o))/4").font(.system(size: 11)).foregroundColor(Palette.textDim)
            }
            if left { dice }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o == mySeat ? "أنت" : n)\(l.teams && o == partner ? "، شريكك" : "")، \(LUDO_COLOR_NAMES[o])، وصل \(l.home(o)) من 4\(shownRoll(o).map { "، آخر رمية \($0)" } ?? "")\(turnPool(o).count > 1 ? "، رمياته " + turnPool(o).map(String.init).joined(separator: " و") : "")\(turn ? "، عليه الدور" : "")")
        // النرد نفسه زر الرمي: مع VoiceOver الضغط مرتين على اسمك يرمي النرد
        .accessibilityAddTraits(o == mySeat && l.canRoll ? .isButton : [])
        .accessibilityHint(o == mySeat && l.canRoll ? "اضغط مرتين لرمي النرد" : "")
        .accessibilityAction { if o == mySeat && l.canRoll { act(["type": "roll"]) } }
    }

    /// رميات هالدور (للي عليه الدور بس)
    private func turnPool(_ o: Int) -> [Int] { l.turn == o && l.phase != "over" ? l.pool : [] }

    /// النرد جنب الاسم. لك (بدون قارئ الشاشة): تضغطه وترمي، ولو عندك أكثر من رقم تختار الرقم منه
    @ViewBuilder private func myDice(_ o: Int, mySeat: Int?) -> some View {
        let mine = o == mySeat && !reader
        let distinct = l.pool.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        if mine && l.myTurn && l.phase == "move" && distinct.count > 1 {
            // أكثر من رقم: كل رقم نرد صغير، تختار واحد ثم تلمس الحجر
            let usable = Set(l.options.map(\.die))
            HStack(spacing: 4) {
                ForEach(distinct, id: \.self) { d in
                    let on = (pickedDie ?? l.options.first?.die) == d
                    DiceView(value: d, color: LUDO_COLORS[o], size: 32)
                        .padding(2)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Palette.gold : .clear, lineWidth: 3))
                        .opacity(usable.contains(d) ? 1 : 0.4)
                        .onTapGesture { if usable.contains(d) { pickedDie = d } }
                }
            }
        } else {
            let canTap = mine && l.canRoll
            let pool = turnPool(o)
            VStack(spacing: 4) {
                DiceView(value: canTap && l.pool.isEmpty ? nil : shownRoll(o), color: LUDO_COLORS[o], size: canTap ? 46 : 40)
                    .rotationEffect(.degrees(Double(l.rollSeq > 0 ? (l.rolledSeat == o ? l.rollSeq : 0) : (rollTicks[o] ?? 0)) * 360))
                    .animation(.easeOut(duration: 0.45), value: l.rollSeq > 0 ? (l.rolledSeat == o ? l.rollSeq : 0) : (rollTicks[o] ?? 0))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(canTap ? Palette.gold : .clear, lineWidth: 3).padding(-3))
                    .shadow(color: canTap ? Palette.gold.opacity(0.8) : .clear, radius: canTap ? 8 : 0)
                    .onTapGesture { if canTap { act(["type": "roll"]) } }
                // الرميات اللي عنده هالدور (ستة ثم ستة ثم ثلاثة...): نرد صغير لكل وحدة، تختفي لما يلعبها
                if !pool.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(pool.enumerated()), id: \.offset) { _, d in DiceView(value: d, color: LUDO_COLORS[o], size: 20) }
                    }
                }
            }
        }
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
        // السيرفر الجديد يرسل آخر رمية مع عدّادها: النرد الجديد يطلع على طول ويحل محل القديم
        if l.rollSeq > 0 {
            if l.rollSeq != prevRollSeq, let s = l.rolledSeat, let r = l.rolledValue {
                rolls[s] = r
                if prevRollSeq != 0 { rollTicks[s, default: 0] += 1 }
            }
            prevRollSeq = l.rollSeq
            prevPhase = l.phase; prevTurn = l.turn; prevLast = l.lastSig
            return
        }
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
            TimelineView(.animation(paused: hops.isEmpty)) { tl in
                Canvas { ctx, size in
                    drawLudo(ctx, size, l, mySeat ?? 0, l.myTurn && l.phase == "move" ? l.options.map { (l.movableOwner, $0.token) } : [],
                             hops: hops, now: tl.date.timeIntervalSince1970)
                }
            }
            .onChange(of: l.tokens) { _ in animateMoves() }
            .onAppear { prevTokens = l.tokens; prevTokPhase = l.phase }
            // بعد ما توصل كل الأحجار: نوقف التحديث المستمر للرسم
            .task(id: hops.values.map(\.end).max() ?? 0) {
                guard let end = hops.values.map(\.end).max() else { return }
                let wait = end - Date().timeIntervalSince1970 + 0.05
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                if Task.isCancelled { return }
                let now = Date().timeIntervalSince1970
                hops = hops.filter { $0.value.end > now }
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: ludoSide())
            // بدون قارئ الشاشة: تلمس الحجر اللي تبيه ويتحرك
            .overlay(GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { e in if !reader { tapBoard(e.location, geo.size) } })
            })
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
                // زر «ارمِ النرد» انشال: الرمي بالضغط على النرد نفسه (أو على اسمك مع VoiceOver، أو بالسحب)
                EmptyView()
            }
            // قارئ الشاشة: الاختيارات كما هي (كل حجر مع الرقم اللي يمشيه)
            if reader && l.myTurn && l.phase == "move" && l.options.count > 1 {
                Text(l.prompt.isEmpty ? "اختر الحجر" : l.prompt).font(.system(size: 1)).foregroundColor(.clear).accessibilityAddTraits(.isHeader)
                // أكثر من رقم (مثل ستة وستة وأربعة): تختار الرقم اللي تلعبه أول، وبعدين الحجر
                let dice = l.options.reduce(into: [Int]()) { if !$0.contains($1.die) { $0.append($1.die) } }
                if dice.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(dice, id: \.self) { d in
                            MButton(pickedDie == d ? "✓ بالـ\(d)" : "بالـ\(d)") { pickedDie = pickedDie == d ? nil : d }
                                .accessibilityAddTraits(pickedDie == d ? .isSelected : [])
                        }
                    }
                }
                ForEach(l.options.filter { pickedDie == nil || !dice.contains(pickedDie!) || $0.die == pickedDie }) { o in
                    MButton(o.text) { pickedDie = nil; act(["type": "move", "token": o.token, "die": o.die]) }
                }
            }
        }
        .onAppear { Gestures.shared.set("ludo") { read($0) }; noteRoll() }
        .onDisappear { Gestures.shared.clear("ludo") }
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
        let look = Look.diceColors
        Canvas { ctx, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5), cornerRadius: size.width * 0.19)
            ctx.fill(rect, with: .color(look[0]))
            ctx.stroke(rect, with: .color(color), lineWidth: max(1.5, size.width * 0.055))
            for i in value.flatMap({ spots[$0] }) ?? [] {
                let x = (CGFloat(i % 3) + 0.5) / 3 * size.width, y = (CGFloat(i / 3) + 0.5) / 3 * size.height
                let r = size.width * 0.08
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(look[1]))
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

/// خانة الحجر (قبل تدوير اللوحة) حسب تقدّمه: البيت، المسار، ممر المنزل، المنزل
private func ludoCell(_ o: Int, _ i: Int, _ p: Int) -> Cell {
    if p == -1 { return (YARDS[o].0 + YARD_SPOTS[i].0 - 0.5, YARDS[o].1 + YARD_SPOTS[i].1 - 0.5) }
    if p == LudoView.FINISH { return CENTER_SPOT[o] }
    // ممر المنزل 6 خانات: الخمس الملوّنة، والسادسة عند حافة الوسط
    if p > LudoView.LAST_TRACK && p - LudoView.LAST_TRACK - 1 < 5 { return HOME_CELLS[o][p - LudoView.LAST_TRACK - 1] }
    if p > LudoView.LAST_TRACK { return ((HOME_CELLS[o][4].0 + CENTER_SPOT[o].0) / 2, (HOME_CELLS[o][4].1 + CENTER_SPOT[o].1) / 2) }
    return TRACK_CELLS[LudoView.absPos(o, p)]
}

/// حجر يتحرك: الخانات اللي يمر عليها (أولها مكانه القديم)، ومتى يبدأ، ووقت كل قفزة
private struct LudoHop {
    let path: [Cell]
    let startAt: Double
    let step: Double
    var end: Double { startAt + Double(path.count - 1) * step }
}

/// مكان كل حجر على اللوحة (نفس حساب الرسم، مع إزاحة الأحجار المتكدسة)
private func ludoTokenPoints(_ size: CGSize, _ l: LudoView, _ bottom: Int) -> [(owner: Int, index: Int, point: CGPoint)] {
    let U = min(size.width, size.height) / 15
    let turns = (3 - bottom + 4) % 4
    func rot(_ cell: Cell) -> Cell { var p = cell; for _ in 0..<turns { p = (p.1, 14 - p.0) }; return p }
    func xy(_ cell: Cell) -> CGPoint { let (r, c) = rot(cell); return CGPoint(x: c * U + U / 2, y: r * U + U / 2) }
    var out: [(owner: Int, index: Int, point: CGPoint)] = []
    var seen: [String: Int] = [:]
    for o in l.seats {
        let row = o < l.tokens.count ? l.tokens[o] : []
        for (i, p) in row.enumerated() {
            let cell: Cell
            if p == -1 { cell = (YARDS[o].0 + YARD_SPOTS[i].0 - 0.5, YARDS[o].1 + YARD_SPOTS[i].1 - 0.5) }
            else if p == LudoView.FINISH { cell = CENTER_SPOT[o] }
            else if p > LudoView.LAST_TRACK && p - LudoView.LAST_TRACK - 1 < 5 { cell = HOME_CELLS[o][p - LudoView.LAST_TRACK - 1] }
            else if p > LudoView.LAST_TRACK { cell = ((HOME_CELLS[o][4].0 + CENTER_SPOT[o].0) / 2, (HOME_CELLS[o][4].1 + CENTER_SPOT[o].1) / 2) }
            else { cell = TRACK_CELLS[LudoView.absPos(o, p)] }
            let pt = xy(cell)
            let key = "\(Int(pt.x)),\(Int(pt.y))"
            let n = seen[key] ?? 0
            seen[key] = n + 1
            out.append((o, i, CGPoint(x: pt.x + CGFloat(n) * U * 0.18, y: pt.y - CGFloat(n) * U * 0.18)))
        }
    }
    return out
}

private func drawLudo(_ ctx: GraphicsContext, _ size: CGSize, _ l: LudoView, _ bottom: Int, _ movable: [(Int, Int)], hops: [String: LudoHop] = [:], now: Double = 0) {
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
    // الأحجار (أكثر من حجر في خانة: تُزاح قليلاً). نرسم الواقفة أول، والمتحركة فوقها
    var seen: [String: Int] = [:]
    var flying: [(Int, CGPoint, CGFloat)] = []
    for o in l.seats {
        let row = o < l.tokens.count ? l.tokens[o] : []
        for (i, p) in row.enumerated() {
            if let hop = hops["\(o)-\(i)"], now < hop.end, hop.path.count > 1 {
                // بين خانتين: ينتقل بنعومة ويرتفع في نص القفزة
                let t = min(max((now - hop.startAt) / hop.step, 0), Double(hop.path.count - 1))
                let k = min(Int(t), hop.path.count - 2)
                let f = CGFloat(t - Double(k))
                let e = f * f * (3 - 2 * f)
                let a = xy(hop.path[k]), b = xy(hop.path[k + 1])
                let lift = t <= 0 ? 0 : CGFloat(sin(Double.pi * Double(f))) * (hop.path.count == 2 && hop.step > 0.4 ? 1.6 : 1)
                flying.append((o, CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e), lift))
                continue
            }
            let pt = xy(ludoCell(o, i, p))
            let key = "\(Int(pt.x)),\(Int(pt.y))"
            let n = seen[key] ?? 0
            seen[key] = n + 1
            let q = CGPoint(x: pt.x + CGFloat(n) * U * 0.18, y: pt.y - CGFloat(n) * U * 0.18)
            if movable.contains(where: { $0.0 == o && $0.1 == i }) { ctx.stroke(circle(q, U * 0.5), with: .color(Palette.gold), lineWidth: U * 0.14) }
            if LUDO_3D { drawPawn(ctx, LUDO_COLORS[o], q, p == LudoView.FINISH ? U * 0.25 : U * 0.36, 0, U) } else {
                // الشكل القديم: دائرة مسطحة بإطار ونقطة بيضاء
                let r = p == LudoView.FINISH ? U * 0.23 : U * 0.36
                ctx.fill(circle(q, r), with: .color(LUDO_COLORS[o]))
                ctx.stroke(circle(q, r), with: .color(Color(red: 0.05, green: 0.17, blue: 0.13)), lineWidth: U * 0.09)
                if p != LudoView.FINISH { ctx.fill(circle(q, U * 0.14), with: .color(Color.white.opacity(0.67))) }
            }
        }
    }
    for (o, q, lift) in flying { drawPawn(ctx, LUDO_COLORS[o], q, U * 0.36, lift, U) }
}

/// حجر بشكل مجسّم: ظل على الأرض، قاعدة أغمق، ورأس كروي بلمعة.
/// lift (٠ إلى ١): وهو يقفز يرتفع ويكبر شوي، وظله يصغر ويخف
private func drawPawn(_ ctx: GraphicsContext, _ color: Color, _ q: CGPoint, _ r: CGFloat, _ lift: CGFloat, _ U: CGFloat) {
    let sh = 1 - min(max(lift, 0), 1.6) * 0.25
    ctx.fill(Path(ellipseIn: CGRect(x: q.x - r * 0.95 * sh, y: q.y + r * 0.2, width: r * 1.9 * sh, height: r * 0.75 * sh)), with: .color(.black.opacity(0.35 * sh)))
    let s = r * (1 + lift * 0.14)
    let c = CGPoint(x: q.x, y: q.y - lift * U * 0.42 - s * 0.12)
    // القاعدة
    let base = Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y + s * 0.05, width: s * 1.9, height: s * 0.9))
    ctx.fill(base, with: .color(color))
    ctx.fill(base, with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.55)]), startPoint: CGPoint(x: c.x, y: c.y), endPoint: CGPoint(x: c.x, y: c.y + s * 0.95)))
    // الرأس الكروي
    let hc = CGPoint(x: c.x, y: c.y - s * 0.18), hl = CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.38)
    let head = Path(ellipseIn: CGRect(x: hc.x - s * 0.78, y: hc.y - s * 0.78, width: s * 1.56, height: s * 1.56))
    ctx.fill(head, with: .color(color))
    ctx.fill(head, with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]), center: hl, startRadius: 0, endRadius: s * 0.75))
    ctx.fill(head, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.5)]), center: hl, startRadius: s * 0.45, endRadius: s * 1.4))
    ctx.stroke(head, with: .color(.black.opacity(0.33)), lineWidth: U * 0.035)
    // لمعة
    ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.45, y: c.y - s * 0.65, width: s * 0.34, height: s * 0.34)), with: .color(.white.opacity(0.75)))
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
                // انتهت الصكة (أو المباراة): بعد طقة آخر قطعة
                if !first && phase == "playing" && (d.phase == "handOver" || d.phase == "matchOver") { s.dominoEnd(at: 0.5) }
            } else if let j {
                // الجاكارو: توزيع الورق، وصوت الورقة، ونقرة لكل خطوة يمشيها الحجر
                if (first && !j.hasMove) || (!first && deal != nil && deal != j.dealNo) { s.deal(newHand: true) }
                if !first && j.hasMove {
                    s.jackarooCard()
                    // رجوع ٤ وتبديل حجرين: صوتهم الخاص بدل نقرات الخطوات
                    switch j.lastKind {
                    case "back": s.jackarooBack(at: 0.25)
                    case "swap": s.jackarooSwap(at: 0.25)
                    default: if j.lastSteps > 0 { s.marbleSteps(j.lastSteps, at: 0.25) }
                    }
                    let arrive = 0.25 + Double(min(max(j.lastSteps, 1), 13)) * Sounds.stepGap
                    // أكل حجر: بعد ما يوصل الحجر
                    if j.captures > 0 { s.capture(at: arrive) }
                    // دخل حجر منطقة الأمان (المنزل)
                    if j.enteredSafe > 0 { s.jackarooHome(at: arrive + (j.captures > 0 ? 0.5 : 0)) }
                }
            } else if let l, !first {
                // لودو: صوت النرد مع كل رمية، ونقرة لكل خطوة يمشيها الحجر
                let newTurnRoll = l.phase == "move" && (phase != "move" || ludoTurn != l.turn)
                let moveChanged = l.lastSig != ludoLast && l.lastSig != "null"
                let rolledNow = newTurnRoll || (moveChanged && phase != "move")
                if rolledNow { s.dice() }
                if moveChanged && l.moved {
                    let at = rolledNow && !newTurnRoll ? 0.6 : 0
                    s.steps(l.lastSteps, at: at)
                    // أكل حجر: بعد ما يوصل الحجر
                    if l.captures > 0 { s.capture(at: at + Double(min(max(l.lastSteps, 1), 13)) * Sounds.stepGap) }
                    // وصل الحجر المنزل
                    if l.finished { s.ludoHome(at: at + Double(min(max(l.lastSteps, 1), 13)) * Sounds.stepGap) }
                }
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
