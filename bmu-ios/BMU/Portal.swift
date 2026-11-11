import Foundation

enum PortalError: LocalizedError {
    case wrongCredentials
    case network
    case message(String)

    var errorDescription: String? {
        switch self {
        case .wrongCredentials: return "Tələbə nömrəsi və ya şifrə yanlışdır"
        case .network: return "İnternet bağlantısını yoxlayın və yenidən cəhd edin"
        case .message(let m): return m
        }
    }
}

/// Yönləndirmələr yalnız universitetin HTTPS ünvanına gedə bilər (şifrə başqa yerə sızmaz).
final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if request.url?.scheme == "https" && request.url?.host == Portal.host {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

/// my.beu.edu.az portalına telefonun özündən giriş (Android-dəki PortalClient.kt ilə eyni məntiq).
/// Şifrə yalnız universitetin saytına göndərilir; cookie-lər yalnız yaddaşda saxlanır.
actor Portal {
    static let shared = Portal()
    static let host = "my.beu.edu.az"
    static let base = "https://my.beu.edu.az/"

    private var session = Portal.makeSession()
    /// Sessiya bitəndə avtomatik yenidən giriş üçün (yalnız RAM-da).
    private var creds: (String, String)?
    private var generation = 0

    private static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 40
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "az,en;q=0.8"
        ]
        return URLSession(configuration: c, delegate: RedirectGuard(), delegateQueue: nil)
    }

    var hasSession: Bool { creds != nil }

    private func request(_ path: String) -> URLRequest {
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let s = Portal.base + p
        let url = URL(string: s) ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)!
        return URLRequest(url: url)
    }

    private func sendData(_ r: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, resp) = try await session.data(for: r)
            if let u = resp.url, u.host != Portal.host { throw PortalError.network }
            return (data, resp)
        } catch let e as PortalError {
            throw e
        } catch {
            throw PortalError.network
        }
    }

    private func send(_ r: URLRequest) async throws -> String {
        let (data, _) = try await sendData(r)
        return String(decoding: data, as: UTF8.self)
    }

    private static func isLoginPage(_ body: String) -> Bool {
        body.contains("auth.php") && body.contains("name=\"password\"")
    }

    /// Sessiya bitibsə (giriş forması gəlibsə) bir dəfə yenidən daxil olub sorğunu təkrarlayır.
    private func withSession(_ r: URLRequest) async throws -> String {
        let gen = generation
        let body = try await send(r)
        guard Portal.isLoginPage(body), let c = creds else { return body }
        if gen == generation { _ = try await login(c.0, c.1) }
        return try await send(r)
    }

    private static func form(_ pairs: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return Data(pairs.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&").utf8)
    }

    /// Giriş: əvvəl giriş səhifəsi (PHPSESSID cookie), sonra form → auth.php. Uğurlu olsa açılan səhifənin HTML-i.
    func login(_ number: String, _ password: String) async throws -> String {
        session.invalidateAndCancel()
        session = Portal.makeSession()
        _ = try await send(request("index.php"))
        var r = request("auth.php")
        r.httpMethod = "POST"
        r.setValue(Portal.base + "index.php", forHTTPHeaderField: "Referer")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Portal.form([("username", number), ("password", password), ("LogIn", "")])
        let html = try await send(r)
        if html.range(of: "parol səhvdir", options: .caseInsensitive) != nil || html.contains("name=\"password\"") {
            creds = nil
            throw PortalError.wrongCredentials
        }
        creds = (number, password)
        generation += 1
        return html
    }

    func logout() {
        creds = nil
        generation += 1
        session.invalidateAndCancel()
        session = Portal.makeSession()
    }

    /// Portalın istənilən səhifəsinin HTML-i.
    func fetch(_ path: String) async throws -> String {
        try await withSession(request(path))
    }

    /// Şəkil və s. ikili fayl (HTML gəlibsə xəta).
    func fetchData(_ path: String) async throws -> Data {
        let (data, resp) = try await sendData(request(path))
        if let mime = (resp as? HTTPURLResponse)?.mimeType, mime.hasPrefix("text/html") { throw PortalError.network }
        return data
    }

    /// Portalın Ajax.ajax({method:'POST'}) funksiyasının eynisi: "index.php?a=1&b=2" → POST index.php, gövdə "a=1&b=2&<vaxt>".
    func ajax(_ urlWithQuery: String, referer: String = "index.php") async throws -> String {
        let parts = urlWithQuery.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        let query = parts.count > 1 ? String(parts[1]) : ""
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        var r = request(path)
        r.httpMethod = "POST"
        r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        r.setValue(Portal.base + referer, forHTTPHeaderField: "Referer")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(((query.isEmpty ? "" : query + "&") + String(millis)).utf8)
        return try await withSession(r)
    }

    /// Kodlaşdırılmış form gövdəsi ilə POST.
    func post(_ path: String, _ params: [(String, String)], referer: String = "index.php") async throws -> String {
        var r = request(path)
        r.httpMethod = "POST"
        r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        r.setValue(Portal.base + referer, forHTTPHeaderField: "Referer")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Portal.form(params)
        return try await withSession(r)
    }
}

/// "Məni xatırla": nömrə və şifrə iPhone-un Keychain-ində (yalnız bu cihazda, şifrələnmiş).
enum Keychain {
    private static let service = "com.nexora.beueduaz.credentials"
    private static let account = "student"

    static func save(_ number: String, _ password: String) {
        clear()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("\(number)\n\(password)".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> (String, String)? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8),
              let i = s.firstIndex(of: "\n") else { return nil }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    static func clear() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        _ = SecItemDelete(q as CFDictionary)
    }
}
