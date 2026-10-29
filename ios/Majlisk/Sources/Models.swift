import Foundation

/// أسماء الأوراق كما في الخادم (shared/baloot/cards.ts)
let SUITS = ["S", "H", "C", "D"]
let SUIT_NAMES = ["S": "سبيت", "H": "هاص", "C": "شريا", "D": "ديمن"]
let SUIT_SYMBOLS = ["S": "♠", "H": "♥", "C": "♣", "D": "♦"]
let RANK_NAMES = ["A": "أكة", "K": "شايب", "Q": "بنت", "J": "ولد", "10": "10", "9": "9", "8": "8", "7": "7"]
private let RANK_ORDER = ["A", "K", "Q", "J", "10", "9", "8", "7"]

struct Card: Hashable {
    let suit: String
    let rank: String
    var label: String { "\(RANK_NAMES[rank] ?? rank) \(SUIT_NAMES[suit] ?? suit)" }
    var image: String { "\(suit)\(rank)" }
    var json: JSON { ["suit": suit, "rank": rank] }
    init(suit: String, rank: String) { self.suit = suit; self.rank = rank }
    init?(_ o: JSON?) {
        guard let o, let s = o["suit"] as? String, let r = o["rank"] as? String else { return nil }
        suit = s; rank = r
    }
}

/// ترتيب اليد: حسب اللون ثم الرتبة
func sortHand(_ hand: [Card]) -> [Card] {
    hand.sorted { a, b in
        let sa = SUITS.firstIndex(of: a.suit) ?? 0, sb = SUITS.firstIndex(of: b.suit) ?? 0
        if sa != sb { return sa < sb }
        return (RANK_ORDER.firstIndex(of: a.rank) ?? 0) < (RANK_ORDER.firstIndex(of: b.rank) ?? 0)
    }
}

/// مزايدة: نحتفظ بالكائن كما أرسله الخادم لنعيده كما هو
struct Bid: Identifiable {
    let type: String
    let suit: String?
    let raw: JSON
    var id: String { label }
    var label: String {
        switch type {
        case "pass": return "بس"
        case "sun": return "صن"
        case "ashkal": return "أشكل"
        case "secondHokm": return "حكم ثاني"
        case "qablak": return "قبلك"
        case "confirmHokm": return "تأكيد الحكم"
        case "hokm": return "حكم \(SUIT_NAMES[suit ?? ""] ?? "") \(SUIT_SYMBOLS[suit ?? ""] ?? "")"
        default: return type
        }
    }
}

func teamOf(_ seat: Int) -> Int { seat % 2 }

struct SeatInfo: Equatable { let username: String; let isBot: Bool; let away: Bool }
struct Person: Equatable { let uid: String; let username: String }
struct VoiceMember: Equatable { let uid: String; let username: String; let sessionId: String; let muted: Bool; let mic: Bool; let blocked: Bool }
struct PlayedCard: Equatable { let seat: Int; let card: Card }
struct Contract: Equatable { let mode: String; let trump: String?; let buyer: Int; let qabaTo: Int }
struct Doubling: Equatable { let level: Int; let gahwa: Bool; let locked: Bool }
struct Declared: Equatable { let seat: Int; let kinds: [String]; let cards: [String]?; let cancelled: Bool }
struct LastHand: Equatable { let points: [Int]; let kaboot: Int? }

struct GameActions {
    let bids: [Bid]
    let doubleLabel: String?
    let canPassDouble: Bool
    let chooseLock: Bool
    let legal: [Card]
}

struct GameView {
    let phase: String
    let scores: [Int]
    let turn: Int
    let qaba: Card?
    let bidRound: Int
    let contract: Contract?
    let doubling: Doubling
    let trick: [PlayedCard]
    let lastTrick: [PlayedCard]?
    let trickNo: Int
    let lastHand: LastHand?
    let outcomeStatus: String
    let outcomeWinner: Int?
    let handCounts: [Int]
    let myHand: [Card]
    let balootSeat: Int?
    let projectsWinningTeam: Int?
    let declared: [Declared]
    let actions: GameActions
    let hokmBidKey: String?

    var myTurn: Bool {
        !actions.bids.isEmpty || actions.doubleLabel != nil || actions.canPassDouble || actions.chooseLock || !actions.legal.isEmpty
    }
}

struct HandRecord {
    let match: Int
    let projects: [Int]?
    let teams: [String]
    let contract: String
    let level: Int
    let gahwa: Bool
    let buyer: String
    let buyerTeam: Int
    let abnat: [Int]
    let points: [Int]
    let buyerFailed: Bool
    let kaboot: Int?
}

/// حالة الطاولة كما يرسلها الخادم لكل شخص (shared/table.ts → viewFor)
struct TableView {
    let id: String
    let ownerUid: String
    let isPrivate: Bool
    let mySeat: Int?
    let seats: [SeatInfo?]
    let seatUids: [String]
    let spectators: [Person]
    let voice: [VoiceMember]
    let voiceBlocked: [String]
    let game: GameView?
    let kind: String
    let variant: String
    /// لعبة غير البلوت بدأت (الدومينو والجاكارو واللودو تأتي في المرحلة الثانية)
    let otherGame: Bool
    let history: [HandRecord]

    var hasGame: Bool { game != nil || otherGame }
    var playing: Bool { (game != nil && game!.phase != "matchOver") || otherGame }
    func seat(_ i: Int) -> SeatInfo? { i < seats.count ? seats[i] : nil }
    func seatUid(_ i: Int) -> String { i < seatUids.count ? seatUids[i] : "" }

    init(_ o: JSON) {
        id = o.str("id")
        ownerUid = o.str("ownerUid")
        isPrivate = o.bool("isPrivate")
        mySeat = o.intOrNil("mySeat")
        seats = o.arr("seats").map { ($0 as? JSON).map { SeatInfo(username: $0.str("username"), isBot: $0.bool("isBot"), away: $0.bool("away")) } }
        seatUids = o.strs("seatUids")
        spectators = o.objs("spectators").map { Person(uid: $0.str("uid"), username: $0.str("username")) }
        voice = o.objs("voice").map {
            VoiceMember(uid: $0.str("uid"), username: $0.str("username"), sessionId: $0.str("sessionId"), muted: $0.bool("muted"), mic: $0.bool("mic"), blocked: $0.bool("blocked"))
        }
        voiceBlocked = o.strs("voiceBlocked")
        game = o.obj("game").map(TableView.parseGame)
        kind = o.str("kind", "baloot")
        variant = o.str("variant", "classic")
        otherGame = ["domino", "jackaroo", "ludo"].contains { o.obj($0) != nil }
        history = o.objs("history").map(TableView.parseRecord)
    }

    private static func played(_ a: [JSON]) -> [PlayedCard] {
        a.compactMap { p in Card(p.obj("card")).map { PlayedCard(seat: p.int("seat"), card: $0) } }
    }

    private static func parseGame(_ g: JSON) -> GameView {
        let a = g.obj("actions") ?? [:]
        let outcome = g.obj("outcome") ?? [:]
        let d = g.obj("doubling") ?? [:]
        let hokmBid = g.obj("hokmBid")
        return GameView(
            phase: g.str("phase"),
            scores: g.ints("scores"),
            turn: g.int("turn"),
            qaba: Card(g.obj("qaba")),
            bidRound: g.int("bidRound", 1),
            contract: g.obj("contract").map { Contract(mode: $0.str("mode"), trump: $0.strOrNil("trump"), buyer: $0.int("buyer"), qabaTo: $0.int("qabaTo")) },
            doubling: Doubling(level: d.int("level", 1), gahwa: d.bool("gahwa"), locked: d.bool("locked")),
            trick: played(g.objs("trick")),
            lastTrick: g.obj("lastTrick").map { played($0.objs("cards")) },
            trickNo: g.int("trickNo"),
            lastHand: g.obj("lastHand").map { LastHand(points: $0.ints("points"), kaboot: $0.intOrNil("kaboot")) },
            outcomeStatus: outcome.str("status", "ongoing"),
            outcomeWinner: outcome.intOrNil("winner"),
            handCounts: g.ints("handCounts"),
            myHand: g.objs("myHand").compactMap { Card($0) },
            balootSeat: g.intOrNil("balootSeat"),
            projectsWinningTeam: g.obj("projects")?.intOrNil("winningTeam"),
            declared: g.objs("declared").map {
                Declared(seat: $0.int("seat"), kinds: $0.strs("kinds"), cards: $0["cards"] == nil || $0["cards"] is NSNull ? nil : $0.strs("cards"), cancelled: $0.bool("cancelled"))
            },
            actions: GameActions(
                bids: a.objs("bids").map { Bid(type: $0.str("type"), suit: $0.strOrNil("suit"), raw: $0) },
                doubleLabel: a.obj("double")?.str("label"),
                canPassDouble: a.bool("canPassDouble"),
                chooseLock: a.bool("chooseLock"),
                legal: a.objs("legal").compactMap { Card($0) }
            ),
            hokmBidKey: hokmBid.map { "\($0.int("seat"))\($0.str("suit"))" }
        )
    }

    private static func parseRecord(_ r: JSON) -> HandRecord {
        HandRecord(
            match: r.int("match", 1),
            projects: r["projects"] is [Any] ? r.ints("projects") : nil,
            teams: r.strs("teams"),
            contract: r.str("contract"),
            level: r.int("level", 1),
            gahwa: r.bool("gahwa"),
            buyer: r.str("buyer"),
            buyerTeam: r.int("buyerTeam"),
            abnat: r.ints("abnat"),
            points: r.ints("points"),
            buyerFailed: r.bool("buyerFailed"),
            kaboot: r.intOrNil("kaboot")
        )
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
