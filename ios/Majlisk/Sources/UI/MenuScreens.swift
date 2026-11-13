import SwiftUI
import FirebaseFirestore

struct CoinsBadge: View {
    let profile: Profile?
    var body: some View {
        let unlimited = profile?.unlimited == true
        let coins = profile?.coins
        Text(unlimited ? "🪙 ∞" : "🪙 \(coins.map(String.init) ?? "…")")
            .font(.system(size: 18, weight: .bold)).foregroundColor(Palette.gold)
            .accessibilityLabel(unlimited ? "رصيدك عملات لا محدودة، حساب المطوّر" : coins == nil ? "الرصيد غير متاح بعد" : "رصيدك \(coins!) عملة")
    }
}

struct MainMenuScreen: View {
    let profile: Profile?
    var openTable: (String) -> Void = { _ in }
    let navigate: (Route) -> Void
    @State private var getCoins = false
    var body: some View {
        Screen(scroll: false) {
            HStack(spacing: 10) {
                // صورتك الدائرية: تفتح الملف الشخصي
                Button { navigate(.profile) } label: { Avatar(uid: Session.shared.uid, name: profile?.username ?? "", size: 48) }
                    .buttonStyle(.plain).accessibilityLabel("الملف الشخصي")
                VStack(alignment: .leading) {
                    Title("مجلسك")
                    if let name = profile?.username, !name.isEmpty { Note("أهلاً \(name)") }
                    // عدد المتصلين في التطبيق كله (يتحدث على طول)، والضغط يعرض أسماءهم
                    OnlineLine(openTable: openTable)
                }
                Spacer()
                CoinsBadge(profile: profile)
            }
            // شعار التطبيق في المنتصف، والقائمة في أسفل الشاشة
            HStack { Spacer(); Logo(size: 180); Spacer() }.frame(maxHeight: .infinity)
            // الباقة الاحترافية: زر ذهبي بارز (للمشترك: «باقتك الاحترافية»)
            GoldButton(title: profile?.isPro == true ? "👑 باقتك الاحترافية" : "👑 الباقة الاحترافية") { navigate(.pro) }
            MButton("إنشاء طاولة", .primary) { navigate(.createTable) }
            MButton("انضمام إلى طاولة", .primary) { navigate(.joinTable) }
            MButton("الأصدقاء") { navigate(.friends) }
            MButton("الحصول على عملات 🪙") { getCoins = true }
            MButton("الملف الشخصي") { navigate(.profile) }
            MButton("الإعدادات") { navigate(.settings) }
        }
        .sheet(isPresented: $getCoins) {
            Sheet(title: "الحصول على عملات") {
                MButton("شراء عملات", .primary) { getCoins = false; navigate(.shop) }
                MButton("مشاهدة إعلان (+2 🪙)", .primary, label: "مشاهدة إعلان للحصول على عملتين") {
                    getCoins = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Ads.watch() }
                }
                MButton("إلغاء") { getCoins = false }
            }
        }
    }
}

struct CreateTableScreen: View {
    let profile: Profile?
    let navigate: (Route) -> Void
    let openTable: (String) -> Void
    // أولاً تختار اللعبة، ثم إعدادات الطاولة
    @State private var picked: String?
    @State private var variant = "classic"
    @State private var isPrivate = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        if let game = picked {
            Screen {
                TopBar("طاولة \(gameTitle(game, variant))", onBack: { picked = nil })
                // الجاكارو: عادي أو كمبلكس — لودو: فردي أو فرق
                let variants: [(String, String)] = game == "jackaroo" ? [("classic", "عادي"), ("complex", "كمبلكس")] : game == "ludo" ? [("classic", "فردي"), ("teams", "فرق")] : game == "domino" ? [("classic", "100"), ("t150", "150"), ("t200", "200")] : []
                if !variants.isEmpty {
                    Text(game == "domino" ? "هدف المباراة (نقاط)" : "النسخة").foregroundColor(Palette.textDim).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 10) {
                        ForEach(variants, id: \.0) { opt in
                            if variant == opt.0 { MButton("✓ \(opt.1)", .primary, label: "\(opt.1)، محددة") {} }
                            else { MButton(opt.1) { variant = opt.0 } }
                        }
                    }
                }
                SwitchRow(label: "طاولة خاصة", isOn: isPrivate, onChange: { isPrivate = $0 })
                if !error.isEmpty { Text(error).foregroundColor(Palette.goldSoft) }
                MButton("إنشاء الطاولة (2 🪙)", .primary, enabled: !busy) {
                    busy = true; error = ""
                    Task { @MainActor in
                        do {
                            let id = try await Tables.create(isPrivate: isPrivate, kind: game, variant: variant)
                            Announcer.announce("تم إنشاء الطاولة")
                            openTable(id)
                        } catch {
                            self.error = Tables.error(error, "تعذّر إنشاء الطاولة، حاول مرة أخرى")
                            Announcer.announce(self.error)
                        }
                        busy = false
                    }
                }
            }
            // إيماءة الرجوع (VoiceOver: حرف Z بإصبعين): من إعدادات اللعبة لقائمة الألعاب
            .accessibilityAction(.escape) { picked = nil }
        } else {
            Screen {
                TopBar("اختر اللعبة", onBack: { navigate(.menu) })
                Spacer().frame(height: 28)
                GameTile(name: "بلوت", image: "baloot_table") { picked = "baloot"; variant = "classic" }
                GameTile(name: "دومينو", image: "domino_table") { picked = "domino"; variant = "classic" }
                GameTile(name: "جاكارو", image: "jackaroo_table") { picked = "jackaroo"; variant = "classic" }
                GameTile(name: "لودو", image: "ludo_table") { picked = "ludo"; variant = "classic" }
            }
            // ومن قائمة الألعاب للقائمة الرئيسية
            .accessibilityAction(.escape) { navigate(.menu) }
        }
    }
}

private let STATUS = ["waiting": "في الانتظار", "playing": "قيد اللعب", "finished": "في الانتظار"]

struct JoinTableScreen: View {
    let navigate: (Route) -> Void
    let openTable: (String) -> Void
    @State private var rows: [TableRow]?
    @State private var busy = ""
    @State private var reg: ListenerRegistration?
    /// ضغطة مطولة على طاولة: قائمة الموجودين فيها
    @State private var showing: TableRow?
    /// الضغطة المطولة ما تنحسب ضغطة انضمام بعد ما ترفع إصبعك
    @State private var longPressed: String?

    var body: some View {
        Screen {
            TopBar("الطاولات النشطة", onBack: { navigate(.menu) })
            if rows == nil { BodyText("جارٍ التحميل…") }
            else if rows!.isEmpty { BodyText("لا توجد طاولات الآن — أنشئ طاولة جديدة.") }
            ForEach(rows ?? []) { r in
                let game = gameTitle(r.kind, r.variant)
                let spoken = "طاولة \(r.ownerName)، \(game)، \(r.isPrivate ? "مقفلة، " : "")عدد الموجودين \(r.people)، \(STATUS[r.status] ?? "")"
                MButton("\(r.isPrivate ? "🔒 " : "")طاولة \(r.ownerName) · \(game) · الموجودين \(r.people) · \(STATUS[r.status] ?? "")",
                        enabled: !r.isPrivate && busy != r.id, label: spoken) {
                    if longPressed == r.id { longPressed = nil; return }
                    busy = r.id
                    Task { @MainActor in
                        do { try await Tables.join(r.id); openTable(r.id) } catch { Announcer.announce(Tables.error(error, "تعذّر الانضمام")) }
                        busy = ""
                    }
                }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPressed = r.id; showing = r })
                .accessibilityAction(named: "عرض الموجودين") { showing = r }
            }
        }
        .onChange(of: showing?.id) { id in if id == nil { longPressed = nil } }
        .alert(item: $showing) { r in
            Alert(title: Text("الموجودين في طاولة \(r.ownerName)"), message: Text(r.membersText), dismissButton: .default(Text("تم")))
        }
        // الطاولات الخاصة ما تظهر في القائمة (ولا من فيها)، وترجع تظهر أول ما تصير عامة
        .onAppear { reg = Tables.listen { list in DispatchQueue.main.async { update(list.filter { !$0.isPrivate }) } } }
        .onDisappear { reg?.remove(); reg = nil }
    }

    /// ترتيب ثابت (والجديدة تظهر فوق)، ولا نحدّث القائمة إلا إذا تغيّر ما يُقرأ، حتى لا يعيد VoiceOver قراءة الطاولة المحددة
    private func update(_ list: [TableRow]) {
        let pos = Dictionary(uniqueKeysWithValues: (rows ?? []).enumerated().map { ($1.id, $0) })
        let sorted = list.enumerated().sorted { (pos[$0.element.id] ?? -1, $0.offset) < (pos[$1.element.id] ?? -1, $1.offset) }.map(\.element)
        let sig = { (l: [TableRow]) in l.map { "\($0.id)|\($0.ownerName)|\($0.isPrivate)|\($0.people)|\($0.status)|\($0.membersText)" } }
        if rows == nil || sig(sorted) != sig(rows!) { rows = sorted }
    }
}

/// مربع لعبة عريض: اسمها على اليمين وصورتها على اليسار، ويُقرأ زراً واحداً باسم اللعبة
struct GameTile: View {
    let name: String
    let image: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(name).font(.system(size: 30, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                if let path = Bundle.main.path(forResource: image, ofType: "png", inDirectory: "Media"), let img = UIImage(contentsOfFile: path) {
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 128)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 150)
        }
        .buttonStyle(RaisedStyle(base: Palette.gold, fg: Palette.green900))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isButton)
    }
}
