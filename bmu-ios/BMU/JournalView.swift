import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var app: AppState
    @State private var open: JournalCourse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !app.journalSems.isEmpty {
                    SemesterMenu(semesters: app.journalSems, selected: app.journalSel) { v in
                        Task { await app.loadJournal(v) }
                    }
                    .appear(0)
                }
                AbsenceRulesCard().appear(1)
                if app.journalLoading && app.journal.isEmpty { LoadingStack(count: 4, height: 130) }
                if !app.journalError.isEmpty {
                    ErrorCard(text: app.journalError) { Task { await app.loadJournal(nil, force: true) } }
                }
                let risky = app.journal.filter { (AbsenceBudget.left($0) ?? 99) <= 2 }
                if !risky.isEmpty {
                    Label(t("\(risky.count) fəndə qaib limitə çox yaxındır və ya keçib", "\(risky.count) course(s) at or near the absence limit"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(C.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(cornerRadius: 20, tint: C.orange.opacity(0.15))
                        .appear(2)
                }
                ForEach(Array(app.journal.enumerated()), id: \.element.id) { i, c in
                    Button { Haptic.tap(); open = c } label: { JournalCard(course: c) }
                        .buttonStyle(PressStyle())
                        .appear(i + 3)
                        .scrollFx()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Jurnal", "Journal"))
        .track("journal")
        .task { if app.journal.isEmpty && !app.journalLoading { await app.loadJournal() } }
        .refreshable { Haptic.soft(); await refreshWork { await app.loadJournal(app.journalSel.isEmpty ? nil : app.journalSel, force: true) } }
        .sheet(item: $open) { c in
            JournalDetail(course: c)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// "Qaib necə hesablanır?" — açılıb-bağlanan izah.
struct AbsenceRulesCard: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptic.tap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack {
                    Label(t("Qaib necə hesablanır?", "How are absences counted?"), systemImage: "questionmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(C.indigo)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    rule("clock", t("1 qaib = 40 dəqiqəlik 1 dərs saatı. Bütöv dərs (80 dəq) = 2 qaib.",
                                    "1 absence = one 40-minute class hour. A full class (80 min) = 2 absences."))
                    rule("percent", t("Fənn üzrə faiz = bütün qaiblər ÷ bütün saatlar × 100 (yuxarı yuvarlaqlaşdırılır).",
                                      "Course % = all absences ÷ all hours × 100 (rounded up)."))
                    rule("exclamationmark.shield", t("Limit fənnin saatlarının 25%-idir (mühazirə + məşğələ + lab limitlərinin cəmi).",
                                                     "The limit is 25% of the course hours (lecture + practice + lab limits combined)."))
                    rule("checkmark.circle", t("Limitə bərabər olmaq olar. Limiti keçəndə fəndən kəsilirsən.",
                                               "Being exactly at the limit is allowed. Going over it fails the course."))
                    rule("hand.tap", t("Fənnə toxun — daha neçə dərs buraxa biləcəyini gör.", "Tap a course to see how many classes you can still miss."))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(C.indigo).frame(width: 20)
            Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func absenceColor(_ c: JournalCourse) -> Color {
    let left = AbsenceBudget.left(c) ?? 99
    if left < 0 || c.percent > ABSENCE_LIMIT_PERCENT { return C.rose }
    if left <= 2 || c.percent >= ABSENCE_LIMIT_PERCENT * 0.6 { return C.orange }
    return C.green
}

private struct JournalCard: View {
    let course: JournalCourse

    var body: some View {
        let color = absenceColor(course)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.title).font(.headline).lineLimit(2).foregroundStyle(Color.primary)
                    Text(course.teacher.isEmpty ? course.code : "\(course.code) · \(course.teacher)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(fmt(course.percent))%")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(color)
            }
            ScoreBar(value: course.percent, max: ABSENCE_LIMIT_PERCENT * 1.2, mark: ABSENCE_LIMIT_PERCENT, color: color)
            if let left = AbsenceBudget.left(course) {
                Label(AbsenceBudget.text(left), systemImage: left < 0 ? "xmark.octagon.fill" : left <= 2 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(color)
            }
            HStack(spacing: 14) {
                ForEach(course.rows) { r in
                    HStack(spacing: 4) {
                        Text(kindShort(r.label)).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(r.missed)").font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(r.missed > 0 ? C.rose : .secondary)
                    }
                }
                Spacer()
                Text(t("cəmi \(AbsenceBudget.missed(course)) qaib", "\(AbsenceBudget.missed(course)) absences"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 24)
    }
}

func kindLabel(_ k: String) -> String {
    switch k {
    case "Məşğələ": return t("Məşğələ", "Practice")
    case "Laboratoriya": return t("Laboratoriya", "Lab")
    default: return t("Mühazirə", "Lecture")
    }
}

private func kindShort(_ k: String) -> String {
    switch k {
    case "Məşğələ": return t("MƏŞ", "PRC")
    case "Laboratoriya": return "LAB"
    default: return t("MÜH", "LEC")
    }
}

/// Fənnin qaib təfərrüatı.
private struct JournalDetail: View {
    let course: JournalCourse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let color = absenceColor(course)
        let limit = AbsenceBudget.courseLimit(course)
        let left = AbsenceBudget.left(course)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        ZStack {
                            Ring(progress: course.percent / ABSENCE_LIMIT_PERCENT, color: color, width: 9).frame(width: 92, height: 92)
                            VStack(spacing: 0) {
                                Text("\(fmt(course.percent))%").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(color)
                                Text(t("limit 25%", "limit 25%")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            if let left {
                                Text(left >= 0 ? t("Daha \(left) qaib", "\(left) more") : t("Limit keçilib", "Over the limit"))
                                    .font(.title3.weight(.bold)).foregroundStyle(color)
                                Text(AbsenceBudget.text(left)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(t("1 qaib ≈ \(String(format: "%.2f", AbsenceBudget.onePercent(course)))%", "1 absence ≈ \(String(format: "%.2f", AbsenceBudget.onePercent(course)))%"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 24, tint: color.opacity(0.12))
                    .appear(0)

                    GlassSection(title: t("Bölmələr", "Sections"), icon: "square.split.2x2") {
                        ForEach(course.rows) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(kindLabel(r.label)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(t("\(r.hours) saat", "\(r.hours) h")).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 14) {
                                    Label("\(r.attended)", systemImage: "checkmark.circle.fill").foregroundStyle(C.green)
                                    Label("\(r.missed)", systemImage: "xmark.circle.fill").foregroundStyle(r.missed > 0 ? C.rose : .secondary)
                                    if r.limit > 0 { Text(t("limit \(fmt(r.limit))", "limit \(fmt(r.limit))")).foregroundStyle(.secondary) }
                                }
                                .font(.caption.monospacedDigit())
                            }
                            .padding(.vertical, 4)
                            if r.id != course.rows.last?.id { Divider() }
                        }
                    }
                    .appear(1)

                    GlassSection(title: t("Hesab", "Calculation"), icon: "function") {
                        InfoRow(label: t("Ümumi saat", "Total hours"), value: "\(AbsenceBudget.hours(course))")
                        InfoRow(label: t("Ümumi qaib", "Total absences"), value: "\(AbsenceBudget.missed(course))")
                        if let limit { InfoRow(label: t("Fənn limiti", "Course limit"), value: t("\(fmt(limit)) → \(Int((limit + 1e-9).rounded(.down))) qaib", "\(fmt(limit)) → \(Int((limit + 1e-9).rounded(.down))) absences")) }
                        Text(t("Bir bölmənin limitini keçmək kəsilmə deyil — yalnız fənn üzrə cəm vacibdir.",
                               "Exceeding one section's limit is not a fail — only the course total matters."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .appear(2)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle(course.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Bağla", "Close")) { dismiss() } } }
        }
    }
}
