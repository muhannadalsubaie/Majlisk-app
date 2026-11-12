import Foundation
import Combine
import Network
import FirebaseFirestore
import FirebaseAuth
import FirebaseMessaging

/// tableId: الطاولة اللي فيها الصديق المتصل الآن (إن وُجدت)
struct Friend: Identifiable, Equatable { let uid: String; let username: String; var online = false; var tableId: String? = nil; var tablePrivate = false; var tableGame = ""; var id: String { uid } }
struct TableInvite: Equatable { let tableId: String; let code: String; let fromUid: String; let fromName: String }
struct HubState: Equatable { var friends: [Friend] = []; var requests: [Friend] = []; var invites: [TableInvite] = [] }

private func friends(_ o: JSON, _ key: String) -> [Friend] { o.objs(key).map { Friend(uid: $0.str("uid"), username: $0.str("username"), online: $0.bool("online"),
                                                                                   tableId: $0.str("tableId").isEmpty ? nil : $0.str("tableId"), tablePrivate: $0.bool("tablePrivate"),
                                                                                   tableGame: $0.str("tableKind").isEmpty ? "" : gameTitle($0.str("tableKind"), $0.str("tableVariant"))) } }
private func invites(_ o: JSON) -> [TableInvite] {
    o.objs("invites").map { TableInvite(tableId: $0.str("tableId"), code: $0.str("code"), fromUid: $0.str("fromUid"), fromName: $0.str("fromName")) }
}

enum Social {
    static func listFriends() async throws -> HubState {
        let r = try await Api.post("/friends/list")
        return HubState(friends: friends(r, "friends"), requests: friends(r, "requests"), invites: invites(r))
    }
    /// true = أصبحتما صديقين مباشرة (كان قد أرسل لك طلباً)
    static func requestFriend(_ username: String) async throws -> Bool { try await Api.post("/friends/request", ["username": username]).bool("friends") }
    static func respondFriend(_ uid: String, accept: Bool) async throws { try await Api.post("/friends/respond", ["uid": uid, "accept": accept]) }
    static func removeFriend(_ uid: String) async throws { try await Api.post("/friends/remove", ["uid": uid]) }
    static func listBans() async throws -> [Friend] { friends(try await Api.post("/bans/list"), "bans") }
    static func unban(_ uid: String) async throws { try await Api.post("/bans/remove", ["uid": uid]) }
    static func inviteFriend(tableId: String, uid: String, seat: Int?) async throws {
        var body: JSON = ["uid": uid]
        if let seat { body["seat"] = seat }
        try await Api.post("/tables/\(tableId)/inviteFriend", body)
    }
    static func respondInvite(_ tableId: String, accept: Bool) async throws { try await Api.post("/invites/respond", ["tableId": tableId, "accept": accept]) }

    private static let errors = [
        "user-not-found": "لا يوجد لاعب بهذا الاسم",
        "self": "هذا اسمك أنت",
        "already-friends": "أنتما صديقان بالفعل",
        "not-friends": "هذا اللاعب ليس في قائمة أصدقائك",
        "offline": "صديقك غير متصل وما فعّل إشعارات التطبيق",
        "no-invite": "انتهت صلاحية الدعوة",
        "not-enough-coins": "رصيدك من العملات لا يكفي",
        "not-owner": "الدعوة لمالك الطاولة فقط",
        "table-full": "الطاولة ممتلئة",
        "not-found": "الطاولة لم تعد موجودة",
        "no-username": "اختر اسم مستخدم أولاً",
    ]
    static func error(_ e: Error) -> String { errors[(e as? ApiError)?.code ?? ""] ?? "حدث خطأ، حاول مرة أخرى" }
}

/// اتصال دائم بمركز اللاعب: يجعلك "متصلاً" لأصدقائك، ويستقبل طلبات الصداقة والدعوات فوراً
final class Hub: ObservableObject {
    static let shared = Hub()
    @Published private(set) var state = HubState()
    /// يزيد كلما اتصل صديق أو خرج: قائمة الأصدقاء تتحدث فوراً
    @Published private(set) var presence = 0
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        Online.shared.start()
        loop = Task { [weak self] in
            var retry = 0
            while !Task.isCancelled {
                guard let token = try? await Api.token() else { try? await Task.sleep(nanoseconds: 3_000_000_000); continue }
                // دخول جديد بهالحساب على هالجوال: يصير هو جوال الحساب (والجوال الثاني يتسجل خروجه) قبل ما نتصل
                if let uid = Auth.auth().currentUser?.uid, Prefs.claimedUid != uid {
                    if (try? await Api.post("/profile/claim-device", ["device": Prefs.deviceId])) != nil { Prefs.claimedUid = uid }
                    else { try? await Task.sleep(nanoseconds: 3_000_000_000); continue }
                }
                let url = URL(string: Api.wsURL("/me/ws", token: token).absoluteString + "&device=" + Prefs.deviceId)!
                let ws = URLSession.shared.webSocketTask(with: url)
                self?.task = ws
                ws.resume()
                // نبضة كل 15 ثانية: بها يعرف الخادم أنك متصل (وإذا انقطعت تصير "غير متصل" لأصدقائك)
                let ping = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 15_000_000_000); try? await ws.send(.string("ping")) } }
                while !Task.isCancelled {
                    guard let msg = try? await ws.receive() else { break }
                    retry = 0
                    if case .string(let text) = msg { self?.handle(text) }
                }
                ping.cancel()
                if Task.isCancelled { break }
                retry = min(retry + 1, 6)
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000 * retry))
            }
        }
    }

    private func handle(_ text: String) {
        guard text != "pong", let data = text.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        switch msg.str("type") {
        case "state":
            let s = HubState(friends: friends(msg, "friends"), requests: friends(msg, "requests"), invites: invites(msg))
            DispatchQueue.main.async { self.state = s }
        case "presence": DispatchQueue.main.async { self.presence += 1 }
        // الحساب انفتح من جوال ثاني: نسجّل خروج هالجوال
        case "loggedOut":
            Task { @MainActor in
                // نتأكد من الخادم إن جوال ثاني فعلاً أخذ الحساب (ما نطلع بالغلط). لو ما قدرنا نتأكد ما نطلع
                guard let r = try? await Api.post("/profile/device-status", ["device": Prefs.deviceId]),
                      (r["current"] as? Bool) == false else { return }
                Prefs.claimedUid = nil
                Messaging.messaging().deleteToken { _ in }
                Announcer.announce("انفتح حسابك من جوال ثاني، فتسجّل خروجك من هالجوال")
                Session.shared.signOut()
            }
        case "notice": Sounds.shared.notify(); Announcer.announce(msg.str("text"))
        case "invite": Sounds.shared.inviteIn(); Announcer.announce("\(msg.obj("invite")?.str("fromName") ?? "") يدعوك لطاولته")
        default: break
        }
    }

    func stop() {
        Online.shared.stop()
        loop?.cancel(); loop = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        DispatchQueue.main.async { self.state = HubState() }
    }

    /// أزل دعوة من القائمة محلياً بعد الرد عليها
    func dropInvite(_ tableId: String) { state.invites.removeAll { $0.tableId == tableId } }
}

/// لاعب متصل في التطبيق (me = أنت)، وطاولته لو هو جالس على طاولة: اللعبة، وخاصة أو عامة
struct OnlinePlayer: Identifiable, Equatable {
    let uid: String; let username: String; let me: Bool
    var tableId: String? = nil; var tablePrivate = false; var tableGame = ""
    var id: String { uid }
}

/// المتصلون في التطبيق كله: العدد يوصل من الخادم على طول مع كل دخول وطلوع، وقائمة الأسماء تنطلب لما تفتحها
final class Online: ObservableObject {
    static let shared = Online()
    @Published private(set) var count: Int?
    @Published private(set) var list: [OnlinePlayer]?
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var retry = 0
            while !Task.isCancelled {
                guard let token = try? await Api.token() else { try? await Task.sleep(nanoseconds: 3_000_000_000); continue }
                let ws = URLSession.shared.webSocketTask(with: Api.wsURL("/presence/ws", token: token))
                self?.task = ws
                ws.resume()
                let ping = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 15_000_000_000); try? await ws.send(.string("ping")) } }
                while !Task.isCancelled {
                    guard let msg = try? await ws.receive() else { break }
                    retry = 0
                    if case .string(let text) = msg { self?.handle(text) }
                }
                ping.cancel()
                if Task.isCancelled { break }
                retry = min(retry + 1, 6)
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000 * retry))
            }
        }
    }

    private func handle(_ text: String) {
        guard text != "pong", let data = text.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        switch msg.str("type") {
        case "online":
            let n = msg.int("count")
            DispatchQueue.main.async { self.count = n }
        default: break
        }
    }

    /// قائمة المتصلين مع طاولة كل واحد (من الخادم)
    func requestList() {
        list = nil
        Task { @MainActor in
            guard let r = try? await Api.post("/online/list") else { list = []; return }
            count = r.int("count")
            list = r.objs("players").map {
                OnlinePlayer(uid: $0.str("uid"), username: $0.str("username"), me: $0.bool("me"),
                             tableId: $0.strOrNil("tableId"), tablePrivate: $0.bool("tablePrivate"),
                             tableGame: $0["tableKind"] != nil ? gameTitle($0.str("tableKind"), $0.strOrNil("tableVariant")) : "")
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        DispatchQueue.main.async { self.count = nil; self.list = nil }
    }
}

let GAME_NAMES = ["baloot": "بلوت", "domino": "دومينو", "jackaroo": "جاكارو", "ludo": "لودو"]

/// اسم اللعبة كما في الخادم (shared/games.ts → gameTitle)
func gameTitle(_ kind: String, _ variant: String?) -> String {
    let base = GAME_NAMES[kind] ?? "بلوت"
    if kind == "jackaroo" && variant == "complex" { return base + " كمبلكس" }
    if kind == "ludo" && variant == "teams" { return base + " فرق" }
    if kind == "domino" { return base + (variant == "t150" ? " 150" : variant == "t200" ? " 200" : " 100") }
    return base
}

struct TableRow: Identifiable {
    let id, ownerName: String; let isPrivate: Bool; let players, people: Int; let status, kind, variant: String
    /// الموجودين: (الاسم، player|bot|spectator)
    var members: [(name: String, role: String)] = []
    /// نتيجة اللعب الجاري (فاضي إذا ما فيه لعب)
    var score: String = ""

    /// قائمة الموجودين مقروءة: اللاعبين ثم المشاهدين
    var membersText: String {
        if members.isEmpty { return "القائمة غير متوفرة الحين" }
        let players = members.filter { $0.role != "spectator" }.map { $0.role == "bot" ? "\($0.name) (روبوت)" : $0.name }
        let specs = members.filter { $0.role == "spectator" }.map(\.name)
        return [
            players.isEmpty ? "ما فيه لاعبين" : "اللاعبين: " + players.joined(separator: "، "),
            specs.isEmpty ? "ما فيه مشاهدين" : "المشاهدين: " + specs.joined(separator: "، "),
            // اللعب جاري: نتيجة الصكة
            status == "playing" && !score.isEmpty ? score : nil,
        ].compactMap { $0 }.joined(separator: "\n")
    }
}

enum Tables {
    static let errors = [
        "not-enough-coins": "رصيدك من العملات لا يكفي",
        "no-username": "اختر اسم مستخدم أولاً",
        "table-full": "الطاولة ممتلئة",
        "banned": "مالك الطاولة حظرك من هذه الطاولة",
        "join-rejected": "رفض مالك الطاولة طلب انضمامك، تقدر تدخل بدعوة منه أو بعد نصف ساعة من طلبك",
        "banned-by-owner": "مالك هذه الطاولة حظرك، فلا يمكنك دخول طاولاته",
        "kicked": "أُخرجت من هذه الطاولة، ويمكنك العودة إليها بعد ساعة من طردك. يمكنك دخول أي طاولة أخرى الآن",
        "not-found": "الطاولة غير موجودة",
        "not-a-member": "لست عضواً في هذه الطاولة",
        "private": "هذه طاولة خاصة — تحتاج دعوة من مالكها",
        "not-owner": "هذا الإجراء لمالك الطاولة فقط",
    ]
    static func error(_ e: Error, _ fallback: String) -> String { errors[(e as? ApiError)?.code ?? ""] ?? fallback }

    static func create(isPrivate: Bool, kind: String, variant: String) async throws -> String {
        try await Api.post("/tables", ["isPrivate": isPrivate, "kind": kind, "variant": variant]).str("id")
    }
    static func join(_ id: String) async throws { try await Api.post("/tables/\(id)/join") }
    /// طلب انضمام لطاولة خاصة (يوصل للمالك تنبيه)، وحالته: pending / accepted / ignored
    /// الحالة وكم دقيقة باقية (للمعلّق والمرفوض)
    static func requestJoin(_ id: String) async throws -> (String, Int) { let r = try await Api.post("/tables/\(id)/join-request"); return (r.str("status"), r.int("minutes")) }
    static func joinRequestStatus(_ id: String) async throws -> (String, Int) { let r = try await Api.post("/tables/\(id)/join-request/status"); return (r.str("status"), r.int("minutes")) }
    static func deleteAccount() async throws { try await Api.post("/me/delete") }

    /// الطاولات النشطة (أحدث 50) — تتحدث مباشرة
    static func listen(_ onRows: @escaping ([TableRow]) -> Void) -> ListenerRegistration {
        Firestore.firestore().collection("tables").order(by: "updatedAt", descending: true).limit(to: 50).addSnapshotListener { snap, _ in
            guard let snap else { onRows([]); return }
            onRows(snap.documents.map { d in
                let x = d.data()
                return TableRow(
                    id: d.documentID,
                    ownerName: x["ownerName"] as? String ?? "",
                    isPrivate: x["isPrivate"] as? Bool == true,
                    players: (x["players"] as? NSNumber)?.intValue ?? 0,
                    people: (x["people"] as? NSNumber)?.intValue ?? 0,
                    status: x["status"] as? String ?? "",
                    kind: x["kind"] as? String ?? "baloot",
                    variant: x["variant"] as? String ?? "classic",
                    members: ((x["members"] as? String).flatMap { $0.data(using: .utf8) }
                        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? [])
                        .map { (name: $0["name"] as? String ?? "", role: $0["role"] as? String ?? "") },
                    score: x["score"] as? String ?? ""
                )
            })
        }
    }
}

/// اتصال حي بالطاولة: يستقبل الحالة والإعلانات، ويعيد الاتصال تلقائياً عند الانقطاع
/// رسالة في دردشة الطاولة الكتابية
struct ChatMessage: Identifiable, Equatable { let id = UUID(); let uid: String; let name: String; let text: String; let mine: Bool }

/// اختيار كل لاعب للدردشة الكتابية (له وحده، ويُحفظ لكل الطاولات):
/// read توصله ويقرأها VoiceOver، silent توصله بلا قراءة، off ما توصله ولا يرسل.
enum ChatMode: String, CaseIterable {
    case read, silent, off
    var label: String {
        switch self {
        case .read: return "توصلني ويقرأها قارئ الشاشة"
        case .silent: return "توصلني بدون قراءة (أرجع لها بنفسي)"
        case .off: return "مطفأة (ما توصلني ولا أرسل)"
        }
    }
}

final class ChatSettings: ObservableObject {
    static let shared = ChatSettings()
    @Published private(set) var mode = ChatMode(rawValue: Prefs.chatMode) ?? .read
    func set(_ m: ChatMode) { Prefs.chatMode = m.rawValue; mode = m }
}

struct JoinRequest: Identifiable, Equatable { let uid: String; let name: String; var id: String { uid } }

final class TableConnection: ObservableObject {
    let tableId: String
    @Published private(set) var view: TableView?
    /// يزيد مع كل حالة جديدة من الخادم (لمقارنة الحالة السابقة بالجديدة)
    @Published private(set) var version = 0
    @Published private(set) var connected = false
    @Published private(set) var closed = false
    /// أخرجه المالك أو حظره: لا نعيد الاتصال
    @Published private(set) var kicked: String?
    /// للمالك: صديق يطلب الانضمام لطاولته الخاصة (موافق / تجاهل)
    @Published var joinRequest: JoinRequest?
    /// يُستدعى مع كل حالة تصل (حتى والتطبيق في الخلفية): لأصوات اللعب
    var onState: ((TableView) -> Void)?

    // ───── الدردشة الكتابية ─────
    /// مقعدك (لتمييز رسائلك وعدم قراءتها عليك)
    var myUid = ""
    /// نافذة الدردشة مفتوحة الآن (فلا نزيد عدد غير المقروء)
    var chatOpen = false { didSet { if chatOpen { unread = 0 } } }
    @Published private(set) var chat: [ChatMessage] = []
    @Published private(set) var unread = 0
    /// آخر رسالة وصلت (تظهر لحظات في زاوية الشاشة)
    @Published private(set) var toast: ChatMessage?
    private var chatModeSub: Any?

    func sendChat(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { send(["type": "chat", "text": String(t.prefix(200))]) }
    }

    private func chatPrefMessage() -> String { "{\"type\":\"chatPref\",\"off\":\(ChatSettings.shared.mode == .off)}" }

    private var ws: URLSessionWebSocketTask?
    private var stopped = false
    private var loop: Task<Void, Never>?
    private var wake: CheckedContinuation<Void, Never>?

    init(_ tableId: String) {
        self.tableId = tableId
        // تغيّر اختيارك للدردشة: نبلغ الخادم فوراً، وإن أطفأتها نمسح الرسائل
        chatModeSub = ChatSettings.shared.$mode.dropFirst().sink { [weak self] m in
            guard let self else { return }
            self.ws?.send(.string("{\"type\":\"chatPref\",\"off\":\(m == .off)}")) { _ in }
            if m == .off { DispatchQueue.main.async { self.chat = []; self.unread = 0; self.toast = nil } }
        }
    }

    func start() {
        guard loop == nil else { return }
        pathMonitor.start(queue: .global(qos: .utility))
        loop = Task { [weak self] in
            var retry = 0
            while let self, !self.stopped {
                if let token = try? await Api.token() {
                    let ws = URLSession.shared.webSocketTask(with: Api.wsURL("/tables/\(self.tableId)/ws", token: token))
                    self.ws = ws
                    ws.resume()
                    ws.send(.string(self.chatPrefMessage())) { _ in }
                    ws.send(.string("{\"type\":\"caps\",\"voice\":true}")) { _ in }
                    // حركة انرسلت والاتصال ميت (ضاعت): نعيد إرسالها مع الاتصال الجديد
                    if let p = self.pending {
                        if Date().timeIntervalSince(p.at) < 20 { self.resent = true; ws.send(.string(p.text)) { _ in } } else { self.pending = nil }
                    }
                    // نبضة كل 3 ثوانٍ: الخادم يكتشف انقطاع نتك خلال ثوانٍ، ونحن نكتشف الاتصال الميت (ما يرد) فنعيده فوراً
                    self.lastHeard = Date()
                    let ping = Task { [weak self] in
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            if let self, Date().timeIntervalSince(self.lastHeard) > 8 { ws.cancel(with: .goingAway, reason: nil); break }
                            try? await ws.send(.string("ping"))
                        }
                    }
                    defer { ping.cancel() }
                    while !self.stopped {
                        guard let msg = try? await ws.receive() else { break }
                        self.lastHeard = Date()
                        if !self.connected { await MainActor.run { self.connected = true } }
                        retry = 0
                        if case .string(let text) = msg, text != "pong" { self.handle(text) }
                    }
                    await MainActor.run { self.connected = false }
                }
                if self.stopped { break }
                retry = min(retry + 1, 6)
                // بعد عدة محاولات: هل الطاولة أُغلقت أو أُخرجنا منها؟ أم الشبكة فقط؟
                if retry >= 3, let member = try? await Api.get("/tables/\(self.tableId)/member"), !member.bool("member") {
                    self.stopped = true
                    await MainActor.run { self.closed = true }
                    break
                }
                await self.sleep(seconds: retry)
            }
        }
    }

    private func sleep(seconds: Int) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            wake = c
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in self?.resumeWake() }
        }
    }

    private func resumeWake() { DispatchQueue.main.async { self.wake?.resume(); self.wake = nil } }

    /// العودة للتطبيق: نعيد الاتصال فوراً بدل انتظار المحاولة التالية
    func reconnectNow() { if !connected { resumeWake() } }

    private var lastHeard = Date()
    /// رجع النت (أو تغيّرت الشبكة): نعيد الاتصال فوراً، فيُعلن رجوعك للبقية على طول
    private lazy var pathMonitor: NWPathMonitor = {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self, path.status == .satisfied else { return }
            DispatchQueue.main.async {
                if self.connected && Date().timeIntervalSince(self.lastHeard) > 3.5 { self.ws?.cancel(with: .goingAway, reason: nil) }
                self.reconnectNow()
            }
        }
        return m
    }()

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        switch msg.str("type") {
        case "state":
            pending = nil
            if let v = msg.obj("view") { let parsed = TableView(v); DispatchQueue.main.async {
                self.view = parsed; self.version += 1; self.onState?(parsed)
                // المحادثة الصوتية تتابع المنضمين هنا (مو من الشاشة): والتطبيق في الخلفية الشاشة ما تتحدث، فما كنت تسمع من دخل جديد
                Voice.shared.sync(parsed.voice, table: self.tableId)
            } }
        case "voice":
            // المحادثة الصوتية من غرفتها المستقلة: نحدّث القائمة بس (بدون الطاولة كاملة)
            let list = VoiceMember.list(msg.objs("voice"))
            DispatchQueue.main.async {
                guard var v = self.view else { return }
                v.voice = list
                self.view = v; self.version += 1; self.onState?(v)
                Voice.shared.sync(list, table: self.tableId)
            }
        case "events":
            // كل حدث إعلان مستقل حتى يقرأها قارئ الشاشة بالترتيب
            // أحداث الحركة الواحدة تُقرأ جملة واحدة، وتنتظر ما قبلها حتى يكتمل (لا تقطع بعضها)
            let events = msg.strs("events").filter { !$0.isEmpty }
            // المزايدة والدبل بأصوات منطوقة (حكم، صن، بس/ولا، دبل...)
            let voices = msg.strs("voices")
            if !voices.isEmpty { Sounds.shared.voices(voices) }
            // الانضمام ورجوع الاتصال بنغمة الانضمام، والمغادرة وانقطاع الاتصال بنغمة المغادرة
            if events.contains(where: { $0.hasPrefix("انضم ") || $0.hasPrefix("عاد اتصال") }) { Sounds.shared.tableJoin() }
            else if events.contains(where: { $0.hasPrefix("غادر ") || $0.hasPrefix("انقطع اتصال") || ($0.hasPrefix("خرج ") && $0.contains("من الطاولة")) }) { Sounds.shared.tableLeave() }
            else if events.contains(where: { $0.hasSuffix("انضم للمحادثة الصوتية") }) { Sounds.shared.voiceJoin() }
            else if events.contains(where: { $0.hasSuffix("غادر المحادثة الصوتية") }) { Sounds.shared.voiceLeave() }
            // المزايدة والدبل: التعليق الصوتي يبيّن وش اشترى أو قال، فقارئ الشاشة ما يقرأ نصها
            // (يقول بس «دور فلان» مع تغيّر الدور)، ويبقى ما سواها مثل «ورقة الأرض لفلان»
            let spoken = voices.isEmpty ? events : events.filter { !isBidLine($0) }
            if !spoken.isEmpty { Announcer.announceEvent(spoken.joined(separator: "، ")) }
        case "joinRequest":
            let r = JoinRequest(uid: msg.str("uid"), name: msg.str("name"))
            DispatchQueue.main.async {
                self.joinRequest = r
                Sounds.shared.joinRequest()
                // قارئ الشاشة يقرأ الطلب على طول
                Announcer.announceNow("\(r.name) طلب الانضمام")
            }
        case "chat":
            let mode = ChatSettings.shared.mode
            guard mode != .off else { return }
            let m = ChatMessage(uid: msg.str("uid"), name: msg.str("name"), text: msg.str("text"), mine: msg.str("uid") == myUid)
            // سطر من الطاولة نفسها (مثل الدعوات): ينكتب في الدردشة بس، لأن قارئ الشاشة قرأه من الإعلان
            if m.uid == "system" { DispatchQueue.main.async { self.chat = Array((self.chat + [m]).suffix(100)) }; return }
            DispatchQueue.main.async {
                self.chat = Array((self.chat + [m]).suffix(100))
                if !m.mine {
                    Sounds.shared.chat()
                    if !self.chatOpen { self.unread += 1 }
                    self.toast = m
                }
            }
            if !m.mine && mode == .read { Announcer.announce("\(m.name): \(m.text)") }
        case "error":
            pending = nil
            if resent { resent = false } else { Announcer.announce(msg.str("message")) }
        case "kicked":
            stopped = true
            let banned = msg.bool("banned")
            DispatchQueue.main.async { self.kicked = banned ? "banned" : "kicked" }
            Announcer.announce(banned ? "حظرك مالك الطاولة" : "أخرجك مالك الطاولة")
        case "closed":
            stopped = true
            DispatchQueue.main.async { self.closed = true }
            Announcer.announce("أُغلقت الطاولة")
        default: break
        }
    }

    /// آخر حركة لعب انرسلت ولسا ما جا رد الخادم عليها. لو الاتصال ميت وهو يبان شغال (النت انقطع ثواني)
    /// كانت الحركة تضيع: الحين لو ما وصل شي من الخادم خلال ثانيتين ونص نعيد الاتصال على طول،
    /// ونعيد إرسال الحركة مع الاتصال الجديد
    private var pending: (text: String, at: Date)?
    /// أعدنا إرسال حركة: لو كانت انلعبت قبل، خطأ الخادم («ليس دورك») ما ينقرأ
    private var resent = false

    func send(_ msg: JSON) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: data, encoding: .utf8) else { return }
        let isMove = msg["action"] != nil
        let at = Date()
        if isMove { pending = (s, at); resent = false }
        guard connected, let ws else { Announcer.announce("جارٍ إعادة الاتصال بالطاولة…"); return }
        ws.send(.string(s)) { _ in }
        if isMove {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, let p = self.pending, p.at == at, self.lastHeard < at else { return }
                self.ws?.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func send(_ type: String, _ extra: JSON = [:]) { send(extra.merging(["type": type]) { a, _ in a }) }

    func stop() {
        stopped = true
        pathMonitor.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        loop?.cancel()
        resumeWake()
    }
}


/// سطور المزايدة والدبل اللي يغطيها التعليق الصوتي
func isBidLine(_ e: String) -> Bool {
    let patterns = [".* اشترى .*", ".* (بس|ولا)$", ".*أكد الحكم.*", ".* قال قبلك$", ".* دبّل$", "^(مقفل|مفتوح)$", ".*: (مقفل|مفتوح)$"]
    return patterns.contains { e.range(of: $0, options: .regularExpression) != nil }
}
