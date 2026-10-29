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
    private var isOwner: Bool { v.ownerUid == uid }

    /// كل الموجودين الذين يمكن وضعهم في مقعد: الجالسون في مقاعد أخرى والمشاهدون
    private func candidates(_ seat: Int) -> [Candidate] {
        let seated = (0..<4).filter { $0 != seat && v.seat($0) != nil }.map { Candidate(id: v.seatUid($0), label: "\(occupantLabel(v, $0)) — من المقعد \($0 + 1)") }
        let watching = v.spectators.map { Candidate(id: $0.uid, label: "\($0.username)\($0.uid == uid ? " (أنت)" : "") — مشاهد") }
        return (seated + watching).filter { !$0.id.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("المقاعد")
            ForEach([Team(id: "الفريق الأول", seats: [0, 2]), Team(id: "الفريق الثاني", seats: [1, 3])]) { team in
                Text(team.id).foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
                ForEach(team.seats, id: \.self) { i in
                    ItemRow {
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
            if isOwner { MButton("بدء المباراة", .primary, enabled: v.seats.count == 4 && v.seats.allSatisfy { $0 != nil }) { conn.send("start") } }
            else { BodyText("بانتظار مالك الطاولة لبدء المباراة") }
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
            if friends == nil { BodyText("جارٍ التحميل…") }
            else if friends!.isEmpty { BodyText("لا يوجد أصدقاء بعد. أضفهم من شاشة الأصدقاء، أو أضف روبوتاً.") }
            ForEach((friends ?? []).sorted { $0.online && !$1.online }) { f in
                ItemRow {
                    Text("\(f.username)، \(f.online ? "متصل" : "غير متصل")").frame(maxWidth: .infinity, alignment: .leading)
                    if f.online {
                        SmallButton("دعوة", enabled: busy != f.uid, label: "دعوة \(f.username)") {
                            busy = f.uid
                            Task { @MainActor in
                                do {
                                    try await Social.inviteFriend(tableId: tableId, uid: f.uid, seat: seat)
                                    Announcer.announce(seat != nil ? "أُرسلت الدعوة إلى \(f.username) للمقعد \(seat! + 1)" : "أُرسلت الدعوة إلى \(f.username)")
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
struct VoiceButton: View {
    let tableId: String
    let uid: String
    @ObservedObject private var voice = Voice.shared

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
            .accessibilityLabel(status)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleMute() }
            .accessibilityAction(named: Text(voice.joined ? "الخروج من المحادثة الصوتية" : "العودة للمحادثة الصوتية")) { toggleJoin() }
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
