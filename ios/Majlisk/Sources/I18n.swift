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

/// القراءة ثنائية اللغة: نقسم النص لأجزاء حسب الحروف (عربي / لاتيني)، وكل جزء ياخذ لغته،
/// فـ VoiceOver يقرأ العربي بالناطق العربي والإنجليزي بالإنجليزي. المسافات والأرقام والرموز تمشي مع اللي قبلها.
func langRuns(_ s: String) -> [(Range<String.Index>, String)] {
    // رموز اللغة العامة (ar / en / fr): صوت العربي في الآيفون لغته ar-001 مو ar-SA، فـ «ar-SA» ما يلقى له صوت
    // ويرجع VoiceOver لصوت لغة الجهاز (فينقرأ الكلام العربي بالإنجليزي). الرمز العام يطابق أي صوت عربي
    let latin = I18n.shared.lang == "fr" ? "fr" : "en"
    func cls(_ u: Unicode.Scalar) -> String? {
        let v = u.value
        if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) || (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) { return "ar" }
        if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || ((0xC0...0x24F).contains(v) && CharacterSet.letters.contains(u)) { return latin }
        return nil
    }
    var out: [(Range<String.Index>, String)] = []
    var start = s.startIndex
    var cur: String? = nil
    // نهاية آخر حرف من لغة القطعة الحالية: بعد اسم إنجليزي، المسافات والأرقام والرموز تروح مع العربي اللي بعده
    // (فـ «Mohanad: 10 هاص» ينقرأ «Mohanad» بالإنجليزي و«10 هاص» بالعربي، مو العشرة بالإنجليزي)
    var lastEnd = s.startIndex
    var prevLetter: String? = nil
    var i = s.startIndex
    while i < s.endIndex {
        let u = s[i].unicodeScalars.first
        var k = u.flatMap(cls)
        // رقم ملتصق باسم إنجليزي (مثل ibrahim997) يبقى جزء من الاسم
        if k == nil, s[i].isNumber, prevLetter == latin { k = latin }
        if let k {
            if cur == nil { cur = k } else if k != cur {
                // من إنجليزي لعربي: الأرقام بينهم عربية. ومن عربي لإنجليزي: تبقى مع العربي
                let cut = cur == "ar" ? i : lastEnd
                out.append((start..<cut, cur!)); start = cut; cur = k
            }
            lastEnd = s.index(after: i)
        }
        if !s[i].isNumber { prevLetter = k }
        i = s.index(after: i)
    }
    out.append((start..<s.endIndex, cur ?? (I18n.shared.rtl ? "ar" : latin)))
    return out
}

/// نص مترجم ومعلّم بلغاته (للعرض ولـ VoiceOver)
func trSpoken(_ s0: String) -> AttributedString {
    let s = tr(s0)
    guard !s.isEmpty else { return AttributedString(s) }
    // نعلّم اللغات على NSAttributedString (مفتاح VoiceOver المعروف) ونحوّله مع خصائص UIKit (فيها خصائص قارئ الشاشة)
    let m = NSMutableAttributedString(string: s)
    for (r, l) in langRuns(s) where !r.isEmpty { m.addAttribute(.accessibilitySpeechLanguage, value: l, range: NSRange(r, in: s)) }
    return (try? AttributedString(m, including: \.uiKit)) ?? AttributedString(s)
}
func trSpoken(_ s: Substring) -> AttributedString { trSpoken(String(s)) }

/// الأرقام داخل الكلام العربي بالأرقام العربية (٧ بدل 7): الصوت العربي في الآيفون كان يتخطى الرقم الإنجليزي
/// لما تكون القطعة معلّمة عربي (فينقال «Mohanad: دايمن» بدون السبعة). الرقم العربي ينقرأ بالعربي دايماً
func arabicDigits(_ s: Substring) -> String {
    String(s.map { c -> Character in
        guard let v = c.asciiValue, v >= 48, v <= 57 else { return c }
        return Character(Unicode.Scalar(0x0660 + UInt32(v - 48))!)
    })
}

/// العدد بالكلمات العربية (٧ ← سبعة، ١٠ ← عشرة، ٢٥ ← خمسة وعشرين)
func arabicNumberWords(_ n: Int) -> String {
    // بالفصحى: الصوت العربي ينطقها صح (العامية مثل «ميتين» كان ينطقها غلط)
    let ones = ["صفر", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة", "عشرة",
                "أحد عشر", "اثنا عشر", "ثلاثة عشر", "أربعة عشر", "خمسة عشر", "ستة عشر", "سبعة عشر", "ثمانية عشر", "تسعة عشر"]
    let tens = ["", "", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون"]
    let hundreds = ["", "مئة", "مئتان", "ثلاثمئة", "أربعمئة", "خمسمئة", "ستمئة", "سبعمئة", "ثمانمئة", "تسعمئة"]
    func below1000(_ n: Int) -> String {
        var parts: [String] = []
        if n >= 100 { parts.append(hundreds[n / 100]) }
        let r = n % 100
        if r > 0 {
            if r < 20 { parts.append(ones[r]) }
            else if r % 10 == 0 { parts.append(tens[r / 10]) }
            else { parts.append("\(ones[r % 10]) و\(tens[r / 10])") }
        }
        return parts.joined(separator: " و")
    }
    if n < 0 { return "سالب " + arabicNumberWords(-n) }
    if n < 20 { return ones[n] }
    if n < 1000 { return below1000(n) }
    let th = n / 1000, rest = n % 1000
    let thWord: String
    switch th {
    case 1: thWord = "ألف"
    case 2: thWord = "ألفان"
    case 3...10: thWord = "\(ones[th]) آلاف"
    default: thWord = "\(below1000(th)) ألف"
    }
    return rest == 0 ? thWord : "\(thWord) و\(below1000(rest))"
}

/// الأرقام في الكلام العربي تنقال كلمات: الصوت العربي في الآيفون يتخطى الرقم (إنجليزي أو عربي)
/// لما يجي بعد اسم إنجليزي («Mohanad: 7 ديمن» كان ينقرأ «Mohanad: ديمن»). الكلمة تنقرأ دايماً.
/// الأرقام الطويلة أو الملتصقة بنقطة أو نقطتين (وقت، كسر) تبقى أرقام عربية
func arabicSpokenNumbers(_ s: Substring) -> String {
    var out = ""
    let chars = Array(s)
    var i = 0
    func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    while i < chars.count {
        guard isDigit(chars[i]) else { out.append(chars[i]); i += 1; continue }
        var j = i
        while j < chars.count, isDigit(chars[j]) { j += 1 }
        let digits = String(chars[i..<j])
        let joinedBefore = i >= 2 && (chars[i - 1] == "." || chars[i - 1] == ":" || chars[i - 1] == "/") && isDigit(chars[i - 2])
        let joinedAfter = j + 1 < chars.count && (chars[j] == "." || chars[j] == ":" || chars[j] == "/") && isDigit(chars[j + 1])
        if digits.count <= 6, !joinedBefore, !joinedAfter, let n = Int(digits) {
            out += arabicNumberWords(n)
        } else {
            out += arabicDigits(Substring(digits))
        }
        i = j
    }
    return out
}

/// نص للقراءة: كل قطعة بلغتها، والأرقام في القطع العربية تنقال كلمات عربية
func spokenAttributed(_ s: String, _ base: [NSAttributedString.Key: Any] = [:], words: Bool? = nil) -> NSAttributedString {
    let m = NSMutableAttributedString()
    let runs = langRuns(s)
    // الأرقام كلمات بس لما يكون فيه لغتين (اسم إنجليزي): الصوت العربي يتخطى الرقم بعد الإنجليزي.
    // الكلام العربي وحده يقرأ الأرقام أرقام عادي (النتيجة 225، المتصلون 11)
    let asWords = words ?? (runs.count > 1)
    for (r, l) in runs where !r.isEmpty {
        var attrs = base
        attrs[.accessibilitySpeechLanguage] = l
        m.append(NSAttributedString(string: l == "ar" && asWords ? arabicSpokenNumbers(s[r]) : String(s[r]), attributes: attrs))
    }
    return m
}

/// وصف قارئ الشاشة مترجم ومعلّم بلغاته
func spokenText(_ s0: String) -> Text {
    let s = tr(s0)
    return Text((try? AttributedString(spokenAttributed(s), including: \.uiKit)) ?? AttributedString(s))
}

/// إعلان قارئ الشاشة معلّم بلغاته
func spokenNS(_ s: String, queued: Bool, words: Bool? = nil) -> NSAttributedString {
    spokenAttributed(s, [.accessibilitySpeechQueueAnnouncement: queued], words: words)
}

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
