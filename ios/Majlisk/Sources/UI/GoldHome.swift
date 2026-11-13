import SwiftUI

/// اللعبة اللي اختارها من الواجهة الذهبية: شاشة إنشاء الطاولة تفتح عليها مباشرة
enum PendingGame { static var game: String? }

/// طاولة مجسمة صغيرة (حافة خشب، ولباد أخضر، وورقتين)
private struct MiniTable: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(LinearGradient(colors: [Color(red: 0.63, green: 0.42, blue: 0.2), Color(red: 0.29, green: 0.18, blue: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .fill(RadialGradient(colors: [Color(red: 0.18, green: 0.65, blue: 0.48), Color(red: 0.06, green: 0.29, blue: 0.22)], center: .center, startRadius: 0, endRadius: 140))
                        .padding(9)
                )
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.98)).frame(width: 30, height: 42).rotationEffect(.degrees(-10)).offset(x: -12)
                        RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.98)).frame(width: 30, height: 42).rotationEffect(.degrees(8)).offset(x: 12)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 3)
                )
                .frame(width: 250, height: 130)
                .rotation3DEffect(.degrees(48), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 16)
        }
        .accessibilityHidden(true)
    }
}

private struct GameCard: View {
    let name: String
    let icon: String
    let featured: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Text(icon).font(.system(size: 28))
                Spacer()
                Text(name).font(.system(size: 18, weight: .heavy)).foregroundColor(Pro.cream)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(14)
            .background(LinearGradient(colors: featured ? [Color(red: 0.12, green: 0.48, blue: 0.35), Color(red: 0.07, green: 0.28, blue: 0.21)] : [Color(red: 0.17, green: 0.23, blue: 0.29), Color(red: 0.09, green: 0.13, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Pro.goldLight.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("طاولة \(name)")
    }
}

private struct NavItem: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(icon).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(active ? Pro.goldLight : Pro.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// الواجهة الذهبية: الشاشة الرئيسية للمشترك في الباقة الاحترافية (تفتح على طول أول ما يفتح التطبيق)
struct GoldMenuScreen: View {
    let profile: Profile?
    let openTable: (String) -> Void
    let navigate: (Route) -> Void
    @State private var getCoins = false

    private func play(_ game: String?) { PendingGame.game = game; navigate(.createTable) }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.106, green: 0.145, blue: 0.188), Pro.deep], center: .top, startRadius: 0, endRadius: 700).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // الرأس: صورتك بإطار ذهبي، واسمك، وعضو ذهبي، والرصيد
                    HStack(spacing: 12) {
                        Button { navigate(.profile) } label: {
                            Avatar(uid: Session.shared.uid, name: profile?.username ?? "", size: 50)
                                .padding(3)
                                .overlay(Circle().stroke(AngularGradient(colors: [Pro.goldLight, Pro.goldDark, Pro.goldLight, Pro.gold, Pro.goldLight], center: .center), lineWidth: 3))
                        }
                        .buttonStyle(.plain).accessibilityLabel("الملف الشخصي")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile?.username ?? "").font(.system(size: 18, weight: .heavy)).foregroundColor(Pro.cream).accessibilityAddTraits(.isHeader)
                            Text("👑 عضو ذهبي").font(.system(size: 12, weight: .bold)).foregroundColor(Pro.goldLight)
                        }
                        Spacer()
                        Button { getCoins = true } label: {
                            Text(profile?.unlimited == true ? "🪙 ∞" : "🪙 \(profile?.coins.map(String.init) ?? "…")")
                                .font(.system(size: 15, weight: .heavy)).foregroundColor(Pro.cream)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(LinearGradient(colors: [Color(red: 0.137, green: 0.176, blue: 0.22), Color(red: 0.078, green: 0.106, blue: 0.133)], startPoint: .top, endPoint: .bottom))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("رصيدك \(profile?.coins.map(String.init) ?? "") عملة، الحصول على عملات")
                    }
                    // بطاقة «العب الآن» بطاولة مجسمة
                    ZStack(alignment: .bottom) {
                        MiniTable().padding(.top, 6).frame(maxHeight: .infinity, alignment: .top)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("مجلسك الذهبي").font(.system(size: 22, weight: .heavy)).foregroundColor(Pro.goldLight)
                                Text("طاولتك بشكلها المميز").font(.system(size: 13)).foregroundColor(Pro.dim)
                            }
                            Spacer()
                            Button { play(nil) } label: {
                                Text("العب الآن").font(.system(size: 16, weight: .heavy)).padding(.horizontal, 20).frame(minHeight: 48)
                            }
                            .buttonStyle(RaisedStyle(base: Pro.gold, fg: Pro.ink))
                        }
                        .padding(16)
                    }
                    .frame(height: 220)
                    .background(LinearGradient(colors: [Color(red: 0.137, green: 0.188, blue: 0.24), Pro.night], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Pro.goldLight.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 10)
                    // الألعاب
                    HStack {
                        Text("الألعاب").font(.system(size: 17, weight: .heavy)).foregroundColor(Pro.cream).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("انضمام إلى طاولة") { navigate(.joinTable) }.font(.system(size: 14, weight: .bold)).foregroundColor(Pro.goldLight)
                    }
                    HStack(spacing: 14) {
                        GameCard(name: "بلوت", icon: "🃏", featured: true) { play("baloot") }
                        GameCard(name: "دومينو", icon: "🁫", featured: false) { play("domino") }
                    }
                    HStack(spacing: 14) {
                        GameCard(name: "جاكارو", icon: "🎯", featured: false) { play("jackaroo") }
                        GameCard(name: "لودو", icon: "🎲", featured: false) { play("ludo") }
                    }
                    // المتصلون
                    OnlineLine(openTable: openTable)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Color(red: 0.078, green: 0.106, blue: 0.133)).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Pro.goldLight.opacity(0.18), lineWidth: 1))
                    // شريط التنقل
                    HStack(spacing: 0) {
                        NavItem(icon: "👥", label: "الأصدقاء") { navigate(.friends) }
                        NavItem(icon: "🎴", label: "الطاولات") { navigate(.joinTable) }
                        NavItem(icon: "🎨", label: "الشكل") { navigate(.look) }
                        NavItem(icon: "👑", label: "الباقة", active: true) { navigate(.pro) }
                        NavItem(icon: "👤", label: "حسابي") { navigate(.profile) }
                        NavItem(icon: "⚙️", label: "الإعدادات") { navigate(.settings) }
                    }
                    .padding(.vertical, 6)
                    .background(LinearGradient(colors: [Color(red: 0.137, green: 0.176, blue: 0.22), Color(red: 0.078, green: 0.106, blue: 0.133)], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
            }
            .modifier(BounceOnlyWhenScrolls())
        }
        .foregroundColor(Pro.cream)
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $getCoins) {
            Sheet(title: "الحصول على عملات") {
                MButton("شراء عملات", .primary) { getCoins = false; navigate(.shop) }
                MButton("مشاهدة إعلان (+2 🪙)", .primary, label: "مشاهدة إعلان للحصول على عملتين") {
                    getCoins = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Ads.watch() }
                }
                MButton("إلغاء") { getCoins = false }
            }
        }
    }
}
