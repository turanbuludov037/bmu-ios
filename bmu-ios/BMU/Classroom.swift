import SwiftUI
import AuthenticationServices
import CryptoKit
import QuickLook

// =====================================================================
//  Google Classroom (rəsmi API, yalnız oxumaq) — Android Classroom.kt ilə eyni qaydalar:
//   - Yalnız portaldakı universitet poçtu (…@std.beu.edu.az) ilə qoşulmaq olar; fərqli hesab gəlsə icazə dərhal ləğv olunur.
//   - Giriş: Google-un öz səhifəsi (ASWebAuthenticationSession + PKCE). Yeniləmə açarı yalnız bu iPhone-un Keychain-indədir.
// =====================================================================

struct GcCourse: Identifiable, Sendable {
    let id: String, name: String, section: String, link: String
}

struct GcFile: Identifiable, Sendable {
    let id = UUID()
    let title: String, url: String
    let kind: String          // drive / youtube / link / form
    let driveId: String
}

struct GcPost: Identifiable, Sendable {
    let id: String
    let courseId: String
    let kind: String          // ann / work / mat
    let title: String, text: String
    let created: Date
    let due: Date?
    let link: String
    let files: [GcFile]
    var state = ""
    var late = false
    var grade = ""
    var done: Bool { state == "TURNED_IN" || state == "RETURNED" }
    var headline: String {
        if !title.isEmpty { return title }
        let first = text.split(separator: "\n").first.map { String($0).trimmed } ?? ""
        return first.isEmpty ? (files.first?.title ?? "") : String(first.prefix(90))
    }
}

enum Classroom {
    static let scopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.announcements.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.courseworkmaterials.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/drive.readonly"
    ]
    private static let api = "https://classroom.googleapis.com/v1"
    private static var owner: String { (UserDefaults.standard.string(forKey: "lastNumber") ?? "").lowercased() }
    private static var refreshKey: String { "gc_refresh_\(owner)" }

    static var configured: Bool { FirebaseConfig.clientId != nil && FirebaseConfig.reversedClientId != nil }
    static var isConnected: Bool { Keychain.get(refreshKey) != nil }

    private static var accessToken: String?
    private static var accessExpiry = Date.distantPast

    // MARK: giriş

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func form(_ pairs: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }.joined(separator: "&").utf8)
    }

    /// Google səhifəsini açır, universitet hesabını yoxlayır, yeniləmə açarını saxlayır.
    @MainActor
    static func connect(session: WebAuthenticationSession, expectEmail: String) async throws {
        guard let clientId = FirebaseConfig.clientId, let scheme = FirebaseConfig.reversedClientId else {
            throw CloudError.denied(t("Classroom hələ qoşulmayıb (iOS client yoxdur)", "Classroom is not set up yet (no iOS client)"))
        }
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = randomString()
        let challenge = b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "login_hint", value: expectEmail), .init(name: "hd", value: "std.beu.edu.az"),
            .init(name: "prompt", value: "consent select_account")
        ]
        let back = try await session.authenticate(using: c.url!, callbackURLScheme: scheme)
        guard let code = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CloudError.denied(t("Google girişi ləğv edildi", "Google sign-in was cancelled"))
        }
        let tok = try await tokenCall([("client_id", clientId), ("code", code), ("code_verifier", verifier),
                                       ("redirect_uri", redirect), ("grant_type", "authorization_code")])
        guard let access = tok["access_token"] as? String else { throw CloudError.denied(t("Google cavab vermədi", "Google did not respond")) }
        let email = try await userEmail(access)
        if !expectEmail.isEmpty && email != expectEmail.lowercased() {
            await revoke(access)
            throw CloudError.denied(t("Yalnız universitet poçtunla (\(expectEmail)) qoşula bilərsən. Seçilən: \(email)",
                                      "Only your university e-mail (\(expectEmail)) can be used. Selected: \(email)"))
        }
        accessToken = access
        accessExpiry = Date().addingTimeInterval(Double(tok["expires_in"] as? Int ?? 3500))
        if let rt = tok["refresh_token"] as? String { Keychain.set(refreshKey, rt) }
    }

    static func disconnect() async {
        if let rt = Keychain.get(refreshKey) { await revoke(rt) }
        Keychain.set(refreshKey, nil)
        accessToken = nil
    }

    /// Çıxışda: bu nömrənin Classroom girişi silinir.
    static func clearOnLogout() {
        Keychain.set(refreshKey, nil)
        accessToken = nil
    }

    private static func tokenCall(_ pairs: [(String, String)]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = form(pairs)
        let (data, _) = try await URLSession.shared.data(for: r)
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let e = o["error"] as? String { throw CloudError.denied("Google: \(e)") }
        return o
    }

    private static func token() async throws -> String {
        if let a = accessToken, Date() < accessExpiry.addingTimeInterval(-60) { return a }
        guard let rt = Keychain.get(refreshKey), let clientId = FirebaseConfig.clientId else {
            throw CloudError.denied(t("Classroom-a qoşul", "Connect Classroom"))
        }
        let o = try await tokenCall([("client_id", clientId), ("refresh_token", rt), ("grant_type", "refresh_token")])
        guard let a = o["access_token"] as? String else { throw CloudError.denied(t("Google girişi bitib, yenidən qoşul", "Google session expired, connect again")) }
        accessToken = a
        accessExpiry = Date().addingTimeInterval(Double(o["expires_in"] as? Int ?? 3500))
        return a
    }

    private static func revoke(_ token: String) async {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = form([("token", token)])
        _ = try? await URLSession.shared.data(for: r)
    }

    // MARK: API

    private static func get(_ url: String, token: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw CloudError.network }
        var r = URLRequest(url: u)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: r) } catch { throw CloudError.network }
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { accessToken = nil; throw CloudError.denied(t("Google girişi bitib, yenidən qoşul", "Google session expired, connect again")) }
        if code >= 400 {
            let msg = (o["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(code)"
            throw CloudError.denied(msg)
        }
        return o
    }

    private static func list(_ url: String, field: String, token: String, pages: Int = 2) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var next: String? = nil
        for _ in 0..<pages {
            let sep = url.contains("?") ? "&" : "?"
            let o = try await get(url + (next.map { "\(sep)pageToken=\($0)" } ?? ""), token: token)
            out += o[field] as? [[String: Any]] ?? []
            next = o["nextPageToken"] as? String
            if next == nil { break }
        }
        return out
    }

    /// Xəta olanda boş siyahı (bir bölmə açılmasa, qalanları görünsün).
    private static func safeList(_ url: String, field: String, token: String) async -> [[String: Any]] {
        (try? await list(url, field: field, token: token, pages: 1)) ?? []
    }

    private static func userEmail(_ token: String) async throws -> String {
        let o = try await get("https://www.googleapis.com/oauth2/v3/userinfo", token: token)
        return (o["email"] as? String ?? "").trimmed.lowercased()
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func time(_ s: Any?) -> Date {
        guard let s = s as? String else { return .distantPast }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? .distantPast
    }

    private static func due(_ o: [String: Any]) -> Date? {
        guard let d = o["dueDate"] as? [String: Any], let y = d["year"] as? Int, let m = d["month"] as? Int, let day = d["day"] as? Int else { return nil }
        let t = o["dueTime"] as? [String: Any]
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day
        c.hour = t?["hours"] as? Int ?? 23; c.minute = t?["minutes"] as? Int ?? 59
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)
    }

    private static func files(_ o: [String: Any]) -> [GcFile] {
        (o["materials"] as? [[String: Any]] ?? []).compactMap { m -> GcFile? in
            if let d = (m["driveFile"] as? [String: Any])?["driveFile"] as? [String: Any] {
                return GcFile(title: d["title"] as? String ?? "Drive", url: d["alternateLink"] as? String ?? "", kind: "drive", driveId: d["id"] as? String ?? "")
            }
            if let y = m["youtubeVideo"] as? [String: Any] {
                return GcFile(title: y["title"] as? String ?? "YouTube", url: y["alternateLink"] as? String ?? "", kind: "youtube", driveId: "")
            }
            if let l = m["link"] as? [String: Any] {
                return GcFile(title: l["title"] as? String ?? (l["url"] as? String ?? "Link"), url: l["url"] as? String ?? "", kind: "link", driveId: "")
            }
            if let f = m["form"] as? [String: Any] {
                return GcFile(title: f["title"] as? String ?? "Form", url: f["formUrl"] as? String ?? "", kind: "form", driveId: "")
            }
            return nil
        }
    }

    static func courses() async throws -> [GcCourse] {
        let tok = try await token()
        return try await list("\(api)/courses?studentId=me&courseStates=ACTIVE&pageSize=50", field: "courses", token: tok).map {
            GcCourse(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", section: $0["section"] as? String ?? "",
                     link: $0["alternateLink"] as? String ?? "")
        }
    }

    /// Kursun elanları, tapşırıqları (təhvil vəziyyəti ilə) və materialları — ən yenisi əvvəl.
    static func posts(_ cid: String) async throws -> [GcPost] {
        let tok = try await token()
        async let anns = safeList("\(api)/courses/\(cid)/announcements?pageSize=30", field: "announcements", token: tok)
        async let works = safeList("\(api)/courses/\(cid)/courseWork?pageSize=40", field: "courseWork", token: tok)
        async let mats = safeList("\(api)/courses/\(cid)/courseWorkMaterials?pageSize=30", field: "courseWorkMaterial", token: tok)
        async let subs = safeList("\(api)/courses/\(cid)/courseWork/-/studentSubmissions?userId=me&pageSize=60", field: "studentSubmissions", token: tok)
        let (a, w, m, s) = await (anns, works, mats, subs)
        var state: [String: [String: Any]] = [:]
        for x in s { if let id = x["courseWorkId"] as? String { state[id] = x } }
        var out: [GcPost] = []
        for o in a {
            out.append(GcPost(id: o["id"] as? String ?? UUID().uuidString, courseId: cid, kind: "ann", title: "",
                              text: o["text"] as? String ?? "", created: time(o["creationTime"]), due: nil,
                              link: o["alternateLink"] as? String ?? "", files: files(o)))
        }
        for o in w {
            let id = o["id"] as? String ?? UUID().uuidString
            var p = GcPost(id: id, courseId: cid, kind: "work", title: o["title"] as? String ?? "",
                           text: o["description"] as? String ?? "", created: time(o["creationTime"]), due: due(o),
                           link: o["alternateLink"] as? String ?? "", files: files(o))
            if let sub = state[id] {
                p.state = sub["state"] as? String ?? ""
                p.late = sub["late"] as? Bool ?? false
                if let g = sub["assignedGrade"] as? Double { p.grade = fmt(g) + ((o["maxPoints"] as? Double).map { " / " + fmt($0) } ?? "") }
            }
            out.append(p)
        }
        for o in m {
            out.append(GcPost(id: o["id"] as? String ?? UUID().uuidString, courseId: cid, kind: "mat", title: o["title"] as? String ?? "",
                              text: o["description"] as? String ?? "", created: time(o["creationTime"]), due: nil,
                              link: o["alternateLink"] as? String ?? "", files: files(o)))
        }
        return out.sorted { $0.created > $1.created }
    }

    /// Drive faylını endirir (Google sənədləri PDF kimi) → müvəqqəti fayl.
    static func download(_ f: GcFile) async throws -> URL {
        let tok = try await token()
        let meta = try await get("https://www.googleapis.com/drive/v3/files/\(f.driveId)?fields=mimeType,name&supportsAllDrives=true", token: tok)
        let mime = meta["mimeType"] as? String ?? ""
        var name = meta["name"] as? String ?? f.title
        let url: String
        if mime.hasPrefix("application/vnd.google-apps") {
            url = "https://www.googleapis.com/drive/v3/files/\(f.driveId)/export?mimeType=application/pdf"
            if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        } else {
            url = "https://www.googleapis.com/drive/v3/files/\(f.driveId)?alt=media&supportsAllDrives=true"
        }
        var r = URLRequest(url: URL(string: url)!)
        r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: r)
        if ((resp as? HTTPURLResponse)?.statusCode ?? 0) >= 400 { throw CloudError.denied(t("Fayl açılmadı", "Could not open the file")) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_"))
        try data.write(to: dest, options: .atomic)
        return dest
    }
}

// MARK: - Ekranlar

struct ClassroomView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var connected = Classroom.isConnected
    @State private var busy = false
    @State private var error = ""
    @State private var key = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !error.isEmpty { ErrorCard(text: error) { error = "" } }
                if !connected {
                    VStack(spacing: 14) {
                        IconBox(icon: "graduationcap.circle.fill", color: C.green, size: 72)
                        Text("Google Classroom").font(.title2.weight(.bold))
                        Text(t("Kurslar, tapşırıqlar, son tarixlər və mühazirə faylları — hamısı bir yerdə. Yalnız universitet poçtunla (\(app.profile.email)) qoşula bilərsən. Tətbiq heç nə dəyişmir, yalnız oxuyur.",
                               "Courses, assignments, deadlines and lecture files in one place. Only your university e-mail (\(app.profile.email)) can be used. Read-only."))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { connect() } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) } else { Image(systemName: "person.crop.circle.badge.checkmark") }
                                Text(t("Google ilə qoşul", "Connect with Google")).font(.headline)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .glassButton(prominent: true).tint(C.green).disabled(busy || !Classroom.configured)
                        if !Classroom.configured {
                            Text(t("Hələ quraşdırılmayıb: GoogleService-Info.plist-də CLIENT_ID yoxdur.", "Not set up yet: CLIENT_ID missing in GoogleService-Info.plist."))
                                .font(.caption).foregroundStyle(C.orange)
                        }
                    }
                    .padding(22)
                    .glassCard(cornerRadius: 28, tint: C.green.opacity(0.1))
                    .appear(0)
                } else {
                    AsyncContent(key: key, load: { try await Classroom.courses() }) { courses in
                        VStack(spacing: 10) {
                            if courses.isEmpty { EmptyCard(icon: "tray", text: t("Aktiv kurs yoxdur", "No active courses")) }
                            ForEach(Array(courses.enumerated()), id: \.element.id) { i, c in
                                NavigationLink { CourseView(course: c) } label: {
                                    NavRow(icon: "book.closed.fill", color: [C.green, C.indigo, C.orange, C.purple, C.teal, C.pink][i % 6],
                                           title: c.name, subtitle: c.section)
                                }
                                .buttonStyle(PressStyle())
                                .appear(i)
                            }
                            Button(role: .destructive) {
                                Task { await Classroom.disconnect(); withAnimation { connected = false }; Usage.shared.action("classroom_disconnect") }
                            } label: {
                                Label(t("Classroom-dan ayrıl", "Disconnect Classroom"), systemImage: "link.badge.plus").frame(maxWidth: .infinity)
                            }
                            .glassButton().tint(C.rose).padding(.top, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("Classroom")
        .refreshable { key += 1 }
        .track("classroom")
    }

    private func connect() {
        busy = true; error = ""
        Haptic.tap()
        Task {
            do {
                try await Classroom.connect(session: webAuth, expectEmail: app.profile.email)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { connected = true }
                Usage.shared.action("classroom_connect")
                Haptic.success()
            } catch {
                self.error = error.localizedDescription
                Haptic.error()
            }
            busy = false
        }
    }
}

private struct CourseView: View {
    let course: GcCourse
    @State private var filter = "all"
    @State private var key = 0
    @State private var preview: URL?
    @State private var opening: UUID?
    @State private var error = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $filter) {
                    Text(t("Hamısı", "All")).tag("all")
                    Text(t("Tapşırıq", "Work")).tag("work")
                    Text(t("Elan", "Posts")).tag("ann")
                    Text(t("Material", "Materials")).tag("mat")
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { _, _ in Haptic.select() }
                if !error.isEmpty { ErrorCard(text: error) { error = "" } }
                AsyncContent(key: key, load: { try await Classroom.posts(course.id) }) { posts in
                    let list = posts.filter { filter == "all" || $0.kind == filter }
                    VStack(spacing: 10) {
                        if list.isEmpty { EmptyCard(icon: "tray", text: t("Burada heç nə yoxdur", "Nothing here")) }
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                            PostCard(post: p, opening: opening) { f in open(f) }
                                .appear(min(i, 10))
                                .scrollFx()
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.86), value: filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { key += 1 }
        .quickLookPreview($preview)
        .toolbar {
            if let u = URL(string: course.link), !course.link.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Link(destination: u) { Image(systemName: "safari") } }
            }
        }
        .track("classroom_course")
    }

    private func open(_ f: GcFile) {
        Usage.shared.action("classroom_file", f.kind)
        if f.kind != "drive" || f.driveId.isEmpty {
            if let u = URL(string: f.url) { openURL(u) }
            return
        }
        guard opening == nil else { return }
        opening = f.id
        Haptic.tap()
        Task {
            defer { opening = nil }
            do { preview = try await Classroom.download(f) } catch {
                if let u = URL(string: f.url) { openURL(u) } else { self.error = error.localizedDescription }
            }
        }
    }
}

private struct PostCard: View {
    let post: GcPost
    let opening: UUID?
    let open: (GcFile) -> Void

    private var icon: (String, Color) {
        switch post.kind {
        case "work": return ("pencil.and.list.clipboard", C.orange)
        case "mat": return ("doc.text.fill", C.indigo)
        default: return ("megaphone.fill", C.green)
        }
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconBox(icon: icon.0, color: icon.1, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.headline).font(.subheadline.weight(.semibold)).lineLimit(3)
                    Text(PostCard.df.string(from: post.created)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if post.kind == "work" { status }
            }
            if !post.text.isEmpty && !post.title.isEmpty {
                Text(post.text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            } else if post.title.isEmpty && post.text.count > 90 {
                Text(post.text).font(.caption).foregroundStyle(.secondary).lineLimit(5)
            }
            if let due = post.due {
                Label(t("Son tarix: ", "Due: ") + PostCard.df.string(from: due), systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!post.done && due < Date() ? C.rose : C.orange)
            }
            if !post.files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.files) { f in
                            Button { open(f) } label: {
                                HStack(spacing: 6) {
                                    if opening == f.id { ProgressView().controlSize(.small) }
                                    else { Image(systemName: f.kind == "youtube" ? "play.rectangle.fill" : f.kind == "link" ? "link" : f.kind == "form" ? "list.bullet.clipboard" : "doc.fill") }
                                    Text(f.title).lineLimit(1)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassCapsule(interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var status: some View {
        if post.done {
            Text(post.grade.isEmpty ? t("Təhvil verilib", "Turned in") : post.grade)
                .font(.caption2.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(C.green))
        } else if post.late || (post.due.map { $0 < Date() } ?? false) {
            Text(t("Gecikib", "Late")).font(.caption2.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(C.rose))
        } else {
            Text(t("Gözləyir", "To do")).font(.caption2.weight(.bold)).foregroundStyle(C.orange)
                .padding(.horizontal, 8).padding(.vertical, 4).glassCapsule()
        }
    }
}

// MARK: - Qrup yoldaşları

struct MatesView: View {
    @EnvironmentObject private var app: AppState
    @State private var visible = UserDefaults.standard.bool(forKey: "mates_visible")
    @State private var mates: [Mate] = []
    @State private var loading = false
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { visible }, set: { setVisible($0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Mən də görünüm", "Make me visible")).font(.subheadline.weight(.semibold))
                        Text(t("Potokundakı yoldaşlar səni görür, sən də onları. İstədiyin vaxt söndürə bilərsən — qeydin silinir.",
                               "Classmates in your stream see you and you see them. Turn off any time — your entry is deleted."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(C.green)
                .disabled(busy || !FirebaseConfig.enabled)
                .padding(16)
                .glassCard(cornerRadius: 22)
                .appear(0)

                if !FirebaseConfig.enabled {
                    EmptyCard(icon: "icloud.slash", text: CloudError.notConfigured.localizedDescription)
                }
                if !error.isEmpty { ErrorCard(text: error) { Task { await load() } } }
                if visible {
                    let online = mates.filter(\.online).count
                    HStack {
                        Text(t("\(mates.count) nəfər", "\(mates.count) people")).font(.headline)
                        Spacer()
                        HStack(spacing: 5) { Circle().fill(C.green).frame(width: 8, height: 8); Text(t("\(online) onlayn", "\(online) online")) }
                            .font(.caption.weight(.semibold)).foregroundStyle(C.green)
                    }
                    .padding(.horizontal, 4)
                    if loading && mates.isEmpty { LoadingStack(count: 4, height: 70) }
                    if !loading && mates.isEmpty && error.isEmpty {
                        EmptyCard(icon: "person.2.slash", text: t("Hələ potokundan görünən yoldaş yoxdur", "No visible classmates yet"))
                    }
                    ForEach(Array(mates.enumerated()), id: \.element.id) { i, m in
                        MateRow(mate: m).appear(min(i, 12)).scrollFx()
                    }
                } else if FirebaseConfig.enabled {
                    EmptyCard(icon: "eye.slash", text: t("Yoldaşlarını görmək üçün özün də görünən ol", "Become visible to see your classmates"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: visible)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: mates.count)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Qrup yoldaşları", "Classmates"))
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                if visible { await load() }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .track("mates")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            mates = try await Cloud.shared.mates()
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setVisible(_ on: Bool) {
        busy = true
        Haptic.select()
        Task {
            do {
                try await Cloud.shared.publish(on, photo: Prefs.shared.customPhoto.flatMap { UIImage(data: $0) } ?? app.photo)
                UserDefaults.standard.set(on, forKey: "mates_visible")
                visible = on
                if on { await load() } else { mates = [] }
                Usage.shared.action(on ? "mates_on" : "mates_off")
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

private struct MateRow: View {
    let mate: Mate

    private var seen: String {
        if mate.online { return t("onlayn", "online") }
        guard let d = mate.lastSeen else { return "" }
        let m = Int(Date().timeIntervalSince(d) / 60)
        return t("\(durationText(max(m, 1))) əvvəl", "\(durationText(max(m, 1))) ago")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let d = mate.photo, let img = UIImage(data: d) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Text(String(mate.name.prefix(1))).font(.headline.weight(.bold)).foregroundStyle(C.onLime)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(C.lime)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                Circle().fill(mate.online ? C.green : Color.gray.opacity(0.5))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(mate.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(mate.group) · \(seen)").font(.caption).foregroundStyle(mate.online ? C.green : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(cornerRadius: 20)
    }
}
