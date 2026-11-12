import Foundation

/// نصوص القراءة السريعة في البلوت — نفس صياغة التطبيق الحالي
struct BalootText {
    let view: TableView
    let g: GameView
    let shownTrick: [PlayedCard]
    private var mySeat: Int? { view.mySeat }
    private var me: Int { view.mySeat ?? 0 }

    /// الأكلة اللي على الشاشة (بعد آخر ورقة تبقى الأكلة المنتهية ظاهرة لحظة)
    private var shownTrickNo: Int { g.trick.isEmpty && !shownTrick.isEmpty ? g.trickNo - 1 : g.trickNo }
    /// المشاريع تنكشف وتنقرأ في اللفة الثانية فقط
    var revealing: Bool { g.phase == "playing" && shownTrickNo == 1 }
    /// أوراق مشروع هذا المقعد المكشوفة (في اللفة الثانية فقط)
    func faces(_ seat: Int) -> [Card] { revealing ? g.declared.filter { $0.seat == seat }.flatMap(\.faces) : [] }

    func name(_ s: Int) -> String { view.seat(s)?.username ?? "مقعد \(s + 1)" }
    private func teamWord(_ s: Int) -> String { mySeat == nil ? "فريق \(name(s))" : teamOf(s) == teamOf(me) ? "فريقك" : "الخصم" }

    /// الأوراق الموجودة على الطاولة الآن ومن لعب كل ورقة، بالترتيب
    func trick() -> String {
        // القراءة دائماً للأكلة الحالية (لا الأكلة السابقة الظاهرة لحظة على الشاشة)
        if !g.trick.isEmpty { return g.trick.map { "\(name($0.seat)): \($0.card.label)" }.joined(separator: "، ") }
        if (g.phase == "bidding" || g.phase == "doubling" || g.phase == "waraq"), let q = g.qaba { return "ورقة الأرض: \(q.label)" }
        return "لا توجد أوراق على الطاولة"
    }

    /// نوع اللعب يبقى مكتوب ومقروء طول الجولة (حتى بعد توزيع كل الأوراق)
    var contractHidden: Bool { false }

    /// نوع اللعب: من اشترى، وعلى ماذا، والدبل
    func contract() -> String {
        guard let c = g.contract else {
            let ground = g.qaba.map { "، ورقة الأرض \($0.label)" } ?? ""
            // اشترى أحد وما تأكد بعد (حكم ينتظر التأكيد، صن/أشكل ممكن ياخذه اللي قبله، حكم ثاني)
            if let p = g.pendingBuy {
                let kind = ["sun": "صن", "ashkal": "أشكل", "secondHokm": "حكم ثاني"][p.kind] ?? "حكم"
                let who = p.seat == mySeat ? "أنت اشتريت \(kind)" : "\(name(p.seat)) اشترى \(kind)، \(teamWord(p.seat))"
                return "\(who)\(ground)، \(start())"
            }
            return "لم يشترِ أحد بعد، اللفة \(g.bidRound == 1 ? "الأولى" : "الثانية")\(ground)، \(start())"
        }
        let mode = c.mode == "sun" ? "صن" : "حكم \(SUIT_NAMES[c.trump ?? ""] ?? "")"
        var parts = [c.buyer == mySeat ? "أنت اشتريت \(mode)" : "\(name(c.buyer)) اشترى \(mode)، \(teamWord(c.buyer))"]
        if c.qabaTo != c.buyer { parts.append("ورقة الأرض لـ\(c.qabaTo == mySeat ? "ك" : name(c.qabaTo))") }
        parts.append(start())
        let d = g.doubling
        if d.gahwa { parts.append("قهوة" + by()) }
        else if d.level > 1 {
            let label = [2: "دبل", 3: "ثري", 4: "فور"][d.level] ?? ""
            parts.append(label + by() + (c.mode == "hokm" ? (d.locked ? " مقفل" : " مفتوح") : ""))
        } else { parts.append("بدون دبل") }
        return parts.joined(separator: "، ")
    }

    /// البداية (أول من يلعب) عند اللاعب اللي بعد الموزّع
    private func start() -> String {
        let first = (g.dealer + 1) % 4
        return first == mySeat ? "البداية عندك" : "البداية عند \(name(first))"
    }

    /// المشاريع: في اللفة الأولى مين عنده مشروع ونوعه (سرا، خمسين، مية) بلا تفاصيل، وفي اللفة الثانية
    /// نوعه وأوراقه بعد ما ينكشف، وبعد اللفة الثانية تنمسح
    func projects() -> String {
        let active = g.phase == "playing" && shownTrickNo <= 1
        var lines = (active ? g.declared : []).map { d -> String in
            let who = d.seat == mySeat ? "أنت" : name(d.seat)
            if let cards = d.cards {
                return "\(who): " + d.kinds.enumerated().map { i, k in cards[safe: i].map { "\(k): \($0)" } ?? k }.joined(separator: "، و")
            }
            if d.cancelled { return "\(who): أُلغي المشروع" }
            return "\(who): \(d.kinds.joined(separator: " و"))"
        }
        if let b = g.balootSeat { lines.append("\(b == mySeat ? "أنت" : name(b)): بلوت") }
        let projects = lines.isEmpty ? "لا توجد مشاريع معلنة" : lines.joined(separator: ". ")
        return g.phase == "playing" ? "\(projects). \(tricks())" : projects
    }

    /// عدد الأكلات لكل فريق في الصكة الحالية (لنا ولهم، وللمشاهد بأسماء الفريقين)
    func tricks() -> String {
        let w = g.tricksWon, a = w.count > 0 ? w[0] : 0, b = w.count > 1 ? w[1] : 0
        if mySeat == nil { return "الأكلات: فريق \(name(0)) و\(name(2)) \(a)، فريق \(name(1)) و\(name(3)) \(b)" }
        let mine = teamOf(me) == 0 ? a : b, theirs = teamOf(me) == 0 ? b : a
        return "الأكلات: لنا \(mine)، لهم \(theirs)"
    }

    /// دور مين الآن، وفي أي مرحلة
    func turn() -> String {
        if g.phase == "matchOver" { return "انتهت المباراة" }
        let who = g.turn == mySeat ? "دورك" : "دور \(name(g.turn))"
        switch g.phase {
        case "bidding": return who
        case "doubling": return g.myTurn ? "دورك تقرر الدبل" : "بانتظار قرار الدبل"
        case "waraq": return g.myTurn ? "دورك: بس أو ورق" : "بانتظار \(name(g.turn)): بس أو ورق"
        default: return "\(who) في اللعب"
        }
    }

    /// مين قال آخر دبل: الدبل والفور من المدبّل، والثري والقهوة من المشتري
    private func lastDoubler() -> Int? {
        guard let c = g.contract else { return nil }
        let d = g.doubling
        if d.level <= 1 { return nil }
        return !d.gahwa && d.level % 2 == 0 ? d.doubler : c.buyer
    }
    private func by() -> String {
        guard let s = lastDoubler() else { return "" }
        return s == mySeat ? " منك" : " من \(name(s))"
    }

    func statusLine() -> String? {
        guard let c = g.contract else { return nil }
        let mode = c.mode == "sun" ? "صن" : "حكم \(SUIT_NAMES[c.trump ?? ""] ?? "") \(SUIT_SYMBOLS[c.trump ?? ""] ?? "")"
        let level = g.doubling.gahwa ? "قهوة" : [2: "دبل", 3: "ثري", 4: "فور"][g.doubling.level]
        let lock = c.mode == "hokm" && g.doubling.level > 1 && !g.doubling.gahwa ? (g.doubling.locked ? " (مقفل)" : " (مفتوح)") : ""
        // المشتري ونوع اللعب جنبه، طول الجولة
        let kind = c.mode == "sun" && c.qabaTo != c.buyer ? "أشكل" : mode
        return "المشتري \(name(c.buyer)) — \(kind)\(level.map { " — \($0)\(by())" } ?? "")\(lock)"
    }
}
