import SwiftUI

// ملّاك (لعبة العقارات): الحالة من الخادم (كلها مكشوفة) ومعها "ui" لهذا اللاعب:
// الأزرار المتاحة ونصوص قارئ الشاشة ووصف الخانات.

/// نوع الخانة: city / station / utility / chance / chest / tax / go / jail / rest / goToJail
struct MallakSquare { let name: String; let kind: String; var group = -1; var price = 0 }

/// اللوحة (نفس لوحة الخادم): 40 خانة
let MALLAK_BOARD: [MallakSquare] = [
    .init(name: "الانطلاق", kind: "go"), .init(name: "الهفوف", kind: "city", group: 0, price: 60), .init(name: "صندوق المجلس", kind: "chest"),
    .init(name: "المبرز", kind: "city", group: 0, price: 70), .init(name: "الزكاة", kind: "tax"), .init(name: "مطار الرياض", kind: "station", price: 200),
    .init(name: "بريدة", kind: "city", group: 1, price: 100), .init(name: "فرصة", kind: "chance"), .init(name: "عنيزة", kind: "city", group: 1, price: 100),
    .init(name: "الرس", kind: "city", group: 1, price: 120), .init(name: "السجن", kind: "jail"), .init(name: "أبها", kind: "city", group: 2, price: 140),
    .init(name: "الكهرباء", kind: "utility", price: 150), .init(name: "خميس مشيط", kind: "city", group: 2, price: 140), .init(name: "النماص", kind: "city", group: 2, price: 160),
    .init(name: "قطار الشمال", kind: "station", price: 200), .init(name: "الشفا", kind: "city", group: 3, price: 180), .init(name: "صندوق المجلس", kind: "chest"),
    .init(name: "الهدا", kind: "city", group: 3, price: 180), .init(name: "الحوية", kind: "city", group: 3, price: 200), .init(name: "الاستراحة", kind: "rest"),
    .init(name: "الدمام", kind: "city", group: 4, price: 220), .init(name: "فرصة", kind: "chance"), .init(name: "الخبر", kind: "city", group: 4, price: 220),
    .init(name: "الظهران", kind: "city", group: 4, price: 240), .init(name: "مطار الدمام", kind: "station", price: 200), .init(name: "البلد", kind: "city", group: 5, price: 260),
    .init(name: "الحمراء", kind: "city", group: 5, price: 260), .init(name: "المياه", kind: "utility", price: 150), .init(name: "أبحر", kind: "city", group: 5, price: 280),
    .init(name: "روح للسجن", kind: "goToJail"), .init(name: "تبوك", kind: "city", group: 6, price: 300), .init(name: "العلا", kind: "city", group: 6, price: 300),
    .init(name: "صندوق المجلس", kind: "chest"), .init(name: "أملج", kind: "city", group: 6, price: 320), .init(name: "مطار جدة", kind: "station", price: 200),
    .init(name: "فرصة", kind: "chance"), .init(name: "الدرعية", kind: "city", group: 7, price: 350), .init(name: "رسوم البلدية", kind: "tax"),
    .init(name: "طريق الملك فهد", kind: "city", group: 7, price: 400),
]

private func hex(_ v: UInt32) -> Color { Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255) }
let MALLAK_GROUP_COLORS: [Color] = [0x8B5A2B, 0x5BC0EB, 0xD63AF9, 0xF28C28, 0xE63946, 0xF4D35E, 0x2A9D8F, 0x1D3FBB].map(hex)
let MALLAK_PLAYER_COLORS: [Color] = [0xE53935, 0x1E88E5, 0xFDD835, 0x43A047, 0x8E24AA, 0xFF7043].map(hex)
let MALLAK_PLAYER_COLOR_NAMES = ["الأحمر", "الأزرق", "الأصفر", "الأخضر", "البنفسجي", "البرتقالي"]

struct MallakPlayer { let seat: Int, cash: Int, pos: Int, inJail: Bool, jailCards: Int, bankrupt: Bool }
struct MallakActionBtn: Identifiable { let id: Int; let type: String; let label: String; let amount: Int? }
struct MallakProp: Identifiable { var id: Int { square }; let square: Int; let name: String; let houses: Int; let mortgaged: Bool; let build: Bool, sell: Bool, mortgage: Bool, unmortgage: Bool }
struct MallakPlayerUi: Identifiable { var id: Int { seat }; let seat: Int; let text: String; let cash: Int; let pos: Int; let bankrupt: Bool; let inJail: Bool }

struct MallakView {
    let phase: String
    let turn: Int
    let seats: [Int]
    /// حسب رقم المقعد (6)، nil لغير المشارك
    let players: [MallakPlayer?]
    let owner: [Int?]
    let houses: [Int]
    let mortgaged: [Bool]
    let dice: (Int, Int)?
    let rollSeq: Int
    /// آخر حركة حجر: مين ومن وين لوين ونوعها (roll / card / jail)، ورقمها
    let moveSeat: Int, moveFrom: Int, moveTo: Int, moveKind: String, moveSeq: Int
    let cardSeq: Int
    let winner: Int?
    let myTurn: Bool
    let prompt: String
    let actions: [MallakActionBtn]
    let myProps: [MallakProp]
    let canTrade: Bool
    let squares: [String]
    let playersUi: [MallakPlayerUi]
    let hereText: String, turnText: String, tradeText: String, auctionText: String, cardText: String
    let log: [String]

    var alive: [Int] { seats.filter { $0 < players.count && players[$0]?.bankrupt == false } }

    init(_ s: JSON, _ ui: JSON, log: [String]) {
        players = s.arr("players").map { ($0 as? JSON).map { MallakPlayer(seat: $0.int("seat"), cash: $0.int("cash"), pos: $0.int("pos"), inJail: $0.bool("inJail"), jailCards: $0.int("jailCards"), bankrupt: $0.bool("bankrupt")) } }
        phase = s.str("phase"); turn = s.int("turn"); seats = s.ints("seats")
        owner = s.arr("owner").map { ($0 as? NSNumber)?.intValue }
        houses = s.ints("houses")
        mortgaged = s.arr("mortgaged").map { ($0 as? NSNumber)?.boolValue ?? false }
        let d = s.ints("dice")
        dice = d.count == 2 ? (d[0], d[1]) : nil
        rollSeq = s.int("rollSeq")
        let lm = s.obj("lastMove")
        moveSeat = lm?.int("seat", -1) ?? -1; moveFrom = lm?.int("from") ?? 0; moveTo = lm?.int("to") ?? 0
        moveKind = lm?.str("kind") ?? ""; moveSeq = lm?.int("seq") ?? 0
        cardSeq = s.obj("lastCard")?.int("seq") ?? 0
        winner = s.intOrNil("winner")
        myTurn = ui.bool("myTurn"); prompt = ui.str("prompt")
        actions = ui.objs("actions").enumerated().map { MallakActionBtn(id: $0.offset, type: $0.element.str("type"), label: $0.element.str("label"), amount: $0.element.intOrNil("amount")) }
        myProps = ui.objs("myProps").map { MallakProp(square: $0.int("square"), name: $0.str("name"), houses: $0.int("houses"), mortgaged: $0.bool("mortgaged"),
                                                      build: $0.bool("build"), sell: $0.bool("sell"), mortgage: $0.bool("mortgage"), unmortgage: $0.bool("unmortgage")) }
        canTrade = ui.bool("canTrade")
        squares = ui.strs("squares")
        playersUi = ui.objs("players").map { MallakPlayerUi(seat: $0.int("seat"), text: $0.str("text"), cash: $0.int("cash"), pos: $0.int("pos"), bankrupt: $0.bool("bankrupt"), inJail: $0.bool("inJail")) }
        hereText = ui.str("hereText"); turnText = ui.str("turnText"); tradeText = ui.str("tradeText")
        auctionText = ui.str("auctionText"); cardText = ui.str("cardText")
        self.log = log
    }
}
