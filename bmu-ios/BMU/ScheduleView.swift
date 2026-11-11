import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var app: AppState
    @State private var day = Day.startOfToday()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WeekStrip(day: $day) { app.lessons[Day.key($0)]?.isEmpty == false }

                    HStack {
                        Text(Day.title(day)).font(.headline)
                        Spacer()
                        if !Day.cal.isDateInToday(day) {
                            Button("Bu gün") { withAnimation(.snappy) { day = Day.startOfToday() } }
                                .glassButton()
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 4)

                    DayLessons(date: day, emptyText: "Bu gün dərs yoxdur")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Cədvəl")
            .refreshable { await app.ensureMonth(day, force: true) }
            .task(id: Day.key(Day.monday(of: day))) {
                // həftə iki aya düşə bilər: hər ikisini yüklə
                let monday = Day.monday(of: day)
                await app.ensureMonth(monday)
                await app.ensureMonth(Day.add(6, to: monday))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    withAnimation(.snappy) { day = Day.add(v.translation.width < 0 ? 1 : -1, to: day) }
                }
            )
        }
    }
}

/// Həftə zolağı: B.e … Baz, seçilmiş gün rəngli, dərsi olan günün altında nöqtə.
struct WeekStrip: View {
    @Binding var day: Date
    let hasLessons: (Date) -> Bool

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
                    withAnimation(.snappy) { day = d }
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

    private func shift(_ n: Int) {
        withAnimation(.snappy) { day = Day.add(n, to: day) }
    }
}
