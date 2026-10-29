import Foundation
import FirebaseFirestore

struct Friend: Identifiable, Equatable { let uid: String; let username: String; var online = false; var id: String { uid } }
struct TableInvite: Equatable { let tableId: String; let code: String; let fromUid: String; let fromName: String }
struct HubState: Equatable { var friends: [Friend] = []; var requests: [Friend] = []; var invites: [TableInvite] = [] }

private func friends(_ o: JSON, _ key: String) -> [Friend] { o.objs(key).map { Friend(uid: $0.str("uid"), username: $0.str("username"), online: $0.bool("online")) } }
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
        "offline": "صديقك غير متصل الآن",
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
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var retry = 0
            while !Task.isCancelled {
                guard let token = try? await Api.token() else { try? await Task.sleep(nanoseconds: 3_000_000_000); continue }
                let ws = URLSession.shared.webSocketTask(with: Api.wsURL("/me/ws", token: token))
                self?.task = ws
                ws.resume()
                // نبقيه حياً برسالة كل 30 ثانية (كما في التطبيق الحالي)
                let ping = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 30_000_000_000); try? await ws.send(.string("ping")) } }
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
        case "notice": Announcer.announce(msg.str("text"))
        case "invite": Announcer.announce("\(msg.obj("invite")?.str("fromName") ?? "") يدعوك لطاولته")
        default: break
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        DispatchQueue.main.async { self.state = HubState() }
    }

    /// أزل دعوة من القائمة محلياً بعد الرد عليها
    func dropInvite(_ tableId: String) { state.invites.removeAll { $0.tableId == tableId } }
}

let GAME_NAMES = ["baloot": "بلوت", "domino": "دومينو", "jackaroo": "جاكارو", "ludo": "لودو"]

/// اسم اللعبة كما في الخادم (shared/games.ts → gameTitle)
func gameTitle(_ kind: String, _ variant: String?) -> String {
    let base = GAME_NAMES[kind] ?? "بلوت"
    if kind == "jackaroo" && variant == "complex" { return base + " كمبلكس" }
    if kind == "ludo" && variant == "teams" { return base + " فرق" }
    return base
}

struct TableRow: Identifiable { let id, ownerName: String; let isPrivate: Bool; let players, people: Int; let status, kind, variant: String }

enum Tables {
    static let errors = [
        "not-enough-coins": "رصيدك من العملات لا يكفي",
        "no-username": "اختر اسم مستخدم أولاً",
        "table-full": "الطاولة ممتلئة",
        "banned": "مالك الطاولة حظرك من هذه الطاولة",
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
                    variant: x["variant"] as? String ?? "classic"
                )
            })
        }
    }
}

/// اتصال حي بالطاولة: يستقبل الحالة والإعلانات، ويعيد الاتصال تلقائياً عند الانقطاع
final class TableConnection: ObservableObject {
    let tableId: String
    @Published private(set) var view: TableView?
    /// يزيد مع كل حالة جديدة من الخادم (لمقارنة الحالة السابقة بالجديدة)
    @Published private(set) var version = 0
    @Published private(set) var connected = false
    @Published private(set) var closed = false
    /// أخرجه المالك أو حظره: لا نعيد الاتصال
    @Published private(set) var kicked: String?
    private var ws: URLSessionWebSocketTask?
    private var stopped = false
    private var loop: Task<Void, Never>?
    private var wake: CheckedContinuation<Void, Never>?

    init(_ tableId: String) { self.tableId = tableId }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var retry = 0
            while let self, !self.stopped {
                if let token = try? await Api.token() {
                    let ws = URLSession.shared.webSocketTask(with: Api.wsURL("/tables/\(self.tableId)/ws", token: token))
                    self.ws = ws
                    ws.resume()
                    // نبضة كل 25 ثانية: الاتصال الصامت يقطعه الخادم بعد قليل (فيخرج صاحبه من المحادثة الصوتية)
                    let ping = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 25_000_000_000); ws.sendPing { _ in } } }
                    defer { ping.cancel() }
                    while !self.stopped {
                        guard let msg = try? await ws.receive() else { break }
                        if !self.connected { await MainActor.run { self.connected = true } }
                        retry = 0
                        if case .string(let text) = msg { self.handle(text) }
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

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let msg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        switch msg.str("type") {
        case "state":
            if let v = msg.obj("view") { let parsed = TableView(v); DispatchQueue.main.async { self.view = parsed; self.version += 1 } }
        case "events":
            // كل حدث إعلان مستقل حتى يقرأها قارئ الشاشة بالترتيب
            // أحداث الحركة الواحدة تُقرأ جملة واحدة، وتسبق ما تأخر من قبلها فلا تتراكم القراءة
            let events = msg.strs("events").filter { !$0.isEmpty }
            if !events.isEmpty { Announcer.announceNow(events.joined(separator: "، ")) }
        case "error": Announcer.announce(msg.str("message"))
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

    func send(_ msg: JSON) {
        guard connected, let ws, let data = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: data, encoding: .utf8) else {
            Announcer.announce("جارٍ إعادة الاتصال بالطاولة…"); return
        }
        ws.send(.string(s)) { _ in }
    }

    func send(_ type: String, _ extra: JSON = [:]) { send(extra.merging(["type": type]) { a, _ in a }) }

    func stop() {
        stopped = true
        ws?.cancel(with: .goingAway, reason: nil)
        loop?.cancel()
        resumeWake()
    }
}
