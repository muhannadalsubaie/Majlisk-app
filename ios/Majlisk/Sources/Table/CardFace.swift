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

struct CardFace: View {
    let card: Card
    var body: some View {
        if let img = CardImages.get(card) {
            Image(uiImage: img).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Text("\(RANK_NAMES[card.rank] ?? "") \(SUIT_SYMBOLS[card.suit] ?? "")").accessibilityHidden(true)
        }
    }
}
