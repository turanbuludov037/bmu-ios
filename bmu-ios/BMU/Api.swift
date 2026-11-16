import Foundation

/// Portalın 2-ci mərhələ bölmələri (Android Data.kt-dəki Transcript, Tuition, Library, Turnstile, UniDocs, Settings, OnlServ).
enum Api {
    private static var portal: Portal { Portal.shared }

    private static func fail(_ az: String, _ en: String) -> PortalError { .message(t(az, en)) }

    // MARK: təhsil

    static func transcript() async throws -> Transcript {
        let html = try await portal.fetch("index.php?mod=transkript")
        guard let r = await offMain({ Parsers.transcript(html) }) else { throw fail("Transkript oxunmadı", "Transcript could not be loaded") }
        return r
    }

    static func curriculum() async throws -> Curriculum {
        let html = try await portal.fetch("index.php?mod=course_struct")
        guard let r = await offMain({ Parsers.curriculum(html) }) else { throw fail("Tədris planı oxunmadı", "Curriculum could not be loaded") }
        return r
    }

    static func registration() async throws -> Registration {
        let html = try await portal.fetch("index.php?mod=course_reg")
        guard let r = await offMain({ Parsers.registration(html) }) else { throw fail("Qeydiyyat məlumatı oxunmadı", "Registration could not be loaded") }
        return r
    }

    // MARK: xidmətlər

    static func tuition() async throws -> (title: String, rows: [TuitionRow]) {
        let html = try await portal.fetch("index.php?mod=stud_th")
        guard let r = await offMain({ Parsers.tuition(html) }) else { throw fail("Təhsil haqqı cədvəli oxunmadı", "Tuition table could not be loaded") }
        return r
    }

    private static let gateDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static func turnstile(from: Date, to: Date) async throws -> (gates: [Gate], total: String) {
        let url = "index.php?mod=card&ajx=1&action=ShowResult&date1=\(gateDate.string(from: from))&date2=\(gateDate.string(from: to))"
        let body = try await portal.ajax(url, referer: "index.php?mod=card")
        guard let r = await offMain({ Parsers.extractAjaxData(body).flatMap { Parsers.turnstile($0) } ?? Parsers.turnstile(body) }) else {
            throw fail("Qeydlər oxunmadı", "Records could not be loaded")
        }
        return r
    }

    static func docCategories(parent: String) async throws -> [DocCat] {
        let html = try await portal.post("index.php?mod=uni_docs", [("action", "GetDocCategories"), ("parent_id", parent), ("ajx", "1")],
                                         referer: "index.php?mod=uni_docs")
        guard let r = await offMain({ Parsers.docCategories(html, parent: parent) ?? Parsers.extractAjaxData(html).flatMap { Parsers.docCategories($0, parent: parent) } }) else {
            throw fail("Kateqoriyalar oxunmadı", "Categories could not be loaded")
        }
        return r
    }

    static func docs(cat: String, parent: String) async throws -> (headers: [String], items: [DocItem]) {
        let html = try await portal.post("index.php?mod=uni_docs", [("action", "GetDocsByCat"), ("cat_id", cat), ("parent_id", parent), ("ajx", "1")],
                                         referer: "index.php?mod=uni_docs")
        guard let r = await offMain({ Parsers.docList(html) }) else { throw fail("Sənəd siyahısı oxunmadı", "Document list could not be loaded") }
        return r
    }

    static func onlineOrders() async throws -> [OnlOrder] {
        let html = try await portal.fetch("index.php?mod=onlserv&tab=sifaris")
        guard let r = await offMain({ Parsers.onlineOrders(html) ?? Parsers.extractAjaxData(html).flatMap { Parsers.onlineOrders($0) } }) else {
            throw fail("Sifarişlər oxunmadı", "Orders could not be loaded")
        }
        return r
    }

    // MARK: kitabxana

    /// "?mod=lib&..." → "index.php?mod=lib&..."
    static func libPath(_ href: String) -> String {
        if href.hasPrefix("?") { return "index.php" + href }
        return href.hasPrefix("/") ? String(href.dropFirst()) : href
    }

    private static func query(_ fields: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
        return fields.filter { !$0.1.trimmed.isEmpty }
            .map { "\($0.0)=\($0.1.trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
    }

    /// type: 1 kitab, 2 jurnal, 3 elektron material. Ətraflı axtarış (mode=3) yalnız kitab üçün.
    static func libSearch(type: Int, fields: [(String, String)], advanced: Bool) async throws -> (items: [LibBook], total: Int) {
        let url = "index.php?mod=lib&type=\(type)" + (advanced ? "&mode=3&search=+Axtar+" : "") + "&" + query(fields)
        let html = try await portal.fetch(url)
        guard let r = await offMain({ Parsers.books(html) }) else { throw fail("Cavab oxunmadı", "Could not read the response") }
        return r
    }

    static func libDetail(_ href: String) async throws -> LibDetail {
        let html = try await portal.fetch(libPath(href))
        guard let r = await offMain({ Parsers.libDetail(html) }) else { throw fail("Material məlumatı oxunmadı", "Item details could not be loaded") }
        return r
    }

    static func libOrder(_ href: String, form: [String: String]) async throws {
        let path = libPath(href)
        _ = try await portal.post(path, form.map { ($0.key, $0.value) }, referer: path)
    }

    /// type: 4 = Sifarişlərim, 5 = Növbəyə durma, 6 = İstifadəçi kartım
    static func libRows(type: Int, showAll: Bool = false) async throws -> LibRows {
        let path = "index.php?mod=lib&type=\(type)"
        let html: String
        if type == 6 && showAll {
            html = try await portal.post(path, [("chckHamsi", "Hamısını göstər")], referer: path)
        } else {
            html = try await portal.fetch(path)
        }
        guard let r = await offMain({ Parsers.libRows(html) }) else { throw fail("Siyahı oxunmadı", "List could not be loaded") }
        return r
    }

    // MARK: hesab

    /// Portalın qaydası: ən azı 8 simvol, ən azı 1 rəqəm, yalnız hərf/rəqəm və !@#$%^&*
    static func passwordValid(_ p: String) -> Bool {
        p.range(of: #"^(?=.*[0-9])[a-zA-Z0-9!@#$%^&*]{8,}$"#, options: .regularExpression) != nil
    }

    /// Parolu dəyişir və yeni parolla girişi yoxlayır. "Məni xatırla" açıqdırsa saxlanmış parol da yenilənir.
    static func changePassword(number: String, old: String, new: String) async throws -> String {
        let msg = try await portal.call("settings", "UpdatePassword", [("oldPassw", old), ("newPassw", new), ("newPasswAgain", new)])
        do {
            _ = try await portal.login(number, new)
        } catch {
            _ = try? await portal.login(number, old)          // yoxlama girişi sessiyanı sıfırlayır → köhnə parolla bərpa
            throw fail("Parol dəyişdirilmədi: " + String(Parsers.plain(msg).prefix(150)), "Password was not changed: " + String(Parsers.plain(msg).prefix(150)))
        }
        if Keychain.load() != nil { Keychain.save(number, new) }
        let text = Parsers.plain(msg)
        return text.isEmpty ? t("Parol dəyişdirildi", "Password changed") : text
    }

    static func englishName() async throws -> (name: String, surname: String, father: String) {
        let html = try await portal.call("settings", "StudNameInfo")
        guard let r = await offMain({ Parsers.englishName(html) }) else { throw fail("Məlumat oxunmadı", "Could not read the data") }
        return r
    }

    static func saveEnglishName(name: String, surname: String, father: String) async throws -> String {
        let html = try await portal.call("settings", "SaveStudNameInfo", [("name_en", name), ("sname_en", surname), ("fname_en", father), ("type", "save")])
        let text = Parsers.plain(html)
        return text.isEmpty ? t("Yadda saxlanıldı", "Saved") : text
    }

    static func file(_ path: String) async throws -> PortalFile {
        try await portal.fetchFile(path)
    }
}
