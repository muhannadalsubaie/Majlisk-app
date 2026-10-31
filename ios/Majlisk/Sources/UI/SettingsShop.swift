import SwiftUI

/// الإعدادات: تُفتح من القائمة الرئيسية كشاشة، أو من قائمة الطاولة (embedded) دون مغادرة الطاولة —
/// وهناك نُخفي قسم الحساب لأنه يُخرجك من اللعبة.
struct SettingsScreen: View {
    let embedded: Bool
    let onBack: () -> Void
    @State private var muted = Prefs.muted
    @State private var confirmDelete = false

    var body: some View {
        Screen {
            TopBar("الإعدادات", onBack: onBack)
            SectionTitle("الصوت")
            SwitchRow(label: "كتم عام لجميع الأصوات", isOn: muted, onChange: { muted = $0; Prefs.muted = $0 })
            if !embedded {
                SectionTitle("الحساب")
                MButton("تسجيل الخروج") { Session.shared.signOut() }
                MButton("حذف الحساب", .danger) { confirmDelete = true }
                MButton("سياسة الخصوصية") { UIApplication.shared.open(URL(string: Api.site + "/privacy.html")!) }
                // في آخر الإعدادات العامة فقط، بخط صغير جداً: رخصة صور الكروت (LGPL) تشترط ذكرها مع رابط المصدر والرخصة
                Text("صور الكروت: Vectorized Playing Cards لكريس أغيلار (Chris Aguilar)، رخصة LGPL-3.0. المؤثرات الصوتية: Kenney، رخصة CC0.")
                    .font(.system(size: 10)).foregroundColor(Palette.textDim)
                Link("مصدر صور الكروت", destination: URL(string: "https://github.com/richardschneider/cardsJS/tree/master/cards")!)
                    .font(.system(size: 10)).foregroundColor(Palette.textDim)
                Link("رخصة صور الكروت", destination: URL(string: "https://www.gnu.org/licenses/lgpl-3.0.html")!)
                    .font(.system(size: 10)).foregroundColor(Palette.textDim)
            }
        }
        .confirm("حذف الحساب", isPresented: $confirmDelete,
                 message: "سيتم حذف حسابك نهائياً: اسم المستخدم، والعملات، وقائمة الأصدقاء، وبيانات الدخول. لا يمكن التراجع عن هذا الإجراء.",
                 confirm: "حذف نهائياً", destructive: true) {
            Announcer.announce("جارٍ حذف الحساب…")
            Task { @MainActor in
                do { try await Tables.deleteAccount(); Session.shared.signOut(); Announcer.announce("تم حذف حسابك نهائياً") }
                catch { Announcer.announce("تعذّر حذف الحساب الآن، حاول مرة أخرى") }
            }
        }
    }
}

/// متجر العملات: الباقات بأسعار App Store، والشراء عبره
struct ShopScreen: View {
    let profile: Profile?
    let navigate: (Route) -> Void
    @State private var packs: [StorePack]?
    @State private var busy = ""

    var body: some View {
        Screen {
            TopBar("شراء عملات", onBack: { navigate(.menu) })
            BodyText("رصيدك الحالي: \(profile?.unlimited == true ? "لا محدود" : profile?.coins.map(String.init) ?? "…") 🪙")
            if packs == nil { BodyText("جارٍ تحميل الباقات…") }
            ForEach(packs ?? []) { p in
                let base = p.coins - p.bonus
                let spoken = "\(base) عملة\(p.bonus > 0 ? " زائد \(p.bonus) هدية" : "")، بسعر \(p.price)"
                ItemRow {
                    VStack(alignment: .leading) {
                        Text("\(base) عملة").bold()
                        if p.bonus > 0 { Text("+ \(p.bonus) هدية").foregroundColor(Palette.goldSoft) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    SmallButton(busy == p.id ? "جارٍ…" : p.price, primary: true, enabled: busy.isEmpty, label: "شراء \(spoken)") {
                        busy = p.id
                        Task { @MainActor in await Store.buy(p.id); busy = "" }
                    }
                }
            }
        }
        .task { packs = await Store.loadPacks() }
    }
}
