import SwiftUI

/// زر الدردشة الكتابية (فوق الميكروفون): عليه عدد الرسائل غير المقروءة
struct ChatButton: View {
    @ObservedObject var conn: TableConnection
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Text(trSpoken(conn.unread > 0 ? "💬 الدردشة (\(conn.unread))" : "💬 الدردشة"))
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: 200, minHeight: 40)
                .foregroundColor(Palette.green900)
                .background(Palette.gold)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityLabel(spokenText(conn.unread > 0 ? "الدردشة، \(conn.unread) رسائل جديدة" : "الدردشة"))
    }
}

/// آخر رسالة وصلت: تظهر ٥ ثوانٍ في الزاوية (VoiceOver يقرؤها من الإعلان، فلا نكررها هنا)
struct ChatToast: View {
    @ObservedObject var conn: TableConnection
    @State private var shown: ChatMessage?
    var body: some View {
        Group {
            if let m = shown {
                Text(trSpoken("\(m.name): \(m.text)"))
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: 170, alignment: .leading)
                    .background(Color.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.gold, lineWidth: 1))
                    .padding(12)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: conn.toast) { m in
            shown = m
            guard let m else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if shown == m { shown = nil } }
        }
    }
}

/// نافذة الدردشة: الرسائل، وخانة الكتابة وزر الإرسال
struct ChatSheet: View {
    @ObservedObject var conn: TableConnection
    let close: () -> Void
    @State private var text = ""
    var body: some View {
        Sheet(title: "الدردشة") {
            if conn.chat.isEmpty { Note("ما فيه رسائل بعد.") }
            ForEach(conn.chat) { m in
                HStack {
                    if m.mine { Spacer(minLength: 40) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trSpoken(m.mine ? "أنت" : m.name)).font(.system(size: 12)).foregroundColor(Palette.goldSoft)
                        Text(trSpoken(m.text)).font(.system(size: 15)).foregroundColor(Palette.text)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(m.mine ? Color(red: 0.23, green: 0.37, blue: 0.18) : Palette.green700)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenText("\(m.mine ? "أنت" : m.name): \(m.text)"))
                    if !m.mine { Spacer(minLength: 40) }
                }
            }
            Field(label: "اكتب رسالة…", text: $text)
                .onChange(of: text) { t in if t.count > 200 { text = String(t.prefix(200)) } }
            MButton("إرسال", .primary, enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty) {
                conn.sendChat(text); text = ""
            }
            MButton("إغلاق", action: close)
        }
    }
}

/// الدردشة تحت الطاولة: فوق مربع صغير بآخر الرسائل (ارتفاعه محدود، ما يوصل للأوراق، ويتمرر)،
/// وتحته خانة الكتابة وزر الإرسال جنب الميكروفون. تكتب وتضغط إرسال وتنرسل على طول
struct ChatBar<Mic: View>: View {
    @ObservedObject var conn: TableConnection
    @ViewBuilder let mic: () -> Mic
    @State private var text = ""
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }
    private func send() { guard canSend else { return }; conn.sendChat(text); text = "" }
    var body: some View {
        VStack(spacing: 6) {
            if !conn.chat.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(conn.chat) { m in
                                (Text(trSpoken("\(m.mine ? "أنت" : m.name): ")).foregroundColor(Palette.goldSoft) + Text(trSpoken(m.text)).foregroundColor(Palette.text))
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(m.id)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    // على قد الرسائل، وبحد أقصى ٩٦ (ما يوصل للأوراق، والباقي يتمرر)
                    .frame(height: min(96, CGFloat(conn.chat.count) * 20 + 12))
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.green700, lineWidth: 1))
                    .onAppear { if let l = conn.chat.last { proxy.scrollTo(l.id, anchor: .bottom) } }
                    .onChange(of: conn.chat.count) { _ in if let l = conn.chat.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                }
            }
            HStack(spacing: 8) {
                TextField(tr("اكتب رسالة…"), text: $text)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: text) { t in if t.count > 200 { text = String(t.prefix(200)) } }
                    .font(.system(size: 14))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Palette.green800)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.green700, lineWidth: 1))
                    .accessibilityLabel(spokenText("اكتب رسالة"))
                // زر الإرسال (مكان زر الدردشة)
                Button(action: send) {
                    Text(trSpoken("إرسال ➤"))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundColor(Palette.green900)
                        .background(canSend ? Palette.gold : Palette.goldSoft.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .accessibilityLabel(spokenText("إرسال"))
                mic()
            }
        }
        // الرسائل ظاهرة دائماً: ما فيه «غير مقروءة»
        .onAppear { conn.chatOpen = true }
        .onDisappear { conn.chatOpen = false }
    }
}
