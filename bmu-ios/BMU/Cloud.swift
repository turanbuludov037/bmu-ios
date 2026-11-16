import Foundation
import CryptoKit
import UIKit

// =====================================================================
//  Firebase (SDK-sız, REST ilə): Android-dəki Cloud.kt ilə EYNİ hesablar və qaydalar.
//   - Hesab adı "<nömrə>@mybeu.app" (və ya "<nömrə>_yeniN@mybeu.app"), parol = SHA-256("bmu-mobil:<nömrə>:<portal parolu>").
//     Portal parolunun özü serverə getmir.
//   - Konfiqurasiya: BMU/GoogleService-Info.plist (Firebase Console → iOS tətbiqi). Fayl yoxdursa bulud funksiyaları sönülüdür.
// =====================================================================

enum FirebaseConfig {
    static let plist: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: Any]
    }()
    static var apiKey: String? { (plist?["API_KEY"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static var projectId: String { plist?["PROJECT_ID"] as? String ?? "mybeu-nexora" }
    /// Google ilə giriş (Classroom) üçün iOS OAuth client — plist-də CLIENT_ID varsa.
    static var clientId: String? { (plist?["CLIENT_ID"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static var reversedClientId: String? { (plist?["REVERSED_CLIENT_ID"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static let bundleId = "com.nexora.beueduaz"
    static var enabled: Bool { apiKey != nil }
}

enum CloudError: LocalizedError {
    case notConfigured, network, auth(String), denied(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return t("Bulud hələ qoşulmayıb (GoogleService-Info.plist yoxdur)", "Cloud is not set up yet (GoogleService-Info.plist missing)")
        case .network: return t("İnternet bağlantısını yoxlayın", "Check your internet connection")
        case .auth(let m): return t("Hesaba qoşulmaq alınmadı: ", "Could not connect the account: ") + m
        case .denied(let m): return m
        }
    }
}

// MARK: - Firestore dəyərləri (REST formatı)

enum FS {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func value(_ v: Any) -> [String: Any] {
        switch v {
        case let s as String: return ["stringValue": s]
        case let b as Bool: return ["booleanValue": b]
        case let i as Int: return ["integerValue": String(i)]
        case let i as Int64: return ["integerValue": String(i)]
        case let d as Double: return ["doubleValue": d]
        case let d as Date: return ["timestampValue": iso.string(from: d)]
        case let m as [String: Any]: return ["mapValue": ["fields": fields(m)]]
        case let a as [Any]: return ["arrayValue": ["values": a.map { value($0) }]]
        default: return ["nullValue": NSNull()]
        }
    }

    static func fields(_ m: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in m { out[k] = value(v) }
        return out
    }

    static func decode(_ v: [String: Any]) -> Any? {
        if let s = v["stringValue"] as? String { return s }
        if let b = v["booleanValue"] as? Bool { return b }
        if let s = v["integerValue"] as? String { return Int(s) ?? 0 }
        if let d = v["doubleValue"] as? Double { return d }
        if let s = v["timestampValue"] as? String {
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        if let m = v["mapValue"] as? [String: Any] { return decodeFields(m["fields"] as? [String: Any] ?? [:]) }
        if let a = v["arrayValue"] as? [String: Any] {
            return (a["values"] as? [[String: Any]] ?? []).compactMap { decode($0) }
        }
        return nil
    }

    static func decodeFields(_ f: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in f { if let m = v as? [String: Any], let d = decode(m) { out[k] = d } }
        return out
    }
}

struct Mate: Identifiable, Sendable {
    let id: String
    let name: String, group: String
    let photo: Data?
    let online: Bool
    let lastSeen: Date?
}

// MARK: - Bulud

actor Cloud {
    static let shared = Cloud()

    private var idToken: String?
    private var refreshToken: String?
    private var expiry = Date.distantPast
    private(set) var uid: String?
    private var number = ""
    private var profile = Profile()

    var connected: Bool { uid != nil }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    // MARK: hesab adı və açar

    static func email(_ number: String, _ i: Int) -> String {
        let base = number.trimmed.lowercased()
        return i <= 0 ? "\(base)@mybeu.app" : "\(base)_yeni\(i)@mybeu.app"
    }

    /// Portal parolundan hesablanan Firebase parolu (Android ilə eyni).
    static func key(_ number: String, _ password: String) -> String {
        let digest = SHA256.hash(data: Data("bmu-mobil:\(number.trimmed):\(password)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Potok: qrup kodunun son rəqəmləri olmadan (135a1 → 135a).
    static func groupCode(_ raw: String) -> String {
        (raw.replacingOccurrences(of: " ", with: "").groups(#"\d{2,4}[A-Za-z][0-9lIoO|]*"#)?[0] ?? "").lowercased()
    }
    static func stream(_ raw: String) -> String {
        var g = groupCode(raw)
        while let last = g.last, last.isNumber { g.removeLast() }
        return g
    }

    // MARK: HTTP

    private func request(_ url: String, method: String = "GET", body: Any? = nil, auth: Bool = true) async throws -> Any? {
        guard let key = FirebaseConfig.apiKey else { throw CloudError.notConfigured }
        let sep = url.contains("?") ? "&" : "?"
        guard let u = URL(string: url + sep + "key=" + key) else { throw CloudError.network }
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.setValue(FirebaseConfig.bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let tok = try await validToken() { r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: r) } catch { throw CloudError.network }
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 400 {
            let msg = ((json as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
            if code == 404 { return nil }
            throw CloudError.auth(msg)
        }
        return json
    }

    private func validToken() async throws -> String? {
        guard let tok = idToken else { return nil }
        if Date() < expiry.addingTimeInterval(-120) { return tok }
        guard let rt = refreshToken, let key = FirebaseConfig.apiKey,
              let u = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(key)") else { return tok }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue(FirebaseConfig.bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data("grant_type=refresh_token&refresh_token=\(rt)".utf8)
        guard let (data, _) = try? await session.data(for: r),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["id_token"] as? String else { return tok }
        idToken = id
        refreshToken = o["refresh_token"] as? String ?? rt
        expiry = Date().addingTimeInterval(Double(o["expires_in"] as? String ?? "3600") ?? 3600)
        return id
    }

    private func authCall(_ action: String, _ body: [String: Any]) async throws -> [String: Any] {
        let r = try await request("https://identitytoolkit.googleapis.com/v1/accounts:\(action)", method: "POST",
                                  body: body.merging(["returnSecureToken": true]) { a, _ in a }, auth: false)
        guard let o = r as? [String: Any] else { throw CloudError.auth("EMPTY") }
        return o
    }

    private func adopt(_ o: [String: Any]) {
        idToken = o["idToken"] as? String
        refreshToken = o["refreshToken"] as? String
        uid = o["localId"] as? String
        expiry = Date().addingTimeInterval(Double(o["expiresIn"] as? String ?? "3600") ?? 3600)
    }

    /// Daxil ol: uğurlu = true, parol/hesab səhvi = false, internet xətası = throw.
    private func trySignIn(_ email: String, _ key: String) async throws -> Bool {
        do { adopt(try await authCall("signInWithPassword", ["email": email, "password": key])); return true }
        catch CloudError.auth { return false }
    }

    private func tryCreate(_ email: String, _ key: String) async throws -> Bool {
        do { adopt(try await authCall("signUp", ["email": email, "password": key])); return true }
        catch CloudError.auth { return false }
    }

    // MARK: Firestore

    private var docsBase: String { "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents" }

    func getDoc(_ path: String, auth: Bool = true) async throws -> [String: Any]? {
        guard let o = try await request("\(docsBase)/\(path)", auth: auth) as? [String: Any] else { return nil }
        return FS.decodeFields(o["fields"] as? [String: Any] ?? [:])
    }

    func setDoc(_ path: String, _ data: [String: Any]) async throws {
        _ = try await request("\(docsBase)/\(path)", method: "PATCH", body: ["fields": FS.fields(data)])
    }

    func updateDoc(_ path: String, _ data: [String: Any]) async throws {
        let mask = data.keys.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        _ = try await request("\(docsBase)/\(path)?\(mask)", method: "PATCH", body: ["fields": FS.fields(data)])
    }

    func deleteDoc(_ path: String) async throws {
        _ = try await request("\(docsBase)/\(path)", method: "DELETE")
    }

    /// Sadə sorğu: bərabərlik şərtləri (AND).
    func query(_ collection: String, equals: [(String, Any)]) async throws -> [(id: String, data: [String: Any])] {
        let filters: [[String: Any]] = equals.map {
            ["fieldFilter": ["field": ["fieldPath": $0.0], "op": "EQUAL", "value": FS.value($0.1)]]
        }
        let whereClause: [String: Any] = filters.count == 1 ? filters[0] : ["compositeFilter": ["op": "AND", "filters": filters]]
        let body: [String: Any] = ["structuredQuery": ["from": [["collectionId": collection]], "where": whereClause]]
        let r = try await request("\(docsBase):runQuery", method: "POST", body: body)
        var out: [(id: String, data: [String: Any])] = []
        for row in r as? [[String: Any]] ?? [] {
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String else { continue }
            let id = String(name.split(separator: "/").last ?? "")
            out.append((id: id, data: FS.decodeFields(doc["fields"] as? [String: Any] ?? [:])))
        }
        return out
    }

    // MARK: qoşulma (Android Cloud.signIn ilə eyni addımlar)

    func connect(number: String, password: String, profile: Profile) async {
        guard FirebaseConfig.enabled, !number.isEmpty else { return }
        self.number = number.trimmed.lowercased()
        self.profile = profile
        do { try await signIn(number: number, password: password) } catch { uid = nil }
    }

    private func signIn(number: String, password: String) async throws {
        let base = number.trimmed.lowercased()
        let key = Cloud.key(number, password)
        let old = Keychain.get("fb_key_\(base)")
        let latestDoc: [String: Any]? = (try? await getDoc("latest/\(base)", auth: false)) ?? nil
        let known = latestDoc?["n"] as? Int
        var idx = known ?? Int(Keychain.get("fb_idx_\(base)") ?? "") ?? 0

        var ok = try await trySignIn(Cloud.email(number, idx), key)
        // parol saytdan dəyişilib, köhnəsi bu telefondadır → köhnə ilə gir, yenisinə dəyiş
        if !ok, let old, old != key, try await trySignIn(Cloud.email(number, idx), old) {
            if let tok = idToken, let o = try? await authCall("update", ["idToken": tok, "password": key]) { adopt(o); ok = true }
        }
        var fresh = false
        if !ok && known == nil, try await tryCreate(Cloud.email(number, idx), key) { ok = true; fresh = idx > 0 }
        if !ok {
            for i in (idx + 1)...(idx + 30) {
                if try await tryCreate(Cloud.email(number, i), key) { idx = i; ok = true; fresh = true; break }
                if try await trySignIn(Cloud.email(number, i), key) { idx = i; ok = true; break }
            }
        }
        guard ok, let me = uid else { throw CloudError.auth("SIGN_IN") }
        Keychain.set("fb_key_\(base)", key)
        Keychain.set("fb_idx_\(base)", String(idx))
        if known != idx { try? await setDoc("latest/\(base)", ["n": idx]) }
        if fresh {
            for d in (try? await query("students", equals: [("number", base)])) ?? [] where d.id != me {
                try? await deleteDoc("students/\(d.id)")
            }
        }
        if UserDefaults.standard.bool(forKey: "mates_visible") { try? await publish(true, photo: nil) }
    }

    /// Tətbiqdən parol dəyişəndə Firebase parolu da dəyişir.
    func passwordChanged(number: String, old: String, new: String) async {
        guard FirebaseConfig.enabled else { return }
        let base = number.trimmed.lowercased()
        if uid == nil { try? await signIn(number: number, password: old) }
        guard let tok = try? await validToken(), let o = try? await authCall("update", ["idToken": tok, "password": Cloud.key(number, new)]) else { return }
        adopt(o)
        Keychain.set("fb_key_\(base)", Cloud.key(number, new))
    }

    func signOut() async {
        if let me = uid, UserDefaults.standard.bool(forKey: "mates_visible") {
            try? await updateDoc("students/\(me)", ["online": false, "lastSeen": Date()])
        }
        idToken = nil; refreshToken = nil; uid = nil; number = ""
    }

    // MARK: qrup yoldaşları

    private func thumb(_ img: UIImage?) -> String {
        guard let img else { return "" }
        let side: CGFloat = 96
        let size = CGSize(width: side, height: side * img.size.height / max(img.size.width, 1))
        let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString() ?? ""
    }

    /// Görünmək / görünməmək. Görünməyəndə qeyd silinir.
    func publish(_ on: Bool, photo: UIImage?) async throws {
        guard let me = uid else { throw CloudError.notConfigured }
        if !on { try await deleteDoc("students/\(me)"); return }
        let p = profile
        var data: [String: Any] = [
            "number": number, "name": String(p.fullName.prefix(110)), "group": Cloud.groupCode(p.group),
            "stream": Cloud.stream(p.group), "course": p.course, "visible": true, "online": true, "lastSeen": Date()
        ]
        let ph = thumb(photo)
        data["photo"] = ph.count < 39000 ? ph : ""
        try await setDoc("students/\(me)", data)
    }

    func setOnline(_ on: Bool) async {
        guard let me = uid, UserDefaults.standard.bool(forKey: "mates_visible") else { return }
        try? await updateDoc("students/\(me)", ["online": on, "lastSeen": Date()])
    }

    /// Potokdakı görünən tələbələr (onlayn olanlar əvvəl).
    func mates() async throws -> [Mate] {
        guard let me = uid else { throw CloudError.notConfigured }
        let rows = try await query("students", equals: [("stream", Cloud.stream(profile.group)), ("visible", true)])
        let now = Date()
        var list: [Mate] = []
        for r in rows where r.id != me {
            let seen = r.data["lastSeen"] as? Date
            var online = r.data["online"] as? Bool ?? false
            if let seen, now.timeIntervalSince(seen) >= 600 { online = false }
            if seen == nil { online = false }
            let photoText = r.data["photo"] as? String ?? ""
            list.append(Mate(id: r.id, name: r.data["name"] as? String ?? "", group: r.data["group"] as? String ?? "",
                             photo: Data(base64Encoded: photoText), online: online, lastSeen: seen))
        }
        list.sort { a, b in
            if a.online != b.online { return a.online }
            return a.name < b.name
        }
        return list
    }

    // MARK: analitika

    func saveUsage(_ id: String, _ data: [String: Any]) async {
        guard uid != nil else { return }
        var d = data
        d["updated"] = Date()
        try? await setDoc("usage/\(id)", d)
    }

    func saveLive(_ data: [String: Any]) async {
        guard uid != nil, !number.isEmpty else { return }
        var d = data
        d["updated"] = Date()
        try? await setDoc("live/\(number)", d)
    }
}
