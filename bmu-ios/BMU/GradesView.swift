import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var app: AppState
    @State private var open: GradeRow?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !app.gradeSems.isEmpty {
                        SemesterMenu(semesters: app.gradeSems, selected: app.gradeSel) { v in
                            Task { await app.loadGrades(v) }
                        }
                    }
                    if app.gradesLoading && app.grades.isEmpty { LoadingCard(text: "Qiymətlər yüklənir…") }
                    if !app.gradesError.isEmpty {
                        ErrorCard(text: app.gradesError) { Task { await app.loadGrades(app.gradeSel.isEmpty ? nil : app.gradeSel) } }
                    }
                    if !app.grades.isEmpty {
                        GradesSummary(rows: app.grades)
                        Text("Fənnə toxun — bütün balları və imtahandan nə qədər lazım olduğunu gör.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    } else if !app.gradesLoading && app.gradesError.isEmpty && !app.gradeSems.isEmpty {
                        EmptyCard(icon: "tray", text: "Bu semestrdə qiymət yoxdur")
                    }
                    ForEach(app.grades) { r in
                        Button { open = r } label: { GradeCard(row: r) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Qiymətlər")
            .task { if app.grades.isEmpty && !app.gradesLoading { await app.loadGrades() } }
            .refreshable { await app.loadGrades(app.gradeSel.isEmpty ? nil : app.gradeSel) }
            .sheet(item: $open) { r in
                GradeDetail(row: r)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
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
            item("\(rows.count)", "Fənn")
            Divider().frame(height: 34)
            item("\(akts)", "AKTS")
            Divider().frame(height: 34)
            item("\(passed)/\(rows.count)", "Girişi 34+")
        }
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 22, tint: C.indigo.opacity(0.12))
    }

    private func item(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
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
                    Text(row.title).font(.headline).multilineTextAlignment(.leading).lineLimit(2)
                    Text("\(row.code) · \(row.akts) AKTS").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let exam { LetterBadge(letter: GradeCalc.letter(entry: entry, exam: exam)) }
            }
            ScoreBar(value: entry, max: Double(GradeRules.entryMax), mark: Double(GradeRules.entryMin),
                     color: ok ? C.green : C.indigo)
            HStack {
                Text("Giriş: \(fmt(entry)) / \(GradeRules.entryMax)").font(.caption.weight(.semibold))
                Spacer()
                if let exam {
                    Text("İmtahan: \(fmt(exam)) / \(GradeRules.examMax)").font(.caption).foregroundStyle(.secondary)
                } else if ok {
                    Text("İmtahana buraxılırsan").font(.caption.weight(.medium)).foregroundStyle(C.green)
                } else {
                    Text("34-ə \(fmt(Double(GradeRules.entryMin) - entry)) bal qalıb").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !row.missed.isEmpty && row.missed != "0" {
                Label("Qaib: \(row.missed)", systemImage: "person.fill.xmark")
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Giriş balı").font(.headline)
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
                            Text("Cəmi").font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(fmt(entry)) / \(GradeRules.entryMax)").font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        let open = GradeCalc.entryOpen(row)
                        if open > 0 {
                            Text("Hələ yazılmayan hissələrdən \(open) bal yığa bilərsən.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("İmtahan").font(.headline)
                        InfoRow(label: "Semestr sonu (SSİ)", value: row.score("SSI"))
                        InfoRow(label: "Əlavə imtahan (Əİ)", value: row.score("ƏI"))
                        InfoRow(label: "Təkrar imtahan (Tİ)", value: row.score("TI"))
                        InfoRow(label: "Ortalama", value: row.score("ORT"))
                        if let exam {
                            Divider()
                            HStack {
                                Text("Yekun: \(fmt(entry + exam)) bal").font(.subheadline.weight(.bold))
                                Spacer()
                                LetterBadge(letter: GradeCalc.letter(entry: entry, exam: exam))
                            }
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22)

                    if exam == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("İmtahandan nə qədər lazımdır?").font(.headline)
                            if entry < Double(GradeRules.entryMin) {
                                Text("İmtahana buraxılmaq üçün giriş balı ən azı \(GradeRules.entryMin) olmalıdır. Hələ \(fmt(Double(GradeRules.entryMin) - entry)) bal lazımdır.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(GradeRules.letters, id: \.0) { item in
                                    HStack {
                                        LetterBadge(letter: item.0).scaleEffect(0.75).frame(width: 34, height: 34)
                                        Text("\(item.1)+ bal").font(.subheadline)
                                        Spacer()
                                        if let need = GradeCalc.neededExam(entry: entry, target: item.1) {
                                            Text("imtahandan \(need)").font(.subheadline.weight(.semibold))
                                        } else {
                                            Text("mümkün deyil").font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Text("İmtahandan ən azı \(GradeRules.examMin) bal lazımdır.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 22)
                    }
                }
                .padding(16)
            }
            .navigationTitle(row.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bağla") { dismiss() }
                }
            }
        }
    }
}
