import UIKit
import Foundation
import Combine
import Network
import FirebaseFirestore
import FirebaseAuth
import FirebaseMessaging

/// tableId: الطاولة اللي فيها الصديق المتصل الآن (إن وُجدت)
struct Friend: Identifiable, Equatable { let uid: String; let username: String; var online = false; var tableId: String? = nil; var tablePrivate = false; var tableGame = ""; var id: String { uid } }
struct TableInvite: Equatable { let tableId: String; let code: String; let fromUid: String; let fromName: String; var game = "" }
struct HubState: Equatable { var friends: [Friend] = []; var requests: [Friend] = []; var invites: [TableInvite] = [] }

private func friends(_ o: JSON, _ key: String) -> [Friend] { o.objs(key).map { Friend(uid: $0.str("uid"), username: $0.str("username"), online: $0.bool("online"),
                                                                                   tableId: $0.str("tableId").isEmpty ? nil : $0.str("tableId"), tablePrivate: $0.bool("tablePrivate"),
                                                                                   tableGame: $0.str("tableKind").isEmpty ? "" : gameTitle($0.str("tableKind"), $0.str("tableVariant"))) } }
private func invites(_ o: JSON) -> [TableInvite] {
    o.objs("invites").map { TableInvite(tableId: $0.str("tableId"), code: $0.str("code"), fromUid: $0.str("fromUid"), fromName: $0.str("fromName"), game: $0.str("game")) }
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
        "invite-wait": "أرسلت له دعوة قبل شوي. تقدر ترسل له دعوة ثانية بعد ١٠ دقائق من الأولى",
        "not-enough-coins": "رصيدك من العملات لا يكفي",
        "not-owner": "الدعوة لمالك الطاولة فقط",
        "table-full": "الطاولة ممتلئة",
        "not-found": "الطاولة لم تعد موجودة",
        "no-username": "اختر اسم مستخدم أولاً",
        "request-blocked": "ما تقدر ترسل له طلب صداقة الحين، جرّب بكرة",
        "busy": "لحظة، جرّب مرة ثانية",
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

    /// الحساب مفتوح في جهاز ثاني: هالجهاز «مقفول» (بدون تسجيل خروج). أي جهاز يفتح التطبيق ياخذ الحساب
    /// على طول والثاني يتقفل؛ لو رجعت فتحته هنا ينفتح ويتقفل الثاني.
    @Published private(set) var locked = false

    /// فتحت التطبيق (أو رجعت له): هالجهاز ياخذ الحساب، والجهاز الثاني يتقفل
    func takeOver() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task { @MainActor in
            guard (try? await Api.post("/profile/claim-device", ["device": Prefs.deviceId])) != nil else { return }
            Prefs.claimedUid = uid
            if self.locked { self.locked = false; self.start() }
        }
    }

    /// تسجيل خروج: ما يبقى القفل لحساب ثاني يدخل
    func clearLock() { DispatchQueue.main.async { self.locked = false } }

    /// جهاز ثاني أخذ الحساب: نقفل هالجهاز (نوقف الاتصال والمحادثة الصوتية) بدون تسجيل خروج
    @MainActor func lock() {
        guard !locked else { return }
        locked = true
        stop()
        Voice.shared.leave(quiet: true)
        Announcer.announce("حسابك انفتح في جهاز ثاني. افتح التطبيق هنا متى ما بغيت ترجع له")
    }

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
                } else if Auth.auth().currentUser != nil,
                          let r = try? await Api.post("/profile/device-status", ["device": Prefs.deviceId]), (r["current"] as? Bool) == false {
                    // رجع الاتصال (بعد انقطاع) وجهاز ثاني أخذ الحساب وقتها: نتقفل بدل ما نرجع ناخذه
                    await MainActor.run { self?.lock() }
                    break
                }
                let url = URL(string: Api.wsURL("/me/ws", token: token).absoluteString + "&device=" + Prefs.deviceId)!
                let ws = URLSession.shared.webSocketTask(with: url)
                self?.task = ws
                ws.resume()
                // فتحت التطبيق (أو رجع الاتصال): إعلان المطور اللي فاتك
                Announce.shared.refresh()
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
        // الحساب انفتح من جهاز ثاني: نقفل هالجهاز (بدون تسجيل خروج)
        case "loggedOut":
            Task { @MainActor in
                // نتأكد من الخادم إن جهاز ثاني فعلاً أخذ الحساب (ما نتقفل بالغلط)
                guard let r = try? await Api.post("/profile/device-status", ["device": Prefs.deviceId]),
                      (r["current"] as? Bool) == false else { return }
                self.lock()
            }
        case "notice": Sounds.shared.notify(); Announcer.announce(msg.str("text"))
        case "invite":
            Sounds.shared.inviteIn()
            let inv = msg.obj("invite"), g = inv?.str("game") ?? ""
            Announcer.announce(g.isEmpty ? "\(inv?.str("fromName") ?? "") يدعوك لطاولته" : "\(inv?.str("fromName") ?? "") دعاك لطاولة \(g)")
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
        // إعلان المطور وصل الحين
        case "announce":
            let id = (msg["id"] as? NSNumber)?.int64Value ?? 0
            let t = msg.str("text")
            DispatchQueue.main.async { Announce.shared.offer(id, t) }
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

let GAME_NAMES = ["baloot": "بلوت", "domino": "دومينو", "jackaroo": "جاكارو", "ludo": "لودو",
                  "tarneeb": "طرنيب", "trix": "تريكس", "konkan": "كنكان", "shayeb": "شايب"]
/// ألعاب الورق التجريبية: تطلع بس للي فتحها له الخادم (/me/features)
let BETA_GAMES = ["tarneeb", "trix", "konkan", "shayeb"]

/// المزايا المفتوحة لهالحساب من الخادم: الألعاب التجريبية (تطلع في إنشاء الطاولة وتغيير اللعبة)
/// إعلان المطور: رسالة توصل لكل مستخدمي التطبيق مرة وحدة (المتصل الحين، واللي يفتح التطبيق بعدين).
/// بدون رد ولا تفاعل: تنقرأ وتنقفل بس.
final class Announce: ObservableObject {
    static let shared = Announce()
    @Published private(set) var current: (id: Int64, text: String)?
    private var seenId: Int64 { Int64(UserDefaults.standard.string(forKey: "announceSeen") ?? "0") ?? 0 }
    func offer(_ id: Int64, _ text: String) {
        guard id > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id > seenId, current?.id != id else { return }
        current = (id, text)
        Sounds.shared.notify()
        if UIAccessibility.isVoiceOverRunning { Announcer.announce("إعلان: \(text)") }
    }
    func seen() {
        if let c = current { UserDefaults.standard.set(String(c.id), forKey: "announceSeen") }
        current = nil
    }
    func refresh() {
        Task {
            guard let o = try? await Api.get("/me/announce"), let a = o.obj("announce") else { return }
            let id = (a["id"] as? NSNumber)?.int64Value ?? 0
            let t = a.str("text")
            await MainActor.run { self.offer(id, t) }
        }
    }
    /// المطور بس (الخادم يرفض غيره). نص فاضي يمسح الإعلان
    func send(_ text: String) async -> Bool {
        guard let o = try? await Api.post("/admin/announce", ["text": text]) else { return false }
        return o.bool("ok")
    }
}

final class Features: ObservableObject {
    static let shared = Features()
    @Published private(set) var betaGames: [String] = []
    func refresh() {
        Task {
            guard let o = try? await Api.get("/me/features") else { return }
            let list = o.strs("betaGames").filter { BETA_GAMES.contains($0) }
            await MainActor.run { self.betaGames = list }
        }
    }
}

/// اسم اللعبة كما في الخادم (shared/games.ts → gameTitle)
func gameTitle(_ kind: String, _ variant: String?) -> String {
    let base = GAME_NAMES[kind] ?? "بلوت"
    if kind == "jackaroo" && variant == "complex" { return base + " كمبلكس" }
    if (kind == "ludo" || kind == "trix") && variant == "teams" { return base + " فرق" }
    if kind == "domino" { return base + (variant == "t150" ? " 150" : variant == "t200" ? " 200" : " 100") }
    return base
}

struct TableRow: Identifiable {
    let id, ownerName: String; let isPrivate: Bool; let players, people: Int; let status, kind, variant: String
    /// الموجودين: (الاسم، player|bot|spectator)
    var members: [(name: String, role: String)] = []
    /// نتيجة اللعب الجاري (فاضي إذا ما فيه لعب)
    var score: String = ""
    /// طاولة ثابتة بكلمة مرور (الباقة الاحترافية)
    var locked = false

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
        "friends-only": "صاحب الطاولة مفعّل خصوصية اللاعب: طاولته للأصدقاء فقط",
        "kicked": "أُخرجت من هذه الطاولة، ويمكنك العودة إليها بعد ساعة من طردك، أو قبلها بدعوة من مالكها. يمكنك دخول أي طاولة أخرى الآن",
        "not-found": "الطاولة غير موجودة",
        "not-a-member": "لست عضواً في هذه الطاولة",
        "private": "هذه طاولة خاصة — تحتاج دعوة من مالكها",
        "not-owner": "هذا الإجراء لمالك الطاولة فقط",
        "wrong-password": "كلمة المرور غير صحيحة",
        "too-many-attempts": "محاولات كثيرة غلط، جرّب بعد ربع ساعة",
        "password-required": "هذه الطاولة بكلمة مرور",
        "bad-password": "كلمة المرور من 4 إلى 20 حرف",
        "pro-only": "هذي الميزة للمشتركين في الباقة الاحترافية",
    ]
    static func error(_ e: Error, _ fallback: String) -> String { errors[(e as? ApiError)?.code ?? ""] ?? fallback }

    /// password = طاولة ثابتة بكلمة مرور (الباقة الاحترافية)
    static func create(isPrivate: Bool, kind: String, variant: String, password: String? = nil) async throws -> String {
        var b: JSON = ["isPrivate": isPrivate, "kind": kind, "variant": variant]
        if let password { b["password"] = password }
        return try await Api.post("/tables", b).str("id")
    }
    static func join(_ id: String, password: String? = nil) async throws {
        if let password { try await Api.post("/tables/\(id)/join", ["password": password]) } else { try await Api.post("/tables/\(id)/join") }
    }
    /// طلب انضمام لطاولة خاصة (يوصل للمالك تنبيه)، وحالته: pending / accepted / ignored
    /// الحالة وكم دقيقة باقية (للمعلّق والمرفوض)
    static func requestJoin(_ id: String) async throws -> (String, Int) { let r = try await Api.post("/tables/\(id)/join-request"); return (r.str("status"), r.int("minutes")) }
    static func joinRequestStatus(_ id: String) async throws -> (String, Int) { let r = try await Api.post("/tables/\(id)/join-request/status"); return (r.str("status"), r.int("minutes")) }
    static func deleteAccount() async throws { try await Api.post("/me/delete") }

    private static func row(_ id: String, _ x: [String: Any]) -> TableRow {
        TableRow(
            id: id,
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
            score: x["score"] as? String ?? "",
            locked: x["locked"] as? Bool == true
        )
    }

    /// الطاولات النشطة (أحدث 50) — تتحدث مباشرة. والطاولات الثابتة (برقم سري) مخفية عن القائمة العامة:
    /// تطلع بس لصاحبها ولأصدقائه اللي اختارهم (من الخادم، تتحدث كل ٢٠ ثانية)
    static func listen(_ onRows: @escaping ([TableRow]) -> Void) -> ListenerRegistration {
        let box = TablesListener()
        let emit = { DispatchQueue.main.async { onRows(box.fire.filter { !$0.locked } + box.hidden) } }
        box.task = Task {
            while !Task.isCancelled {
                if let r = try? await Api.post("/tables/visible") {
                    box.hidden = r.objs("tables").map { row($0.str("id"), $0) }
                    emit()
                }
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        box.reg = Firestore.firestore().collection("tables").order(by: "updatedAt", descending: true).limit(to: 50).addSnapshotListener { snap, _ in
            box.fire = snap?.documents.map { row($0.documentID, $0.data()) } ?? []
            emit()
        }
        return box
    }
}

/// مستمع قائمة الطاولات: Firestore للعامة + طلب دوري للطاولات الثابتة المخفية، وإيقافهم سوا
final class TablesListener: NSObject, ListenerRegistration {
    var reg: ListenerRegistration?
    var task: Task<Void, Never>?
    var fire: [TableRow] = []
    var hidden: [TableRow] = []
    func remove() { reg?.remove(); task?.cancel() }
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
                    // z: حالة الطاولة توصل مضغوطة (أصغر بثلاث لأربع مرات، أسرع على النت الضعيف)
                    ws.send(.string("{\"type\":\"caps\",\"voice\":true,\"z\":true,\"lock\":true}")) { _ in }
                    // حركات انرسلت والاتصال ميت (ضاعت): نعيد إرسالها بالترتيب مع الاتصال الجديد.
                    // كل حركة لها رقم (mid): لو كانت وصلت الخادم قبل، يتجاهلها ويرد بالحالة بس (ما تنحسب مرتين)
                    await MainActor.run {
                        self.outbox.removeAll { Date().timeIntervalSince($0.at) > 20 }
                        for o in self.outbox { self.resent = true; ws.send(.string(o.text)) { _ in } }
                    }
                    // نبضة كل 3 ثوانٍ: الخادم يكتشف انقطاع نتك خلال ثوانٍ، ونحن نكتشف الاتصال الميت (ما يرد) فنعيده فوراً
                    self.lastHeard = Date(); self.lastData = Date(); self.syncAt = nil
                    let ping = Task { [weak self] in
                        while !Task.isCancelled {
                            let mine = self?.myTurn ?? false
                            try? await Task.sleep(nanoseconds: mine ? 2_000_000_000 : 3_000_000_000)
                            guard let self else { break }
                            let now = Date()
                            // ١٢ ثانية بلا أي رد = الاتصال ميت (كانت ٨: على النت الضعيف كانت تقطع وتعيد بلا داعي)
                            // والدور عندك: ٦ ثوانٍ تكفي، فترجع بسرعة وما يحس البقية بتعليق
                            if now.timeIntervalSince(self.lastHeard) > (self.myTurn ? 6 : 12) { ws.cancel(with: .goingAway, reason: nil); break }
                            // طلبنا الحالة وما وصلت خلال ٤ ثوانٍ: الطاولة ما توصلنا (الاتصال معلّق)، نعيده
                            if let s = self.syncAt, self.lastData < s, now.timeIntervalSince(s) > 4 { ws.cancel(with: .goingAway, reason: nil); break }
                            // الدور عندك وما وصلنا شي من الطاولة ٢٠ ثانية: نطلب الحالة (لا تبقى شاشتك على حالة قديمة).
                            // بس للي الدور عنده: طلب كل الجوالات كان يصحّي الطاولة كل ١٠ ثوانٍ فما تنام أبداً (يزيد المصروف)
                            if self.myTurn, now.timeIntervalSince(self.lastData) > 20, self.syncAt.map({ self.lastData >= $0 }) ?? true { self.resync(ws) }
                            try? await ws.send(.string("ping"))
                        }
                    }
                    defer { ping.cancel() }
                    while !self.stopped {
                        guard let msg = try? await ws.receive() else { break }
                        self.lastHeard = Date()
                        if case .string(let t) = msg, t == "pong" {} else { self.lastData = self.lastHeard }
                        if !self.connected { await MainActor.run { self.connected = true } }
                        retry = 0
                        switch msg {
                        case .string(let text): if text != "pong" { self.handle(text) }
                        // حالة مضغوطة (deflate-raw)
                        case .data(let d): if let text = inflateRaw(d) { self.handle(text) }
                        @unknown default: break
                        }
                    }
                    await MainActor.run { self.connected = false }
                }
                if self.stopped { break }
                retry = min(retry + 1, 6)
                // بعد عدة محاولات: هل الطاولة أُغلقت أو أُخرجنا منها؟ أم الشبكة فقط؟
                if retry >= 3, let member = try? await Api.get("/tables/\(self.tableId)/member"), !member.bool("member") {
                    // غبت أكثر من المهلة (مكالمة مثلاً) فطلعك الخادم من الطاولة: لو الطاولة موجودة نرجعك لها على طول،
                    // وما نقول «أُغلقت الطاولة» إلا لو فعلاً ما تقدر ترجع (انقفلت أو خاصة أو انحذفت)
                    if (try? await Tables.join(self.tableId)) != nil {
                        Announcer.announce("رجعت للطاولة")
                        retry = 0
                        continue
                    }
                    self.stopped = true
                    await MainActor.run { self.closed = true }
                    break
                }
                // أول محاولة على طول، وبعدها تتباعد شوي (ثانية، ثنتين، ...)
                await self.sleep(seconds: retry - 1)
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
    func reconnectNow() { if !connected { resumeWake() } else if let ws { resync(ws) } }

    /// نطلب الحالة الحالية من الطاولة (ونتأكد إن الاتصال يوصل لها فعلاً)
    private func resync(_ ws: URLSessionWebSocketTask) {
        syncAt = Date()
        ws.send(.string("{\"type\":\"sync\"}")) { _ in }
    }

    /// الدور عندك الحين (في أي لعبة)
    private var myTurn: Bool {
        guard let v = view else { return false }
        return v.game?.myTurn == true || v.domino?.myTurn == true || v.jackaroo?.myTurn == true || v.ludo?.myTurn == true
    }

    private var lastHeard = Date()
    /// آخر رسالة حقيقية من الطاولة (غير رد النبضة)
    private var lastData = Date()
    /// متى طلبنا الحالة (nil = ما فيه طلب ينتظر)
    private var syncAt: Date?
    /// آخر شبكة (واي فاي / بيانات): نعيد الاتصال بس لما تتغيّر فعلاً
    private var pathSig: String?
    /// رجع النت (أو تغيّرت الشبكة): نعيد الاتصال فوراً، فيُعلن رجوعك للبقية على طول
    private lazy var pathMonitor: NWPathMonitor = {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self, path.status == .satisfied else { return }
            // بعض الجوالات يوصلها تنبيه «تغيّرت الشبكة» كل شوي وهي ما تغيّرت (المحادثة الصوتية، VPN...):
            // نتصرف بس لما تتغيّر الشبكة فعلاً (واي فاي ↔ بيانات)
            let sig = path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
            DispatchQueue.main.async {
                let changed = self.pathSig != nil && self.pathSig != sig
                self.pathSig = sig
                guard changed else { return }
                // ما نقطع الاتصال على طول (كان يقطعه ويعيده كل ٣ ثوانٍ): نطلب الحالة، ولو ما ردت الطاولة خلال ثوانٍ نعيده
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
            if let v = msg.obj("view") { let parsed = TableView(v); DispatchQueue.main.async {
                // خادم قديم (ما يرد بـ ack): أي حالة تعتبر رد على الحركات
                if !self.serverAcks { self.outbox.removeAll() }
                self.serverView = parsed
                // حركتك الفورية لسا ما وصلت الخادم: تبقى ظاهرة على الحالة الجديدة (ما ترجع الورقة ليدك وتطلع ثاني)
                var shown = parsed
                if let f = self.optimistic { if let p = f(parsed) { shown = p } else { self.optimistic = nil; self.optimisticMid = nil } }
                self.view = shown; self.version += 1; self.onState?(shown)
                // المحادثة الصوتية تتابع المنضمين هنا (مو من الشاشة): والتطبيق في الخلفية الشاشة ما تتحدث، فما كنت تسمع من دخل جديد
                Voice.shared.sync(parsed.voice, table: self.tableId)
            } }
        case "voice":
            // المحادثة الصوتية من غرفتها المستقلة: نحدّث القائمة بس (بدون الطاولة كاملة)
            let list = VoiceMember.list(msg.objs("voice"))
            DispatchQueue.main.async {
                self.serverView?.voice = list
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
            if !spoken.isEmpty { Announcer.announceEvent(spoken.joined(separator: "، "), urgent: view?.ludo != nil) }
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
                // صوت الدردشة حتى للمرسل: رجعت رسالتك من الخادم = انرسلت فعلاً
                Sounds.shared.chat()
                if !m.mine {
                    if !self.chatOpen { self.unread += 1 }
                    self.toast = m
                }
            }
            if !m.mine && mode == .read { Announcer.announce("\(m.name): \(m.text)") }
        case "ack":
            // الخادم استلم الحركة ونفّذها (أو كانت منفّذة قبل)
            let mid = msg.str("mid")
            DispatchQueue.main.async {
                self.serverAcks = true
                self.outbox.removeAll { $0.mid == mid }
                // وصل التأكيد والحركة الفورية لسا معروضة = الخادم تجاهلها (مثلاً وقت مهلة الأكلة): نرجع لحالته
                if self.optimisticMid == mid, self.optimistic != nil { self.revertOptimistic() }
            }
        case "error":
            let mid = msg.str("mid")
            let text = msg.str("message")
            DispatchQueue.main.async {
                if !mid.isEmpty { self.outbox.removeAll { $0.mid == mid } } else if !self.serverAcks { self.outbox.removeAll() }
                // الحركة الفورية رُفضت: ترجع الورقة ليدك
                if self.optimistic != nil && (mid.isEmpty || mid == self.optimisticMid) { self.revertOptimistic() }
                if self.resent { self.resent = false } else { Announcer.announce(text) }
            }
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

    /// الحركات اللي انرسلت ولسا ما أكدها الخادم (ack): تنعاد بالترتيب لو انقطع الاتصال (على الخيط الرئيسي)
    private var outbox: [(mid: String, text: String, at: Date)] = []
    /// الخادم الجديد يرد بـ ack على كل حركة (القديم ما يرد)
    private var serverAcks = false
    /// أعدنا إرسال حركة: لو كانت انلعبت قبل، خطأ الخادم («ليس دورك») ما ينقرأ
    private var resent = false
    /// آخر حالة من الخادم (بدون اللعب الفوري): نرجع لها لو رُفضت الحركة
    private var serverView: TableView?
    /// اللعب الفوري: الحركة اللي تنعرض قبل رد الخادم، ورقمها
    private var optimistic: Optimistic.Patch?
    private var optimisticMid: String?
    private var seq = 0

    private func revertOptimistic() {
        optimistic = nil; optimisticMid = nil
        Sounds.shared.clearLocal()
        if let v = serverView { view = v; version += 1; onState?(v) }
    }

    func send(_ msg: JSON) {
        guard msg["action"] != nil else {
            guard let data = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: data, encoding: .utf8) else { return }
            guard connected, let ws else { Announcer.announce("جارٍ إعادة الاتصال بالطاولة…"); return }
            ws.send(.string(s)) { _ in }
            return
        }
        let at = Date()
        seq += 1
        let mid = "\(Int(at.timeIntervalSince1970 * 1000))-\(seq)"
        var m = msg
        m["mid"] = mid
        guard let data = try? JSONSerialization.data(withJSONObject: m), let s = String(data: data, encoding: .utf8) else { return }
        outbox.append((mid, s, at))
        resent = false
        // اللعب الفوري: الورقة تطلع من يدك على طول، والخادم يأكدها بعدين
        // (على المعروض الحين: فضغطتين ورا بعض على نفس الورقة ما تنلعب مرتين)
        if let base = view, let f = Optimistic.patch(base, m), let shown = f(base) {
            optimistic = f; optimisticMid = mid
            view = shown; version += 1; onState?(shown)
        }
        // ما فيه اتصال الحين: الحركة محفوظة وتنرسل أول ما يرجع
        guard connected, let ws else { Announcer.announce("جارٍ إعادة الاتصال بالطاولة…"); return }
        ws.send(.string(s)) { _ in }
        // ما وصل أي شي من الخادم خلال ٥ ثوانٍ: الاتصال ميت، نعيده (والحركة تنعاد معه)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.outbox.contains(where: { $0.mid == mid }), self.lastHeard < at else { return }
            self.ws?.cancel(with: .goingAway, reason: nil)
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

/// فك حالة الطاولة المضغوطة من الخادم (deflate-raw = zlib في نظام آبل)
func inflateRaw(_ data: Data) -> String? {
    guard let out = try? (data as NSData).decompressed(using: .zlib) else { return nil }
    return String(data: out as Data, encoding: .utf8)
}
