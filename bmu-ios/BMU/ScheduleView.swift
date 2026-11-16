import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var app: AppState
    @State private var day = Day.startOfToday()
    @State private var direction: Edge = .trailing

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
                            Text(n == 0 ? t("dərs yoxdur", "no classes") : t("\(n) dərs", "\(n) class\(n == 1 ? "" : "es")"))
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
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(t("Cədvəl", "Schedule"))
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
