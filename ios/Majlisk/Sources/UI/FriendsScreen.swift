import SwiftUI

/// الأصدقاء: القائمة مع حالة الاتصال، والطلبات الواردة، والمحظورون، وزر إضافة صديق في الأعلى
struct FriendsScreen: View {
    let hub: HubState
    let navigate: (Route) -> Void
    let openTable: (String) -> Void
    @ObservedObject private var hubLive = Hub.shared
    @State private var tab = 0
    @State private var friends: [Friend]?
    @State private var bans: [Friend]?
    @State private var adding = false
    @State private var newName = ""
    @State private var toRemove: Friend?
    @State private var profileOf: Friend?
    @State private var joining = false
    @State private var refreshKey = 0

    /// نتيجة ضغطتك تُقرأ فقط، بلا سطر مكتوب فوق الشاشة
    private func say(_ t: String) { Announcer.announce(t) }
    private func refresh() { refreshKey += 1 }

    /// حالة الصديق: غير متصل، أو متصل في الرئيسية، أو متصل في طاولة (واسم اللعبة، ومقفلة إن كانت)
    private func status(_ f: Friend) -> String {
        if !f.online { return "غير متصل" }
        if f.tableId == nil { return "متصل، في الرئيسية" }
        return ["متصل، في طاولة", f.tableGame, f.tablePrivate ? "مقفلة" : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// الدخول لطاولة الصديق (ضغط مطوّل على اسمه، أو من ملفه)
    private func joinFriend(_ f: Friend) {
        if joining { return }
        // ما هو في طاولة، أو طاولته مقفلة: الضغط المطوّل لا يسوي شي (بلا تلميحات)
        guard f.online, let id = f.tableId, !f.tablePrivate else { return }
        joining = true
        Task { @MainActor in
            do { try await Tables.join(id); profileOf = nil; openTable(id) } catch { say(Tables.error(error, "تعذّر الانضمام")) }
            joining = false
        }
    }

    var body: some View {
        Screen {
            TopBar(title: "الأصدقاء", onBack: { navigate(.menu) }) {
                SmallButton("إضافة صديق") { adding = true }
            }
            Picker("القائمة", selection: $tab) {
                Text("الأصدقاء\(friends.map { " (\($0.count))" } ?? "")").tag(0)
                Text("طلبات الصداقة\(hub.requests.isEmpty ? "" : " \(hub.requests.count)")").tag(1)
                Text("المحظورون").tag(2)
            }
            .pickerStyle(.segmented)
            switch tab {
            case 0:
                if friends == nil { BodyText("جارٍ التحميل…") }
                else if friends!.isEmpty { Note("لا يوجد أصدقاء بعد.") }
                ForEach((friends ?? []).sorted { $0.online && !$1.online }) { f in
                    // الضغط يفتح ملفه، والضغط المطوّل يدخلك طاولته إن كان فيها
                    ItemRow {
                        Text("\(f.online ? "🟢" : "⚪") \(f.username)، \(status(f))").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { profileOf = f }
                    .onLongPressGesture { joinFriend(f) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(f.username)، \(status(f))")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { profileOf = f }
                    .accessibilityAction(named: "دخول طاولته") { joinFriend(f) }
                }
            case 1:
                if hub.requests.isEmpty { Note("لا توجد طلبات صداقة.") }
                ForEach(hub.requests) { r in
                    ItemRow {
                        Text(r.username).frame(maxWidth: .infinity, alignment: .leading)
                        SmallButton("قبول", label: "قبول طلب \(r.username)") {
                            Task { @MainActor in
                                do { try await Social.respondFriend(r.uid, accept: true); say("أصبحت أنت و\(r.username) أصدقاء"); refresh() } catch { say(Social.error(error)) }
                            }
                        }
                        SmallButton("رفض", label: "رفض طلب \(r.username)") {
                            Task { @MainActor in
                                do { try await Social.respondFriend(r.uid, accept: false); say("رُفض طلب \(r.username)") } catch { say(Social.error(error)) }
                            }
                        }
                    }
                }
            default:
                if bans == nil { BodyText("جارٍ التحميل…") }
                else if bans!.isEmpty { Note("لا يوجد محظورون.") }
                ForEach(bans ?? []) { b in
                    ItemRow {
                        Text(b.username).frame(maxWidth: .infinity, alignment: .leading)
                        SmallButton("رفع الحظر", label: "رفع الحظر عن \(b.username)") {
                            Task { @MainActor in
                                do { try await Social.unban(b.uid); bans?.removeAll { $0.uid == b.uid }; Announcer.announce("رُفع الحظر عن \(b.username)") }
                                catch { Announcer.announce(Social.error(error)) }
                            }
                        }
                    }
                }
            }
        }
        // تحديث القائمة فوراً لما يتصل صديق أو يخرج (إشعار من المركز)، وعند أي تغيير، وكل 10 ثوانٍ احتياطاً
        .task(id: "\(hub.friends.count)-\(refreshKey)-\(hubLive.presence)") {
            while !Task.isCancelled {
                if let s = try? await Social.listFriends() { friends = s.friends } else if friends == nil { friends = [] }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .task(id: tab) { if tab == 2 { bans = (try? await Social.listBans()) ?? [] } }
        .sheet(isPresented: $adding) {
            Sheet(title: "إضافة صديق") {
                Field(label: "اسم المستخدم", text: $newName)
                MButton("إرسال طلب صداقة", .primary, enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    Task { @MainActor in
                        do {
                            let became = try await Social.requestFriend(name)
                            say(became ? "أصبحت أنت و\(name) أصدقاء" : "أُرسل طلب الصداقة إلى \(name)")
                            adding = false; newName = ""; refresh()
                        } catch { say(Social.error(error)) }
                    }
                }
                MButton("إلغاء") { adding = false }
            }
        }
        .sheet(item: $profileOf) { f in
            Sheet(title: f.username) {
                BodyText(status(f))
                if f.online && f.tableId != nil && !f.tablePrivate {
                    MButton("دخول طاولته", .primary, enabled: !joining) { joinFriend(f) }
                }
                MButton("حذف من الأصدقاء", .danger) {
                    profileOf = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { toRemove = f }
                }
                MButton("رجوع") { profileOf = nil }
            }
        }
        .confirm("حذف صديق", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
                 message: "هل تريد حذف \(toRemove?.username ?? "") من أصدقائك؟", confirm: "حذف", destructive: true) {
            if let f = toRemove { Task { @MainActor in try? await Social.removeFriend(f.uid); refresh() } }
        }
    }
}
