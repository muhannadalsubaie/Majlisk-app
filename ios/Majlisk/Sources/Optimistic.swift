import Foundation

/// اللعب الفوري: لما تلعب ورقة أو قطعة تطلع من يدك على طول (والبلوت تنحط في الأرض) مع صوتها،
/// بدون انتظار رد الخادم. الخادم يتأكد بعدها: لو قبلها توصل حالته وتكمّل، ولو رفضها ترجع الورقة ليدك.
///
/// يرجع دالة تطبّق الحركة على أي حالة (nil لو الحركة ما تنطبق عليها: انلعبت فعلاً أو ما عادت مسموحة).
/// nil من البداية لو هالحركة ما لها لعب فوري (المزايدة، النرد، ...).
enum Optimistic {
    typealias Patch = (TableView) -> TableView?

    static func patch(_ view: TableView, _ msg: JSON) -> Patch? {
        guard let seat = view.mySeat, let action = msg["action"] as? JSON, action.str("type") == "play" else { return nil }
        let minus = { (counts: [Int]) in counts.enumerated().map { $0.offset == seat ? max(0, $0.element - 1) : $0.element } }
        let f: Patch
        switch msg.str("type") {
        case "action":
            guard let c = action.obj("card") else { return nil }
            let card = Card(suit: c.str("suit"), rank: c.str("rank"))
            f = { v in
                guard var g = v.game, g.phase == "playing", g.myHand.contains(card), g.actions.legal.contains(card), g.trick.count < 4 else { return nil }
                var out = v
                g.myHand.removeAll { $0 == card }
                g.trick.append(PlayedCard(seat: seat, card: card))
                g.handCounts = minus(g.handCounts)
                g.actions.legal = []
                g.actions.canSawa = false
                out.game = g
                return out
            }
            // صوتها يطلع من مقارنة الحالات: الحالة الفورية فيها الورقة في الأرض
            return f(view) == nil ? nil : f
        case "domino":
            guard let t = action.obj("tile") else { return nil }
            let tile = Tile(t)
            f = { v in
                guard var d = v.domino, d.myTurn, d.hand.contains(where: { $0.tile == tile && $0.legal }) else { return nil }
                var out = v
                d.hand.removeAll { $0.tile == tile }
                d.handCounts = minus(d.handCounts)
                d.myTurn = false; d.canDraw = false; d.canPass = false; d.prompt = ""
                out.domino = d
                return out
            }
            guard f(view) != nil else { return nil }
            Sounds.shared.dominoTile(); Sounds.shared.markLocal("domino")
            return f
        case "jackaroo":
            guard let c = action.obj("card") else { return nil }
            let card = JackarooCard(rank: c.str("rank"), suit: c.str("suit"))
            f = { v in
                guard var j = v.jackaroo, j.myTurn, let i = j.hand.firstIndex(where: { $0.card == card && $0.usable }) else { return nil }
                var out = v
                j.hand.remove(at: i)
                j.handCounts = minus(j.handCounts)
                j.myTurn = false; j.prompt = ""
                out.jackaroo = j
                return out
            }
            guard f(view) != nil else { return nil }
            Sounds.shared.jackarooCard(); Sounds.shared.markLocal("jackaroo")
            return f
        default:
            return nil
        }
    }
}
