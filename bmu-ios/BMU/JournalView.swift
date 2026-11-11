import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !app.journalSems.isEmpty {
                        SemesterMenu(semesters: app.journalSems, selected: app.journalSel) { v in
                            Task { await app.loadJournal(v) }
                        }
                    }
                    if app.journalLoading && app.journal.isEmpty { LoadingCard(text: "Jurnal yüklənir…") }
                    if !app.journalError.isEmpty {
                        ErrorCard(text: app.journalError) { Task { await app.loadJournal(nil, force: true) } }
                    }
                    if !app.journal.isEmpty {
                        let risky = app.journal.filter { $0.percent >= ABSENCE_LIMIT_PERCENT * 0.8 }
                        if !risky.isEmpty {
                            Label("\(risky.count) fəndə qaib limitə yaxındır (\(Int(ABSENCE_LIMIT_PERCENT))%)", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(C.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .glassCard(cornerRadius: 20, tint: C.orange.opacity(0.15))
                        }
                    }
                    ForEach(app.journal) { JournalCard(course: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Jurnal")
            .task { if app.journal.isEmpty && !app.journalLoading { await app.loadJournal() } }
            .refreshable { await app.loadJournal(app.journalSel.isEmpty ? nil : app.journalSel, force: true) }
        }
    }
}

private struct JournalCard: View {
    let course: JournalCourse

    private var color: Color {
        if course.percent >= ABSENCE_LIMIT_PERCENT { return C.rose }
        if course.percent >= ABSENCE_LIMIT_PERCENT * 0.6 { return C.orange }
        return C.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.title).font(.headline).lineLimit(2)
                    Text(course.teacher.isEmpty ? course.code : "\(course.code) · \(course.teacher)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(fmt(course.percent))%")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(color)
            }
            ScoreBar(value: course.percent, max: ABSENCE_LIMIT_PERCENT * 1.2, mark: ABSENCE_LIMIT_PERCENT, color: color)
            VStack(spacing: 8) {
                ForEach(course.rows) { r in
                    HStack(spacing: 8) {
                        Text(r.label).font(.subheadline.weight(.medium))
                        Spacer()
                        Label("\(r.attended)", systemImage: "checkmark.circle.fill")
                            .font(.caption.monospacedDigit()).foregroundStyle(C.green)
                        Label("\(r.missed)", systemImage: "xmark.circle.fill")
                            .font(.caption.monospacedDigit()).foregroundStyle(r.missed > 0 ? C.rose : .secondary)
                        if r.limit > 0 {
                            Text("limit \(fmt(r.limit))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
    }
}
