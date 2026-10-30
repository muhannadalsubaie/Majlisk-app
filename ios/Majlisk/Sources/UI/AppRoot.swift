import SwiftUI

enum Route { case splash, auth, menu, createTable, joinTable, table, friends, settings, shop }

struct AppRoot: View {
    @StateObject private var session = Session.shared
    @StateObject private var hub = Hub.shared
    @State private var route: Route = .splash
    @State private var tableId: String?
    @State private var busyInvite = false

    private var signedIn: Bool { session.uid != nil && !(session.profile?.username ?? "").isEmpty }
    /// أي حساب مسجّل بلا اسم مستخدم يجب أن يختار اسماً قبل أي شاشة أخرى
    private var needsUsername: Bool { session.uid != nil && session.profile?.loaded == true && (session.profile?.username ?? "").isEmpty && route != .splash }
    private var pendingInvite: TableInvite? { hub.state.invites.first { !(route == .table && tableId == $0.tableId) } }

    var body: some View {
        content
            .onChange(of: session.uid) { uid in if uid == nil && route != .splash { route = .auth } }
            .onChange(of: signedIn) { on in if on { hub.start(); Store.recover() } else { hub.stop() } }
            .onAppear { if signedIn { hub.start(); Store.recover() } }
            .sheet(isPresented: Binding(get: { pendingInvite != nil && !needsUsername && session.uid != nil }, set: { if !$0, let i = pendingInvite { answer(i, accept: false) } })) {
                if let invite = pendingInvite {
                    Sheet(title: "دعوة لطاولة") {
                        BodyText("\(invite.fromName) يدعوك للعب معه في طاولته.")
                        MButton("قبول", .primary, enabled: !busyInvite) { answer(invite, accept: true) }
                        MButton("رفض", enabled: !busyInvite) { answer(invite, accept: false) }
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if needsUsername {
            ChooseUsernameScreen()
        } else {
            switch route {
            case .splash: SplashScreen(done: afterSplash)
            case .auth: AuthScreen { route = .menu }
            case .menu: MainMenuScreen(profile: session.profile) { route = $0 }
            case .createTable: CreateTableScreen(profile: session.profile, navigate: { route = $0 }, openTable: open)
            case .joinTable: JoinTableScreen(navigate: { route = $0 }, openTable: open)
            case .friends: FriendsScreen(hub: hub.state) { route = $0 }
            case .settings: SettingsScreen(embedded: false) { route = .menu }
            case .shop: ShopScreen(profile: session.profile) { route = $0 }
            case .table:
                if let tableId { TableScreen(tableId: tableId, uid: session.uid ?? "") { route = .menu }.id(tableId) }
                else { Color.clear.onAppear { route = .menu } }
            }
        }
    }

    private func open(_ id: String) { tableId = id; route = .table }

    /// بعد البداية: لو أُغلق التطبيق وأنت في طاولة قبل أقل من دقيقة نرجعك لها
    private func afterSplash() {
        guard session.uid != nil else { route = .auth; return }
        guard let last = Prefs.lastTable, Date().timeIntervalSince1970 - Prefs.lastTableAt < 60 else { route = .menu; return }
        Task { @MainActor in
            let member = (try? await Api.get("/tables/\(last)/member"))?.bool("member") ?? false
            if member { open(last) } else { route = .menu }
        }
    }

    private func answer(_ invite: TableInvite, accept: Bool) {
        busyInvite = true
        Task { @MainActor in
            do {
                try await Social.respondInvite(invite.tableId, accept: accept)
                hub.dropInvite(invite.tableId)
                if accept { open(invite.tableId) }
            } catch {
                hub.dropInvite(invite.tableId)
                Announcer.announce(Social.error(error))
            }
            busyInvite = false
        }
    }
}

/// شاشة البداية: ننتظر Firebase يتذكر الحساب ثم نذهب للقائمة أو الدخول
struct SplashScreen: View {
    let done: () -> Void
    var body: some View {
        ZStack {
            Palette.green900.ignoresSafeArea()
            VStack(spacing: 16) {
                Logo(size: 160)
                ProgressView().tint(Palette.gold).accessibilityLabel("جارٍ التحميل")
            }
        }
        .task { try? await Task.sleep(nanoseconds: 300_000_000); done() }
    }
}

/// حقل اسم المستخدم مع فحص فوري للصيغة والتوفر (القرار النهائي في الخادم)
struct UsernameField: View {
    @Binding var name: String
    @State private var hint = ""
    @State private var ok = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Field(label: "اسم المستخدم", text: $name)
            if !hint.isEmpty { Text(hint).font(.system(size: 15)).foregroundColor(ok ? Palette.online : Palette.textDim) }
        }
        .task(id: name) {
            ok = false
            if name.trimmingCharacters(in: .whitespaces).isEmpty { hint = ""; return }
            if let invalid = Usernames.validate(name) { hint = Usernames.errors[invalid] ?? ""; announceHint(); return }
            hint = "جارٍ التحقق…"
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            if let r = try? await Api.postPublic("/username/available", ["username": name]) {
                if r.bool("available") { hint = "✓ الاسم متاح"; ok = true } else { hint = Usernames.errors[r.str("error", "taken")] ?? Usernames.errors["taken"]! }
                announceHint()
            }
        }
    }
    private func announceHint() { Announcer.announce(hint) }
}

struct AuthScreen: View {
    let done: () -> Void
    @State private var signup = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error = ""

    private func run(_ block: @escaping () async throws -> Void) {
        busy = true; error = ""
        Task { @MainActor in
            do { try await block() } catch { self.error = authMessage(error); Announcer.announce(self.error) }
            busy = false
        }
    }

    var body: some View {
        Screen {
            HStack { Spacer(); Logo(size: 120); Spacer() }
            Title(signup ? "حساب جديد" : "تسجيل الدخول")
            if signup { UsernameField(name: $name) }
            Field(label: "البريد الإلكتروني", text: $email, email: true, ltr: true)
            Field(label: "كلمة المرور", text: $password, secure: true, ltr: true)
            if !error.isEmpty { Text(error).foregroundColor(Palette.goldSoft) }
            MButton(signup ? "إنشاء الحساب (+30 🪙)" : "دخول", .primary, enabled: !busy) {
                run {
                    let mail = email.trimmingCharacters(in: .whitespaces)
                    if signup {
                        try await AuthService.signUp(username: name, email: mail, password: password)
                        Announcer.announce("أهلاً \(name.trimmingCharacters(in: .whitespaces))، حصلت على 30 عملة ترحيبية")
                    } else {
                        try await AuthService.signIn(email: mail, password: password)
                        Announcer.announce("تم تسجيل الدخول")
                    }
                    done()
                }
            }
            MButton("سياسة الخصوصية") { UIApplication.shared.open(URL(string: Api.site + "/privacy.html")!) }
            MButton("الدخول بحساب Apple", enabled: !busy) { run { try await AuthService.apple(); Announcer.announce("تم تسجيل الدخول"); done() } }
            MButton("الدخول بحساب Google", enabled: !busy) { run { try await AuthService.google(); Announcer.announce("تم تسجيل الدخول"); done() } }
            MButton(signup ? "عندي حساب — تسجيل الدخول" : "ما عندي حساب — حساب جديد", enabled: !busy) { signup.toggle(); error = "" }
            if !signup {
                MButton("نسيت كلمة المرور", enabled: !busy) {
                    run {
                        try await AuthService.resetPassword(email.trimmingCharacters(in: .whitespaces))
                        error = "أرسلنا رابط استعادة كلمة المرور إلى بريدك"
                        Announcer.announce(error)
                    }
                }
            }
        }
    }
}

/// يظهر لأي حساب بلا اسم مستخدم (مثل أول دخول بحساب Google) قبل الوصول للقائمة
struct ChooseUsernameScreen: View {
    @State private var name = ""
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        Screen {
            HStack { Spacer(); Logo(size: 100); Spacer() }
            Title("اختر اسم المستخدم")
            UsernameField(name: $name)
            if !error.isEmpty { Text(error).foregroundColor(Palette.goldSoft) }
            MButton("تأكيد", .primary, enabled: !busy) {
                if let invalid = Usernames.validate(name) { error = Usernames.errors[invalid] ?? ""; Announcer.announce(error); return }
                busy = true; error = ""
                Task { @MainActor in
                    do {
                        try await Api.post("/profile/username", ["username": name])
                        Announcer.announce("تم حجز اسم المستخدم \(name)")
                    } catch {
                        self.error = Usernames.errors[(error as? ApiError)?.code ?? ""] ?? "حدث خطأ، حاول مرة أخرى"
                        Announcer.announce(self.error)
                    }
                    busy = false
                }
            }
            MButton("تسجيل الخروج", enabled: !busy) { Session.shared.signOut() }
        }
    }
}
