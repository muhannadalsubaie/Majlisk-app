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
    let handCounts: [Int]
    let boneyard: Int
    let moveSig: String
    let lastKind: String?
    let myTurn: Bool, canDraw: Bool, canPass: Bool
    let hand: [DominoHandTile]
    let ends: (left: Int, right: Int)?
    let endsText: String, lineText: String, scoreText: String
    let sideNames: [String]
    let mySide: Int
    let prompt: String

    init(_ s: JSON, _ ui: JSON) {
        let rules = s.obj("rules") ?? [:]
        phase = s.str("phase"); turn = s.int("turn")
        players = rules.int("players", 4); target = rules.int("target", 100)
        scores = s.ints("scores")
        line = s.objs("line").map { PlacedTile(tile: Tile($0.obj("tile")), seat: $0.int("seat"), outer: $0.int("outer"), side: $0.str("side")) }
        handCounts = s.arr("hands").map { ($0 as? [Any])?.count ?? 0 }
        boneyard = s.arr("boneyard").count
        moveSig = jsonSig(s["lastMove"]) + "|\(s.str("phase"))|\(s.int("handNo"))"
        lastKind = s.obj("lastMove")?.str("kind")
        myTurn = ui.bool("myTurn"); canDraw = ui.bool("canDraw"); canPass = ui.bool("canPass")
        hand = ui.objs("hand").enumerated().map { i, h in
            DominoHandTile(id: i, tile: Tile(h.obj("tile")), label: h.str("label"), legal: h.bool("legal"), askSide: h.bool("askSide"))
        }
        ends = ui.obj("ends").map { (left: $0.int("left"), right: $0.int("right")) }
        endsText = ui.str("endsText"); lineText = ui.str("lineText"); scoreText = ui.str("scoreText")
        sideNames = ui.strs("sideNames"); mySide = ui.int("mySide", -1); prompt = ui.str("prompt")
    }
}

// ───── الجاكارو ─────

struct Marble { let zone: String; let pos: Int }

struct JackarooCard {
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
    let handCounts: [Int]
    let moveSig: String
    let hasMove: Bool
    let myTurn: Bool, burning: Bool
    let hand: [JackarooHandCard]
    let boardText: String, mineText: String, prompt: String

    func safeCount(_ team: Int) -> Int {
        [team, team + 2].reduce(0) { n, o in n + (o < marbles.count ? marbles[o].filter { $0.zone == "safe" }.count : 0) }
    }

    init(_ s: JSON, _ ui: JSON, mySeat: Int?) {
        let rules = s.obj("rules") ?? [:]
        phase = s.str("phase"); turn = s.int("turn"); winnerTeam = s.intOrNil("winnerTeam")
        dealNo = s.int("dealNo"); segment = rules.int("segment", 19)
        marbles = s.arr("marbles").map { (($0 as? [Any]) ?? []).compactMap { $0 as? JSON }.map { Marble(zone: $0.str("zone"), pos: $0.int("pos")) } }
        let hands = s.arr("hands").map { ($0 as? [Any]) ?? [] }
        handCounts = hands.map(\.count)
        moveSig = jsonSig(s["lastMove"]) + "|\(s.int("dealNo"))|\(s.str("phase"))"
        hasMove = s.obj("lastMove") != nil
        myTurn = ui.bool("myTurn"); burning = ui.bool("burning")
        let uiHand = ui.objs("hand")
        let mine: [JSON] = mySeat.flatMap { $0 < hands.count ? hands[$0].compactMap { $0 as? JSON } : nil } ?? []
        hand = mine.enumerated().map { i, c in
            let h = i < uiHand.count ? uiHand[i] : [:]
            return JackarooHandCard(
                id: i, card: JackarooCard(rank: c.str("rank"), suit: c.str("suit")), label: h.str("label"), usable: h.bool("usable"),
                moves: h.objs("moves").enumerated().map { k, m in JackarooMove(id: k, move: m.obj("move") ?? [:], text: m.str("text")) })
        }
        boardText = ui.str("boardText"); mineText = ui.str("mineText"); prompt = ui.str("prompt")
    }
}

// ───── لودو ─────

struct LudoOption: Identifiable { var id: Int { token }; let token: Int; let text: String }

struct LudoView {
    static let FINISH = 56, LAST_TRACK = 50
    static let STARTS = [0, 13, 26, 39]
    static let SAFE: Set<Int> = [0, 8, 13, 21, 26, 34, 39, 47]
    static func absPos(_ owner: Int, _ p: Int) -> Int { (STARTS[owner] + p) % 52 }

    let seats: [Int]
    let tokens: [[Int]]
    let turn: Int
    let phase: String
    let dice: Int?, lastRoll: Int?, winner: Int?
    let teams: Bool
    let moveSig: String
    let moved: Bool
    let myTurn: Bool
    let options: [LudoOption]
    let movableOwner: Int
    let boardText: String, mineText: String, prompt: String

    func home(_ o: Int) -> Int { o < tokens.count ? tokens[o].filter { $0 == LudoView.FINISH }.count : 0 }

    init(_ s: JSON, _ ui: JSON) {
        let last = s.obj("lastMove")
        seats = s.ints("seats")
        tokens = s.arr("tokens").map { (($0 as? [Any]) ?? []).map { ($0 as? NSNumber)?.intValue ?? -1 } }
        turn = s.int("turn"); phase = s.str("phase")
        dice = s.intOrNil("dice"); lastRoll = last?.intOrNil("roll"); winner = s.intOrNil("winner")
        teams = s.obj("rules")?.bool("teams") ?? false
        moveSig = jsonSig(s["lastMove"]) + "|\(s.int("turn"))|\(s.str("phase"))|\(s.intOrNil("dice") ?? -1)"
        moved = last?.obj("token") != nil
        myTurn = ui.bool("myTurn")
        options = ui.objs("options").map { LudoOption(token: $0.int("token"), text: $0.str("text")) }
        movableOwner = ui.int("movableOwner", -1)
        boardText = ui.str("boardText"); mineText = ui.str("mineText"); prompt = ui.str("prompt")
    }
}
