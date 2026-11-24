import SwiftUI

// لوحة اللعبة على الطاولة (عقد التريكس، سحب وأرض الكنكان): الخادم يرسلها مع واجهة اللعبة، وكل جزء اختياري.

struct CardsBoardInfo {
    struct Step { let label: String, state: String }
    struct Mark { let card: CardsCard, by: String? }
    struct RowInfo { let id: String, title: String, text: String, cards: [CardsCard], low: String?, high: String?, lowMine: Bool, highMine: Bool }
    struct Heap { let count: Int, can: Bool, text: String, card: CardsCard? }
    struct Progress { let value: Int, need: Int, text: String }
    /// الشايب: أوراق اللي تسحب منه (مقلوبة)
    struct Draw { let seat: Int, name: String, count: Int }
    let title: String, sub: String, tone: String
    let steps: [Step]
    let counter: String
    let marks: [Mark]
    let rows: [RowInfo]
    let stock: Heap?, discard: Heap?
    let progress: Progress?
    let read: String
    let draw: Draw?

    init(_ b: JSON) {
        func heap(_ o: JSON?) -> Heap? { o.map { Heap(count: $0.int("count"), can: $0.bool("can"), text: $0.str("text"), card: $0.obj("card").map { CardsCard($0) }) } }
        title = b.str("title"); sub = b.str("sub"); tone = b.str("tone")
        steps = b.objs("steps").map { Step(label: $0.str("label"), state: $0.str("state")) }
        counter = b.str("counter")
        marks = b.objs("marks").map { Mark(card: CardsCard($0.obj("card")), by: $0["by"] as? String) }
        rows = b.objs("rows").map { r in
            RowInfo(id: r.str("id"), title: r.str("title"), text: r.str("text"), cards: r.objs("cards").map { CardsCard($0) },
                    low: r["low"] as? String, high: r["high"] as? String, lowMine: r.bool("lowMine"), highMine: r.bool("highMine"))
        }
        stock = heap(b.obj("stock")); discard = heap(b.obj("discard"))
        progress = b.obj("progress").map { Progress(value: $0.int("value"), need: $0.int("need"), text: $0.str("text")) }
        read = b.str("read")
        draw = b.obj("draw").map { Draw(seat: $0.int("seat"), name: $0.str("name"), count: $0.int("count")) }
    }
}

/// لون العقد: شايب الهاص أحمر، البنات بنفسجي، الديمن ذهبي، اللطوش أزرق، التركس أخضر
func boardTone(_ tone: String) -> Color {
    switch tone {
    case "red": return Color(red: 0.90, green: 0.45, blue: 0.45)
    case "purple": return Color(red: 0.70, green: 0.62, blue: 0.86)
    case "blue": return Color(red: 0.51, green: 0.72, blue: 0.91)
    case "green": return Color(red: 0.50, green: 0.81, blue: 0.60)
    default: return Palette.gold
    }
}

/// رأس اللوحة: اسم العقد بلونه، وتحته وش تتجنب، وعقود المملكة (انلعب، الحين، باقي)
struct CardsBoardHeader: View {
    let b: CardsBoardInfo
    var body: some View {
        let tone = boardTone(b.tone)
        VStack(spacing: 3) {
            if !b.title.isEmpty {
                Text(trSpoken(b.title)).font(.system(size: 18, weight: .heavy)).foregroundColor(tone).lineLimit(1).accessibilityAddTraits(.isHeader)
            }
            if !b.sub.isEmpty {
                Text(trSpoken(b.sub)).font(.system(size: 12)).foregroundColor(Palette.textDim).multilineTextAlignment(.center).lineLimit(2)
            }
            if !b.steps.isEmpty {
                WrapLayout(spacing: 4) {
                    ForEach(Array(b.steps.enumerated()), id: \.offset) { _, st in
                        let now = st.state == "now"
                        Text(trSpoken(st.state == "done" ? "✓ \(st.label)" : st.label))
                            .font(.system(size: 11, weight: now ? .bold : .regular))
                            .foregroundColor(now ? Color(red: 0.1, green: 0.08, blue: 0.02) : st.state == "done" ? Palette.textDim : Palette.text)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(now ? tone : Color.white.opacity(0.08)))
                            .opacity(st.state == "done" ? 0.6 : 1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText("العقود: " + b.steps.map { "\($0.label) \($0.state == "done" ? "انلعب" : $0.state == "now" ? "الحين" : "باقي")" }.joined(separator: "، ")))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// الأوراق الخطرة في العقد: اللي ما انأكلت واضحة، واللي انأكلت باهتة وتحتها اسم اللي أكلها
struct CardsMarksRow: View {
    let b: CardsBoardInfo
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(b.marks.enumerated()), id: \.offset) { _, m in
                VStack(spacing: 1) {
                    CardsFace(c: m.card, w: 26, h: 38).opacity(m.by == nil ? 1 : 0.4)
                    Text(trSpoken(m.by ?? " ")).font(.system(size: 9)).foregroundColor(boardTone(b.tone)).lineLimit(1).frame(width: 44)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// صفوف التركس على الطاولة: كل نوع صف، والخانة الفاضية مكان الورقة اللي تنزل بعدها (ذهبية إذا معك)
struct TrixRows: View {
    let rows: [CardsBoardInfo.RowInfo]
    private func slot(_ label: String, _ mine: Bool) -> some View {
        Text(trSpoken(label)).font(.system(size: 9)).foregroundColor(mine ? Palette.gold : Palette.textDim).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 24, height: 34)
            .background(RoundedRectangle(cornerRadius: 6).fill(mine ? Palette.gold.opacity(0.35) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(mine ? Palette.gold : Color.white.opacity(0.33), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows, id: \.id) { r in
                let red = r.id.hasSuffix("H") || r.id.hasSuffix("D")
                HStack(spacing: 6) {
                    Text(trSpoken(r.title)).font(.system(size: 12, weight: .bold)).foregroundColor(red ? Color(red: 0.94, green: 0.6, blue: 0.6) : Palette.text).lineLimit(1).frame(width: 40, alignment: .leading)
                    HStack(spacing: 3) {
                        if let low = r.low { slot(low, r.lowMine) }
                        HStack(spacing: r.cards.count > 6 ? -11 : 2) {
                            ForEach(Array(r.cards.enumerated()), id: \.offset) { _, f in CardsFace(c: f, w: 24, h: 34) }
                        }
                        if let high = r.high { slot(high, r.highMine) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText(r.text))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

/// ظهر الورقة (كومة السحب)
private struct CardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(LinearGradient(colors: [Color(red: 0.48, green: 0.18, blue: 0.18), Color(red: 0.29, green: 0.10, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.91, green: 0.84, blue: 0.65), lineWidth: 2))
            .frame(width: 40, height: 58)
    }
}

/// الكنكان: كومة السحب (مقلوبة) وكومة الأرض (آخر ورقة مكشوفة)، وتنضغط إذا تقدر تسحب منها
struct KonkanHeaps: View {
    let stock: CardsBoardInfo.Heap?, discard: CardsBoardInfo.Heap?
    let onStock: () -> Void, onDiscard: () -> Void
    var body: some View {
        HStack(spacing: 28) {
            if let st = stock {
                Button(action: onStock) {
                    VStack(spacing: 2) {
                        ZStack { CardBack(); CardBack().offset(x: 3, y: 3) }
                        Text(trSpoken("السحب \(st.count)")).font(.system(size: 10)).foregroundColor(Palette.textDim)
                    }
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(st.can ? Palette.gold : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain).disabled(!st.can)
                .accessibilityElement(children: .ignore).accessibilityLabel(spokenText(st.text)).accessibilityAddTraits(st.can ? .isButton : [])
            }
            if let d = discard {
                Button(action: onDiscard) {
                    VStack(spacing: 2) {
                        if let card = d.card { CardsFace(c: card, w: 40, h: 58) }
                        else { RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.33), lineWidth: 1).frame(width: 40, height: 58) }
                        Text(trSpoken("الأرض \(d.count)")).font(.system(size: 10)).foregroundColor(Palette.textDim)
                    }
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(d.can ? Palette.gold : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain).disabled(!d.can)
                .accessibilityElement(children: .ignore).accessibilityLabel(spokenText(d.text)).accessibilityAddTraits(d.can ? .isButton : [])
            }
        }
    }
}

/// شريط الفتح في الكنكان: مجموع تنزيلك من الـ51 (يصير أخضر لما يكمل)
struct KonkanProgress: View {
    let p: CardsBoardInfo.Progress
    var body: some View {
        let done = p.value >= p.need
        let frac = min(1, max(0, CGFloat(p.value) / CGFloat(max(p.need, 1))))
        let color = done ? Color(red: 0.50, green: 0.81, blue: 0.60) : Palette.gold
        VStack(alignment: .leading, spacing: 3) {
            Text(trSpoken(p.text)).font(.system(size: 12)).foregroundColor(done ? color : Palette.goldSoft).lineLimit(2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.13))
                    Capsule().fill(color).frame(width: g.size.width * frac)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText(p.text))
    }
}


/// الشايب: أوراق اللي تسحب منه مقلوبة صغيرة فوق الطاولة. تضغط وحدة: تنقلب (3D) وتنزل لأوراقك وتنرسل الحركة.
/// قارئ الشاشة: عنصر واحد «اسحب من فلان»، والإجراءات «كرت 1، كرت 2…».
struct ShayebDrawRow: View {
    let d: CardsBoardInfo.Draw
    let onPick: (Int) -> Void
    @State private var picked: Int?
    private func pick(_ i: Int) {
        guard picked == nil else { return }
        // صوت السحب على طول وقت الضغط (ما ينعاد لما يوصل رد الخادم)
        Sounds.shared.cardsFx(["c-draw"], won: nil); Sounds.shared.markLocal("cards")
        withAnimation(.easeIn(duration: 0.3)) { picked = i }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onPick(i); picked = nil }
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(trSpoken("اسحب من \(d.name)")).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.goldSoft)
            HStack(spacing: d.count > 9 ? -8 : 4) {
                ForEach(0..<d.count, id: \.self) { i in
                    let on = picked == i
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [Color(red: 0.48, green: 0.18, blue: 0.18), Color(red: 0.29, green: 0.10, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Palette.gold : Color(red: 0.91, green: 0.84, blue: 0.65), lineWidth: 1.5))
                        .frame(width: 26, height: 38)
                        .rotation3DEffect(.degrees(on ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .scaleEffect(on ? 1.25 : 1)
                        .offset(y: on ? 60 : 0)
                        .onTapGesture { pick(i) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText("اسحب من \(d.name): معه \(d.count) \(d.count == 1 ? "ورقة" : "أوراق") مقلوبة. اختر كرت من الإجراءات"))
        .accessibilityActions {
            ForEach(0..<d.count, id: \.self) { i in Button(tr("كرت \(i + 1)")) { pick(i) } }
        }
    }
}
