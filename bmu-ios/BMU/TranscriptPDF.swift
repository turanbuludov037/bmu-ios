import UIKit

/// Transkript çıxarışı: tətbiqin rəngləri ilə A4 PDF (paylaşmaq, çap etmək, fayla saxlamaq üçün).
/// Portaldan gələn bütün mətnlər HTML kimi deyil, mətn kimi yazılır (escape).
@MainActor
enum TranscriptPDF {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ tr: Transcript, profile: Profile) -> String {
        var h = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica; color: #1B2850; font-size: 10pt; }
        h1 { font-size: 18pt; margin: 0 0 2pt 0; }
        .sub { color: #5a6488; margin-bottom: 10pt; }
        .gpa { display: inline-block; background: #4558B8; color: white; border-radius: 8pt; padding: 6pt 10pt; font-weight: bold; margin-right: 6pt; }
        .info { width: 100%; border-collapse: collapse; margin: 8pt 0 12pt 0; }
        .info td { padding: 2pt 4pt; border-bottom: 0.5pt solid #dde1f2; }
        .info td:first-child { color: #5a6488; width: 40%; }
        h2 { font-size: 11.5pt; color: #4558B8; margin: 14pt 0 4pt 0; }
        table.c { width: 100%; border-collapse: collapse; }
        table.c th { text-align: left; background: #EEF1FF; padding: 3pt 4pt; font-size: 9pt; }
        table.c td { padding: 3pt 4pt; border-bottom: 0.5pt solid #e6e9f5; }
        .num { text-align: right; white-space: nowrap; }
        .sum { color: #5a6488; font-size: 9pt; margin-top: 3pt; }
        .foot { margin-top: 16pt; color: #8a92b2; font-size: 8pt; }
        </style></head><body>
        """
        h += "<h1>\(esc(t("Transkript", "Transcript")))</h1>"
        h += "<div class=\"sub\">\(esc(profile.fullName)) · \(esc(profile.number))\(profile.group.isEmpty ? "" : " · " + esc(profile.group))</div>"
        h += "<span class=\"gpa\">\(esc(t("ÜOMG", "GPA"))): \(esc(tr.uomg.isEmpty ? "—" : tr.uomg))</span>"
        if !tr.credits.isEmpty { h += "<span class=\"gpa\" style=\"background:#2E8B57\">\(esc(tr.credits)) \(esc(t("AKTS", "ECTS")))</span>" }
        if !tr.header.isEmpty {
            h += "<table class=\"info\">"
            for kv in tr.header { h += "<tr><td>\(esc(kv.key))</td><td>\(esc(kv.value))</td></tr>" }
            h += "</table>"
        }
        for s in tr.sems {
            h += "<h2>\(esc(s.label))</h2><table class=\"c\"><tr><th>\(esc(t("Kod", "Code")))</th><th>\(esc(t("Fənn", "Course")))</th>"
            h += "<th class=\"num\">\(esc(t("AKTS", "ECTS")))</th><th class=\"num\">\(esc(t("Bal", "Score")))</th><th class=\"num\">\(esc(t("Hərf", "Letter")))</th></tr>"
            for r in s.rows {
                h += "<tr><td>\(esc(r.code))</td><td>\(esc(r.title))\(r.repeatMark.isEmpty ? "" : " <i>(\(esc(r.repeatMark)))</i>")</td>"
                h += "<td class=\"num\">\(r.credit)</td><td class=\"num\">\(esc(r.score))</td><td class=\"num\"><b>\(esc(r.letter))</b></td></tr>"
            }
            h += "</table><div class=\"sum\">S-ÜOMG: \(esc(s.sUomg.isEmpty ? "—" : s.sUomg)) · ÜOMG: \(esc(s.uomg.isEmpty ? "—" : s.uomg)) · SQK: \(esc(s.sqk)) · TQK: \(esc(s.tqk))</div>"
        }
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        h += "<div class=\"foot\">\(esc(t("myBEU tətbiqi ilə hazırlanıb", "Generated with the myBEU app"))) · \(f.string(from: Date())) · \(esc(t("Rəsmi sənəd deyil", "Not an official document")))</div>"
        h += "</body></html>"
        return h
    }

    /// PDF faylı (müvəqqəti qovluqda) — paylaşma vərəqi üçün.
    static func file(_ tr: Transcript, profile: Profile) -> URL? {
        let fmt = UIMarkupTextPrintFormatter(markupText: html(tr, profile: profile))
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(fmt, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)          // A4
        let printable = page.insetBy(dx: 36, dy: 40)
        r.setValue(NSValue(cgRect: page), forKey: "paperRect")
        r.setValue(NSValue(cgRect: printable), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<max(r.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let name = (profile.number.isEmpty ? "transkript" : "transkript_\(profile.number)") + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try (data as Data).write(to: url, options: .atomic); return url } catch { return nil }
    }
}
