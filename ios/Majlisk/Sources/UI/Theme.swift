import SwiftUI

/// ألوان التصميم المؤقت (الأخضر الغامق والذهبي، مثل التطبيق الحالي).
/// كل ألوان التطبيق وخطوطه من هنا فقط، فتغيير التصميم لاحقاً يكون في هذا الملف.
enum Palette {
    static let green900 = Color(red: 0x0D / 255, green: 0x2B / 255, blue: 0x20 / 255)
    static let green800 = Color(red: 0x13 / 255, green: 0x3A / 255, blue: 0x2B / 255)
    static let green700 = Color(red: 0x1B / 255, green: 0x4D / 255, blue: 0x39 / 255)
    static let gold = Color(red: 0xD4 / 255, green: 0xAF / 255, blue: 0x37 / 255)
    static let goldSoft = Color(red: 0xE8 / 255, green: 0xCF / 255, blue: 0x7A / 255)
    static let text = Color(red: 0xF3 / 255, green: 0xEF / 255, blue: 0xE2 / 255)
    static let textDim = Color(red: 0xB9 / 255, green: 0xC4 / 255, blue: 0xBD / 255)
    static let danger = Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
    static let online = Color(red: 0x7F / 255, green: 0xD4 / 255, blue: 0x8F / 255)
}

enum ButtonKind { case primary, secondary, danger }

/// زر التطبيق: كبير وسهل اللمس، ونصه هو ما يُقرأ
struct MButton: View {
    let title: String
    var kind: ButtonKind = .secondary
    var fill = true
    var enabled = true
    var label: String? = nil
    let action: () -> Void

    init(_ title: String, _ kind: ButtonKind = .secondary, fill: Bool = true, enabled: Bool = true, label: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.fill = fill; self.enabled = enabled; self.label = label; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: 50)
                .padding(.horizontal, 14)
                .foregroundColor(kind == .primary ? Palette.green900 : Palette.text)
                .background(kind == .primary ? Palette.gold : kind == .danger ? Palette.danger : Palette.green700)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .opacity(enabled ? 1 : 0.5)
        }
        .disabled(!enabled)
        .accessibilityLabel(label ?? title)
    }
}

/// شاشة كاملة قابلة للتمرير بخلفية التطبيق
struct Screen<Content: View>: View {
    var scroll = true
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            Palette.green900.ignoresSafeArea()
            if scroll {
                ScrollView { VStack(alignment: .leading, spacing: 12) { content() }.padding(16) }
            } else {
                VStack(alignment: .leading, spacing: 12) { content() }.padding(16)
            }
        }
        .foregroundColor(Palette.text)
    }
}

/// عنوان الشاشة: يقرؤه VoiceOver كعنوان
struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 26, weight: .bold)).foregroundColor(Palette.text).accessibilityAddTraits(.isHeader)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 21, weight: .bold)).foregroundColor(Palette.goldSoft).accessibilityAddTraits(.isHeader)
    }
}

struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 16)).foregroundColor(Palette.textDim).fixedSize(horizontal: false, vertical: true) }
}

struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 18)).foregroundColor(Palette.text).fixedSize(horizontal: false, vertical: true) }
}

/// شريط أعلى الشاشة: العنوان، وزر الرجوع
struct TopBar<Actions: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        HStack(spacing: 8) {
            Title(title).frame(maxWidth: .infinity, alignment: .leading)
            actions()
            if let onBack { MButton("رجوع", fill: false, action: onBack) }
        }
    }
}

extension TopBar where Actions == EmptyView {
    init(_ title: String, onBack: (() -> Void)? = nil) { self.title = title; self.onBack = onBack; self.actions = { EmptyView() } }
}

/// مفتاح تشغيل/إيقاف بعنوان ووصف: الصف كله عنصر واحد لـ VoiceOver
struct SwitchRow: View {
    let label: String
    let isOn: Bool
    let onChange: (Bool) -> Void
    var description: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
                Text(label).font(.system(size: 18)).foregroundColor(Palette.text)
            }
            .tint(Palette.gold)
            if let description { Note(description).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(description ?? "")
    }
}

/// صف بعنصر ونص وأزرار
struct ItemRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.green800)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// نافذة منبثقة بعنوان: VoiceOver يبقى داخلها حتى تُغلق
struct Sheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            Palette.green800.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Title(title)
                    content()
                }.padding(16)
            }
        }
        .foregroundColor(Palette.text)
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityAddTraits(.isModal)
    }
}

/// حقل نص بعنوان
struct Field: View {
    let label: String
    @Binding var text: String
    var secure = false
    var email = false
    var ltr = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).foregroundColor(Palette.textDim).accessibilityHidden(true)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(email ? .emailAddress : .default)
            .textContentType(secure ? .password : email ? .emailAddress : .username)
            .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
            .padding(12)
            .background(Palette.green800)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(Palette.text)
            .accessibilityLabel(label)
        }
    }
}

struct Logo: View {
    let size: CGFloat
    var body: some View {
        if let img = UIImage(contentsOfFile: Bundle.main.path(forResource: "logo", ofType: "png", inDirectory: "Resources") ?? "") {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

extension View {
    /// تأكيد بخيارين بالعربي
    func confirm(_ title: String, isPresented: Binding<Bool>, message: String, confirm: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button(confirm, role: destructive ? .destructive : nil, action: action)
            Button("إلغاء", role: .cancel) {}
        } message: { Text(message) }
    }
}
