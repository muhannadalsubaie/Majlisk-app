import SwiftUI

private enum Page: Equatable {
    case main, players, invite, friends, settings, stop, changeGame
    case replace(Int), member(String), confirm(ban: Bool, uid: String)
}

/// صفحة تنفتح عليها القائمة مباشرة (من إجراءات قارئ الشاشة على زر القائمة)
enum TableMenuStart: Identifiable { case main, players, invite, friends; var id: Self { self } }

/// قائمة الطاولة: اللاعبون، دعوة صديق، مشاهدة إعلان، المحادثة الصوتية، الإعدادات، مغادرة
struct TableMenu: View {
    let v: TableView
    let uid: String
    @ObservedObject var conn: TableConnection
    let onLeave: () -> Void
    let onClose: () -> Void
    var start: TableMenuStart = .main
    @ObservedObject private var voice = Voice.shared
    @ObservedObject private var hub = Hub.shared
    @State private var page: Page = .main
    @State private var friendState: [String: String] = [:]

    private var view: TableView { conn.view ?? v }
    private var isOwner: Bool { view.ownerUid == uid }

    /// بجانب اسم كل لاعب (غير الروبوت): في المحادثة الصوتية أو خارجها
    private func voiceTag(_ u: String) -> String {
        u.isEmpty ? "" : view.voice.contains(where: { $0.uid == u }) ? "، في المحادثة الصوتية" : "، خارج المحادثة الصوتية"
    }

    private func seatLabel(_ i: Int) -> String {
        guard let s = view.seat(i) else { return "مقعد فارغ" }
        let me = view.mySeat ?? 0
        let tags = [
            i == view.mySeat ? "أنت" : nil,
            s.isBot ? "روبوت" : nil,
            s.away ? "انقطع اتصاله" : nil,
            view.mySeat != nil && i != view.mySeat && teamOf(i) == teamOf(me) ? "شريكك" : nil,
        ].compactMap { $0 }
        return s.username + (tags.isEmpty ? "" : " (\(tags.joined(separator: "، ")))")
    }
    private func nameOf(_ u: String) -> String? {
        if let i = view.seatUids.firstIndex(of: u), let s = view.seat(i) { return s.username }
        return view.spectators.first { $0.uid == u }?.username
    }
    /// أي حاضر حقيقي غيرك: تضغطه فتظهر خياراته
    private func canManage(_ u: String?) -> Bool { guard let u, !u.isEmpty else { return false }; return u != uid && !u.hasPrefix("bot-") }

    var body: some View {
        pages.onAppear {
            switch start {
            case .main: break
            case .players: page = .players
            case .invite: page = .invite
            case .friends: page = .friends
            }
        }
    }

    @ViewBuilder private var pages: some View {
        switch page {
        case .main:
            Sheet(title: "القائمة") {
                if isOwner {
                    SwitchRow(label: "طاولة خاصة", isOn: view.isPrivate, onChange: { conn.send("setPrivate", ["isPrivate": $0]) })
                } else { Note(view.isPrivate ? "طاولة خاصة: الدخول بالدعوة فقط" : "طاولة عامة") }
                MButton("اللاعبون") { page = .players }
                if isOwner { MButton("دعوة صديق") { page = .invite } }
                MButton("الأصدقاء") { page = .friends }
                MButton("مشاهدة إعلان (+2 🪙)") { onClose(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Ads.watch() } }
                MButton(voice.joined ? "مغادرة المحادثة الصوتية" : "الانضمام للمحادثة الصوتية", enabled: !voice.busy) {
                    if voice.joined { Voice.shared.leave() } else { Voice.shared.join(view.id, uid: uid) }
                    onClose()
                }
                MButton("الإعدادات") { page = .settings }
                if isOwner { MButton("تغيير اللعبة") { page = .changeGame } }
                if isOwner && (view.hasGame || view.seats.contains { $0 != nil }) { MButton("إيقاف اللعبة", .danger) { page = .stop } }
                MButton("مغادرة الطاولة", .danger, action: onLeave)
                MButton("إغلاق القائمة", action: onClose)
            }
        case .stop:
            Sheet(title: "إيقاف اللعبة") {
                BodyText("إيقاف نهائي: تُلغى المباراة وترجع النتيجة صفر صفر، ويصبح الجميع مشاهدين والمقاعد فارغة. بعدها تختار أنت من يلعب من صفحة اللاعبين.")
                MButton("إيقاف اللعبة", .danger) { conn.send("stop"); onClose() }
                MButton("إلغاء") { page = .main }
            }
        case .changeGame:
            // المالك يغيّر لعبة الطاولة: تنتهي اللعبة الحالية، ويبقى الكل في أماكنهم للعبة الجديدة
            Sheet(title: "تغيير اللعبة") {
                BodyText("الحالية: \(gameTitle(view.kind, "classic")). لو غيّرتها تنتهي اللعبة الحالية، ويبقى الكل في أماكنهم للعبة الجديدة. خيارات اللعبة (فردي أو فرق، عادي أو كومبلكس، نهاية المباراة) تختارها من صفحة المقاعد.")
                // اسم اللعبة بس
                ForEach(["baloot", "domino", "jackaroo", "ludo"].filter { $0 != view.kind }, id: \.self) { k in
                    MButton(gameTitle(k, "classic"), .primary) { conn.send("changeGame", ["kind": k]); onClose() }
                }
                MButton("رجوع") { page = .main }
            }
        case .invite:
            InviteFriendsSheet(tableId: view.id, seat: nil, title: "دعوة صديق") { page = .main }
        case .friends:
            // قائمة الأصدقاء كاملة (الأصدقاء، الطلبات، المحظورون) من داخل الطاولة
            // دخول طاولة صديق من هنا: تطلع من طاولتك وتنتقل لطاولته على طول
            FriendsScreen(hub: hub.state, navigate: { _ in page = .main }, openTable: { id in
                if id == view.id { onClose(); return }
                conn.send("leave")
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Push.shared.switchTable = id }
            })
        case .settings:
            SettingsScreen(embedded: true) { page = .main }
        case .players:
            Sheet(title: "اللاعبون") {
                ForEach(0..<4, id: \.self) { i in
                    let u = view.seatUid(i)
                    let muted = !u.isEmpty && view.voiceBlocked.contains(u) ? "، مكتوم" : ""
                    let vt = view.seat(i).map { $0.isBot ? "" : voiceTag(u) } ?? ""
                    ItemRow {
                        if canManage(u) { MButton(seatLabel(i) + vt + muted) { page = .member(u) } }
                        else { Text(seatLabel(i) + vt).frame(maxWidth: .infinity, alignment: .leading) }
                        let s = view.seat(i)
                        // المالك يستبدل المقعد الفاضي أو الروبوت، أو نفسه (حتى أثناء اللعب: يصير مشاهد ويبقى المالك)
                        if isOwner && !canManage(u) && (s == nil || s!.isBot || i == view.mySeat) {
                            SmallButton("استبدال", label: i == view.mySeat ? "استبدال نفسك بمشاهد" : "استبدال \(s?.username ?? "المقعد الفارغ")") { page = .replace(i) }
                        }
                    }
                }
                SectionTitle("المشاهدون")
                if view.spectators.isEmpty { Note("لا يوجد مشاهدون") }
                ForEach(view.spectators, id: \.uid) { s in
                    if canManage(s.uid) { MButton("\(s.username) (مشاهد)\(voiceTag(s.uid))\(view.voiceBlocked.contains(s.uid) ? "، مكتوم" : "")") { page = .member(s.uid) } }
                    else { BodyText("\(s.username)\(s.uid == uid ? " (أنت)" : "")\(voiceTag(s.uid))") }
                }
                MButton("رجوع") { page = .main }
            }
        case .member(let u):
            let name = nameOf(u)
            let seat = view.seatUids.firstIndex(of: u) ?? -1
            let blocked = view.voiceBlocked.contains(u)
            Sheet(title: name ?? "لم يعد على الطاولة") {
                if let name {
                    switch friendState[u] ?? "" {
                    case "friend": Note("صديقك")
                    case "sent": Note("أُرسل طلب الصداقة")
                    case "none":
                        MButton("إضافة صديق", .primary) {
                            Task { @MainActor in
                                do {
                                    let became = try await Social.requestFriend(name)
                                    friendState[u] = "sent"
                                    Announcer.announce(became ? "أصبح \(name) صديقك" : "أُرسل طلب صداقة إلى \(name)")
                                } catch { Announcer.announce(Social.error(error)) }
                            }
                        }
                    default: EmptyView()
                    }
                    if isOwner {
                        MButton("تعيينه مالكاً للطاولة") { conn.send("setOwner", ["uid": u]); onClose() }
                        MButton(blocked ? "إلغاء الكتم في المحادثة الصوتية" : "كتم في المحادثة الصوتية") {
                            conn.send("voiceBlock", ["uid": u, "blocked": !blocked]); page = .players
                        }
                        MButton("طرد من الطاولة", .danger) { page = .confirm(ban: false, uid: u) }
                        MButton("حظر من الطاولة", .danger) { page = .confirm(ban: true, uid: u) }
                        if seat >= 0 && view.seat(seat)?.away == true {
                            MButton("روبوت مكانه الآن") { conn.send("botNow", ["seat": seat]); page = .players }
                        }
                        if seat >= 0 { MButton("استبداله بمشاهد") { page = .replace(seat) } }
                    }
                }
                MButton("رجوع") { page = .players }
            }
            .task(id: u) {
                if friendState[u] == nil {
                    let isFriend = (try? await Social.listFriends().friends.contains { $0.uid == u }) ?? false
                    friendState[u] = isFriend ? "friend" : "none"
                }
            }
        case .confirm(let ban, let u):
            let name = nameOf(u) ?? "هذا الشخص"
            Sheet(title: ban ? "حظر \(name)؟" : "طرد \(name)؟") {
                BodyText((ban ? "سيخرج من الطاولة، ولن يستطيع دخول هذه الطاولة ولا أي طاولة تملكها."
                    : "سيخرج من الطاولة. يستطيع دخول أي طاولة أخرى فوراً، والعودة لهذه الطاولة بعد ساعة.")
                    + (view.playing && view.seatUids.contains(u) ? " يحل روبوت مكانه في اللعب." : ""))
                MButton(ban ? "حظر" : "طرد", .danger) { conn.send(ban ? "ban" : "kick", ["uid": u]); page = .players }
                MButton("إلغاء") { page = .member(u) }
            }
        case .replace(let seat):
            Sheet(title: "من يجلس مكان \(view.seat(seat)?.username ?? "المقعد الفارغ")؟") {
                if view.spectators.isEmpty { BodyText("لا يوجد مشاهدون للاستبدال. ادعُ صديقاً أولاً، وبعد دخوله يظهر هنا.") }
                ForEach(view.spectators, id: \.uid) { s in
                    MButton(s.username, .primary) { conn.send("replace", ["seat": seat, "uid": s.uid]); page = .players }
                }
                MButton("رجوع") { page = .players }
            }
        }
    }
}
