import SwiftUI

/// اسم الجالس في مقعد مع وسومه (أنت، روبوت)
func occupantLabel(_ v: TableView, _ i: Int) -> String {
    guard let s = v.seat(i) else { return "فارغ" }
    let tags = [i == v.mySeat ? "أنت" : nil, s.isBot ? "روبوت" : nil].compactMap { $0 }
    return s.username + (tags.isEmpty ? "" : " (\(tags.joined(separator: "، ")))")
}

private struct Candidate: Identifiable { let id: String; let label: String }
private struct Team: Identifiable { let id: String; let seats: [Int] }

private enum SeatPanel: Identifiable {
    case invite(Int), add(Int), change(Int)
    var id: String { switch self { case .invite(let s): return "i\(s)"; case .add(let s): return "a\(s)"; case .change(let s): return "c\(s)" } }
}

/// المقاعد قبل بدء المباراة، مقسّمة بالفريقين.
/// مالك الطاولة: يدعو صديقاً لمقعد فارغ، أو "إضافة لاعب" (أحد الموجودين أو روبوت)،
/// ويغيّر من يجلس في كل مقعد، ويُخلي أي مقعد.
struct SeatsLobby: View {
    let v: TableView
    let uid: String
    @ObservedObject var conn: TableConnection
    @State private var panel: SeatPanel?
    /// وقت كل دور اللي اختاره المالك (٠ = بدون)
    @State private var turnLimit = 0
    /// نافذة إعدادات المباراة (تفتح من «بدء المباراة»)
    @State private var setup = false
    /// خيارات الباقة الاحترافية (البلوت، والمالك مشترك): تنضبط قبل البداية بس
    @ObservedObject private var session = Session.shared
    @State private var manual = false
    @State private var qaid = false
    private var pro: Bool { session.profile?.isPro == true }
    private var isOwner: Bool { v.ownerUid == uid }

    /// كل الموجودين الذين يمكن وضعهم في مقعد: الجالسون في مقاعد أخرى والمشاهدون
    private func candidates(_ seat: Int) -> [Candidate] {
        let seated = (0..<4).filter { $0 != seat && v.seat($0) != nil }.map { Candidate(id: v.seatUid($0), label: "\(occupantLabel(v, $0)) — من المقعد \($0 + 1)") }
        let watching = v.spectators.map { Candidate(id: $0.uid, label: "\($0.username)\($0.uid == uid ? " (أنت)" : "") — مشاهد") }
        return (seated + watching).filter { !$0.id.isEmpty }
    }

    @State private var targetText = ""

    /// خيار من اثنين (فردي/فرق، عادي/كومبلكس): المالك يغيّره، والباقين يشوفونه بس
    @ViewBuilder private func choice(_ a: String, _ b: String, second: Bool, send: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach([false, true], id: \.self) { isB in
                let on = isB == second
                SmallButton(isB ? b : a, primary: on, label: "\(isB ? b : a)\(on ? "، محدد" : "")") { if isOwner && !on { send(isB) } }
                    .disabled(!isOwner && !on)
            }
        }
    }

    /// خيارات اللعبة فوق المقاعد
    @ViewBuilder private var options: some View {
        if v.kind == "ludo" || v.kind == "domino" {
            choice("فردي", "فرق", second: v.optTeams) { conn.send("setOptions", ["teams": $0]) }
        }
        if v.kind == "jackaroo" {
            choice("عادي", "كومبلكس", second: v.optComplex) { conn.send("setOptions", ["complex": $0]) }
        }
        if v.kind == "domino" {
            if isOwner {
                HStack(spacing: 8) {
                    TextField("نهاية المباراة", text: $targetText)
                        .keyboardType(.numberPad)
                        .padding(10).background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("نهاية المباراة، الحالية \(v.optTarget)")
                    SmallButton("حفظ", primary: true, label: "حفظ نهاية المباراة") {
                        if let n = Int(targetText.filter(\.isNumber)) { conn.send("setOptions", ["target": n]) }
                    }
                }
                .onAppear { targetText = "\(v.optTarget)" }
                .onChange(of: v.optTarget) { targetText = "\($0)" }
            } else {
                Note("نهاية المباراة: \(v.optTarget)")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            options
            SectionTitle("المقاعد")
            ForEach([Team(id: "الفريق الأول", seats: [0, 2]), Team(id: "الفريق الثاني", seats: [1, 3])]) { team in
                Text(team.id).foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
                ForEach(team.seats, id: \.self) { i in
                    ItemRow {
                        if let m = v.seat(i) { Avatar(uid: v.seatUid(i), name: m.username, size: 32) }
                        Text("المقعد \(i + 1): \(occupantLabel(v, i))").frame(maxWidth: .infinity, alignment: .leading)
                        if isOwner {
                            if v.seat(i) == nil {
                                SmallButton("دعوة صديق", label: "دعوة صديق للمقعد \(i + 1)") { panel = .invite(i) }
                                SmallButton("إضافة لاعب", label: "إضافة لاعب في المقعد \(i + 1)") { panel = .add(i) }
                            } else {
                                SmallButton("تغيير", label: "تغيير المقعد \(i + 1)") { panel = .change(i) }
                            }
                        }
                    }
                }
            }
            if !v.spectators.isEmpty {
                Note("المشاهدون: " + v.spectators.map { $0.uid == uid ? "\($0.username) (أنت)" : $0.username }.joined(separator: "، "))
            }
            // «بدء المباراة» يفتح نافذة إعدادات المباراة: فيها وقت كل دور (قائمة منسدلة) وأي إعدادات تنضاف بعدين، ثم «ابدأ»
            if isOwner { MButton("بدء المباراة", .primary, enabled: v.startCounts.contains(v.seats.filter { $0 != nil }.count)) { setup = true } }
            else { BodyText("بانتظار مالك الطاولة لبدء المباراة") }
        }
        .sheet(isPresented: $setup) {
            Sheet(title: "إعدادات المباراة") {
                Menu {
                    ForEach(TURN_LIMITS, id: \.self) { s in
                        Button(s == turnLimit ? "✓ \(turnLimitLabel(s))" : turnLimitLabel(s)) { turnLimit = s }
                    }
                } label: {
                    Text("وقت كل دور: \(turnLimitLabel(turnLimit)) ▾")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(Palette.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.green900).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("وقت كل دور، \(turnLimitLabel(turnLimit))")
                Note("لو خلص وقت اللاعب، الروبوت يلعب عنه أفضل حركة.")
                if v.kind == "baloot" {
                    if pro {
                        SwitchRow(label: "إعلان المشاريع يدوي", isOn: manual, onChange: { manual = $0 })
                        SwitchRow(label: "القيد والقطع", isOn: qaid, onChange: { qaid = $0 })
                        Note("🔒 هذي الخيارات تنضبط قبل بداية المباراة بس. بعد ما تبدأ يتغير المؤقت فقط.")
                    } else if session.profile?.proAccess == true {
                        Note("👑 إعلان المشاريع يدوي، والقيد والقطع، وتغيير المؤقت أثناء اللعب: للمشتركين في الباقة الاحترافية.")
                    }
                }
                MButton("ابدأ", .primary, enabled: v.startCounts.contains(v.seats.filter { $0 != nil }.count)) { setup = false; conn.send("start", ["turnLimit": turnLimit, "manualProjects": pro && manual, "qaid": pro && qaid]) }
                MButton("إلغاء") { setup = false }
            }
        }
        .sheet(item: $panel) { p in
            switch p {
            case .invite(let seat):
                InviteFriendsSheet(tableId: v.id, seat: seat, title: "دعوة صديق للمقعد \(seat + 1)") { panel = nil }
            case .add(let seat):
                Sheet(title: "إضافة لاعب في المقعد \(seat + 1)") {
                    let list = candidates(seat)
                    ForEach(list) { c in MButton(c.label) { conn.send("replace", ["seat": seat, "uid": c.id]); panel = nil } }
                    if list.isEmpty { BodyText("لا يوجد أحد آخر في الطاولة.") }
                    MButton("إضافة روبوت (1 🪙)", .primary, label: "إضافة روبوت، عملة واحدة") { conn.send("addBot", ["seat": seat]); panel = nil }
                    MButton("رجوع") { panel = nil }
                }
            case .change(let seat):
                Sheet(title: "المقعد \(seat + 1): \(occupantLabel(v, seat))") {
                    let list = candidates(seat)
                    ForEach(list) { c in MButton(c.label) { conn.send("replace", ["seat": seat, "uid": c.id]); panel = nil } }
                    if list.isEmpty { BodyText("لا يوجد أحد آخر في الطاولة.") }
                    let info = v.seat(seat)
                    MButton(info?.isBot == true ? "إزالة الروبوت" : seat == v.mySeat ? "أخلِ مقعدي وأصبح مشاهداً" : "إخلاء المقعد (يصبح مشاهداً)", .danger) {
                        conn.send("vacate", ["seat": seat]); panel = nil
                    }
                    MButton("رجوع") { panel = nil }
                }
            }
        }
    }
}

/// قائمة الأصدقاء مع حالة الاتصال (تُحدَّث كل 10 ثوانٍ) وزر دعوة للمتصلين
struct InviteFriendsSheet: View {
    let tableId: String
    let seat: Int?
    let title: String
    let onClose: () -> Void
    @State private var friends: [Friend]?
    @State private var busy = ""

    var body: some View {
        Sheet(title: title) {
            // الأصدقاء اللي موجودين في نفس الطاولة (جالسين أو يتفرجون) ما يطلعون في الدعوة
            let outside = (friends ?? []).filter { $0.tableId != tableId }
            if friends == nil { BodyText("جارٍ التحميل…") }
            else if friends!.isEmpty { BodyText("لا يوجد أصدقاء بعد. أضفهم من شاشة الأصدقاء، أو أضف روبوتاً.") }
            else if outside.isEmpty { BodyText("كل أصدقائك موجودين في الطاولة.") }
            ForEach(outside.sorted { $0.online && !$1.online }) { f in
                ItemRow {
                    Text("\(f.username)، \(f.online ? "متصل" : "غير متصل")").frame(maxWidth: .infinity, alignment: .leading)
                    // غير المتصل تصله الدعوة إشعار على جواله
                    Group {
                        SmallButton("دعوة", enabled: busy != f.uid, label: "دعوة \(f.username)") {
                            busy = f.uid
                            Task { @MainActor in
                                do {
                                    try await Social.inviteFriend(tableId: tableId, uid: f.uid, seat: seat)
                                    // الخادم يعلن للكل «فلان أرسل دعوة إلى فلان» (وتنكتب في الدردشة)، فما نكررها هنا
                                    if seat != nil { onClose() }
                                } catch { Announcer.announce(Social.error(error)) }
                                busy = ""
                            }
                        }
                    }
                }
            }
            MButton("رجوع", action: onClose)
        }
        .task {
            while !Task.isCancelled {
                if let s = try? await Social.listFriends() { friends = s.friends } else if friends == nil { friends = [] }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
}

private struct MatchGroup: Identifiable { let id: Int; let hands: [HandRecord] }
private struct Numbered: Identifiable { let id: Int; let record: HandRecord }

private let LEVELS = [2: "دبل", 3: "ثري", 4: "فور"]

/// سجل المباراة: كل صكة بأبناطها ثم مشاريعها ثم نقاطها، كلٌّ في سطر — فقرة واحدة تُقرأ دفعة واحدة
struct HistoryView: View {
    let history: [HandRecord]
    let onClose: () -> Void

    private func lines(_ r: HandRecord, _ n: Int) -> String {
        let level = r.gahwa ? "قهوة" : LEVELS[r.level] ?? ""
        let tm = { (x: Int) in r.teams[safe: x] ?? "" }
        let p = r.projects ?? []
        let projects = (p[safe: 0] ?? 0) != 0 || (p[safe: 1] ?? 0) != 0 ? "\(tm(0)) \(p[0])، \(tm(1)) \(p[1])" : "لا توجد"
        return [
            "الصكة \(n): \(r.contract)\(level.isEmpty ? "" : " \(level)")\(r.kaboot != nil ? "، كبوت" : "").",
            "المشتري: \(r.buyer) (\(tm(r.buyerTeam))).",
            "الأبناط: \(tm(0)) \(r.abnat[safe: 0] ?? 0)، \(tm(1)) \(r.abnat[safe: 1] ?? 0).",
            "المشاريع: \(projects).",
            "النقاط: \(tm(0)) \(r.points[safe: 0] ?? 0)، \(tm(1)) \(r.points[safe: 1] ?? 0).",
        ].joined(separator: "\n")
    }

    var body: some View {
        Sheet(title: "السجل") {
            if history.isEmpty { BodyText("لم تنتهِ أي صكة بعد") }
            let matches = Dictionary(grouping: history, by: \.match).sorted { $0.key > $1.key }.map { MatchGroup(id: $0.key, hands: $0.value) }
            ForEach(matches) { m in
                let match = m.id
                let hands = m.hands
                let t0 = hands.reduce(0) { $0 + ($1.points[safe: 0] ?? 0) }
                let t1 = hands.reduce(0) { $0 + ($1.points[safe: 1] ?? 0) }
                Text("المباراة \(match): \(hands[0].teams[safe: 0] ?? "") \(t0)، \(hands[0].teams[safe: 1] ?? "") \(t1)")
                    .foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
                ForEach(hands.enumerated().map { Numbered(id: $0.offset, record: $0.element) }) { n in
                    Text(lines(n.record, n.id + 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Palette.green900).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            MButton("إغلاق", action: onClose)
        }
    }
}

/// زر المحادثة الصوتية — للاعبين والمشاهدين.
/// ضغطة: فتح/كتم الميكروفون. ومن إجراءات VoiceOver (أو الضغط المطول): انضمام/مغادرة.
/// بعد ما تلعب ورقة: مؤشر VoiceOver ينتقل لزر الميكروفون بصمت (اسمه مخفي لحظات)،
/// فتسمع ورقتك وباقي اللعب بدل اسم الزر، ويُقرأ عادي لما تحرك المؤشر.
final class MicFocus: ObservableObject {
    static let shared = MicFocus()
    @Published private(set) var request = 0
    @Published private(set) var silent = false

    func take() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        silent = true
        Announcer.interruptNextEvents()
        request += 1
        let n = request
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.request == n { self.silent = false } }
    }
}

struct VoiceButton: View {
    let tableId: String
    let uid: String
    @ObservedObject private var voice = Voice.shared
    @ObservedObject private var micFocus = MicFocus.shared
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        // أثناء إعادة الاتصال الصامتة يبقى الزر على حاله: في المحادثة والميكروفون مغلق
        let joined = voice.joined || voice.reconnecting
        let muted = voice.muted || voice.reconnecting
        let status = voice.busy && !voice.reconnecting ? "جارٍ الاتصال بالمحادثة الصوتية" : !joined ? "أنت خارج المحادثة الصوتية" : muted ? "الميكروفون مغلق" : "الميكروفون مفتوح"
        // نفس ألوان زر الميكروفون في التطبيق الحالي: ذهبي مفتوح، وأخضر بإطار ذهبي مغلق، وباهت خارج المحادثة
        let on = joined && !muted
        Text("🎤 \(status)")
            .font(.system(size: 13, weight: .bold))
            .lineLimit(2)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: 200, minHeight: 40)
            .foregroundColor(!joined ? Palette.textDim : muted ? Palette.gold : Palette.green900)
            .background(on ? Palette.gold : Palette.green700)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.gold, lineWidth: joined && muted ? 2 : 1))
            .onTapGesture(perform: toggleMute)
            .onLongPressGesture(perform: toggleJoin)
            .accessibilityElement(children: .ignore)
            // صامت بعد لعب ورقة: بلا أي نص
            .accessibilityLabel(micFocus.silent ? "" : status)
            // صامت بعد لعب ورقة: ما ينطق شي أبداً (ولا «زر»)، عشان تسمع لعب اللي بعدك
            .accessibilityAddTraits(micFocus.silent ? [] : .isButton)
            .accessibilityRemoveTraits(micFocus.silent ? [.isButton, .isStaticText] : [])
            .accessibilityAction { toggleMute() }
            .accessibilityAction(named: Text(voice.joined ? "الخروج من المحادثة الصوتية" : "العودة للمحادثة الصوتية")) { toggleJoin() }
            .accessibilityFocused($focused)
            .onChange(of: micFocus.request) { _ in focused = true }
    }

    private func toggleMute() {
        guard !voice.busy else { return }
        // خرجت بنفسك: الضغطة العادية لا تعيدك، العودة بالضغط المطول فقط
        if !voice.joined { Announcer.announce("أنت خارج المحادثة الصوتية"); return }
        Voice.shared.setMuted(!voice.muted)
    }

    private func toggleJoin() {
        guard !voice.busy else { return }
        if voice.joined { Voice.shared.leave() } else { Voice.shared.join(tableId, uid: uid) }
    }
}
