import SwiftUI

/// "Təhsil" tab-ı: qiymətlər, jurnal, transkript, tədris planı, dərs qeydiyyatı.
struct EducationView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink { GradesView() } label: {
                        NavRow(icon: "chart.bar.fill", color: C.indigo, title: t("Qiymətlər", "Grades"),
                               subtitle: t("Cari ballar, hərf qiyməti, imtahandan nə lazımdır", "Current scores, letters, what you need on the exam"))
                    }.appear(0)
                    NavigationLink { JournalView() } label: {
                        NavRow(icon: "checklist", color: C.green, title: t("Elektron jurnal", "Attendance"),
                               subtitle: t("Qaiblər, limit və daha neçə dərs buraxa bilərsən", "Absences, limits and how many classes you can still miss"))
                    }.appear(1)
                    NavigationLink { TranscriptView() } label: {
                        NavRow(icon: "doc.text.fill", color: C.purple, title: t("Transkript", "Transcript"),
                               subtitle: t("Bütün semestrlər, ÜOMG", "All semesters, GPA"))
                    }.appear(2)
                    NavigationLink { CurriculumView() } label: {
                        NavRow(icon: "list.bullet.rectangle.fill", color: C.rose, title: t("Tədris planı", "Curriculum"),
                               subtitle: t("Keçdiyin və qarşıda olan fənlər", "Passed and upcoming courses"))
                    }.appear(3)
                    NavigationLink { RegistrationView() } label: {
                        NavRow(icon: "square.and.pencil", color: C.orange, title: t("Dərs qeydiyyatı", "Course registration"),
                               subtitle: t("Bu semestrə yazıldığın fənlər", "Courses you registered for"))
                    }.appear(4)
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(t("Təhsil", "Study"))
        }
    }
}

// MARK: - Transkript

struct TranscriptView: View {
    @State private var key = 0
    @State private var semIndex: Int?

    var body: some View {
        ScrollView {
            AsyncContent(key: key, load: { try await Api.transcript() }) { tr in
                content(tr)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Transkript", "Transcript"))
        .refreshable { Haptic.soft(); key += 1 }
    }

    @ViewBuilder
    private func content(_ tr: Transcript) -> some View {
        let def = tr.sems.lastIndex(where: { s in s.rows.contains { $0.letter.count == 1 } }) ?? (tr.sems.count - 1)
        let idx = min(semIndex ?? def, tr.sems.count - 1)
        let sem = tr.sems[idx]
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    Ring(progress: (Double(tr.uomg) ?? 0) / 100, color: C.purple, width: 9).frame(width: 96, height: 96)
                    VStack(spacing: 0) {
                        Text(tr.uomg.isEmpty ? "—" : tr.uomg).font(.title2.weight(.heavy).monospacedDigit())
                        Text(t("ÜOMG", "GPA")).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Ümumi orta bal", "Overall average")).font(.headline)
                    if !tr.credits.isEmpty {
                        Label(t("\(tr.credits) AKTS tamamlanıb", "\(tr.credits) ECTS completed"), systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(C.green)
                    }
                    Text(t("\(tr.sems.count) semestr", "\(tr.sems.count) semesters")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glassCard(cornerRadius: 26, tint: C.purple.opacity(0.14))
            .appear(0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(tr.sems.enumerated()), id: \.element.id) { i, s in
                        Button {
                            Haptic.select()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { semIndex = i }
                        } label: {
                            Text(s.label).font(.footnote.weight(.semibold))
                                .foregroundStyle(i == idx ? Color.white : Color.primary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background { if i == idx { Capsule().fill(C.purple.gradient) } }
                                .glassCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .appear(1)

            HStack(spacing: 10) {
                mini(t("S-ÜOMG", "Sem GPA"), sem.sUomg)
                mini(t("ÜOMG", "GPA"), sem.uomg)
                mini("SQK", sem.sqk)
                mini("TQK", sem.tqk)
            }
            .appear(2)

            ForEach(Array(sem.rows.enumerated()), id: \.element.id) { i, r in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text("\(r.code) · \(r.credit) AKTS" + (r.repeatMark.isEmpty ? "" : " · \(r.repeatMark)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(r.score).font(.headline.monospacedDigit())
                    if r.letter.count == 1 { LetterBadge(letter: r.letter).scaleEffect(0.8).frame(width: 36, height: 36) }
                    else if !r.letter.isEmpty { Text(r.letter).font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                }
                .padding(14)
                .glassCard(cornerRadius: 20)
                .appear(i + 3)
                .scrollFx()
            }
            .id(idx)

            if !tr.header.isEmpty {
                GlassSection(title: t("Məlumat", "Details"), icon: "info.circle") {
                    ForEach(tr.header) { InfoRow(label: $0.key, value: $0.value) }
                }
            }
        }
    }

    private func mini(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Tədris planı

struct CurriculumView: View {
    @State private var key = 0

    var body: some View {
        ScrollView {
            AsyncContent(key: key, load: { try await Api.curriculum() }) { c in
                CurriculumContent(plan: c)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Tədris planı", "Curriculum"))
        .refreshable { Haptic.soft(); key += 1 }
    }
}

private struct CurriculumContent: View {
    let plan: Curriculum
    @State private var openSem: Int?

    private func color(_ status: String) -> Color {
        switch status {
        case "passed": return C.green
        case "failed": return C.rose
        case "current": return C.orange
        default: return .gray
        }
    }

    var body: some View {
        let all = plan.semesters.flatMap(\.courses)
        let total = all.reduce(0) { $0 + $1.akts }
        let passed = all.filter { $0.status == "passed" }.reduce(0) { $0 + $1.akts }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                ZStack {
                    Ring(progress: total > 0 ? Double(passed) / Double(total) : 0, color: C.green, width: 9).frame(width: 90, height: 90)
                    Text(total > 0 ? "\(passed * 100 / total)%" : "—").font(.title3.weight(.heavy).monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title).font(.headline).lineLimit(3)
                    Text(t("\(passed) / \(total) AKTS keçilib", "\(passed) / \(total) ECTS passed")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glassCard(cornerRadius: 26, tint: C.green.opacity(0.12))
            .appear(0)

            HStack(spacing: 12) {
                legend(C.green, t("keçib", "passed"))
                legend(C.orange, t("indi", "now"))
                legend(C.rose, t("kəsilib", "failed"))
                legend(.gray, t("qarşıda", "upcoming"))
            }
            .font(.caption)
            .padding(.horizontal, 4)

            ForEach(Array(plan.semesters.enumerated()), id: \.element.id) { i, s in
                let isOpen = openSem == s.number || (openSem == nil && s.courses.contains { $0.status == "current" })
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { openSem = isOpen ? -1 : s.number }
                    } label: {
                        HStack {
                            Text(t("\(s.number)-ci semestr", "Semester \(s.number)")).font(.headline)
                            Spacer()
                            let a = s.courses.reduce(0) { $0 + $1.akts }
                            Text("\(a) AKTS").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                ForEach(s.courses) { c in Circle().fill(color(c.status)).frame(width: 6, height: 6) }
                            }
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isOpen ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isOpen {
                        ForEach(s.courses) { c in
                            HStack(spacing: 10) {
                                Circle().fill(color(c.status)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.subheadline).lineLimit(2)
                                    Text("\(c.tag) · \(c.theory)/\(c.practice)").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("\(c.akts)").font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 22)
                .appear(i + 1)
            }
        }
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(text).foregroundStyle(.secondary) }
    }
}

// MARK: - Dərs qeydiyyatı

struct RegistrationView: View {
    @State private var key = 0

    var body: some View {
        ScrollView {
            AsyncContent(key: key, load: { try await Api.registration() }) { r in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        IconBox(icon: r.confirmed ? "checkmark.seal.fill" : r.closed ? "lock.fill" : "hourglass", color: r.confirmed ? C.green : r.closed ? C.rose : C.orange, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.term.isEmpty ? t("Dərs qeydiyyatı", "Registration") : r.term).font(.headline)
                            Text(r.confirmed ? t("Qeydiyyat təsdiqlənib", "Registration confirmed")
                                 : r.closed ? t("Qeydiyyat hazırda bağlıdır", "Registration is closed")
                                 : t("Təsdiq gözlənilir", "Awaiting confirmation"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 0) {
                            Text("\(r.totalAkts)").font(.title2.weight(.heavy).monospacedDigit())
                            Text("AKTS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 24, tint: (r.confirmed ? C.green : C.orange).opacity(0.12))
                    .appear(0)

                    if r.courses.isEmpty {
                        EmptyCard(icon: "tray", text: t("Qeydiyyatda fənn yoxdur", "No registered courses"))
                    }
                    ForEach(Array(r.courses.enumerated()), id: \.element.id) { i, c in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(c.code).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(c.akts) AKTS").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5).glassCapsule()
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 20)
                        .appear(i + 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Dərs qeydiyyatı", "Registration"))
        .refreshable { Haptic.soft(); key += 1 }
    }
}
