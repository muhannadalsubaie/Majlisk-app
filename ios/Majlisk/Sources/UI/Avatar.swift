import SwiftUI
import PhotosUI

/// الصور الشخصية: تُحمّل من الخادم مرة وتُحفظ في الذاكرة، وتتحدث لما يغيّرها صاحبها
final class Avatars: ObservableObject {
    static let shared = Avatars()
    private var cache: [String: UIImage?] = [:]
    /// رقم نسخة لكل صورة: يزيد لما تغيّر صورتك فتنعاد قراءتها
    @Published private(set) var versions: [String: Int] = [:]

    func bump(_ uid: String) { DispatchQueue.main.async { self.cache[uid] = nil; self.versions[uid, default: 0] += 1 } }

    func load(_ uid: String) async -> UIImage? {
        if let hit = cache[uid] { return hit }
        guard let url = URL(string: "\(Api.base)/avatar/\(uid)?v=\(versions[uid] ?? 0)") else { return nil }
        var img: UIImage?
        if let (data, resp) = try? await URLSession.shared.data(from: url), (resp as? HTTPURLResponse)?.statusCode == 200 {
            img = UIImage(data: data)
        }
        await MainActor.run { self.cache[uid] = .some(img) }
        return img
    }

    /// نجهّز الصورة للرفع: مربعة من الوسط، 192×192، JPEG
    static func prepare(_ data: Data) -> String? {
        guard let src = UIImage(data: data) else { return nil }
        let side = min(src.size.width, src.size.height)
        let out = CGSize(width: 192, height: 192)
        let r = UIGraphicsImageRenderer(size: out)
        let img = r.image { _ in
            let scale = 192 / side
            let w = src.size.width * scale, h = src.size.height * scale
            src.draw(in: CGRect(x: (192 - w) / 2, y: (192 - h) / 2, width: w, height: h))
        }
        return img.jpegData(compressionQuality: 0.85)?.base64EncodedString()
    }
}

/// أيقونة دائرية بالصورة الشخصية، وإن ما فيه صورة فأول حرف من الاسم. للعين فقط: الاسم جنبها يقرأه VoiceOver
struct Avatar: View {
    let uid: String?
    let name: String
    var size: CGFloat = 36
    @ObservedObject private var avatars = Avatars.shared
    @State private var img: UIImage?

    private var bot: Bool { (uid ?? "").isEmpty || uid!.hasPrefix("bot-") }

    var body: some View {
        ZStack {
            Circle().fill(Palette.green700)
            if let img { Image(uiImage: img).resizable().scaledToFill() }
            else { Text(bot ? "🤖" : String(name.trimmingCharacters(in: .whitespaces).prefix(1))).font(.system(size: size * 0.42, weight: .bold)).foregroundColor(Palette.gold) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Palette.gold, lineWidth: 1.5))
        .accessibilityHidden(true)
        .task(id: "\(uid ?? "")|\(avatars.versions[uid ?? ""] ?? 0)") {
            img = bot ? nil : await avatars.load(uid!)
        }
    }
}

/// الملف الشخصي: صورتك الدائرية واسمك، وتغيير الصورة أو حذفها
struct ProfileScreen: View {
    let profile: Profile?
    let onBack: () -> Void
    @ObservedObject private var session = Session.shared
    @State private var pick: PhotosPickerItem?
    @State private var busy = false

    var body: some View {
        Screen {
            TopBar("الملف الشخصي", onBack: onBack)
            VStack(spacing: 12) {
                Avatar(uid: session.uid, name: profile?.username ?? "", size: 140)
                Title(profile?.username ?? "")
            }
            .frame(maxWidth: .infinity)
            PhotosPicker(selection: $pick, matching: .images) {
                Text("تغيير الصورة").font(.system(size: 18, weight: .bold)).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(RaisedStyle(base: Palette.gold, fg: Palette.green900, border: nil))
            .disabled(busy)
            MButton("حذف الصورة", enabled: !busy) { Task { await send(["remove": true], ok: "تم حذف صورتك", fail: "تعذّر حذف الصورة") } }
            Note("صورتك تطلع دائرية جنب اسمك في الطاولات وعند أصدقائك.")
        }
        .onChange(of: pick) { item in
            guard let item else { return }
            Task {
                busy = true
                defer { busy = false; pick = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let b64 = Avatars.prepare(data) else {
                    Announcer.announce("تعذّر فتح الصورة"); return
                }
                await send(["image": b64], ok: "تم تغيير صورتك", fail: "تعذّر رفع الصورة، حاول مرة أخرى")
            }
        }
    }

    private func send(_ body: JSON, ok: String, fail: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Api.post("/profile/avatar", body)
            if let uid = session.uid { Avatars.shared.bump(uid) }
            Announcer.announce(ok)
        } catch { Announcer.announce(fail) }
    }
}
