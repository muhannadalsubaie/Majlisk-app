import SwiftUI

/// زر الدردشة الكتابية (فوق الميكروفون): عليه عدد الرسائل غير المقروءة
struct ChatButton: View {
    @ObservedObject var conn: TableConnection
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            Text(conn.unread > 0 ? "💬 الدردشة (\(conn.unread))" : "💬 الدردشة")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: 200, minHeight: 40)
                .foregroundColor(Palette.green900)
                .background(Palette.gold)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityLabel(conn.unread > 0 ? "الدردشة، \(conn.unread) رسائل جديدة" : "الدردشة")
    }
}

/// آخر رسالة وصلت: تظهر ٥ ثوانٍ في الزاوية (VoiceOver يقرؤها من الإعلان، فلا نكررها هنا)
struct ChatToast: View {
    @ObservedObject var conn: TableConnection
    @State private var shown: ChatMessage?
    var body: some View {
        Group {
            if let m = shown {
                Text("\(m.name): \(m.text)")
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
                        Text(m.mine ? "أنت" : m.name).font(.system(size: 12)).foregroundColor(Palette.goldSoft)
                        Text(m.text).font(.system(size: 15)).foregroundColor(Palette.text)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(m.mine ? Color(red: 0.23, green: 0.37, blue: 0.18) : Palette.green700)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m.mine ? "أنت" : m.name): \(m.text)")
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
