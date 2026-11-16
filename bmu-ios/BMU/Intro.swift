import SwiftUI

/// Tətbiqlə tanışlıq: ilk girişdən sonra bir dəfə göstərilir, Profil → "Tətbiqlə tanışlıq"-dan yenidən açılır.
struct IntroView: View {
    let done: () -> Void
    @State private var page = 0
    @State private var bounce = 0

    private struct Page: Identifiable {
        let id: Int
        let icon: String
        let color: Color
        let title: String
        let text: String
    }

    private var pages: [Page] {
        [
            Page(id: 0, icon: "graduationcap.fill", color: C.indigo, title: t("myBEU-ya xoş gəldin!", "Welcome to myBEU!"),
                 text: t("Portalın hər şeyi bir yerdə: cədvəl, qiymətlər, davamiyyət, transkript, kitabxana və daha çoxu.",
                         "Everything from the portal in one place: schedule, grades, attendance, transcript, library and more.")),
            Page(id: 1, icon: "calendar.badge.clock", color: C.teal, title: t("Dərs cədvəli", "Schedule"),
                 text: t("Dərsdən əvvəl xatırlatma gəlir. Cədvəl şəklini yükləsən otaq, müəllim və alt/üst həftə də görünür. Həftəni şəkil kimi paylaşa, telefonun təqviminə köçürə bilərsən.",
                         "Get a reminder before each class. Add a timetable photo to see rooms, teachers and the upper/lower week. Share the week as an image or copy it to your calendar.")),
            Page(id: 2, icon: "chart.bar.xaxis", color: C.purple, title: t("Qiymətlər", "Grades"),
                 text: t("Hər fəndə finaldan nə qədər lazım olduğunu görürsən: keçmək üçün giriş + final ≥ 51 və final ≥ 17. Bal yazılanda bildiriş gəlir.",
                         "See what you need on the final for every course: to pass, entry + final ≥ 51 and final ≥ 17. You get a notification when a score is posted.")),
            Page(id: 3, icon: "checklist.checked", color: C.green, title: t("Davamiyyət", "Attendance"),
                 text: t("Hər fəndə daha neçə qaib edə biləcəyini və limitə nə qədər qaldığını göstərir. Qaib yazılanda xəbər verir.",
                         "Shows how many more classes you can miss in each course and how close you are to the limit. You're notified when an absence is recorded.")),
            Page(id: 4, icon: "lock.shield.fill", color: C.orange, title: t("Təhlükəsizlik", "Security"),
                 text: t("Şifrən yalnız bu iPhone-da şifrəli saxlanılır. Face ID kilidi qoya bilərsən. İnternet olmayanda son saxlanan məlumat göstərilir.",
                         "Your password is stored encrypted only on this iPhone. You can add a Face ID lock. Without internet, the last saved data is shown."))
        ]
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(t("Keç", "Skip")) { Haptic.tap(); done() }
                        .glassButton()
                        .opacity(page < pages.count - 1 ? 1 : 0)
                }
                .padding(.horizontal, 20)

                TabView(selection: $page) {
                    ForEach(pages) { p in
                        VStack(spacing: 24) {
                            Spacer()
                            Image(systemName: p.icon)
                                .font(.system(size: 64, weight: .semibold))
                                .foregroundStyle(p.color)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, value: bounce)
                                .frame(width: 140, height: 140)
                                .glassCard(cornerRadius: 40, tint: p.color.opacity(0.2))
                            Text(p.title).font(.title.weight(.bold)).multilineTextAlignment(.center)
                            Text(p.text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                            Spacer()
                        }
                        .tag(p.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    Haptic.tap()
                    if page < pages.count - 1 {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
                    } else {
                        Haptic.success(); done()
                    }
                } label: {
                    Text(page < pages.count - 1 ? t("Növbəti", "Next") : t("Başla", "Get started"))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .glassButton(prominent: true).tint(C.btn)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: page) { _, _ in bounce += 1; Haptic.select() }
        .track("intro")
    }
}
