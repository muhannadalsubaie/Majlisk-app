import SwiftUI

/// خيار شكل: اسم يُقرأ، وألوانه
struct LookOption { let name: String; let colors: [Color] }

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// تخصيص الشكل (الباقة الاحترافية): يتحفظ في الجوال، ويطلع للمشترك بس — غيره يشوف الشكل العادي (الخيار الأول).
/// كل لعبة تقرأ ألوانها من هنا.
final class Look: ObservableObject {
    static let shared = Look()

    static let felts = [
        LookOption(name: "أخضر زمردي", colors: [rgb(0x1E6B4A), rgb(0x145036), rgb(0x0B241B)]),
        LookOption(name: "أزرق ليلي", colors: [rgb(0x3A68AC), rgb(0x1F3B66), rgb(0x0E1C33)]),
        LookOption(name: "عنابي", colors: [rgb(0xA52A3A), rgb(0x6A1420), rgb(0x3A0C13)]),
        LookOption(name: "بنفسجي", colors: [rgb(0x7A4FB0), rgb(0x4A2D70), rgb(0x2A1746)]),
        LookOption(name: "رمادي فحمي", colors: [rgb(0x4A525C), rgb(0x2B3036), rgb(0x15181C)]),
        LookOption(name: "رملي", colors: [rgb(0xD9C08A), rgb(0xB09460), rgb(0x8A6F3A)]),
    ]
    static let shapes = ["دائرية", "مستطيلة", "ثمانية", "مربعة"]
    static let rims = [
        LookOption(name: "خشب", colors: [rgb(0x8A5A2B), rgb(0x5C3A1A), rgb(0x3B2410)]),
        LookOption(name: "ذهب", colors: [rgb(0xF1DDA0), rgb(0xD9B45A), rgb(0x8A6A22)]),
        LookOption(name: "رخام", colors: [rgb(0xF2F0EA), rgb(0xC8C4BA), rgb(0x8E8A80)]),
        LookOption(name: "أسود", colors: [rgb(0x3A3F46), rgb(0x22262B), rgb(0x0B0F14)]),
    ]
    static let cardEdges = [
        LookOption(name: "كلاسيكي", colors: [Color(white: 0.8)]),
        LookOption(name: "ذهبي", colors: [rgb(0xD9B45A)]),
        LookOption(name: "عنابي", colors: [rgb(0x7A1F2B)]),
        LookOption(name: "أزرق", colors: [rgb(0x2B4C7E)]),
    ]
    static let tiles = [
        LookOption(name: "عاجي", colors: [rgb(0xFAF7EE), rgb(0x1A1A1A), rgb(0x9E9886)]),
        LookOption(name: "أسود بنقط ذهبية", colors: [rgb(0x2A2E33), rgb(0xF1DDA0), rgb(0x0B0F14)]),
        LookOption(name: "ذهبي", colors: [rgb(0xF1DDA0), rgb(0x2A1E05), rgb(0x8A6A22)]),
        LookOption(name: "أزرق", colors: [rgb(0x3A68AC), .white, rgb(0x1B3157)]),
    ]
    static let sizes: [(String, CGFloat)] = [("صغير", 0.85), ("وسط", 1), ("كبير", 1.15)]
    static let jkBoards = [
        LookOption(name: "أسود وخشب", colors: [rgb(0x1C1C1E), rgb(0x0B0B0C), rgb(0xE4C48F)]),
        LookOption(name: "خشب وزمرد", colors: [rgb(0x7A4A22), rgb(0x4A2D13), rgb(0x2FA57B)]),
        LookOption(name: "ليلي وذهب", colors: [rgb(0x1F3B66), rgb(0x0E1C33), rgb(0xD9B45A)]),
    ]
    static let dice = [
        LookOption(name: "عاجي", colors: [.white, Color(white: 0.1)]),
        LookOption(name: "ذهبي", colors: [rgb(0xF1DDA0), rgb(0x2A1E05)]),
        LookOption(name: "أسود", colors: [rgb(0x2A2E33), rgb(0xF1DDA0)]),
        LookOption(name: "ياقوتي", colors: [rgb(0xC8394B), .white]),
    ]

    private static func saved(_ k: String, _ d: Int = 0) -> Int { UserDefaults.standard.object(forKey: "look.\(k)") as? Int ?? d }
    private func save(_ k: String, _ v: Int) { UserDefaults.standard.set(v, forKey: "look.\(k)") }

    @Published var balootFelt = Look.saved("balootFelt") { didSet { save("balootFelt", balootFelt) } }
    @Published var balootShape = Look.saved("balootShape") { didSet { save("balootShape", balootShape) } }
    @Published var balootRim = Look.saved("balootRim") { didSet { save("balootRim", balootRim) } }
    @Published var cardEdge = Look.saved("cardEdge") { didSet { save("cardEdge", cardEdge) } }
    @Published var dominoFelt = Look.saved("dominoFelt") { didSet { save("dominoFelt", dominoFelt) } }
    @Published var dominoRim = Look.saved("dominoRim") { didSet { save("dominoRim", dominoRim) } }
    @Published var dominoTile = Look.saved("dominoTile") { didSet { save("dominoTile", dominoTile) } }
    @Published var dominoSize = Look.saved("dominoSize", 1) { didSet { save("dominoSize", dominoSize) } }
    @Published var jkBoard = Look.saved("jkBoard") { didSet { save("jkBoard", jkBoard) } }
    @Published var ludoDice = Look.saved("ludoDice") { didSet { save("ludoDice", ludoDice) } }

    /// المشترك يشوف اختياره، وغيره الشكل العادي
    /// يتحدث من ملف اللاعب (Session) كل ما تغيّر
    static var pro = false
    private static func pick(_ list: [LookOption], _ i: Int) -> [Color] { (pro && list.indices.contains(i) ? list[i] : list[0]).colors }

    static var felt: [Color] { pick(felts, shared.balootFelt) }
    static var shape: Int { pro ? shared.balootShape : 0 }
    static var rim: [Color] { pick(rims, shared.balootRim) }
    static var edge: Color { pick(cardEdges, shared.cardEdge)[0] }
    static var dFelt: [Color] { pick(felts, shared.dominoFelt) }
    static var dRim: [Color] { pick(rims, shared.dominoRim) }
    static var tile: [Color] { pick(tiles, shared.dominoTile) }
    static var tileScale: CGFloat { pro && sizes.indices.contains(shared.dominoSize) ? sizes[shared.dominoSize].1 : 1 }
    static var jk: [Color] { pick(jkBoards, shared.jkBoard) }
    static var diceColors: [Color] { pick(dice, shared.ludoDice) }

    /// شكل طاولة البلوت
    static func tableShape(_ i: Int) -> AnyShape {
        switch i {
        case 1: return AnyShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        case 2: return AnyShape(OctagonShape())
        case 3: return AnyShape(RoundedRectangle(cornerRadius: 10))
        default: return AnyShape(Circle())
        }
    }
}

struct OctagonShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = min(r.width, r.height) * 0.29
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}
