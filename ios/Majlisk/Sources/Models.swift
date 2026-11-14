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
/// ترتيب يدك من اليمين لليسار: هاص، شريا، ديمن، سبيت (اللي ما معك منه يُتخطّى)،
/// وفي كل لون الأكبر يمين ثم الأصغر. الأوراق تُرسم من اليسار لليمين، فنرجعها مقلوبة.
private let HAND_SUITS_LTR = ["S", "D", "C", "H"]
func sortHand(_ hand: [Card]) -> [Card] {
    hand.sorted { a, b in
        let sa = HAND_SUITS_LTR.firstIndex(of: a.suit) ?? 0, sb = HAND_SUITS_LTR.firstIndex(of: b.suit) ?? 0
        if sa != sb { return sa < sb }
        return (RANK_ORDER.firstIndex(of: a.rank) ?? 0) > (RANK_ORDER.firstIndex(of: b.rank) ?? 0)
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
        case "double": return "دبل"
        case "hokm": return "حكم \(SUIT_NAMES[suit ?? ""] ?? "") \(SUIT_SYMBOLS[suit ?? ""] ?? "")"
        default: return type
        }
    }
}

func teamOf(_ seat: Int) -> Int { seat % 2 }

struct SeatInfo: Equatable { let username: String; let isBot: Bool; let away: Bool }
struct Person: Equatable { let uid: String; let username: String }
struct VoiceMember: Equatable {
    let uid: String; let username: String; let sessionId: String; let muted: Bool; let mic: Bool; let blocked: Bool
    /// قائمة المحادثة الصوتية (من الحالة كاملة، أو من رسالة «voice» الخفيفة)
    static func list(_ a: [JSON]) -> [VoiceMember] {
        a.map { VoiceMember(uid: $0.str("uid"), username: $0.str("username"), sessionId: $0.str("sessionId"), muted: $0.bool("muted"), mic: $0.bool("mic"), blocked: $0.bool("blocked")) }
    }
}
struct PlayedCard: Equatable { let seat: Int; let card: Card }
struct Contract: Equatable { let mode: String; let trump: String?; let buyer: Int; let qabaTo: Int }
struct Doubling: Equatable {
    let level: Int; let gahwa: Bool; let locked: Bool
    /** مين يقرر الدبل الحين: لاعب واحد، أو فريق (إلا اللي قال بس)، وما فيه أحد وقت اختيار مقفل/مفتوح */
    var awaitingSeat: Int? = nil, awaitingTeam: Int? = nil, passed: [Int] = [], lockPending: Int? = nil
    /// أول من دبّل (الثري والقهوة من المشتري، والفور من المدبّل)
    var doubler: Int? = nil
    var deciders: [Int] {
        if lockPending != nil { return [] }
        if let s = awaitingSeat { return [s] }
        guard let t = awaitingTeam else { return [] }
        return [t, t + 2].filter { !passed.contains($0) }
    }
    /** اسم الخيار: دبل، ثري، فور، قهوة */
    var label: String { ["دبل", "دبل", "ثري", "فور", "قهوة"][min(max(level, 1), 4)] }
}
struct Declared: Equatable { let seat: Int; let kinds: [String]; let cards: [String]?; let cancelled: Bool; var faces: [Card] = [] }
struct LastHand: Equatable { let points: [Int]; let kaboot: Int? }

struct GameActions {
    let bids: [Bid]
    let doubleLabel: String?
    let canPassDouble: Bool
    let chooseLock: Bool
    let legal: [Card]
    /// سوا: دورك تبدأ الأكلة وكل أوراقك مضمونة تاكل
    var canSawa = false
    /// «ورق»: الزر يطلع، وwaraqDecision = دورك تختار بس أو ورق (بعد الشراء)
    var canWaraq = false
    var waraqDecision = false
    /// إعلان المشروع (يدوي): دورك في اللفة الأولى ومعك مشروع ما أعلنته
    var canProject = false
    /// القيد والقطع: أنواع المشروع اللي تقدر تعلنها، وفرش أوراق مشروعك، واللي تقدر تسجّل عليهم
    var declareKinds: [String] = []
    var canShowProject = false
    var qaidTargets: [Int] = []
}

struct GameView {
    let phase: String
    let scores: [Int]
    let turn: Int
    /// الموزّع: البداية (أول من يلعب) عند اللاعب اللي بعده
    let dealer: Int
    let qaba: Card?
    let bidRound: Int
    let contract: Contract?
    let doubling: Doubling
    let trick: [PlayedCard]
    let lastTrick: [PlayedCard]?
    let trickNo: Int
    /// كم أكلة لكل فريق في الصكة الحالية
    var tricksWon: [Int] = [0, 0]
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
    /// من اشترى الحكم الثاني (قبل وبعد ما يحدد اللون)
    let secondHokmSeat: Int?
    /// مهلة ما بعد التوزيع: الدور ما بدأ بعد (ما ينعلن «دور فلان» لين تخلص)
    var dealing = false
    /// شراء ما تأكد بعد: (المقعد، hokm/sun/ashkal/secondHokm)
    var pendingBuy: (seat: Int, kind: String)? = nil
    /// «سوا»: أوراق الكل الباقية مكشوفة (كل لاعب قدامه أوراقه) لين تنحسب الصكة
    var sawaHands: [[Card]]? = nil
    /// القيد: أنواع المشاريع اللي أعلنها اللاعبين (صوت المشروع يشتغل أول ما ينعلن)
    var kindDeclared: [String] = []

    var myTurn: Bool {
        !actions.bids.isEmpty || actions.doubleLabel != nil || actions.canPassDouble || actions.chooseLock || !actions.legal.isEmpty || actions.waraqDecision
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
    var voice: [VoiceMember]
    let voiceBlocked: [String]
    let game: GameView?
    let kind: String
    let variant: String
    /// لعبة غير البلوت بدأت (الدومينو أو الجاكارو أو اللودو)
    let otherGame: Bool
    let history: [HandRecord]
    let domino: DominoView?
    let jackaroo: JackarooView?
    let ludo: LudoView?
    /// كم لاعب يقدر يبدأ اللعبة
    let startCounts: [Int]
    /// مؤقت الدور: الثواني المختارة (٠ = بدون)، واللي عليه الوقت، ومتى يخلص وقته (بساعة الجوال)
    var clockLimit = 0
    var clockSeat: Int?
    var clockDeadline: Date?
    /// خيارات اللعبة من صفحة المقاعد: فرق، كمبلكس، هدف الدومينو
    let optTeams: Bool, optComplex: Bool, optTarget: Int
    /// اسم مالك الطاولة
    let ownerName: String
    /// خيارات مباراة البلوت (الباقة الاحترافية): إعلان المشاريع يدوي، والقيد والقطع
    var manualProjects = false
    var qaid = false
    /// زر سوا مسموح في هالمباراة
    var sawaOn = true
    /// كل اللاعبين مشتركين: المالك يقدر يغير المؤقت أثناء اللعب
    var allPro = false
    /// عنوان الطاولة: اسم اللعبة (والدومينو بهدفه)
    var title: String { kind == "domino" ? "دومينو \(optTarget)" : gameTitle(kind, variant) }

    var hasGame: Bool { game != nil || otherGame }
    var playing: Bool {
        (game != nil && game!.phase != "matchOver") || (domino != nil && domino!.phase != "matchOver") || jackaroo?.phase == "playing" || (ludo != nil && ludo!.phase != "over")
    }
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
        voice = VoiceMember.list(o.objs("voice"))
        voiceBlocked = o.strs("voiceBlocked")
        game = o.obj("game").map(TableView.parseGame)
        kind = o.str("kind", "baloot")
        variant = o.str("variant", "classic")
        otherGame = ["domino", "jackaroo", "ludo"].contains { o.obj($0) != nil }
        history = o.objs("history").map(TableView.parseRecord)
        let ui = o.obj("ui") ?? [:]
        domino = o.obj("domino").map { DominoView($0, ui, log: o.objs("dominoLog")) }
        jackaroo = o.obj("jackaroo").map { JackarooView($0, ui, mySeat: o.intOrNil("mySeat")) }
        let counts = o.ints("startCounts"); startCounts = counts.isEmpty ? [4] : counts
        let clock = o.obj("clock") ?? [:]
        clockLimit = clock.int("limit")
        clockSeat = clock.intOrNil("seat")
        // الباقي من لحظة وصول الحالة (ما نعتمد على ساعة الخادم)
        clockDeadline = (clock["remainingMs"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue / 1000) }
        let opts = o.obj("options") ?? [:]
        optTeams = opts.bool("teams"); optComplex = opts.bool("complex"); optTarget = opts.int("target", 100)
        ownerName = o.str("ownerName")
        manualProjects = o.bool("manualProjects")
        qaid = o.bool("qaid")
        sawaOn = (o["sawaOn"] as? Bool) ?? true
        allPro = o.bool("allPro")
        ludo = o.obj("ludo").map { LudoView($0, ui, log: o.strs("ludoLog")) }
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
            dealer: g.int("dealer"),
            qaba: Card(g.obj("qaba")),
            bidRound: g.int("bidRound", 1),
            contract: g.obj("contract").map { Contract(mode: $0.str("mode"), trump: $0.strOrNil("trump"), buyer: $0.int("buyer"), qabaTo: $0.int("qabaTo")) },
            doubling: Doubling(level: d.int("level", 1), gahwa: d.bool("gahwa"), locked: d.bool("locked"), awaitingSeat: d.intOrNil("awaitingSeat"), awaitingTeam: d.intOrNil("awaitingTeam"), passed: d.ints("passed"), lockPending: d.intOrNil("lockPending"), doubler: d.intOrNil("doubler")),
            trick: played(g.objs("trick")),
            lastTrick: g.obj("lastTrick").map { played($0.objs("cards")) },
            trickNo: g.int("trickNo"),
            tricksWon: g.ints("tricksWon"),
            lastHand: g.obj("lastHand").map { LastHand(points: $0.ints("points"), kaboot: $0.intOrNil("kaboot")) },
            outcomeStatus: outcome.str("status", "ongoing"),
            outcomeWinner: outcome.intOrNil("winner"),
            handCounts: g.ints("handCounts"),
            myHand: g.objs("myHand").compactMap { Card($0) },
            balootSeat: g.intOrNil("balootSeat"),
            projectsWinningTeam: g.obj("projects")?.intOrNil("winningTeam"),
            declared: g.objs("declared").map {
                Declared(seat: $0.int("seat"), kinds: $0.strs("kinds"), cards: $0["cards"] == nil || $0["cards"] is NSNull ? nil : $0.strs("cards"), cancelled: $0.bool("cancelled"), faces: $0.objs("faces").compactMap { Card($0) })
            },
            actions: GameActions(
                bids: a.objs("bids").map { Bid(type: $0.str("type"), suit: $0.strOrNil("suit"), raw: $0) },
                doubleLabel: a.obj("double")?.str("label"),
                canPassDouble: a.bool("canPassDouble"),
                chooseLock: a.bool("chooseLock"),
                legal: a.objs("legal").compactMap { Card($0) },
                canSawa: a.bool("canSawa"),
                canWaraq: a.bool("canWaraq"),
                waraqDecision: a.bool("waraqDecision"),
                canProject: a.bool("canProject"),
                declareKinds: a.arr("declareKinds").compactMap { $0 as? String },
                canShowProject: a.bool("canShowProject"),
                qaidTargets: a.arr("qaidTargets").compactMap { ($0 as? NSNumber)?.intValue }
            ),
            hokmBidKey: hokmBid.map { "\($0.int("seat"))\($0.str("suit"))" },
            secondHokmSeat: g.intOrNil("secondHokmSeat"),
            dealing: g.bool("dealing"),
            pendingBuy: g.obj("pendingBuy").map { (seat: $0.int("seat"), kind: $0.str("kind")) },
            sawaHands: g.obj("sawaReveal").map { r in r.arr("hands").map { (($0 as? [Any]) ?? []).compactMap { ($0 as? JSON).flatMap { Card($0) } } } },
            kindDeclared: g.objs("kindDeclared").map { $0.str("kind") }
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
