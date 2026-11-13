import SwiftUI

/// ألوان الباقة الاحترافية: ليلي وذهبي
enum Pro {
    static let night = Color(red: 0x10 / 255, green: 0x16 / 255, blue: 0x1C / 255)
    static let night2 = Color(red: 0x1F / 255, green: 0x2A / 255, blue: 0x35 / 255)
    static let deep = Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x14 / 255)
    static let gold = Color(red: 0xD9 / 255, green: 0xB4 / 255, blue: 0x5A / 255)
    static let goldLight = Color(red: 0xF1 / 255, green: 0xDD / 255, blue: 0xA0 / 255)
    static let goldDark = Color(red: 0x8A / 255, green: 0x6A / 255, blue: 0x22 / 255)
    static let ink = Color(red: 0x2A / 255, green: 0x1E / 255, blue: 0x05 / 255)
    static let dim = Color(red: 0xB9 / 255, green: 0xC4 / 255, blue: 0xBD / 255)
    static let emerald = Color(red: 0x1B / 255, green: 0x75 / 255, blue: 0x57 / 255)
    static let cream = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE2 / 255)

    /// مزايا الباقة (نفس الترتيب في كل الشاشات)
    static let features = [
        "اللعب بدون عملات طول مدة الاشتراك",
        "طاولات وألوان وأشكال مميزة لكل الألعاب",
        "طاولة ثابتة باسمك وبكلمة مرور",
        "إخفاء ظهورك أنك متصل",
        "إعلان المشاريع يدوي، والقيد والقطع",
        "زر «ورق» متاح لك حتى لو مو دورك",
        "تشغيل وإيقاف المؤقت أثناء اللعب",
        "إهداء الباقة لأي لاعب",
    ]
}

/// زر ذهبي (أو زمردي) بارز
struct GoldButton: View {
    let title: String
    var emerald = false
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 19, weight: .heavy)).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(RaisedStyle(base: emerald ? Pro.emerald : Pro.gold, fg: emerald ? .white : Pro.ink))
        .opacity(enabled ? 1 : 0.5).disabled(!enabled)
    }
}

private struct Crown: View {
    let size: CGFloat
    var body: some View {
        Text("👑").font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Pro.goldLight, Pro.gold, Pro.goldDark], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 5)
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}

private struct FeatureTile: View {
    let icon: String
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            Text(icon).font(.system(size: 28)).accessibilityHidden(true)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(Pro.cream).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 4)
        .background(Pro.deep).clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Pro.goldLight.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct PriceCard: View {
    let price: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(price).font(.system(size: 30, weight: .heavy)).foregroundColor(Pro.goldLight)
            Text("/ شهر").font(.system(size: 14, weight: .bold)).foregroundColor(Pro.cream)
            Spacer()
            Text("عرض لمدة\n6 أشهر فقط").font(.system(size: 12, weight: .bold)).foregroundColor(Pro.dim).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(red: 0.165, green: 0.14, blue: 0.075), Color(red: 0.1, green: 0.086, blue: 0.043)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Pro.gold, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("السعر \(price) في الشهر، عرض لمدة 6 أشهر فقط")
    }
}

/// نافذة العرض: تطلع أول ما يفتح التطبيق لغير المشتركين (وما ترجع قبل يومين لو قال «ليس الآن»)
struct ProOfferView: View {
    let onSubscribe: () -> Void
    let onDismiss: () -> Void
    @State private var price = Store.proPriceFallback
    private let tiles = [("🎲", "طاولات مميزة"), ("🃏", "ورق وأحجار بأشكالك"), ("🪙", "العب بدون عملات"),
                         ("🔒", "طاولة ثابتة بكلمة مرور"), ("⏱️", "تحكم بالمؤقت ومشاريع يدوية"), ("🎁", "أهدِ الباقة لصديقك")]
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea().onTapGesture(perform: onDismiss).accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 12) {
                    Text("عرض لفترة محدودة").font(.system(size: 13, weight: .heavy)).foregroundColor(Pro.ink)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(LinearGradient(colors: [Pro.goldLight, Pro.gold], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.top, -6)
                    ZStack(alignment: .topTrailing) {
                        Logo(size: 104).overlay(RoundedRectangle(cornerRadius: 104 * 0.22).stroke(Pro.gold, lineWidth: 3))
                            .padding(.top, 10).padding(.trailing, 10)
                        Crown(size: 38)
                    }
                    .accessibilityLabel("شعار مجلسك")
                    Text("الباقة الاحترافية").font(.system(size: 28, weight: .heavy)).foregroundColor(Pro.goldLight).accessibilityAddTraits(.isHeader)
                    Text("ارفع مستوى مجلسك").font(.system(size: 14)).foregroundColor(Pro.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(tiles, id: \.1) { FeatureTile(icon: $0.0, label: $0.1) }
                    }
                    PriceCard(price: price)
                    GoldButton(title: "اشترك الآن", emerald: true, action: onSubscribe)
                    Button(action: onDismiss) {
                        Text("ليس الآن").font(.system(size: 15, weight: .bold)).foregroundColor(Pro.dim).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 16)
                .background(LinearGradient(colors: [Pro.night2, Pro.night], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(Pro.goldLight.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.75), radius: 30, y: 16)
                .padding(.horizontal, 16).padding(.vertical, 40)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityAddTraits(.isModal)
        .task { price = await Store.proPrice() }
    }
}

/// شاشة الباقة الاحترافية: المزايا والسعر والاشتراك، والإهداء
struct ProScreen: View {
    let profile: Profile?
    let onBack: () -> Void
    let onGift: () -> Void
    @State private var price = Store.proPriceFallback
    @State private var busy = false
    var body: some View {
        Screen {
            TopBar("الباقة الاحترافية", onBack: onBack)
            HStack(spacing: 14) {
                Crown(size: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("الباقة الاحترافية").font(.system(size: 26, weight: .heavy)).foregroundColor(Pro.goldLight)
                    Text("كل مزايا مجلسك في اشتراك واحد").font(.system(size: 13)).foregroundColor(Pro.dim)
                }
            }
            if let p = profile, p.isPro {
                Text("✓ مشترك في الباقة حتى \(Date(timeIntervalSince1970: p.proUntil / 1000).formatted(.dateTime.day().month().year()))")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(Pro.goldLight)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Pro.deep).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Pro.gold, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Pro.features, id: \.self) { f in
                    HStack(spacing: 9) {
                        Text("✓").font(.system(size: 18, weight: .heavy)).foregroundColor(Pro.gold).accessibilityHidden(true)
                        Text(f).font(.system(size: 15, weight: .bold)).foregroundColor(Pro.cream)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Pro.deep).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Pro.goldLight.opacity(0.16), lineWidth: 1))
            PriceCard(price: price)
            if profile?.isPro != true {
                GoldButton(title: busy ? "جارٍ…" : "اشترك الآن", emerald: true, enabled: !busy) {
                    busy = true
                    Task { @MainActor in _ = await Store.buyPro(); busy = false }
                }
            }
            MButton("🎁 إهداء الباقة للاعب ثاني", action: onGift)
            MButton("استعادة المشتريات") { Task { await Store.syncPro(announce: true) } }
            Note("الاشتراك يتجدد تلقائياً كل شهر، وتقدر تلغيه في أي وقت من إعدادات اشتراكات Apple.")
            HStack(spacing: 16) {
                Link("الشروط", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("الخصوصية", destination: URL(string: Api.site + "/privacy.html")!)
            }
            .font(.system(size: 13, weight: .bold)).foregroundColor(Pro.goldLight).frame(maxWidth: .infinity)
        }
        .task { price = await Store.proPrice() }
    }
}

/// إهداء الباقة: اسم المستخدم ← نتأكد منه ← الدفع عنه (شهر، ما يتجدد تلقائياً)
struct GiftScreen: View {
    let onBack: () -> Void
    @State private var name = ""
    @State private var found: String?
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        Screen {
            TopBar("إهداء الباقة", onBack: onBack)
            HStack {
                Spacer()
                Text("🎁").font(.system(size: 50)).frame(width: 96, height: 96)
                    .background(LinearGradient(colors: [Pro.goldLight, Pro.gold, Pro.goldDark], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 28)).shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                    .rotationEffect(.degrees(4)).accessibilityHidden(true)
                Spacer()
            }
            BodyText("اكتب اسم المستخدم اللي تبي تهديه الباقة الاحترافية لمدة شهر، وادفع بالنيابة عنه.")
            Field(label: "اسم المستخدم", text: $name).onChange(of: name) { _ in found = nil; error = "" }
            if found == nil {
                MButton("تأكد من الاسم", enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !busy) {
                    busy = true; error = ""
                    Task { @MainActor in
                        do {
                            let r = try await Api.post("/gift/lookup", ["username": name.trimmingCharacters(in: .whitespaces)])
                            if !r.bool("found") { error = "ما لقينا لاعب بهذا الاسم" }
                            else if r.bool("self") { error = "هذا اسمك أنت — للاشتراك لنفسك ارجع لشاشة الباقة" }
                            else { found = r.str("username") }
                        } catch { self.error = "تعذّر التأكد الآن، حاول مرة ثانية" }
                        Announcer.announce(error.isEmpty ? "لقينا \(found ?? "")" : error)
                        busy = false
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundColor(Pro.goldLight) }
            if let who = found {
                HStack(spacing: 12) {
                    Text(String(who.prefix(1))).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                        .frame(width: 46, height: 46).background(Pro.emerald).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(who).font(.system(size: 17, weight: .bold)).foregroundColor(Pro.cream)
                        Text("الباقة الاحترافية · شهر واحد · \(Store.proPriceFallback)").font(.system(size: 13)).foregroundColor(Pro.dim)
                    }
                    Spacer()
                    Text("✓").font(.system(size: 22, weight: .heavy)).foregroundColor(Palette.online)
                }
                .padding(12).background(Pro.night2).clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .combine)
                GoldButton(title: busy ? "جارٍ…" : "ادفع وأهدِ الباقة", enabled: !busy) {
                    busy = true
                    Task { @MainActor in
                        if await Store.buyGift(to: who) { onBack() }
                        busy = false
                    }
                }
                Note("يوصله إشعار بالهدية وتتفعل الباقة عنده شهر. ما تتجدد تلقائياً، وإذا انتهى الشهر تقدر تدفع وتجدد له شهر ثاني.")
            }
        }
    }
}
