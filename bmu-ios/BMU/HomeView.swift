import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroCard()
                    InfoChips()

                    SectionHeader(title: "Bu gün", subtitle: Day.title(Date()))
                    DayLessons(date: Date(), emptyText: "Bu gün dərsin yoxdur")

                    SectionHeader(title: "Sabah", subtitle: Day.title(Day.add(1, to: Date())))
                    DayLessons(date: Day.add(1, to: Date()), emptyText: "Sabah dərs yoxdur")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Ana səhifə")
            .refreshable { await app.refreshHome() }
            .task {
                await app.ensureMonth(Date())
                let tomorrow = Day.add(1, to: Date())
                if Day.monthKey(tomorrow) != Day.monthKey(Date()) { await app.ensureMonth(tomorrow) }
            }
        }
    }
}

/// Yuxarıdakı şüşə kart: şəkil, ad, ixtisas, qrup.
private struct HeroCard: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        let p = app.profile
        HStack(spacing: 16) {
            Avatar(image: app.photo, initials: p.initials, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.fullName).font(.title3.weight(.bold)).lineLimit(2)
                Text(p.program).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    if !p.group.isEmpty { Pill(text: p.group, icon: "person.3.fill") }
                    if !p.course.isEmpty { Pill(text: "\(p.course). kurs", icon: "graduationcap.fill") }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glassCard(cornerRadius: 28, tint: C.indigo.opacity(0.18))
    }
}

private struct Pill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassCapsule()
    }
}

/// Qısa məlumatlar: tələbə nömrəsi, təhsil haqqı borcu, semestr.
private struct InfoChips: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        let p = app.profile
        HStack(spacing: 10) {
            Chip(title: "Nömrə", value: p.number, icon: "number")
            Chip(title: "Borc", value: p.tuitionDebt.isEmpty ? "—" : p.tuitionDebt, icon: "creditcard")
            Chip(title: "Semestr", value: p.termYear.isEmpty ? "—" : "\(p.termYear)/\(p.termNo)", icon: "calendar")
        }
    }

    private struct Chip: View {
        let title: String
        let value: String
        let icon: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.footnote.weight(.semibold)).foregroundStyle(C.indigo)
                Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard(cornerRadius: 20)
        }
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
                    LoadingCard(text: "Cədvəl yüklənir…")
                } else if !app.scheduleError.isEmpty {
                    ErrorCard(text: app.scheduleError) { Task { await app.ensureMonth(date, force: true) } }
                } else {
                    EmptyCard(icon: "sun.max.fill", text: emptyText)
                }
            } else {
                ForEach(list) { LessonRow(lesson: $0, isToday: Day.cal.isDateInToday(date)) }
            }
        }
    }
}
