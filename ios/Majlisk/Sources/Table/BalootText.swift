import Foundation

/// نصوص القراءة السريعة في البلوت — نفس صياغة التطبيق الحالي
struct BalootText {
    let view: TableView
    let g: GameView
    let shownTrick: [PlayedCard]
    private var mySeat: Int? { view.mySeat }
    private var me: Int { view.mySeat ?? 0 }

    func name(_ s: Int) -> String { view.seat(s)?.username ?? "مقعد \(s + 1)" }
    private func teamWord(_ s: Int) -> String { mySeat == nil ? "فريق \(name(s))" : teamOf(s) == teamOf(me) ? "فريقك" : "الخصم" }

    /// الأوراق الموجودة على الطاولة الآن ومن لعب كل ورقة، بالترتيب
    func trick() -> String {
        shownTrick.isEmpty ? "لا توجد أوراق على الطاولة" : shownTrick.map { "\(name($0.seat)): \($0.card.label)" }.joined(separator: "، ")
    }

    /// نوع اللعب: من اشترى، وعلى ماذا، والدبل
    func contract() -> String {
        guard let c = g.contract else {
            let ground = g.qaba.map { "، ورقة الأرض \($0.label)" } ?? ""
            return "لم يشترِ أحد بعد، المزايدة في الجولة \(g.bidRound == 1 ? "الأولى" : "الثانية")\(ground)"
        }
        let mode = c.mode == "sun" ? "صن" : "حكم \(SUIT_NAMES[c.trump ?? ""] ?? "")"
        var parts = [c.buyer == mySeat ? "أنت اشتريت \(mode)" : "\(name(c.buyer)) اشترى \(mode)، \(teamWord(c.buyer))"]
        if c.qabaTo != c.buyer { parts.append("القبلة لـ\(c.qabaTo == mySeat ? "ك" : name(c.qabaTo))") }
        let d = g.doubling
        if d.gahwa { parts.append("قهوة") }
        else if d.level > 1 {
            let label = [2: "دبل", 3: "ثري", 4: "فور"][d.level] ?? ""
            parts.append(label + (c.mode == "hokm" ? (d.locked ? " مقفل" : " مفتوح") : ""))
        } else { parts.append("بدون دبل") }
        return parts.joined(separator: "، ")
    }

    /// المشاريع المعلنة ومن أعلنها (وأوراقها بعد الأكلة الأولى)
    func projects() -> String {
        var lines = g.declared.map { d -> String in
            let who = d.seat == mySeat ? "أنت" : name(d.seat)
            let items = d.kinds.enumerated().map { i, k in d.cards?[safe: i].map { "\(k): \($0)" } ?? k }
            return "\(who): \(items.joined(separator: "، و"))\(d.cancelled ? "، ملغى" : "")"
        }
        if let b = g.balootSeat { lines.append("\(b == mySeat ? "أنت" : name(b)): بلوت") }
        if lines.isEmpty { return "لا توجد مشاريع معلنة" }
        if let w = g.projectsWinningTeam, !g.declared.isEmpty {
            lines.append("المشاريع المحتسبة لـ\(mySeat == nil ? "فريق \(name(w))" : w == teamOf(me) ? "فريقك" : "الخصم")")
        }
        return lines.joined(separator: ". ")
    }

    /// دور مين الآن، وفي أي مرحلة
    func turn() -> String {
        if g.phase == "matchOver" { return "انتهت المباراة" }
        let who = g.turn == mySeat ? "دورك" : "دور \(name(g.turn))"
        switch g.phase {
        case "bidding": return "\(who) في المزايدة"
        case "doubling": return g.myTurn ? "دورك تقرر الدبل" : "بانتظار قرار الدبل"
        default: return "\(who) في اللعب"
        }
    }

    func statusLine() -> String? {
        guard let c = g.contract else { return nil }
        let mode = c.mode == "sun" ? "صن" : "حكم \(SUIT_NAMES[c.trump ?? ""] ?? "") \(SUIT_SYMBOLS[c.trump ?? ""] ?? "")"
        let level = g.doubling.gahwa ? "قهوة" : [2: "دبل", 3: "ثري", 4: "فور"][g.doubling.level]
        let lock = c.mode == "hokm" && g.doubling.level > 1 && !g.doubling.gahwa ? (g.doubling.locked ? " (مقفل)" : " (مفتوح)") : ""
        return "\(mode) — \(name(c.buyer))\(level.map { " — \($0)" } ?? "")\(lock)"
    }
}
