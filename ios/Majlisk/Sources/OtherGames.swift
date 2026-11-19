import Foundation

// الدومينو والجاكارو واللودو: حالة اللعبة من الخادم، ومعها "ui" (الحركات المسموحة ونصوصها
// وقراءات اللوحة) محسوبة في الخادم لهذا اللاعب، فالتطبيق يرسم ويعرض الأزرار ويرسل الحركة كما هي.

/// بصمة ثابتة لجزء من الحالة (للأصوات)
func jsonSig(_ x: Any?) -> String {
    guard let x, JSONSerialization.isValidJSONObject(x),
          let d = try? JSONSerialization.data(withJSONObject: x, options: [.sortedKeys]) else { return "\(x ?? "null")" }
    return String(data: d, encoding: .utf8) ?? ""
}

// ───── الدومينو ─────

struct Tile: Equatable {
    let a: Int, b: Int
    init(a: Int, b: Int) { self.a = a; self.b = b }
    init(_ o: JSON?) { a = o?.int("a") ?? 0; b = o?.int("b") ?? 0 }
    var json: JSON { ["a": a, "b": b] }
    var isDouble: Bool { a == b }
}

struct PlacedTile { let tile: Tile; let seat: Int; let outer: Int; let side: String }
struct DominoHandTile: Identifiable { let id: Int; let tile: Tile; let label: String; let legal: Bool; let askSide: Bool }

struct DominoView {
    let phase: String, turn: Int, players: Int, target: Int
    let scores: [Int]
    let line: [PlacedTile]
    var handCounts: [Int]
    let boneyard: Int
    let moveSig: String
    let lastKind: String?
    /// صاحب آخر حركة (-1 لو ما فيه)
    let lastSeat: Int
    /// زر «قفلة»: تقدر تعلنها الحين، وهل أعلنتها (normal / double)، ونص القفلة القائمة
    let canLock: Bool
    let myLockCall: String?
    let lockText: String
    /// قفلة معلنة الحين (أي لاعب): مقعده ونوعها — للصوت عند كل اللاعبين
    let lockCallSeat: Int
    let lockCallDouble: Bool
    /// نوع نهاية آخر صكة (domino / blocked / lock / lockWrong / ghashim)
    let handKind: String
    var myTurn: Bool, canDraw: Bool, canPass: Bool
    var hand: [DominoHandTile]
    let ends: (left: Int, right: Int)?
    let endsText: String, lineText: String, scoreText: String
    let sideNames: [String]
    let mySide: Int
    var prompt: String
    /// سجل كل جولة (صكة): رقمها وحركاتها بالترتيب
    let log: [(hand: Int, lines: [String])]
    /// من يختار البادئ (بعد فوز فريقه بالصكة)، وخياراتك لو الاختيار لك
    let chooser: Int?
    let starterOptions: [(seat: Int, text: String)]

    init(_ s: JSON, _ ui: JSON, log: [JSON] = []) {
        let rules = s.obj("rules") ?? [:]
        phase = s.str("phase"); turn = s.int("turn")
        players = rules.int("players", 4); target = rules.int("target", 100)
        scores = s.ints("scores")
        line = s.objs("line").map { PlacedTile(tile: Tile($0.obj("tile")), seat: $0.int("seat"), outer: $0.int("outer"), side: $0.str("side")) }
        handCounts = s.arr("hands").map { ($0 as? [Any])?.count ?? 0 }
        boneyard = s.arr("boneyard").count
        // عدد البنك داخل البصمة: كل سحبة تتغير فيها (لو سحب نفس اللاعب مرتين ورا بعض يطلع الصوت كل مرة)
        moveSig = jsonSig(s["lastMove"]) + "|\(s.str("phase"))|\(s.int("handNo"))|\(s.arr("boneyard").count)"
        lastKind = s.obj("lastMove")?.str("kind")
        lastSeat = s.obj("lastMove")?.int("seat", -1) ?? -1
        canLock = ui.bool("canLock")
        myLockCall = ui["myLockCall"] as? String
        lockText = ui.str("lockText")
        lockCallSeat = s.obj("lockCall")?.int("seat", -1) ?? -1
        lockCallDouble = s.obj("lockCall")?.bool("double") ?? false
        handKind = s.obj("lastHand")?.str("kind") ?? ""
        myTurn = ui.bool("myTurn"); canDraw = ui.bool("canDraw"); canPass = ui.bool("canPass")
        hand = ui.objs("hand").enumerated().map { i, h in
            DominoHandTile(id: i, tile: Tile(h.obj("tile")), label: h.str("label"), legal: h.bool("legal"), askSide: h.bool("askSide"))
        }
        ends = ui.obj("ends").map { (left: $0.int("left"), right: $0.int("right")) }
        endsText = ui.str("endsText"); lineText = ui.str("lineText"); scoreText = ui.str("scoreText")
        sideNames = ui.strs("sideNames"); mySide = ui.int("mySide", -1); prompt = ui.str("prompt")
        self.log = log.map { (hand: $0.int("hand"), lines: $0.strs("lines")) }
        chooser = s.intOrNil("chooser")
        starterOptions = ui.objs("starterOptions").map { (seat: $0.int("seat"), text: $0.str("text")) }
    }
}

// ───── الجاكارو ─────

struct Marble { let zone: String; let pos: Int }

struct JackarooCard: Equatable {
    let rank: String, suit: String
    var json: JSON { ["rank": rank, "suit": suit] }
    var red: Bool { suit == "H" || suit == "D" }
    var symbol: String { ["S": "♠", "H": "♥", "D": "♦"][suit] ?? "♣" }
}

struct JackarooMove: Identifiable { let id: Int; let move: JSON; let text: String }
struct JackarooHandCard: Identifiable { let id: Int; let card: JackarooCard; let label: String; let usable: Bool; let moves: [JackarooMove] }

struct JackarooView {
    let phase: String, turn: Int
    let winnerTeam: Int?
    let dealNo: Int, segment: Int
    let marbles: [[Marble]]
    var handCounts: [Int]
    let moveSig: String
    let hasMove: Bool
    /// كم خطوة مشت آخر حركة (لصوت النقرات)
    let lastSteps: Int
    /// كم حجر انأكل في آخر حركة (لصوت الأكل)
    let captures: Int
    /// نوع آخر حركة (back = رجوع ٤، swap = تبديل)، وكم حجر دخل منطقة الأمان (للأصوات)
    var lastKind = ""
    var enteredSafe = 0
    var myTurn: Bool, burning: Bool
    var hand: [JackarooHandCard]
    let boardText: String, oppText: String, mineText: String
    var prompt: String
    /// الأوراق الملعوبة في هذا التوزيع بالترتيب
    let pile: [JackarooCard]
    /// المقاعد اللي تلعب (لاعبين أو ثلاثة أو أربعة)، وفريقين أو كل واحد لنفسه، والفائز في الفردي
    let active: [Int]
    let teams: Bool
    let winner: Int?
    /// أوراق اللفة الحالية في وسط الطاولة: تتجمع حتى عدد اللاعبين، ثم تنمسح وتبدأ اللفة التالية
    var centerCards: [JackarooCard] { pile.isEmpty ? [] : Array(pile.suffix((pile.count - 1) % max(active.count, 1) + 1)) }
    /// عدد أحجار لاعب في منطقة الأمان
    func safeOf(_ o: Int) -> Int { o < marbles.count ? marbles[o].filter { $0.zone == "safe" }.count : 0 }

    func safeCount(_ team: Int) -> Int {
        [team, team + 2].reduce(0) { n, o in n + (o < marbles.count ? marbles[o].filter { $0.zone == "safe" }.count : 0) }
    }

    init(_ s: JSON, _ ui: JSON, mySeat: Int?) {
        let rules = s.obj("rules") ?? [:]
        phase = s.str("phase"); turn = s.int("turn"); winnerTeam = s.intOrNil("winnerTeam")
        let seats = s.ints("seats")
        active = seats.isEmpty ? [0, 1, 2, 3] : seats
        teams = (s["teams"] as? Bool ?? true) && active.count == 4
        winner = s.intOrNil("winner")
        dealNo = s.int("dealNo"); segment = rules.int("segment", 19)
        marbles = s.arr("marbles").map { (($0 as? [Any]) ?? []).compactMap { $0 as? JSON }.map { Marble(zone: $0.str("zone"), pos: $0.int("pos")) } }
        let hands = s.arr("hands").map { ($0 as? [Any]) ?? [] }
        handCounts = hands.map(\.count)
        moveSig = jsonSig(s["lastMove"]) + "|\(s.int("dealNo"))|\(s.str("phase"))"
        hasMove = s.obj("lastMove") != nil
        captures = s.obj("lastMove")?.objs("captured").count ?? 0
        lastKind = s.obj("lastMove")?.obj("move")?.str("kind") ?? ""
        enteredSafe = s.obj("lastMove")?.objs("enteredSafe").count ?? 0
        if let m = s.obj("lastMove")?.obj("move") {
            switch m.str("kind") {
            case "forward", "back", "kingRun": lastSteps = m.int("steps")
            case "split": lastSteps = m.objs("parts").reduce(0) { $0 + $1.int("steps") }
            case "out", "swap": lastSteps = 1
            default: lastSteps = 0
            }
        } else { lastSteps = 0 }
        myTurn = ui.bool("myTurn"); burning = ui.bool("burning")
        let uiHand = ui.objs("hand")
        let mine: [JSON] = mySeat.flatMap { $0 < hands.count ? hands[$0].compactMap { $0 as? JSON } : nil } ?? []
        hand = mine.enumerated().map { i, c in
            let h = i < uiHand.count ? uiHand[i] : [:]
            return JackarooHandCard(
                id: i, card: JackarooCard(rank: c.str("rank"), suit: c.str("suit")), label: h.str("label"), usable: h.bool("usable"),
                moves: h.objs("moves").enumerated().map { k, m in JackarooMove(id: k, move: m.obj("move") ?? [:], text: m.str("text")) })
        }
        boardText = ui.str("boardText"); oppText = ui.str("oppText"); mineText = ui.str("mineText"); prompt = ui.str("prompt")
        pile = s.objs("pile").map { JackarooCard(rank: $0.str("rank"), suit: $0.str("suit")) }
    }
}

// ───── لودو ─────

struct LudoOption: Identifiable { var id: Int { token * 10 + die }; let token: Int; let die: Int; let text: String }

struct LudoAnimKey: Equatable {
    let moveSig: String, lastSig: String, phase: String
    let owner: Int, index: Int, from: Int, to: Int
    let captured: [[Int]]
}

struct LudoView {
    /// المسار 0..50 (51 خانة)، ممر المنزل 51..55 (5 خانات)، المنزل 56
    static let FINISH = 56, LAST_TRACK = 50
    static let STARTS = [0, 13, 26, 39]
    static let SAFE: Set<Int> = [0, 8, 13, 21, 26, 34, 39, 47]
    static func absPos(_ owner: Int, _ p: Int) -> Int { (STARTS[owner] + p) % 52 }

    let seats: [Int]
    var tokens: [[Int]]
    let turn: Int
    let phase: String
    let dice: Int?, lastRoll: Int?, winner: Int?
    /// نسخة بأماكن أحجار ثانية (للرسم قبل ما تبدأ الحركة)
    func withTokens(_ t: [[Int]]) -> LudoView { var c = self; c.tokens = t; return c }
    /// آخر حركة من السيرفر: أي حجر، من وين لوين، ومين انأكل (الحركة على الشاشة والصوت كلهم منها)
    var lastOwner = -1, lastIndex = -1, lastFrom = -1, lastTo = -1
    var lastCaptured: [[Int]] = []
    /// كل اللي تحتاجه حركة الحجر، في قيمة وحدة (تتغير = حالة جديدة من السيرفر)
    var animKey: LudoAnimKey { LudoAnimKey(moveSig: moveSig, lastSig: lastSig, phase: phase, owner: lastOwner, index: lastIndex, from: lastFrom, to: lastTo, captured: lastCaptured) }
    /// من رمى آخر رمية
    let lastSeat: Int?
    let teams: Bool
    let moveSig: String
    let moved: Bool
    /// بصمة آخر حركة، وكم خطوة مشى الحجر
    let lastSig: String
    let lastSteps: Int
    /// كم حجر انأكل في آخر حركة (لصوت الأكل)
    let captures: Int
    /// آخر حركة وصّلت حجر المنزل (لصوت الدخول)
    var finished = false
    let myTurn: Bool
    let options: [LudoOption]
    let movableOwner: Int
    let boardText: String, mineText: String, prompt: String
    /// سجل الرميات والحركات بالترتيب
    let log: [String]
    /// قائمة الأماكن: كل لاعب (اسمه ولونه) وأحجاره في أي خانة
    let positions: [(name: String, color: Int, tokens: [String])]
    let turnText: String, diceText: String
    let canRoll: Bool
    /// الأرقام المتجمعة بانتظار الحركة (الستة ومعها اللي بعدها)
    let pool: [Int]
    /// آخر رمية من السيرفر: مين رماها وكم، وعدّادها (يزيد مع كل رمية)
    let rolledSeat: Int?, rolledValue: Int?, rollSeq: Int

    func home(_ o: Int) -> Int { o < tokens.count ? tokens[o].filter { $0 == LudoView.FINISH }.count : 0 }

    init(_ s: JSON, _ ui: JSON, log: [String] = []) {
        let last = s.obj("lastMove")
        self.log = log
        positions = ui.objs("positions").map { (name: $0.str("name"), color: $0.int("color"), tokens: $0.strs("tokens")) }
        turnText = ui.str("turnText"); diceText = ui.str("diceText"); canRoll = ui.bool("canRoll")
        pool = ui.ints("pool")
        let rolled = s.obj("lastRolled")
        rolledSeat = rolled?.intOrNil("seat"); rolledValue = rolled?.intOrNil("roll"); rollSeq = rolled?.int("seq") ?? 0
        seats = s.ints("seats")
        tokens = s.arr("tokens").map { (($0 as? [Any]) ?? []).map { ($0 as? NSNumber)?.intValue ?? -1 } }
        turn = s.int("turn"); phase = s.str("phase")
        dice = s.intOrNil("dice"); lastRoll = last?.intOrNil("roll"); winner = s.intOrNil("winner")
        lastSeat = last?.intOrNil("seat")
        teams = s.obj("rules")?.bool("teams") ?? false
        moveSig = jsonSig(s["lastMove"]) + "|\(s.int("turn"))|\(s.str("phase"))|\(s.intOrNil("dice") ?? -1)|\(s.ints("pool"))|\(s.obj("lastRolled")?.int("seq") ?? 0)"
        moved = last?.obj("token") != nil
        lastSig = jsonSig(s["lastMove"])
        captures = last?.objs("captured").count ?? 0
        finished = last?.bool("finished") ?? false
        if let f = last?.intOrNil("from"), let t = last?.intOrNil("to") { lastSteps = f == -1 ? 1 : t - f } else { lastSteps = 0 }
        if let tok = last?.obj("token"), let f = last?.intOrNil("from"), let t = last?.intOrNil("to") {
            lastOwner = tok.int("owner"); lastIndex = tok.int("index"); lastFrom = f; lastTo = t
            lastCaptured = (last?.objs("captured") ?? []).map { [$0.int("owner"), $0.int("index")] }
        }
        myTurn = ui.bool("myTurn")
        options = ui.objs("options").map { LudoOption(token: $0.int("token"), die: $0.int("die", s.int("dice")), text: $0.str("text")) }
        movableOwner = ui.int("movableOwner", -1)
        boardText = ui.str("boardText"); mineText = ui.str("mineText"); prompt = ui.str("prompt")
    }
}
