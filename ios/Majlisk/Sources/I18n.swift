import SwiftUI

/// لغة التطبيق: عربي (الأصل) أو إنجليزي أو فرنسي.
/// كل نص عربي (من التطبيق أو من الخادم) يتترجم وقت العرض أو القراءة من القاموس (i18n.json):
/// نص مطابق، أو قالب فيه أماكن ({0}) تتعبى بأجزاء تتترجم هي بعد، وإلا نقسمه على الفواصل ونترجم كل جزء.
final class I18n: ObservableObject {
    static let shared = I18n()
    static let langs: [(code: String, name: String)] = [("ar", "العربية"), ("en", "English"), ("fr", "Français")]
    @Published private(set) var lang: String = UserDefaults.standard.string(forKey: "lang") ?? "ar"

    private struct Tpl { let re: NSRegularExpression; let out: [String]; let weight: Int }
    private var exact: [String: [String]] = [:]
    private var templates: [Tpl] = []
    private var cache: [String: String] = [:]
    private let lock = NSLock()
    private static let arabic = try! NSRegularExpression(pattern: "[\\u0600-\\u06FF]")

    private init() {
        guard let url = Bundle.main.url(forResource: "i18n", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
        for (k, o) in json {
            let out = [o["en"] ?? k, o["fr"] ?? k]
            if !k.contains("{0}") { exact[k] = out; continue }
            // القالب: الأجزاء الثابتة لازم فيها حرف عربي (وإلا يطابق أي شي)
            let literal = k.replacingOccurrences(of: "\\{\\d\\}", with: "", options: .regularExpression)
            guard literal.range(of: "[\u{0621}-\u{064A}]", options: .regularExpression) != nil else { continue }
            var pattern = "^"
            var rest = Substring(k)
            var first = true
            while let r = rest.range(of: "\\{\\d\\}", options: .regularExpression) {
                let lit = String(rest[..<r.lowerBound])
                // مكانين ورا بعض بمسافة ({0} {1}): الثاني كلمة وحدة (رقم أو نقاط)
                pattern += NSRegularExpression.escapedPattern(for: lit) + (!first && lit == " " ? "(\\S+)" : "(.*?)")
                first = false
                rest = rest[r.upperBound...]
            }
            pattern += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                templates.append(Tpl(re: re, out: out, weight: literal.count))
            }
        }
        templates.sort { $0.weight > $1.weight }
    }

    static func hasArabic(_ s: String) -> Bool { arabic.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    var rtl: Bool { lang == "ar" }
    static var direction: LayoutDirection { shared.rtl ? .rightToLeft : .leftToRight }

    func set(_ l: String) {
        lock.lock(); cache.removeAll(); lock.unlock()
        UserDefaults.standard.set(l, forKey: "lang")
        lang = l
        sync()
    }

    /// نبلغ الخادم بلغتك (الإشعارات توصلك بها) — لو مسجّل دخول
    func sync() {
        let l = lang
        Task { _ = try? await Api.post("/profile/lang", ["lang": l]) }
    }

    func tr(_ s: String) -> String {
        let l = lang
        if l == "ar" || s.isEmpty || !I18n.hasArabic(s) { return s }
        lock.lock(); if let c = cache[s] { lock.unlock(); return c }; lock.unlock()
        let r = translate(s, l == "fr" ? 1 : 0, 0)
        lock.lock(); if cache.count > 4000 { cache.removeAll() }; cache[s] = r; lock.unlock()
        return r
    }

    private static let separators: [(String, String)] = [("\n", "\n"), (". ", ". "), (" — ", " — "), ("، ", ", "), ("،", ","), (": ", ": "), (" · ", " · "), (" و", " & ")]

    private func translate(_ s: String, _ i: Int, _ depth: Int) -> String {
        if s.isEmpty || depth > 8 || !I18n.hasArabic(s) { return s }
        if let e = exact[s] { return e[i] }
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count != s.count, !t.isEmpty, let r = s.range(of: t) {
            return String(s[..<r.lowerBound]) + translate(t, i, depth + 1) + String(s[r.upperBound...])
        }
        let ns = s as NSString
        var best: String? = nil
        for tp in templates {
            guard let m = tp.re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
            var out = tp.out[i]
            for n in 1..<m.numberOfRanges {
                let g = ns.substring(with: m.range(at: n))
                out = out.replacingOccurrences(of: "{\(n - 1)}", with: translate(g, i, depth + 1))
            }
            best = out
            break
        }
        if let b = best, I18n.leftover(b) == 0 { return b }
        // نقسم على الفواصل ونترجم كل جزء (لو القالب بلع نص طويل فيه أكثر من جملة، نختار الأنظف)
        for (sep, rep) in I18n.separators where s.contains(sep) {
            let alt = s.components(separatedBy: sep).map { translate($0, i, depth + 1) }.joined(separator: rep)
            if let b = best, I18n.leftover(alt) >= I18n.leftover(b) { return b }
            return alt
        }
        return best ?? s
    }

    /// كم حرف عربي باقي بعد الترجمة
    static func leftover(_ s: String) -> Int { s.unicodeScalars.filter { $0.value >= 0x0621 && $0.value <= 0x064A }.count }
}

/// ترجمة نص للغة التطبيق
func tr(_ s: String) -> String { I18n.shared.tr(s) }
func tr(_ s: Substring) -> String { I18n.shared.tr(String(s)) }
func tr(_ s: String?) -> String? { s.map { I18n.shared.tr($0) } }

/// الجذر: اتجاه الشاشة من لغة التطبيق، ويعاد بناؤه كله لما تتغير اللغة
struct LangRoot<Content: View>: View {
    @ObservedObject private var i18n = I18n.shared
    let content: () -> Content
    var body: some View {
        content()
            .id(i18n.lang)
            .environment(\.layoutDirection, i18n.rtl ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: i18n.lang))
    }
}

/// زر تغيير اللغة (🌐): قبل تسجيل الدخول فوق، وفي الإعدادات
struct LanguageButton: View {
    @ObservedObject private var i18n = I18n.shared
    var body: some View {
        let cur = I18n.langs.first { $0.code == i18n.lang }?.name ?? "العربية"
        Menu {
            ForEach(I18n.langs, id: \.code) { l in
                Button(l.code == i18n.lang ? "✓ \(l.name)" : l.name) { i18n.set(l.code) }
            }
        } label: {
            Text(verbatim: "🌐 \(cur) ▾")
                .font(.system(size: 16, weight: .bold)).foregroundColor(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Palette.green800).clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.gold, lineWidth: 1))
        }
        .accessibilityLabel(Text(verbatim: "Language, اللغة: \(cur)"))
    }
}
