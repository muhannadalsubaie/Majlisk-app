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
    let navigate: (Route) -> Void
    @State private var getCoins = false
    var body: some View {
        Screen(scroll: false) {
            HStack {
                VStack(alignment: .leading) {
                    Title("مجلسك")
                    if let name = profile?.username, !name.isEmpty { Note("أهلاً \(name)") }
                }
                Spacer()
                CoinsBadge(profile: profile)
            }
            // شعار التطبيق في المنتصف، والقائمة في أسفل الشاشة
            HStack { Spacer(); Logo(size: 180); Spacer() }.frame(maxHeight: .infinity)
            MButton("إنشاء طاولة", .primary) { navigate(.createTable) }
            MButton("انضمام إلى طاولة", .primary) { navigate(.joinTable) }
            MButton("الأصدقاء") { navigate(.friends) }
            MButton("الحصول على عملات 🪙") { getCoins = true }
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
    @State private var isPrivate = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        if let game = picked {
            Screen {
                TopBar("طاولة \(gameTitle(game, "classic"))", onBack: { picked = nil })
                let balance = profile?.unlimited == true ? "لا محدود" : "\(profile?.coins.map(String.init) ?? "…") عملة"
                Note("رصيدك: \(balance). إنشاء الطاولة بعملتين، وكل روبوت تضيفه بعملة.")
                SwitchRow(label: "طاولة خاصة", isOn: isPrivate, onChange: { isPrivate = $0 }, description: "الطاولة الخاصة تظهر في القائمة مقفلة، ولا يدخلها إلا من تدعوه.")
                if !error.isEmpty { Text(error).foregroundColor(Palette.goldSoft) }
                MButton("إنشاء الطاولة (2 🪙)", .primary, enabled: !busy) {
                    busy = true; error = ""
                    Task { @MainActor in
                        do {
                            let id = try await Tables.create(isPrivate: isPrivate, kind: game, variant: "classic")
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
        } else {
            Screen {
                TopBar("اختر اللعبة", onBack: { navigate(.menu) })
                Spacer().frame(height: 28)
                GameTile(name: "بلوت", image: "baloot_table") { picked = "baloot" }
                Note("الدومينو والجاكارو واللودو تُضاف قريباً لهذه النسخة.")
            }
        }
    }
}

private let STATUS = ["waiting": "بانتظار اللاعبين", "playing": "جارية", "finished": "بانتظار مباراة جديدة"]

struct JoinTableScreen: View {
    let navigate: (Route) -> Void
    let openTable: (String) -> Void
    @State private var rows: [TableRow]?
    @State private var busy = ""
    @State private var reg: ListenerRegistration?

    var body: some View {
        Screen {
            TopBar("الطاولات النشطة", onBack: { navigate(.menu) })
            Note("الانضمام بعملة واحدة. إن كانت المقاعد ممتلئة تدخل مشاهداً.")
            if rows == nil { BodyText("جارٍ التحميل…") }
            else if rows!.isEmpty { BodyText("لا توجد طاولات الآن — أنشئ طاولة جديدة.") }
            ForEach(rows ?? []) { r in
                let game = gameTitle(r.kind, r.variant)
                let soon = r.kind != "baloot"
                let spoken = "\(game)، طاولة \(r.ownerName)، \(r.isPrivate ? "مقفلة، " : "")\(r.players) من 4 لاعبين، \(r.people) حاضرين، \(STATUS[r.status] ?? "")\(soon ? "، قريباً في هذه النسخة" : "")"
                MButton("\(r.isPrivate ? "🔒 " : "")طاولة \(r.ownerName) · \(game) · \(r.players)/4 · \(STATUS[r.status] ?? "")",
                        enabled: !r.isPrivate && !soon && busy != r.id, label: spoken) {
                    busy = r.id
                    Task { @MainActor in
                        do { try await Tables.join(r.id); openTable(r.id) } catch { Announcer.announce(Tables.error(error, "تعذّر الانضمام")) }
                        busy = ""
                    }
                }
            }
        }
        .onAppear { reg = Tables.listen { list in DispatchQueue.main.async { rows = list } } }
        .onDisappear { reg?.remove(); reg = nil }
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
