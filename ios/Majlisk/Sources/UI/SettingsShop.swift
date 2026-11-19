import SwiftUI

/// الإعدادات: تُفتح من القائمة الرئيسية كشاشة، أو من قائمة الطاولة (embedded) دون مغادرة الطاولة —
/// وهناك نُخفي قسم الحساب لأنه يُخرجك من اللعبة.
struct SettingsScreen: View {
    let embedded: Bool
    let onBack: () -> Void
    @State private var muted = Prefs.muted
    @State private var effects = Double(Prefs.effectsVolume)
    @AppStorage("handStyle") private var handStyle = "fan"
    @ObservedObject private var chatSettings = ChatSettings.shared
    @State private var confirmDelete = false
    @State private var support = false
    @State private var privacy = false
    @ObservedObject private var session = Session.shared

    var body: some View {
        if support { SupportScreen(dev: session.profile?.dev == true || session.profile?.unlimited == true) { support = false } } else { settings }
    }

    @ViewBuilder private var settings: some View {
        Screen {
            TopBar("الإعدادات", onBack: onBack)
            SectionTitle("اللغة")
            HStack { LanguageButton(); Spacer() }
            SectionTitle("الصوت")
            SwitchRow(label: "كتم عام لجميع الأصوات", isOn: muted, onChange: { muted = $0; Prefs.muted = $0 })
            // مستوى صوت المؤثرات: 70% المستوى الأصلي، وتقدر ترفعه لين 100% أو تنزله (كل خطوة 5%)
            Text(trSpoken("مستوى صوت المؤثرات: \(Int(effects))%")).foregroundColor(Palette.text).accessibilityHidden(true)
            Slider(value: $effects, in: 0...100, step: 5, onEditingChanged: { editing in
                if !editing { Prefs.effectsVolume = Int(effects); Sounds.shared.preview() }
            })
            .tint(Palette.gold)
            .accessibilityLabel(spokenText("مستوى صوت المؤثرات"))
            .accessibilityValue("\(Int(effects))%")
            .onChange(of: effects) { v in Prefs.effectsVolume = Int(v) }
            SectionTitle("شكل الورق")
            // اختيارك أنت فقط ويتحفظ على جوالك
            SwitchRow(label: "مروحة (الأوراق فوق بعض)", isOn: handStyle == "fan", onChange: { if $0 { handStyle = "fan" } })
            SwitchRow(label: "كروت جنب بعض (مفصولة)", isOn: handStyle == "row", onChange: { if $0 { handStyle = "row" } })
            SectionTitle("الدردشة الكتابية")
            // اختيارك أنت فقط: ما يأثر على باقي اللاعبين
            ForEach(ChatMode.allCases, id: \.self) { m in
                SwitchRow(label: m.label, isOn: chatSettings.mode == m, onChange: { if $0 { chatSettings.set(m) } })
            }
            if !embedded {
                // خصوصية اللاعب: طاولتك العامة للأصدقاء فقط (الخاصة تبقى بدعوة أو طلب انضمام). محفوظة على حسابك
                SectionTitle("الخصوصية")
                SwitchRow(label: "خصوصية اللاعب", isOn: privacy, onChange: { on in
                    privacy = on
                    Task { do { privacy = (try await Api.post("/profile/privacy", ["on": on]))["on"] as? Bool ?? on } catch { privacy = !on } }
                })
                .task { if let r = try? await Api.post("/profile/privacy"), let on = r["on"] as? Bool { privacy = on } }
                Text(trSpoken("إذا شغلته: طاولتك العامة ما يدخلها إلا أصدقاؤك. الطاولة الخاصة تبقى بدعوة أو طلب انضمام."))
                    .font(.system(size: 13)).foregroundColor(Palette.textDim).frame(maxWidth: .infinity, alignment: .leading)
                SectionTitle("المساعدة")
                MButton("💬 المساعدة والدعم") { support = true }
                SectionTitle("الحساب")
                MButton("تسجيل الخروج") { Session.shared.signOut() }
                MButton("حذف الحساب", .danger) { confirmDelete = true }
                MButton("سياسة الخصوصية") { UIApplication.shared.open(URL(string: Api.site + "/privacy.html")!) }
                // في آخر الإعدادات العامة فقط، بخط صغير جداً: رخصة صور الكروت (LGPL) تشترط ذكرها مع رابط المصدر والرخصة
                Text(trSpoken("صور الكروت: Vectorized Playing Cards لكريس أغيلار (Chris Aguilar)، رخصة LGPL-3.0. المؤثرات الصوتية: Kenney، رخصة CC0."))
                    .font(.system(size: 10)).foregroundColor(Palette.textDim)
                Link(tr("مصدر صور الكروت"), destination: URL(string: "https://github.com/richardschneider/cardsJS/tree/master/cards")!)
                    .font(.system(size: 10)).foregroundColor(Palette.textDim)
                Link(tr("رخصة صور الكروت"), destination: URL(string: "https://www.gnu.org/licenses/lgpl-3.0.html")!)
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
    /// نسخة TestFlight والشراء التجريبي مقفل: نوضح ليش ما يشتغل الشراء
    @State private var sandboxBlocked = false

    var body: some View {
        Screen {
            TopBar("شراء عملات", onBack: { navigate(.menu) })
                .task { if Store.isTestFlight { sandboxBlocked = !(((try? await Api.post("/purchases/config"))?.bool("sandbox")) ?? false) } }
            BodyText("رصيدك الحالي: \(profile?.unlimited == true ? "لا محدود" : profile?.coins.map(String.init) ?? "…") 🪙")
            if sandboxBlocked { BodyText("الشراء غير متاح حالياً في النسخة التجريبية (TestFlight)، ويتوفر من نسخة App Store") }
            if packs == nil { BodyText("جارٍ تحميل الباقات…") }
            ForEach(packs ?? []) { p in
                let base = p.coins - p.bonus
                let spoken = "\(base) عملة\(p.bonus > 0 ? " زائد \(p.bonus) هدية" : "")، بسعر \(p.price)"
                ItemRow {
                    VStack(alignment: .leading) {
                        Text(trSpoken("\(base) عملة")).bold()
                        if p.bonus > 0 { Text(trSpoken("+ \(p.bonus) هدية")).foregroundColor(Palette.goldSoft) }
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
