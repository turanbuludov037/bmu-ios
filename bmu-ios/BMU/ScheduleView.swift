import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var app: AppState
    @State private var day = Day.startOfToday()
    @State private var direction: Edge = .trailing
    @ObservedObject private var tt = TimetableStore.shared
    @State private var share: ShareItem?
    @State private var showPhoto = false
    @State private var exporting = false
    @State private var exportMsg: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WeekStrip(day: $day, direction: $direction) { app.lessons[Day.key($0)]?.isEmpty == false }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Day.title(day)).font(.headline)
                                .contentTransition(.numericText())
                            let n = app.lessons[Day.key(day)]?.count ?? 0
                            let wk = tt.entries.isEmpty ? nil : tt.weekOf(day, lessons: app.lessons)
                            Text((n == 0 ? t("dərs yoxdur", "no classes") : t("\(n) dərs", "\(n) class\(n == 1 ? "" : "es")"))
                                 + (wk.map { " · " + TimetableStore.weekLabel($0) } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !Day.cal.isDateInToday(day) {
                            Button(t("Bu gün", "Today")) { go(to: Day.startOfToday()) }
                                .glassButton()
                                .font(.subheadline.weight(.semibold))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: Day.cal.isDateInToday(day))

                    DayLessons(date: day, emptyText: t("Bu gün dərs yoxdur", "No classes on this day"))
                        .id(Day.key(day))
                        .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                                removal: .opacity))

                    if tt.entries.isEmpty {
                        Button { Haptic.tap(); showPhoto = true } label: {
                            NavRow(icon: "photo.badge.plus", color: C.teal, title: t("Cədvəl şəklini yüklə", "Add timetable photo"),
                                   subtitle: t("Otaqlar, müəllimlər, alt/üst həftə", "Rooms, teachers, upper/lower week"))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(t("Cədvəl", "Schedule"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { shareWeek() } label: {
                            Label(t("Həftəni şəkil kimi paylaş", "Share week as image"), systemImage: "square.and.arrow.up")
                        }
                        Button { exportCalendar() } label: {
                            Label(t("Telefonun təqviminə köçür", "Copy to phone calendar"), systemImage: "calendar.badge.plus")
                        }
                        Button { showPhoto = true } label: {
                            Label(t("Cədvəl şəkli (otaqlar)", "Timetable photo (rooms)"), systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        if exporting { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .navigationDestination(isPresented: $showPhoto) { TimetablePhotoView() }
            .sheet(item: $share) { ActivitySheet(items: $0.items).presentationDetents([.medium, .large]) }
            .alert(t("Təqvim", "Calendar"), isPresented: Binding(get: { exportMsg != nil }, set: { if !$0 { exportMsg = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportMsg ?? "")
            }
            .refreshable { Haptic.soft(); let d = day; await refreshWork { await app.ensureMonth(d, force: true) } }
            .task(id: Day.key(Day.monday(of: day))) {
                // həftə iki aya düşə bilər: hər ikisini yüklə
                let monday = Day.monday(of: day)
                await app.ensureMonth(monday)
                await app.ensureMonth(Day.add(6, to: monday))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    go(to: Day.add(v.translation.width < 0 ? 1 : -1, to: day))
                }
            )
        }
    }

    private func shareWeek() {
        let monday = Day.monday(of: day)
        let wk = tt.entries.isEmpty ? nil : tt.weekOf(day, lessons: app.lessons)
        guard let img = WeekShareCard.render(monday: monday, lessons: app.lessons, group: app.profile.group, week: wk) else { return }
        Haptic.tap()
        Usage.shared.action("share_timetable")
        share = ShareItem(items: [img])
    }

    private func exportCalendar() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let n = try await CalendarExport.export(app)
                Haptic.success()
                exportMsg = t("\(n) dərs təqvimə yazıldı. Yenidən köçürəndə köhnələri silinir.", "\(n) classes added. Exporting again replaces the old ones.")
            } catch {
                Haptic.error()
                exportMsg = error.localizedDescription
            }
        }
    }

    private func go(to d: Date) {
        direction = d > day ? .trailing : .leading
        Haptic.select()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { day = d }
    }
}

/// Həftə zolağı: seçilmiş gün yaylanan şüşə "kapsul" ilə işarələnir, dərsi olan günün altında nöqtə.
struct WeekStrip: View {
    @Binding var day: Date
    @Binding var direction: Edge
    let hasLessons: (Date) -> Bool
    @Namespace private var ns

    var body: some View {
        let monday = Day.monday(of: day)
        HStack(spacing: 4) {
            Button { shift(-7) } label: {
                Image(systemName: "chevron.left").font(.footnote.weight(.bold)).frame(width: 22, height: 44)
            }
            .buttonStyle(.plain)

            ForEach(0..<7, id: \.self) { i in
                let d = Day.add(i, to: monday)
                let selected = Day.cal.isDate(d, inSameDayAs: day)
                let today = Day.cal.isDateInToday(d)
                Button {
                    select(d)
                } label: {
                    VStack(spacing: 4) {
                        Text(Day.weekdays[i]).font(.caption2.weight(.medium))
                        Text("\(Day.cal.component(.day, from: d))").font(.headline.monospacedDigit())
                        Circle()
                            .fill(hasLessons(d) ? (selected ? Color.white : C.indigo) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? Color.white : (today ? C.indigo : Color.primary))
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(C.btn.gradient)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button { shift(7) } label: {
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).frame(width: 22, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .glassCard(cornerRadius: 24)
    }

    private func select(_ d: Date) {
        direction = d > day ? .trailing : .leading
        Haptic.select()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { day = d }
    }

    private func shift(_ n: Int) { select(Day.add(n, to: day)) }
}
