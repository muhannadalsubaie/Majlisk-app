import SwiftUI

/// صور الأوراق (SVG-cards لديفيد بيلو، رخصة LGPL-2.1 — مذكورة في الإعدادات). للعين فقط: الاسم يُقرأ نصاً
enum CardImages {
    private static var cache: [String: UIImage] = [:]
    static func get(_ card: Card) -> UIImage? {
        if let img = cache[card.image] { return img }
        guard let path = Bundle.main.path(forResource: card.image, ofType: "webp", inDirectory: "Media/cards"),
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache[card.image] = img
        return img
    }
}

/// وجه الورقة: الصور الكلاسيكية، أو (للمشترك) شكل مرسوم: 1 خط كبير واضح، 2 ذهبي، 3 ليلي
struct CardFace: View {
    let card: Card
    var body: some View {
        let style = Look.face
        if style > 0 {
            DrawnFace(card: card, style: style).accessibilityHidden(true)
        } else if let img = CardImages.get(card) {
            Image(uiImage: img).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Text("\(RANK_NAMES[card.rank] ?? "") \(SUIT_SYMBOLS[card.suit] ?? "")").accessibilityHidden(true)
        }
    }
}

private struct DrawnFace: View {
    let card: Card
    let style: Int
    var body: some View {
        let red = card.suit == "H" || card.suit == "D"
        let sym = SUIT_SYMBOLS[card.suit] ?? ""
        let ink: Color = style == 2 ? (red ? Color(red: 0.69, green: 0.19, blue: 0.16) : Color(red: 0.16, green: 0.12, blue: 0.02))
            : style == 3 ? (red ? Color(red: 1, green: 0.48, blue: 0.48) : Color(red: 0.95, green: 0.87, blue: 0.63))
            : (red ? Color(red: 0.78, green: 0.16, blue: 0.16) : Color(white: 0.07))
        let bg: [Color] = style == 2 ? [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.95, green: 0.89, blue: 0.74)]
            : style == 3 ? [Color(red: 0.12, green: 0.16, blue: 0.21), Color(red: 0.04, green: 0.06, blue: 0.08)] : [.white, .white]
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(colors: bg, startPoint: .top, endPoint: .bottom)
                if style >= 2 { RoundedRectangle(cornerRadius: w * 0.06).stroke(Color(red: 0.85, green: 0.71, blue: 0.35), lineWidth: 1).padding(w * 0.06) }
                if style == 1 {
                    // خط كبير: الرقم والرمز كبار في النص (أوضح للنظر)
                    VStack(spacing: 0) {
                        Text(card.rank).font(.system(size: w * 0.42, weight: .heavy))
                        Text(sym).font(.system(size: w * 0.46))
                    }
                    .foregroundColor(ink)
                } else {
                    VStack(spacing: 0) {
                        Text(card.rank).font(.system(size: w * 0.26, weight: .heavy))
                        Text(sym).font(.system(size: w * 0.22))
                    }
                    .foregroundColor(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, w * 0.1).padding(.top, w * 0.08)
                    Text(sym).font(.system(size: w * 0.52)).foregroundColor(ink).offset(y: w * 0.12)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}
