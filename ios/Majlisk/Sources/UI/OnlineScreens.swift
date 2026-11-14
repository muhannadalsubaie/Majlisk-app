import SwiftUI

/// تحت اسمك في الشاشة الرئيسية: «المتصلون: ١٢» (يتحدث على طول)، والضغط يفتح قائمتهم
struct OnlineLine: View {
    let openTable: (String) -> Void
    @ObservedObject private var online = Online.shared
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            Text(online.count.map { "المتصلون: \($0)" } ?? "المتصلون: …")
                .font(.system(size: 14, weight: .bold)).foregroundColor(Palette.goldSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(online.count.map { "المتصلون الآن \($0)" } ?? "المتصلون، جارٍ التحميل")
        .accessibilityHint("يعرض أسماء المتصلين")
        .sheet(isPresented: $open) { OnlineSheet(close: { open = false }, openTable: { id in open = false; openTable(id) }) }
    }
}

/// وين اللاعب: «بلوت، طاولة عامة» أو «في الرئيسية»
private func placeText(_ p: OnlinePlayer) -> String {
    guard p.tableId != nil else { return "في الرئيسية" }
    return [p.tableGame, p.tablePrivate ? "طاولة خاصة" : "طاولة عامة"].filter { !$0.isEmpty }.joined(separator: "، ")
}

/// كل المتصلين: صورة واسم ووين هو (اللعبة، وعامة أو خاصة)، وجنبه «إضافة صديق».
/// الضغط يفتح ملفه، والضغط المطوّل يدخلك طاولته (العامة على طول، والخاصة بطلب انضمام)
private struct OnlineSheet: View {
    let close: () -> Void
    let openTable: (String) -> Void
    @ObservedObject private var online = Online.shared
    @ObservedObject private var hub = Hub.shared
    @State private var player: OnlinePlayer?
    @State private var sent: Set<String> = []
    @State private var joining = false

    private func say(_ t: String) { Announcer.announce(t) }

    /// الدخول لطاولته (نفس قائمة الأصدقاء): العامة على طول، والخاصة طلب انضمام وننتظر رد صاحبها
    private func enter(_ p: OnlinePlayer) {
        guard !joining, !p.me, let id = p.tableId else { return }
        joining = true
        Task { @MainActor in
            defer { joining = false }
            do {
                if p.tablePrivate {
                    var (st, mins) = try await Tables.requestJoin(id)
                    if st == "pending" { say("أُرسل طلب الانضمام لمالك الطاولة، ننتظر موافقته") }
                    var n = 0
                    while st == "pending" && n < 155 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if let r = try? await Tables.joinRequestStatus(id) { (st, mins) = r }
                        n += 1
                    }
                    switch st {
                    case "accepted": try await Tables.join(id); player = nil; openTable(id)
                    case "rejected": say("رفض مالك الطاولة طلب الانضمام، تقدر تدخل بدعوة منه أو تحاول بعد \(minutesText(mins))")
                    case "waiting": say("أرسلت نفس الطلب لهالطاولة قبل، ننتظر رد مالكها")
                    default: say("انتهى طلب الانضمام بدون رد من مالك الطاولة")
                    }
                } else {
                    try await Tables.join(id); player = nil; openTable(id)
                }
            } catch { say(Tables.error(error, p.tablePrivate ? "تعذّر إرسال طلب الانضمام" : "تعذّر الانضمام")) }
        }
    }

    private func addFriend(_ p: OnlinePlayer) {
        Task { @MainActor in
            do {
                let became = try await Social.requestFriend(p.username)
                sent.insert(p.uid)
                say(became ? "أصبحت أنت و\(p.username) أصدقاء" : "أُرسل طلب الصداقة إلى \(p.username)")
            } catch { say(Social.error(error)) }
        }
    }

    private func acceptFriend(_ p: OnlinePlayer) {
        Task { @MainActor in
            do { try await Social.respondFriend(p.uid, accept: true); say("أصبحت أنت و\(p.username) أصدقاء") } catch { say(Social.error(error)) }
        }
    }

    private func isFriend(_ p: OnlinePlayer) -> Bool { hub.state.friends.contains { $0.uid == p.uid } }
    private func asked(_ p: OnlinePlayer) -> Bool { hub.state.requests.contains { $0.uid == p.uid } }

    var body: some View {
        Sheet(title: online.count.map { "المتصلون الآن (\($0))" } ?? "المتصلون الآن") {
            if let list = online.list {
                if list.isEmpty { BodyText("ما فيه أحد متصل الحين") }
                ForEach(list) { p in row(p) }
            } else { BodyText("جارٍ التحميل…") }
            MButton("تحديث القائمة") { online.requestList() }
            MButton("إغلاق") { close() }
        }
        .onAppear { online.requestList() }
        .sheet(item: $player) { p in card(p) }
    }

    @ViewBuilder private func row(_ p: OnlinePlayer) -> some View {
        let friend = isFriend(p), req = asked(p)
        let relation: String? = p.me ? "أنت" : friend ? "صديقك" : sent.contains(p.uid) ? "أُرسل طلب الصداقة" : nil
        ItemRow {
            Avatar(uid: p.uid, name: p.username, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.me ? "\(p.username) (أنت)" : p.username).font(.system(size: 16, weight: .bold)).foregroundColor(Palette.text)
                Text(placeText(p)).font(.system(size: 13)).foregroundColor(Palette.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { player = p }
            .onLongPressGesture { enter(p) }
            if p.me { EmptyView() }
            else if friend { Text("صديقك").font(.system(size: 13)).foregroundColor(Palette.goldSoft) }
            else if sent.contains(p.uid) { Text("أُرسل").font(.system(size: 13)).foregroundColor(Palette.textDim) }
            else if req { MButton("قبول", .primary, fill: false) { acceptFriend(p) } }
            else { MButton("إضافة صديق", fill: false) { addFriend(p) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([p.username, placeText(p), relation].compactMap { $0 }.joined(separator: "، "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { player = p }
        .accessibilityActions {
            if !p.me && !friend && !sent.contains(p.uid) {
                Button(req ? "قبول طلب الصداقة" : "إضافة صديق") { req ? acceptFriend(p) : addFriend(p) }
            }
            if !p.me && p.tableId != nil {
                Button(p.tablePrivate ? "طلب انضمام لطاولته" : "دخول طاولته") { enter(p) }
            }
        }
    }

    /// ملف اللاعب: صورته واسمه ووين هو، والدخول لطاولته، وإضافته صديق
    @ViewBuilder private func card(_ p: OnlinePlayer) -> some View {
        let friend = isFriend(p), req = asked(p)
        Sheet(title: p.username) {
            HStack { Spacer(); Avatar(uid: p.uid, name: p.username, size: 110); Spacer() }
            BodyText(p.me ? "هذا أنت" : "\(friend ? "صديقك، " : "")متصل، \(placeText(p))")
            if !p.me && p.tableId != nil {
                MButton(p.tablePrivate ? "طلب انضمام" : "دخول طاولته", .primary, enabled: !joining) { enter(p) }
            }
            if !p.me && !friend && !sent.contains(p.uid) {
                MButton(req ? "قبول طلب الصداقة" : "إضافة صديق") { req ? acceptFriend(p) : addFriend(p) }
            }
            MButton("رجوع") { player = nil }
        }
    }
}
