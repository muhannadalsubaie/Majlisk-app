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
    /// تغيير اسم المستخدم: متى يقدر يغيّر (0 = الحين، nil = ما وصل الرد بعد)
    @State private var nextAt: Double?
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameError = ""

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
            // تغيير اسم المستخدم: مرة كل ستة أشهر، والاسم القديم يصير متاح لغيرك
            let wait = nextAt.map { $0 / 1000 - Date().timeIntervalSince1970 }.flatMap { $0 > 0 ? $0 : nil }
            MButton("تغيير اسم المستخدم", enabled: nextAt != nil && wait == nil) { newName = ""; renameError = ""; renaming = true }
            Note(wait.map { "تقدر تغيّر اسمك بعد \(Int($0 / 86400) + 1) يوم." } ?? "تقدر تغيّر اسم المستخدم مرة كل ستة أشهر، واسمك القديم يصير متاح لغيرك.")
        }
        .task(id: profile?.username ?? "") {
            if let r = try? await Api.post("/profile/rename", ["check": true]) { nextAt = (r["nextAt"] as? NSNumber)?.doubleValue ?? 0 }
        }
        .sheet(isPresented: $renaming) {
            Sheet(title: "تغيير اسم المستخدم") {
                Text("اسمك الحالي: \(profile?.username ?? ""). بعد التغيير ما تقدر تغيّره مرة ثانية إلا بعد ستة أشهر، واسمك القديم يقدر ياخذه أي أحد.")
                    .foregroundColor(Palette.text)
                UsernameField(name: $newName)
                if !renameError.isEmpty { Text(renameError).foregroundColor(Palette.goldSoft) }
                MButton("تأكيد التغيير", .primary, enabled: !busy) { Task { @MainActor in await rename() } }
                MButton("إلغاء", enabled: !busy) { renaming = false }
            }
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

    private func rename() async {
        if let invalid = Usernames.validate(newName) { renameError = Usernames.errors[invalid] ?? ""; Announcer.announce(renameError); return }
        busy = true
        defer { busy = false }
        renameError = ""
        do {
            let r = try await Api.post("/profile/rename", ["username": newName])
            nextAt = (r["nextAt"] as? NSNumber)?.doubleValue ?? 0
            renaming = false
            Announcer.announce("تم تغيير اسمك إلى \(r.str("username", newName))")
        } catch {
            let code = (error as? ApiError)?.code ?? ""
            renameError = code == "too-soon" ? "ما تقدر تغيّر اسمك الحين، مرة كل ستة أشهر"
                : code == "same" ? "هذا اسمك الحالي"
                : Usernames.errors[code] ?? "حدث خطأ، حاول مرة أخرى"
            Announcer.announce(renameError)
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
