import SwiftUI
import UIKit
import EventKit
import PhotosUI

// MARK: - Paylaşım vərəqi

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Həftənin cədvəli şəkil kimi (WhatsApp, Telegram, Story)

/// Şəkil həmişə açıq rənglərdə, şəbəkəyə müraciətsiz telefonda çəkilir.
struct WeekShareCard: View {
    let monday: Date
    let lessons: [String: [Lesson]]
    let group: String
    let week: String?

    private let navy = Color(hex: 0x1B2850), indigo = Color(hex: 0x4558B8)

    private func color(_ type: String) -> Color {
        switch type {
        case "Laboratoriya": return Color(hex: 0xE07A10)
        case "Məşğələ": return Color(hex: 0x2E8B57)
        default: return indigo
        }
    }

    var body: some View {
        let days = (0..<6).map { Day.add($0, to: monday) }.filter { !(lessons[Day.key($0)] ?? []).isEmpty }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Dərs cədvəli", "Class schedule")).font(.system(size: 26, weight: .heavy)).foregroundStyle(navy)
                    Text(range + (group.isEmpty ? "" : " · " + group) + (week.map { " · " + TimetableStore.weekLabel($0) } ?? ""))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(navy.opacity(0.6))
                }
                Spacer()
                Text("myBEU").font(.system(size: 16, weight: .heavy)).foregroundStyle(indigo)
            }
            if days.isEmpty {
                Text(t("Bu həftə dərs yoxdur", "No classes this week")).font(.system(size: 16)).foregroundStyle(navy.opacity(0.7))
            }
            ForEach(days, id: \.self) { d in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Day.weekdaysLong[Day.weekdayIndex(d)] + ", \(Day.cal.component(.day, from: d)) " + Day.months[Day.cal.component(.month, from: d) - 1])
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(indigo)
                    ForEach((lessons[Day.key(d)] ?? []).sorted { Day.minutes($0.start) < Day.minutes($1.start) }) { l in
                        let room = TimetableStore.shared.room(for: d, lesson: l)
                        HStack(alignment: .top, spacing: 10) {
                            Text(l.start).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(navy).frame(width: 46, alignment: .leading)
                            RoundedRectangle(cornerRadius: 2).fill(color(l.type)).frame(width: 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(navy).lineLimit(2)
                                Text(([l.typeLabel] + (room.map { [$0.short] } ?? [])).joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(navy.opacity(0.6))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(LinearGradient(colors: [Color(hex: 0xEEF1FF), Color(hex: 0xF8FAE9)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, .light)
    }

    private var range: String {
        let end = Day.add(5, to: monday)
        return "\(Day.cal.component(.day, from: monday)) \(Day.months[Day.cal.component(.month, from: monday) - 1]) – \(Day.cal.component(.day, from: end)) \(Day.months[Day.cal.component(.month, from: end) - 1])"
    }

    @MainActor
    static func render(monday: Date, lessons: [String: [Lesson]], group: String, week: String?) -> UIImage? {
        let r = ImageRenderer(content: WeekShareCard(monday: monday, lessons: lessons, group: group, week: week))
        r.scale = 3
        return r.uiImage
    }
}

// MARK: - Təqvimə köçürmə

@MainActor
enum CalendarExport {
    private static func idsKey(_ number: String) -> String { "calendar_event_ids_\(number)" }

    /// Bu gündən semestrin sonuna qədər (dərs olmayan aya çatana qədər, ən çox 6 ay) bütün dərsləri təqvimə yazır.
    /// Əvvəlki köçürmənin hadisələri silinir — təkrar basmaq dublikat yaratmır. Yazılan dərs sayını qaytarır.
    static func export(_ app: AppState) async throws -> Int {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            throw PortalError.message(t("Təqvimə icazə verilmədi. Parametrlər → myBEU → Təqvimlər bölməsindən icazə ver.",
                                        "Calendar access was denied. Allow it in Settings → myBEU → Calendars."))
        }
        // aylar: dərs olmayan aya çatana qədər
        var month = Date()
        for i in 0..<6 {
            await app.ensureMonth(month)
            if i > 0 {
                let mk = Day.monthKey(month)
                let any = app.lessons.contains { !$0.value.isEmpty && monthKey($0.key) == mk }
                if !any { break }
            }
            month = Day.cal.date(byAdding: .month, value: 1, to: month) ?? month
        }
        guard let cal = store.defaultCalendarForNewEvents else {
            throw PortalError.message(t("Telefonda yazıla bilən təqvim tapılmadı", "No writable calendar found on this phone"))
        }
        let number = app.profile.number
        // köhnə köçürməni sil
        for id in UserDefaults.standard.stringArray(forKey: idsKey(number)) ?? [] {
            if let e = store.event(withIdentifier: id) { try? store.remove(e, span: .thisEvent, commit: false) }
        }
        try? store.commit()

        let today = Day.key(Date())
        var ids: [String] = []
        for (k, ls) in app.lessons.sorted(by: { $0.key < $1.key }) where k >= today {
            guard let day = keyDate(k) else { continue }
            for l in ls {
                guard let s = Day.cal.date(byAdding: .minute, value: Day.minutes(l.start), to: day) else { continue }
                var e = Day.cal.date(byAdding: .minute, value: Day.minutes(l.end), to: day) ?? s
                if e <= s { e = s.addingTimeInterval(80 * 60) }
                let ev = EKEvent(eventStore: store)
                ev.calendar = cal
                ev.title = "\(l.code) · \(l.title)" + (l.type == "Laboratoriya" || l.type == "Məşğələ" ? " (\(l.typeLabel.lowercased()))" : "")
                ev.startDate = s
                ev.endDate = e
                if let room = TimetableStore.shared.room(for: day, lesson: l) { ev.location = room.label }
                ev.notes = "\(l.typeLabel) · myBEU"
                if (try? store.save(ev, span: .thisEvent, commit: false)) != nil, let id = ev.eventIdentifier { ids.append(id) }
            }
        }
        try store.commit()
        UserDefaults.standard.set(ids, forKey: idsKey(number))
        return ids.count
    }

    private static func keyDate(_ k: String) -> Date? { LibraryDue.keyDate(k) }

    /// "2026-11-18" → "2026-11"
    private static func monthKey(_ k: String) -> String {
        guard let d = keyDate(k) else { return "" }
        return Day.monthKey(d)
    }
}

// MARK: - Cədvəl şəkli (otaqlar, müəllimlər, alt/üst həftə)

struct TimetablePhotoView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = TimetableStore.shared
    @State private var pick: PhotosPickerItem?
    @State private var reading = false
    @State private var error = ""
    @State private var preview: ParsedTimetable?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassSection(title: t("Nə üçündür?", "What is it for?"), icon: "sparkles") {
                    Text(t("Qrupunun dərs cədvəlinin şəklini seç — tətbiq onu telefonda oxuyur və hər dərsin yanında otağı, binanı və müəllimi göstərir. Bölünmüş xanalardan bu həftənin üst və ya alt həftə olduğunu da tapır.",
                           "Pick a photo of your group's timetable — the app reads it on the phone and shows the room, building and teacher next to each class. It also works out whether this is the upper or lower week."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(t("Şəkil heç yerə göndərilmir. Yalnız öz qrupunun (\(app.profile.group)) cədvəlini yükləyə bilərsən.",
                           "The photo is never uploaded. You can only add your own group's (\(app.profile.group)) timetable."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .appear(0)

                PhotosPicker(selection: $pick, matching: .images) {
                    HStack {
                        if reading { ProgressView().controlSize(.small) } else { Image(systemName: "photo.badge.plus") }
                        Text(reading ? t("Oxunur…", "Reading…")
                             : store.entries.isEmpty ? t("Cədvəl şəklini seç", "Choose timetable photo") : t("Yeni şəkil seç", "Choose a new photo"))
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn)
                .disabled(reading)
                .appear(1)

                if !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(C.rose)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 20, tint: C.rose.opacity(0.12))
                }

                if let p = preview {
                    GlassSection(title: t("Oxunan cədvəl", "Recognised timetable"), icon: "checkmark.circle.fill") {
                        Text(t("\(p.entries.count) dərs tapıldı", "\(p.entries.count) classes found") + (p.group.isEmpty ? "" : " · " + p.group))
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button(t("Yadda saxla", "Save")) {
                                store.save(p); preview = nil; Haptic.success()
                                app.rescheduleReminders(); WidgetData.publish(app.lessons)
                            }
                            .glassButton(prominent: true).tint(C.green)
                            Button(t("Ləğv et", "Cancel")) { preview = nil }.glassButton()
                        }
                    }
                    entriesList(p.entries)
                } else if !store.entries.isEmpty {
                    let wk = store.weekOf(Date(), lessons: app.lessons)
                    GlassSection(title: t("Yadda saxlanan cədvəl", "Saved timetable"), icon: "tablecells") {
                        InfoRow(label: t("Qrup", "Group"), value: store.group)
                        InfoRow(label: t("Dərs sayı", "Classes"), value: "\(store.entries.count)")
                        InfoRow(label: t("Bu həftə", "This week"), value: wk.map { TimetableStore.weekLabel($0) } ?? t("bilinmir", "unknown"))
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(t("Cədvəli sil", "Delete timetable"), systemImage: "trash")
                        }
                        .glassButton().tint(C.rose)
                    }
                    entriesList(store.entries)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Cədvəl şəkli", "Timetable photo"))
        .track("timetable_photo")
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .confirmationDialog(t("Cədvəl silinsin?", "Delete the timetable?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("Sil", "Delete"), role: .destructive) {
                store.clear(); app.rescheduleReminders(); WidgetData.publish(app.lessons)
            }
            Button(t("Ləğv et", "Cancel"), role: .cancel) {}
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        reading = true; error = ""; preview = nil
        defer { reading = false; pick = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
                throw PortalError.message(t("Şəkil açılmadı", "The photo could not be opened"))
            }
            let p = try await TimetableStore.read(img, portalGroup: app.profile.group, lessons: app.lessons)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { preview = p }
            Haptic.success()
        } catch {
            self.error = error.localizedDescription
            Haptic.error()
        }
    }

    @ViewBuilder
    private func entriesList(_ entries: [TtEntry]) -> some View {
        ForEach(1...7, id: \.self) { d in
            let list = entries.filter { $0.day == d }
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Day.weekdaysLong[d - 1]).font(.headline)
                    ForEach(list, id: \.self) { e in
                        HStack(alignment: .top, spacing: 10) {
                            Text(e.start).font(.subheadline.weight(.bold).monospacedDigit()).frame(width: 50, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.subject).font(.subheadline.weight(.semibold))
                                let room = Room.of(e.room)
                                let info = [e.kind == "Nəzəri" ? nil : e.kind, room?.short, e.teacher.isEmpty ? nil : e.teacher,
                                            e.week.isEmpty ? nil : TimetableStore.weekLabel(e.week)].compactMap { $0 }
                                if !info.isEmpty { Text(info.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20)
            }
        }
    }
}
