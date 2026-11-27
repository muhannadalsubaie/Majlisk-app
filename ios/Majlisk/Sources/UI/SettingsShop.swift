import SwiftUI

/// الإعدادات: تُفتح من القائمة الرئيسية كشاشة، أو من قائمة الطاولة (embedded) دون مغادرة الطاولة —
/// وهناك نُخفي قسم الحساب لأنه يُخرجك من اللعبة.
struct SettingsScreen: View {
    let embedded: Bool
    let onBack: () -> Void
    @State private var muted = Prefs.muted
    @State private var effects = Double(Prefs.effectsVolume)
    @AppStorage("handStyle") private var handStyle = "fan"
    @ObservedObject private var i18nNames = I18n.shared
    @State private var announceMode = AnnounceMode.current
    @State private var speechRate = AppSpeech.rate
    @State private var annText = ""
    @State private var annMsg = ""
    @ObservedObject private var chatSettings = ChatSettings.shared
    @State private var confirmDelete = false
    @State private var support = false
    @State private var privacy = false
    @ObservedObject private var session = Session.shared

    var body: some View {
        if support { SupportScreen(dev: session.profile?.dev == true || session.profile?.unlimited == true) { support = false } } else {
            settings
        }
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
            // أسماء الأوراق والأنواع في كل الألعاب (العرض وقارئ الشاشة)
            SectionTitle("تسميات الأوراق")
            SwitchRow(label: "تسميات خليجية (أكة، شايب، بنت، ولد…)", isOn: i18nNames.cardNames == "gulf", onChange: { if $0 { I18n.shared.setCardNames("gulf") } })
            SwitchRow(label: "تسميات شامية (قص، كبة، ديناري، بستوني، سنك…)", isOn: i18nNames.cardNames == "levant", onChange: { if $0 { I18n.shared.setCardNames("levant") } })
            // طريقة قراءة الإعلانات مع VoiceOver (تجربة: ثلاث طرق للأسماء الإنجليزية وسط الكلام العربي)
            SectionTitle("قراءة الإعلانات")
            ForEach(AnnounceMode.allCases, id: \.self) { m in
                SwitchRow(label: m.label, isOn: announceMode == m, onChange: { if $0 { announceMode = m; AnnounceMode.current = m } })
            }
            if announceMode == .app {
                Text(trSpoken("سرعة صوت التطبيق")).font(.system(size: 14)).foregroundColor(Palette.text)
                Slider(value: $speechRate, in: 0.3...0.65, step: 0.05)
                    .accessibilityLabel(spokenText("سرعة صوت التطبيق"))
                    .accessibilityValue("\(Int((speechRate - 0.3) / 0.35 * 100))%")
                    .onChange(of: speechRate) { v in AppSpeech.rate = v }
                MButton("تجربة الصوت") { Announcer.announceNow("Mohanad: 10 هاص") }
            }
            // المطور بس: إعلان يوصل لكل مستخدمي التطبيق مرة وحدة
            if session.profile?.dev == true || session.profile?.unlimited == true {
                SectionTitle("إعلان المطور")
                TextEditor(text: $annText)
                    .frame(minHeight: 110).padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.green700, lineWidth: 1))
                    .foregroundColor(Palette.text)
                    .accessibilityLabel(spokenText("نص الإعلان"))
                Text(trSpoken("يوصل لكل اللي يفتحون التطبيق مرة وحدة (المتصلين الحين واللي يدخلون بعدين)، وما يقدرون يردون عليه.")).font(.system(size: 12)).foregroundColor(Palette.textDim)
                MButton("إرسال للكل", .primary, enabled: !annText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    let t = String(annText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
                    Task { let ok = await Announce.shared.send(t); await MainActor.run { annMsg = ok ? "انرسل الإعلان" : "ما انرسل، جرّب مرة ثانية"; if ok { annText = "" } } }
                }
                MButton("مسح الإعلان الحالي") {
                    Task { let ok = await Announce.shared.send(""); await MainActor.run { annMsg = ok ? "انمسح الإعلان، ما بيطلع لأحد بعد الحين" : "ما انمسح، جرّب مرة ثانية" } }
                }
                if !annMsg.isEmpty { Text(trSpoken(annMsg)).font(.system(size: 13)).foregroundColor(Palette.goldSoft) }
            }
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
