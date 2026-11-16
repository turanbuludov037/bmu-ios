import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var app: AppState
    @State private var open: GradeRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !app.gradeSems.isEmpty {
                    SemesterMenu(semesters: app.gradeSems, selected: app.gradeSel) { v in
                        Task { await app.loadGrades(v) }
                    }
                    .appear(0)
                }
                if app.gradesLoading && app.grades.isEmpty { LoadingStack(count: 4, height: 120) }
                if !app.gradesError.isEmpty {
                    ErrorCard(text: app.gradesError) { Task { await app.loadGrades(app.gradeSel.isEmpty ? nil : app.gradeSel) } }
                }
                if !app.grades.isEmpty {
                    GradesSummary(rows: app.grades).appear(1)
                    Label(t("Fənnə toxun — bütün ballar və imtahandan nə qədər lazım olduğu", "Tap a course — all scores and what you need on the exam"),
                          systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                } else if !app.gradesLoading && app.gradesError.isEmpty && !app.gradeSems.isEmpty {
                    EmptyCard(icon: "tray", text: t("Bu semestrdə qiymət yoxdur", "No grades this semester"))
                }
                ForEach(Array(app.grades.enumerated()), id: \.element.id) { i, r in
                    Button { Haptic.tap(); open = r } label: { GradeCard(row: r) }
                        .buttonStyle(PressStyle())
                        .appear(i + 2)
                        .scrollFx()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Qiymətlər", "Grades"))
        .track("grades")
        .task { if app.grades.isEmpty && !app.gradesLoading { await app.loadGrades() } }
        .refreshable { Haptic.soft(); await refreshWork { await app.loadGrades(app.gradeSel.isEmpty ? nil : app.gradeSel) } }
        .sheet(item: $open) { r in
            GradeDetail(row: r)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Semestr xülasəsi: fənn sayı, AKTS, imtahana buraxılan fənnlər.
private struct GradesSummary: View {
    let rows: [GradeRow]

    var body: some View {
        let akts = rows.reduce(0) { $0 + $1.akts }
        let passed = rows.filter { GradeCalc.entryNow($0) >= Double(GradeRules.entryMin) }.count
        HStack(spacing: 0) {
            item("\(rows.count)", t("Fənn", "Courses"))
            Divider().frame(height: 34)
            item("\(akts)", "AKTS")
            Divider().frame(height: 34)
            item("\(passed)/\(rows.count)", t("Girişi 34+", "Entry 34+"))
        }
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 22, tint: C.indigo.opacity(0.12))
    }

    private func item(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GradeCard: View {
    let row: GradeRow

    var body: some View {
        let entry = GradeCalc.entryNow(row)
        let exam = GradeCalc.exam(row)
        let ok = entry >= Double(GradeRules.entryMin)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.headline).multilineTextAlignment(.leading).lineLimit(2).foregroundStyle(Color.primary)
                    Text("\(row.code) · \(row.akts) AKTS").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let exam { LetterBadge(letter: GradeCalc.letter(entry: entry, exam: exam)) }
            }
            ScoreBar(value: entry, max: Double(GradeRules.entryMax), mark: Double(GradeRules.entryMin), color: ok ? C.green : C.indigo)
            HStack {
                Text(t("Giriş: \(fmt(entry)) / \(GradeRules.entryMax)", "Entry: \(fmt(entry)) / \(GradeRules.entryMax)"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.primary)
                Spacer()
                if let exam {
                    Text(t("İmtahan: \(fmt(exam)) / \(GradeRules.examMax)", "Exam: \(fmt(exam)) / \(GradeRules.examMax)")).font(.caption).foregroundStyle(.secondary)
                } else if ok {
                    Text(t("İmtahana buraxılırsan", "Eligible for the exam")).font(.caption.weight(.medium)).foregroundStyle(C.green)
                } else {
                    Text(t("34-ə \(fmt(Double(GradeRules.entryMin) - entry)) bal qalıb", "\(fmt(Double(GradeRules.entryMin) - entry)) points to 34"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !row.missed.isEmpty && row.missed != "0" {
                Label(t("Qaib: \(row.missed)", "Absences: \(row.missed)"), systemImage: "person.fill.xmark")
                    .font(.caption.weight(.medium)).foregroundStyle(C.rose)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
    }
}

/// Fənnin bütün balları + "imtahandan nə qədər lazımdır".
struct GradeDetail: View {
    let row: GradeRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let parts = GradeCalc.parts(row)
        let entry = GradeCalc.entryNow(row)
        let exam = GradeCalc.exam(row)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GlassSection(title: t("Giriş balı", "Entry score"), icon: "sum") {
                        ForEach(parts) { p in
                            HStack {
                                Text(p.key).font(.subheadline.weight(.medium)).frame(width: 52, alignment: .leading)
                                ScoreBar(value: p.value ?? 0, max: Double(p.max), color: p.value == nil ? .gray : C.indigo)
                                Text(p.value.map { "\(fmt($0))/\(p.max)" } ?? "—/\(p.max)")
                                    .font(.subheadline.monospacedDigit()).frame(width: 64, alignment: .trailing)
                            }
                        }
                        Divider()
                        HStack {
                            Text(t("Cəmi", "Total")).font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(fmt(entry)) / \(GradeRules.entryMax)").font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        let open = GradeCalc.entryOpen(row)
                        if open > 0 {
                            Text(t("Hələ yazılmayan hissələrdən \(open) bal yığa bilərsən.", "You can still earn \(open) points from parts not yet graded."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .appear(0)

                    GlassSection(title: t("İmtahan", "Exam"), icon: "pencil.and.list.clipboard") {
                        InfoRow(label: t("Semestr sonu (SSİ)", "Final exam (SSI)"), value: row.score("SSI"))
                        InfoRow(label: t("Əlavə imtahan (Əİ)", "Additional exam"), value: row.score("ƏI"))
                        InfoRow(label: t("Təkrar imtahan (Tİ)", "Retake"), value: row.score("TI"))
                        InfoRow(label: t("Ortalama", "Average"), value: row.score("ORT"))
                        if let exam {
                            Divider()
                            HStack {
                                Text(t("Yekun: \(fmt(entry + exam)) bal", "Total: \(fmt(entry + exam)) points")).font(.subheadline.weight(.bold))
                                Spacer()
                                LetterBadge(letter: GradeCalc.letter(entry: entry, exam: exam))
                            }
                        }
                    }
                    .appear(1)

                    if exam == nil {
                        GlassSection(title: t("İmtahandan nə qədər lazımdır?", "What do you need on the exam?"), icon: "target") {
                            if entry < Double(GradeRules.entryMin) {
                                Text(t("İmtahana buraxılmaq üçün giriş balı ən azı \(GradeRules.entryMin) olmalıdır. Hələ \(fmt(Double(GradeRules.entryMin) - entry)) bal lazımdır.",
                                       "You need at least \(GradeRules.entryMin) entry points to sit the exam. \(fmt(Double(GradeRules.entryMin) - entry)) more needed."))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(GradeRules.letters, id: \.0) { item in
                                    HStack {
                                        LetterBadge(letter: item.0).scaleEffect(0.75).frame(width: 34, height: 34)
                                        Text(t("\(item.1)+ bal", "\(item.1)+ points")).font(.subheadline)
                                        Spacer()
                                        if let need = GradeCalc.neededExam(entry: entry, target: item.1) {
                                            Text(t("imtahandan \(need)", "exam \(need)")).font(.subheadline.weight(.semibold))
                                        } else {
                                            Text(t("mümkün deyil", "not possible")).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Text(t("İmtahandan ən azı \(GradeRules.examMin) bal lazımdır.", "At least \(GradeRules.examMin) points are required on the exam."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .appear(2)
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle(row.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Bağla", "Close")) { dismiss() }
                }
            }
        }
    }
}
