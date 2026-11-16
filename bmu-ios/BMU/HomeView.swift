import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @State private var confetti = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if app.isMyBirthday {
                        BirthdayBanner { confetti += 1 }.appear(0)
                    } else if let n = app.birthdays, n > 0 {
                        Button {
                            Haptic.tap(); confetti += 1
                        } label: {
                            Label(t("Bu gün \(n) tələbənin ad günüdür", "\(n) students have a birthday today"), systemImage: "birthday.cake.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(C.pink)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassCapsule()
                        }
                        .buttonStyle(PressStyle())
                        .appear(0)
                    }

                    HeroCard().appear(1)
                    AnnouncementBanner().appear(2)
                    NextLessonCard().appear(2)
                    QuickTiles().appear(3)

                    SectionHeader(title: t("Bu gün", "Today"), subtitle: Day.title(Date())).appear(4)
                    DayLessons(date: Date(), emptyText: t("Bu gün dərsin yoxdur 🎉", "No classes today 🎉"))

                    SectionHeader(title: t("Sabah", "Tomorrow"), subtitle: Day.title(Day.add(1, to: Date())))
                    DayLessons(date: Day.add(1, to: Date()), emptyText: t("Sabah dərs yoxdur", "No classes tomorrow"))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .overlay { if confetti > 0 { Confetti().id(confetti) } }
            .navigationTitle(app.greeting)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AnnouncementsBell() } }
            .refreshable { Haptic.soft(); await refreshWork { await app.refreshHome() } }
            .task {
                Task { await AnnStore.shared.load(app.profile) }
                await app.ensureMonth(Date())
                let next = Day.add(7, to: Date())
                if Day.monthKey(next) != Day.monthKey(Date()) { await app.ensureMonth(next) }
                if app.isMyBirthday && confetti == 0 { confetti = 1 }
            }
        }
    }
}

private struct BirthdayBanner: View {
    let tap: () -> Void

    var body: some View {
        Button(action: { Haptic.success(); tap() }) {
            HStack(spacing: 12) {
                Text("🎉").font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Ad günün mübarək!", "Happy birthday!")).font(.headline)
                    Text(t("myBEU komandasından ən xoş arzularla", "Best wishes from the myBEU team")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .glassCard(cornerRadius: 22, tint: C.pink.opacity(0.25))
        }
        .buttonStyle(PressStyle())
    }
}

/// Yuxarıdakı şüşə kart: şəkil, ad, ixtisas, qrup.
private struct HeroCard: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        let p = app.profile
        NavigationLink {
            ProfileDetailsView()
        } label: {
            HStack(spacing: 16) {
                Avatar(image: app.photo, initials: p.initials, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.fullName).font(.title3.weight(.bold)).lineLimit(2).foregroundStyle(Color.primary)
                    Text(p.program).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 8) {
                        if !p.group.isEmpty { Pill(text: p.group, icon: "person.3.fill") }
                        if !p.course.isEmpty { Pill(text: t("\(p.course)-ci kurs", "Year \(p.course)"), icon: "graduationcap.fill") }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glassCard(cornerRadius: 28, tint: C.indigo.opacity(0.18))
        }
        .buttonStyle(PressStyle())
    }
}

struct Pill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCapsule()
    }
}

// MARK: - İndiki / növbəti dərs (canlı)

private enum NextState {
    case inClass(Lesson, Double, Int)          // dərs, irəliləyiş 0…1, qalan dəqiqə
    case pause(Lesson, Double, Int)            // tənəffüs: növbəti dərs, irəliləyiş, qalan dəqiqə
    case upcoming(Lesson, Date, Int)           // növbəti dərs, gün, qalan dəqiqə
    case none
}

private func nextState(now: Date, lessons: [String: [Lesson]]) -> NextState {
    let today = Day.cal.startOfDay(for: now)
    let comps = Day.cal.dateComponents([.hour, .minute, .second], from: now)
    let nowMin = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0)) + Double(comps.second ?? 0) / 60
    let list = (lessons[Day.key(today)] ?? []).sorted { Day.minutes($0.start) < Day.minutes($1.start) }
    if let l = list.first(where: { nowMin >= Double(Day.minutes($0.start)) && nowMin < Double(Day.minutes($0.end)) }) {
        let s = Double(Day.minutes(l.start)), e = Double(Day.minutes(l.end))
        return .inClass(l, (nowMin - s) / max(e - s, 1), Int((e - nowMin).rounded(.up)))
    }
    if let next = list.first(where: { nowMin < Double(Day.minutes($0.start)) }) {
        let s = Double(Day.minutes(next.start))
        if let prev = list.last(where: { Double(Day.minutes($0.end)) <= nowMin }) {
            let pe = Double(Day.minutes(prev.end))
            return .pause(next, (nowMin - pe) / max(s - pe, 1), Int((s - nowMin).rounded(.up)))
        }
        return .upcoming(next, today, Int((s - nowMin).rounded(.up)))
    }
    for i in 1...14 {
        let d = Day.add(i, to: today)
        if let first = (lessons[Day.key(d)] ?? []).min(by: { Day.minutes($0.start) < Day.minutes($1.start) }) {
            let mins = Int(d.timeIntervalSince(now) / 60) + Day.minutes(first.start)
            return .upcoming(first, d, mins)
        }
    }
    return .none
}

func durationText(_ m: Int) -> String {
    if m < 1 { return t("1 dəqiqədən az", "under a minute") }
    if m < 60 { return t("\(m) dəq", "\(m) min") }
    if m < 24 * 60 { return t("\(m / 60) saat", "\(m / 60) h") + (m % 60 > 0 ? t(" \(m % 60) dəq", " \(m % 60) min") : "") }
    return t("\(m / (24 * 60)) gün", "\(m / (24 * 60)) d")
}

private struct NextLessonCard: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            let st = nextState(now: ctx.date, lessons: app.lessons)
            switch st {
            case .inClass(let l, let p, let left):
                card(title: t("İndi dərsdəsən", "In class now"), lesson: l, progress: p, color: C.green,
                     detail: t("\(durationText(left)) qalıb · \(l.end)-də bitir", "\(durationText(left)) left · ends at \(l.end)"), icon: "book.fill")
            case .pause(let l, let p, let left):
                card(title: t("Tənəffüs", "Break"), lesson: l, progress: p, color: C.orange,
                     detail: t("Növbəti dərs \(durationText(left)) sonra · \(l.start)", "Next class in \(durationText(left)) · \(l.start)"), icon: "cup.and.saucer.fill")
            case .upcoming(let l, let d, let left):
                let when = Day.cal.isDateInToday(d) ? t("bu gün", "today") : Day.cal.isDateInTomorrow(d) ? t("sabah", "tomorrow") : Day.title(d)
                card(title: t("Növbəti dərs", "Next class"), lesson: l, progress: nil, color: C.indigo,
                     detail: t("\(when) \(l.start) · \(durationText(left)) sonra", "\(when) \(l.start) · in \(durationText(left))"), icon: "clock.fill")
            case .none:
                EmptyView()
            }
        }
    }

    private func card(title: String, lesson: Lesson, progress: Double?, color: Color, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                if let progress {
                    Ring(progress: progress, color: color, width: 6).frame(width: 54, height: 54)
                } else {
                    Circle().fill(color.opacity(0.15)).frame(width: 54, height: 54)
                }
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                    .symbolEffect(.pulse, options: .repeating, isActive: progress != nil)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(color).tracking(0.6)
                Text(lesson.title).font(.headline).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 24, tint: color.opacity(0.12))
    }
}

// MARK: - Sürətli keçidlər

private struct QuickTiles: View {
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            NavigationLink { GradesView() } label: { Tile(icon: "chart.bar.fill", color: C.indigo, title: t("Qiymət", "Grades")) }
            NavigationLink { JournalView() } label: { Tile(icon: "checklist", color: C.green, title: t("Jurnal", "Journal")) }
            NavigationLink { TranscriptView() } label: { Tile(icon: "doc.text.fill", color: C.purple, title: t("Transkript", "Transcript")) }
            NavigationLink { LibraryView() } label: { Tile(icon: "books.vertical.fill", color: C.orange, title: t("Kitabxana", "Library")) }
            NavigationLink { TurnstileView() } label: { Tile(icon: "door.left.hand.open", color: C.teal, title: t("Turniket", "Gates")) }
            NavigationLink { TuitionView() } label: { Tile(icon: "creditcard.fill", color: C.pink, title: t("Ödəniş", "Tuition")) }
            NavigationLink { CurriculumView() } label: { Tile(icon: "list.bullet.rectangle.fill", color: C.rose, title: t("Plan", "Plan")) }
            NavigationLink { DocsView() } label: { Tile(icon: "folder.fill", color: C.navy, title: t("Sənəd", "Docs")) }
        }
        .buttonStyle(PressStyle())
    }
}

/// Bir günün dərsləri (yüklənir / boş / siyahı).
struct DayLessons: View {
    @EnvironmentObject private var app: AppState
    let date: Date
    let emptyText: String

    var body: some View {
        let list = app.lessons[Day.key(date)] ?? []
        let loading = app.loadingMonths.contains(Day.monthKey(date))
        VStack(spacing: 10) {
            if list.isEmpty {
                if loading {
                    LoadingStack(count: 2, height: 74)
                } else if !app.scheduleError.isEmpty {
                    ErrorCard(text: app.scheduleError) { Task { await app.ensureMonth(date, force: true) } }
                } else {
                    EmptyCard(icon: "sun.max.fill", text: emptyText)
                }
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, l in
                    LessonRow(lesson: l, isToday: Day.cal.isDateInToday(date)).appear(i).scrollFx()
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: list.count)
    }
}
