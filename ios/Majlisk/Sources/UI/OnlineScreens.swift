import SwiftUI

/// تحت اسمك في الشاشة الرئيسية: «المتصلون: ١٢» (يتحدث على طول)، والضغط يفتح قائمتهم
struct OnlineLine: View {
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
        .sheet(isPresented: $open) { OnlineSheet { open = false } }
    }
}

/// أسماء كل المتصلين في التطبيق: الضغط على الاسم يفتح ملفه (وتقدر تضيفه صديق)
private struct OnlineSheet: View {
    let close: () -> Void
    @ObservedObject private var online = Online.shared
    @State private var player: OnlinePlayer?
    var body: some View {
        Sheet(title: online.count.map { "المتصلون الآن (\($0))" } ?? "المتصلون الآن") {
            if let list = online.list {
                if list.isEmpty { BodyText("ما فيه أحد متصل الحين") }
                ForEach(list) { p in
                    Button { player = p } label: {
                        ItemRow {
                            Avatar(uid: p.uid, name: p.username, size: 36)
                            Text(p.me ? "\(p.username) (أنت)" : p.username).font(.system(size: 16)).foregroundColor(Palette.text)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(p.me ? "\(p.username)، أنت" : p.username)
                    .accessibilityHint("يفتح ملفه")
                    .accessibilityAddTraits(.isButton)
                }
            } else { BodyText("جارٍ التحميل…") }
            MButton("تحديث القائمة") { online.requestList() }
            MButton("إغلاق") { close() }
        }
        .onAppear { online.requestList() }
        .sheet(item: $player) { p in PlayerCard(p: p) { player = nil } }
    }
}

/// ملف لاعب: صورته واسمه، وإضافته صديق (أو قبول طلبه لو هو اللي طلبك)
private struct PlayerCard: View {
    let p: OnlinePlayer
    let close: () -> Void
    @ObservedObject private var hub = Hub.shared
    @State private var sent = false
    @State private var busy = false
    var body: some View {
        let friend = hub.state.friends.contains { $0.uid == p.uid }
        let asked = hub.state.requests.contains { $0.uid == p.uid }
        Sheet(title: p.username) {
            HStack { Spacer(); Avatar(uid: p.uid, name: p.username, size: 110); Spacer() }
            BodyText(p.me ? "هذا أنت" : friend ? "صديقك، متصل الآن" : "متصل الآن")
            if !p.me && !friend {
                if asked {
                    MButton("قبول طلب الصداقة", .primary, enabled: !busy) {
                        Task { @MainActor in
                            busy = true; defer { busy = false }
                            do { try await Social.respondFriend(p.uid, accept: true); Announcer.announce("أصبحت أنت و\(p.username) أصدقاء") }
                            catch { Announcer.announce(Social.error(error)) }
                        }
                    }
                } else if sent {
                    BodyText("أُرسل طلب الصداقة")
                } else {
                    MButton("إضافة صديق", .primary, enabled: !busy) {
                        Task { @MainActor in
                            busy = true; defer { busy = false }
                            do {
                                let became = try await Social.requestFriend(p.username)
                                sent = true
                                Announcer.announce(became ? "أصبحت أنت و\(p.username) أصدقاء" : "أُرسل طلب الصداقة إلى \(p.username)")
                            } catch { Announcer.announce(Social.error(error)) }
                        }
                    }
                }
            }
            MButton("رجوع") { close() }
        }
    }
}
