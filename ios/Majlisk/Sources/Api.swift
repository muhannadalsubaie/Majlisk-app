import Foundation
import FirebaseAuth

/// خطأ من الخادم: code هو رمز الخطأ (مثل not-enough-coins)
struct ApiError: Error { let code: String }

typealias JSON = [String: Any]

enum Api {
    static let base = "https://majlisk-api.majlisk.workers.dev/api"
    static var site: String { base.replacingOccurrences(of: "/api", with: "") }

    static func token() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw ApiError(code: "unauthenticated") }
        return try await user.getIDToken()
    }

    /// طلب POST بتوكن المستخدم الحالي
    @discardableResult
    static func post(_ path: String, _ body: JSON = [:]) async throws -> JSON {
        try await send(path, body: body, token: try await token())
    }

    /// طلب بلا تسجيل دخول (مثل فحص توفر اسم المستخدم)
    @discardableResult
    static func postPublic(_ path: String, _ body: JSON = [:]) async throws -> JSON {
        try await send(path, body: body, token: nil)
    }

    static func get(_ path: String) async throws -> JSON {
        var req = URLRequest(url: URL(string: base + path)!)
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return try await execute(req)
    }

    private static func send(_ path: String, body: JSON, token: String?) async throws -> JSON {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(req)
    }

    private static func execute(_ req: URLRequest) async throws -> JSON {
        let data: Data, res: URLResponse
        do { (data, res) = try await URLSession.shared.data(for: req) } catch { throw ApiError(code: "network") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) { throw ApiError(code: json["error"] as? String ?? "http-\(status)") }
        return json
    }

    static func wsURL(_ path: String, token: String) -> URL {
        let t = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? token
        return URL(string: base.replacingOccurrences(of: "https", with: "wss") + path + "?token=" + t)!
    }
}

// ───── مساعدات JSON ─────
extension Dictionary where Key == String, Value == Any {
    func str(_ k: String, _ def: String = "") -> String { self[k] as? String ?? def }
    func strOrNil(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String, _ def: Int = 0) -> Int { (self[k] as? NSNumber)?.intValue ?? def }
    func intOrNil(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue }
    func bool(_ k: String) -> Bool { (self[k] as? NSNumber)?.boolValue ?? false }
    func obj(_ k: String) -> JSON? { self[k] as? JSON }
    func arr(_ k: String) -> [Any] { self[k] as? [Any] ?? [] }
    func objs(_ k: String) -> [JSON] { arr(k).compactMap { $0 as? JSON } }
    func ints(_ k: String) -> [Int] { arr(k).map { ($0 as? NSNumber)?.intValue ?? 0 } }
    func strs(_ k: String) -> [String] { arr(k).map { $0 as? String ?? "" } }
}
