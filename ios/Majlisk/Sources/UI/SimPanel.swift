import SwiftUI

private let SIM_GAME_NAMES = [
    "baloot": "بلوت", "domino": "دومينو", "jackaroo": "جاكارو", "ludo": "لودو",
    "tarneeb": "طرنيب", "trix": "تريكس", "konkan": "كونكان", "shayeb": "شايب",
]

/// لوحة محاكاة النشاط (حساب المطور بس، والخادم يرفض غيره): تشغيل وإيقاف، والحدود، والألعاب،
/// وفترة التحديث، والعدد الحالي، وإعادة الضبط
struct SimPanel: View {
    @State private var on = false
    @State private var minP = "", maxP = "", minT = "", maxT = "", every = ""
    @State private var all: [String] = []
    @State private var games: [String] = []
    @State private var status = "جارٍ التحميل…"
    @State private var busy = false

    var body: some View {
        SectionTitle("محاكاة النشاط (نشاط المجلس)")
        Text(trSpoken("حسابات وطاولات تلقائية تطلع في قسم مستقل عليه ✦، ومكتوب عندها إنها تلقائية. ما تدخل في عدد المتصلين الحقيقي ولا الترتيب ولا الأصدقاء، وطاولاتها مقفلة."))
            .font(.system(size: 12)).foregroundColor(Palette.textDim)
        Text(trSpoken(status)).font(.system(size: 13)).foregroundColor(Palette.goldSoft)
            .task { if let r = try? await Api.get("/admin/sim") { apply(r) } else { status = "تعذّر التحميل" } }
        SwitchRow(label: "تشغيل المحاكاة", isOn: on, onChange: { on = $0; send() })
        HStack(spacing: 8) { Field(label: "أقل عدد حسابات", text: $minP, digits: 3); Field(label: "أكثر عدد حسابات", text: $maxP, digits: 3) }
        HStack(spacing: 8) { Field(label: "أقل عدد طاولات", text: $minT, digits: 3); Field(label: "أكثر عدد طاولات", text: $maxT, digits: 3) }
        Field(label: "فترة التحديث (دقايق)", text: $every, digits: 3)
        Text(trSpoken("الألعاب المشمولة")).font(.system(size: 14)).foregroundColor(Palette.text)
        ForEach(all, id: \.self) { g in
            SwitchRow(label: SIM_GAME_NAMES[g] ?? g, isOn: games.contains(g), onChange: { v in
                if v { if !games.contains(g) { games.append(g) } } else { games.removeAll { $0 == g } }
            })
        }
        MButton("حفظ الإعدادات", .primary, enabled: !busy) { send() }
        MButton("إعادة ضبط بيانات المحاكاة (أسماء وتوزيع جديد)", enabled: !busy) { send(reset: true) }
    }

    private func apply(_ r: JSON) {
        guard let c = r["config"] as? JSON else { return }
        on = c.bool("on")
        minP = String(c.int("minPlayers")); maxP = String(c.int("maxPlayers"))
        minT = String(c.int("minTables")); maxT = String(c.int("maxTables"))
        every = String(c.int("everyMin"))
        all = r.arr("games").compactMap { $0 as? String }
        games = c.arr("games").compactMap { $0 as? String }
        status = on ? "شغالة الحين: \(r.int("players")) حساب تلقائي و\(r.int("tables")) طاولة" : "المحاكاة متوقفة"
    }

    private func send(reset: Bool = false) {
        busy = true
        var b: JSON = ["on": on, "games": games]
        if let n = Int(minP) { b["minPlayers"] = n }; if let n = Int(maxP) { b["maxPlayers"] = n }
        if let n = Int(minT) { b["minTables"] = n }; if let n = Int(maxT) { b["maxTables"] = n }
        if let n = Int(every) { b["everyMin"] = n }
        if reset { b["reset"] = true }
        Task { @MainActor in
            if let r = try? await Api.post("/admin/sim", b) { apply(r); Announcer.announce("انحفظت إعدادات المحاكاة، \(status)") }
            else { Announcer.announce("ما انحفظت، جرّب مرة ثانية") }
            busy = false
        }
    }
}
