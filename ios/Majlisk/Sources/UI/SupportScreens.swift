import SwiftUI
import PhotosUI

/// تذكرة دعم: شكوى أو استفسار، ورسائلها (صاحبها والمطور)
struct Ticket: Identifiable, Equatable {
    struct Message: Equatable { let from: String; let text: String; let at: Double }
    let id: String, username: String, kind: String
    let images: Int
    let at: Double
    let status: String
    let messages: [Message]
    var kindLabel: String { kind == "complaint" ? "شكوى" : "استفسار" }
    var statusLabel: String { status == "answered" ? "تم الرد" : status == "closed" ? "مغلقة" : "بانتظار الرد" }
    init(_ o: JSON) {
        id = o.str("id"); username = o.str("username"); kind = o.str("kind"); images = o.int("images")
        at = (o["at"] as? NSNumber)?.doubleValue ?? 0; status = o.str("status")
        messages = o.objs("messages").map { Message(from: $0.str("from"), text: $0.str("text"), at: ($0["at"] as? NSNumber)?.doubleValue ?? 0) }
    }
}

private func timeText(_ ms: Double) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "d/M h:mm a"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

/// نصغّر الصورة (أطول ضلع 1280) ونرسلها JPEG
private func prepareImage(_ data: Data) -> String? {
    guard let img = UIImage(data: data) else { return nil }
    let k = min(1, 1280 / max(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * k, height: img.size.height * k)
    let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    return small.jpegData(compressionQuality: 0.75)?.base64EncodedString()
}

/// المساعدة والدعم: شكوى أو استفسار (نص بدون حد، ولين 4 صور)، وتذاكرك وردود المطور عليها.
/// حساب المطور يشوف كل التذاكر ويرد عليها.
struct SupportScreen: View {
    let dev: Bool
    let onBack: () -> Void
    @State private var kind: String?
    @State private var open: Ticket?
    @State private var all = false
    @State private var tickets: [Ticket]?
    @State private var reload = 0

    var body: some View {
        Group {
            if let kind { NewTicketView(kind: kind) { self.kind = nil; reload += 1 } }
            else if let t = open { TicketView(t: t, asDev: dev && all, onBack: { open = nil; reload += 1 }, onChanged: { reload += 1 }) }
            else {
                Screen {
                    TopBar(all ? "تذاكر الدعم" : "المساعدة والدعم", onBack: onBack)
                    if !all {
                        BodyText("كيف نقدر نساعدك؟")
                        MButton("📝 شكوى", .primary) { kind = "complaint" }
                        MButton("❓ استفسار", .primary) { kind = "question" }
                    }
                    if dev { MButton(all ? "تذاكري أنا" : "🛠 تذاكر الدعم (المطور)") { all.toggle(); tickets = nil } }
                    SectionTitle(all ? "كل التذاكر" : "تذاكري")
                    if tickets == nil { Note("جارٍ التحميل…") }
                    else if tickets!.isEmpty { Note(all ? "ما فيه تذاكر" : "ما عندك تذاكر") }
                    ForEach(tickets ?? []) { t in
                        MButton("\(all ? "\(t.username) · " : "")\(t.kindLabel) · \(t.statusLabel) · \(timeText(t.at))\n\(String((t.messages.first?.text ?? "").prefix(60)))") { open = t }
                    }
                }
            }
        }
        .task(id: "\(all)-\(reload)") {
            let list = (try? await Api.post("/support/list", ["all": all]))?.objs("tickets").map(Ticket.init) ?? []
            tickets = list
            if let o = open { open = list.first { $0.id == o.id } ?? o }
        }
    }
}

private struct NewTicketView: View {
    let kind: String
    let onDone: () -> Void
    @State private var text = ""
    @State private var images: [String] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        Screen {
            TopBar(kind == "complaint" ? "شكوى جديدة" : "استفسار جديد", onBack: onDone)
            Text(kind == "complaint" ? "اكتب شكواك" : "اكتب استفسارك").foregroundColor(Palette.textDim).accessibilityHidden(true)
            TextEditor(text: $text)
                .frame(minHeight: 180).padding(8)
                .scrollContentBackground(.hidden)
                .background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.green700, lineWidth: 1))
                .foregroundColor(Palette.text)
                .accessibilityLabel(kind == "complaint" ? "اكتب شكواك" : "اكتب استفسارك")
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, b64 in
                    Button {
                        images.remove(at: i); Announcer.announce("حُذفت الصورة \(i + 1)")
                    } label: {
                        if let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .accessibilityLabel("الصورة \(i + 1)، اضغط لحذفها")
                }
            }
            if images.count < 4 {
                PhotosPicker(selection: $picks, maxSelectionCount: 4 - images.count, matching: .images) {
                    Text("📎 إرفاق صور (\(images.count) من 4)").font(.system(size: 18, weight: .bold)).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(RaisedStyle(base: Palette.green700, fg: Palette.text, border: Palette.gold))
                .onChange(of: picks) { items in
                    Task { @MainActor in
                        for it in items { if let d = try? await it.loadTransferable(type: Data.self), let s = prepareImage(d) { images.append(s) } }
                        images = Array(images.prefix(4)); picks = []
                        Announcer.announce("أُرفقت \(images.count) من 4 صور")
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundColor(Palette.goldSoft) }
            MButton(busy ? "جارٍ الإرسال…" : "إرسال", .primary, enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy) {
                busy = true
                Task { @MainActor in
                    do {
                        try await Api.post("/support/create", ["kind": kind, "text": text.trimmingCharacters(in: .whitespacesAndNewlines), "images": images])
                        Announcer.announce("وصلت رسالتك، وراح يوصلك الرد هنا وبإشعار")
                        onDone()
                    } catch { self.error = "تعذّر الإرسال، حاول مرة ثانية"; Announcer.announce(self.error) }
                    busy = false
                }
            }
        }
    }
}

private struct TicketImage: View {
    let id: String
    let index: Int
    @State private var img: UIImage?
    var body: some View {
        Group {
            if let img { Image(uiImage: img).resizable().scaledToFit() } else { Note("جارٍ تحميل الصورة…").padding(12) }
        }
        .frame(maxWidth: .infinity).background(Palette.green800).clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("صورة مرفقة \(index + 1)")
        .task { if let d = await Api.bytes("/support/image/\(id)/\(index)") { img = UIImage(data: d) } }
    }
}

private struct TicketView: View {
    let t: Ticket
    let asDev: Bool
    let onBack: () -> Void
    let onChanged: () -> Void
    @State private var reply = ""
    @State private var busy = false
    var body: some View {
        Screen {
            TopBar("\(t.kindLabel)\(asDev ? " · \(t.username)" : "")", onBack: onBack)
            Note("\(t.statusLabel) · \(timeText(t.at))")
            ForEach(Array(t.messages.enumerated()), id: \.offset) { i, m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.from == "dev" ? "الدعم" : asDev ? t.username : "أنت").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.goldSoft)
                    Text(m.text).font(.system(size: 16)).foregroundColor(Palette.text).fixedSize(horizontal: false, vertical: true)
                    Text(timeText(m.at)).font(.system(size: 11)).foregroundColor(Palette.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(m.from == "dev" ? Palette.green700 : Palette.green800).clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                // الصور مع أول رسالة
                if i == 0 { ForEach(0..<t.images, id: \.self) { TicketImage(id: t.id, index: $0) } }
            }
            if t.status != "closed" {
                Field(label: asDev ? "الرد على \(t.username)" : "أضف رسالة", text: $reply)
                MButton(busy ? "جارٍ…" : "إرسال الرد", .primary, enabled: !reply.trimmingCharacters(in: .whitespaces).isEmpty && !busy) {
                    busy = true
                    Task { @MainActor in
                        if (try? await Api.post("/support/reply", ["id": t.id, "text": reply.trimmingCharacters(in: .whitespaces)])) != nil {
                            reply = ""; Announcer.announce("أُرسل الرد"); onChanged()
                        } else { Announcer.announce("تعذّر الإرسال") }
                        busy = false
                    }
                }
                MButton("إغلاق التذكرة") {
                    Task { @MainActor in _ = try? await Api.post("/support/close", ["id": t.id]); onChanged(); onBack() }
                }
            }
        }
    }
}
