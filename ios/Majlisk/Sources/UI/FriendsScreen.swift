import SwiftUI

/// الأصدقاء: القائمة مع حالة الاتصال، والطلبات الواردة، والمحظورون، وزر إضافة صديق في الأعلى
struct FriendsScreen: View {
    let hub: HubState
    let navigate: (Route) -> Void
    @State private var tab = 0
    @State private var friends: [Friend]?
    @State private var bans: [Friend]?
    @State private var message = ""
    @State private var adding = false
    @State private var newName = ""
    @State private var toRemove: Friend?
    @State private var refreshKey = 0

    private func say(_ t: String) { message = t; Announcer.announce(t) }
    private func refresh() { refreshKey += 1 }

    var body: some View {
        Screen {
            TopBar(title: "الأصدقاء", onBack: { navigate(.menu) }) {
                MButton("إضافة صديق", fill: false) { adding = true }
            }
            if !message.isEmpty { Text(message).foregroundColor(Palette.goldSoft) }
            Picker("القائمة", selection: $tab) {
                Text("الأصدقاء\(friends.map { " (\($0.count))" } ?? "")").tag(0)
                Text("طلبات الصداقة\(hub.requests.isEmpty ? "" : " \(hub.requests.count)")").tag(1)
                Text("المحظورون").tag(2)
            }
            .pickerStyle(.segmented)
            switch tab {
            case 0:
                if friends == nil { BodyText("جارٍ التحميل…") }
                else if friends!.isEmpty { Note("لا يوجد أصدقاء بعد — اضغط \"إضافة صديق\" في الأعلى وأضفه باسم المستخدم.") }
                ForEach((friends ?? []).sorted { $0.online && !$1.online }) { f in
                    ItemRow {
                        Text("\(f.online ? "🟢" : "⚪") \(f.username)، \(f.online ? "متصل" : "غير متصل")").frame(maxWidth: .infinity, alignment: .leading)
                        MButton("حذف", fill: false, label: "حذف \(f.username) من الأصدقاء") { toRemove = f }
                    }
                }
            case 1:
                if hub.requests.isEmpty { Note("لا توجد طلبات صداقة.") }
                ForEach(hub.requests) { r in
                    ItemRow {
                        Text(r.username).frame(maxWidth: .infinity, alignment: .leading)
                        MButton("قبول", fill: false, label: "قبول طلب \(r.username)") {
                            Task { @MainActor in
                                do { try await Social.respondFriend(r.uid, accept: true); say("أصبحت أنت و\(r.username) أصدقاء"); refresh() } catch { say(Social.error(error)) }
                            }
                        }
                        MButton("رفض", fill: false, label: "رفض طلب \(r.username)") {
                            Task { @MainActor in
                                do { try await Social.respondFriend(r.uid, accept: false); say("رُفض طلب \(r.username)") } catch { say(Social.error(error)) }
                            }
                        }
                    }
                }
            default:
                Note("من حظرتهم لا يستطيعون دخول أي طاولة تملكها.")
                if bans == nil { BodyText("جارٍ التحميل…") }
                else if bans!.isEmpty { Note("لا يوجد محظورون.") }
                ForEach(bans ?? []) { b in
                    ItemRow {
                        Text(b.username).frame(maxWidth: .infinity, alignment: .leading)
                        MButton("رفع الحظر", fill: false, label: "رفع الحظر عن \(b.username)") {
                            Task { @MainActor in
                                do { try await Social.unban(b.uid); bans?.removeAll { $0.uid == b.uid }; Announcer.announce("رُفع الحظر عن \(b.username)") }
                                catch { Announcer.announce(Social.error(error)) }
                            }
                        }
                    }
                }
            }
        }
        // تحديث القائمة عند أي تغيير في المركز، وكل 20 ثانية لحالة الاتصال
        .task(id: "\(hub.friends.count)-\(refreshKey)") {
            while !Task.isCancelled {
                if let s = try? await Social.listFriends() { friends = s.friends } else if friends == nil { friends = [] }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
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
        .confirm("حذف صديق", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }),
                 message: "هل تريد حذف \(toRemove?.username ?? "") من أصدقائك؟", confirm: "حذف", destructive: true) {
            if let f = toRemove { Task { @MainActor in try? await Social.removeFriend(f.uid); refresh() } }
        }
    }
}
