import SwiftUI

// MARK: - Elanlar: siyahı, səhifə, sorğu, "Gələcəm"

/// Elanların vəziyyəti (ana səhifədəki zəng, siyahı, baxılmamış sayı).
@MainActor
final class AnnStore: ObservableObject {
    static let shared = AnnStore()
    @Published var all: [Ann] = []
    @Published var loaded = false
    @Published var error = ""
    private var loadedAt = Date.distantPast

    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "seen_anns") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "seen_anns") }
    }
    private var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hidden_anns") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hidden_anns") }
    }

    var active: [Ann] { all.filter { $0.active && !hidden.contains($0.id) } }
    var unseen: Int { all.filter { $0.active && !seen.contains($0.id) }.count }

    /// force = false: son 60 saniyədə yüklənibsə təkrar sorğu yoxdur.
    func load(_ p: Profile, force: Bool = false) async {
        guard FirebaseConfig.enabled, !p.number.isEmpty else { return }
        if !force && loaded && Date().timeIntervalSince(loadedAt) < 60 { return }
        loadedAt = Date()
        do {
            let list = try await Cloud.shared.announcements(targets: Cloud.targets(p))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { all = list }
            error = ""
            // fonda bildiriş göndərilməsin deyə: bunlar artıq "bildirilmiş" sayılır
            Updates.markAnnsNotified(list.map(\.id))
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    func markSeen() { seen = seen.union(all.map(\.id)); objectWillChange.send() }
    func hide(_ id: String) { hidden = hidden.union([id]); objectWillChange.send() }

    func update(_ a: Ann) {
        if let i = all.firstIndex(where: { $0.id == a.id }) { all[i] = a }
    }
}

private func targetLabel(_ t0: String) -> String {
    if t0 == "all" { return t("Hamıya", "Everyone") }
    if t0.hasPrefix("course_") { return t("\(t0.dropFirst(7))-ci kurs", "Year \(t0.dropFirst(7))") }
    if t0.hasPrefix("stream_") { return t("Potok \(t0.dropFirst(7))", "Stream \(t0.dropFirst(7))") }
    if t0.hasPrefix("group_") { return t("Qrup \(t0.dropFirst(6))", "Group \(t0.dropFirst(6))") }
    if t0.hasPrefix("student_") { return t("Yalnız sənə", "Only you") }
    return t0
}

private let annDate: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy HH:mm"
    return f
}()

/// Ana səhifənin yuxarısındakı zəng düyməsi (baxılmamış elan sayı ilə).
struct AnnouncementsBell: View {
    @ObservedObject var store = AnnStore.shared
    @State private var ring = 0

    var body: some View {
        NavigationLink { AnnouncementsView() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.body.weight(.semibold))
                    .symbolEffect(.bounce, value: ring)
                    .frame(width: 34, height: 34)
                if store.unseen > 0 {
                    Text("\(store.unseen)")
                        .font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(C.rose))
                        .offset(x: 6, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onChange(of: store.unseen) { _, n in if n > 0 { ring += 1 } }
    }
}

/// Ana səhifədə ən yeni aktiv elan (kart).
struct AnnouncementBanner: View {
    @ObservedObject var store = AnnStore.shared

    var body: some View {
        if let a = store.active.first {
            NavigationLink { AnnouncementDetail(ann: a) } label: {
                HStack(spacing: 14) {
                    IconBox(icon: a.hasPoll ? "chart.bar.doc.horizontal.fill" : a.rsvp ? "calendar.badge.plus" : "megaphone.fill", color: C.orange, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("ELAN", "ANNOUNCEMENT")).font(.caption2.weight(.bold)).foregroundStyle(C.orange).tracking(0.6)
                        Text(a.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
                        if !a.body.isEmpty { Text(a.body).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .glassCard(cornerRadius: 22, tint: C.orange.opacity(0.12))
            }
            .buttonStyle(PressStyle())
        }
    }
}

struct AnnouncementsView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store = AnnStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !FirebaseConfig.enabled { EmptyCard(icon: "icloud.slash", text: CloudError.notConfigured.localizedDescription) }
                if !store.error.isEmpty { ErrorCard(text: store.error) { Task { await store.load(app.profile, force: true) } } }
                if !store.loaded && store.error.isEmpty { LoadingStack(count: 3, height: 90) }
                if store.loaded && store.all.isEmpty && store.error.isEmpty {
                    EmptyCard(icon: "megaphone", text: t("Hələ elan yoxdur", "No announcements yet"))
                }
                ForEach(Array(store.all.enumerated()), id: \.element.id) { i, a in
                    NavigationLink { AnnouncementDetail(ann: a) } label: { AnnRow(ann: a) }
                        .buttonStyle(PressStyle())
                        .appear(min(i, 10))
                        .scrollFx()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Elanlar", "Announcements"))
        .refreshable { Haptic.soft(); let p = app.profile; await refreshWork { await AnnStore.shared.load(p, force: true) } }
        .task {
            await store.load(app.profile, force: true)
            store.markSeen()
        }
        .track("announcements")
    }
}

private struct AnnRow: View {
    let ann: Ann

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBox(icon: ann.hasPoll ? "chart.bar.doc.horizontal.fill" : ann.rsvp ? "calendar.badge.plus" : "megaphone.fill",
                    color: ann.active ? C.orange : .gray, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(ann.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
                if !ann.body.isEmpty { Text(ann.body).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    Text(annDate.string(from: ann.created))
                    Text("·")
                    Text(targetLabel(ann.target))
                    if !ann.active { Text("· " + t("bitib", "ended")) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .opacity(ann.active ? 1 : 0.6)
        .glassCard(cornerRadius: 20)
    }
}

struct AnnouncementDetail: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var ann: Ann
    @State private var choice: Int?
    @State private var going = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let u = URL(string: ann.image), !ann.image.isEmpty {
                    AsyncImage(url: u) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.primary.opacity(0.06)).shimmer()
                    }
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .appear(0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(ann.title).font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        Pill(text: targetLabel(ann.target), icon: "person.2.fill")
                        if let u = ann.until { Pill(text: (ann.active ? t("son: ", "until ") : t("bitib: ", "ended ")) + annDate.string(from: u), icon: "clock") }
                    }
                    if !ann.body.isEmpty {
                        Text(.init(ann.body)).font(.body).tint(C.indigo).textSelection(.enabled).padding(.top, 4)
                    }
                    if let u = URL(string: ann.link), !ann.link.isEmpty {
                        Link(destination: u) {
                            Label(t("Keçidi aç", "Open link"), systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                        }
                        .glassButton(prominent: true).tint(C.btn).padding(.top, 6)
                    }
                }
                .padding(18)
                .glassCard(cornerRadius: 24)
                .appear(1)

                if !error.isEmpty { ErrorCard(text: error) { error = "" } }
                if ann.hasPoll { poll.appear(2) }
                if ann.rsvp { rsvp.appear(3) }

                Button(role: .destructive) {
                    AnnStore.shared.hide(ann.id)
                    Haptic.tap()
                    dismiss()
                } label: {
                    Label(t("Ana səhifədən gizlət", "Hide from home"), systemImage: "eye.slash").frame(maxWidth: .infinity)
                }
                .glassButton()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Elan", "Announcement"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            Usage.shared.action("ann_open", ann.id)
            if let fresh = try? await Cloud.shared.announcement(ann.id) { ann = fresh; AnnStore.shared.update(fresh) }
            let mine = await Cloud.shared.myAnswers(ann.id)
            choice = mine.choice
            going = mine.going
        }
        .track("announcement")
    }

    private var poll: some View {
        GlassSection(title: ann.pollQuestion.isEmpty ? t("Sorğu", "Poll") : ann.pollQuestion, icon: "chart.bar.doc.horizontal") {
            ForEach(Array(ann.pollOptions.enumerated()), id: \.offset) { i, opt in
                Button {
                    vote(i)
                } label: {
                    HStack {
                        Image(systemName: choice == i ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(choice == i ? C.indigo : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(opt).foregroundStyle(Color.primary)
                        Spacer()
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 14, tint: choice == i ? C.indigo.opacity(0.15) : nil, interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(busy || !ann.active)
            }
            Text(!ann.active ? t("Sorğu bitib", "The poll has ended")
                 : choice == nil ? t("Səsini ver — nəticələri yalnız universitet görür", "Vote — only the university sees results")
                 : t("Səsin qeydə alındı, istəsən dəyişə bilərsən", "Your vote is saved, you can change it"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var rsvp: some View {
        GlassSection(title: t("Tədbirə qeydiyyat", "Event sign-up"), icon: "calendar.badge.plus") {
            HStack {
                Text(ann.capacity > 0 ? t("\(ann.rsvpCount) / \(ann.capacity) nəfər yazılıb", "\(ann.rsvpCount) / \(ann.capacity) signed up")
                                      : t("\(ann.rsvpCount) nəfər yazılıb", "\(ann.rsvpCount) signed up"))
                    .font(.subheadline).contentTransition(.numericText())
                Spacer()
                if ann.full && !going { Text(t("Yer qalmayıb", "Full")).font(.caption.weight(.bold)).foregroundStyle(C.rose) }
            }
            if ann.capacity > 0 {
                ScoreBar(value: Double(ann.rsvpCount), max: Double(ann.capacity), color: ann.full ? C.rose : C.green)
            }
            Button { setGoing(!going) } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(going ? t("Gəlməyəcəm (ləğv et)", "Cancel my sign-up") : t("Gələcəm", "I'll attend")).font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .glassButton(prominent: !going)
            .tint(going ? C.rose : C.green)
            .disabled(busy || !ann.active || (ann.full && !going))
        }
    }

    private func vote(_ i: Int) {
        busy = true; error = ""
        Haptic.select()
        let p = app.profile
        let old = choice
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { choice = i }
        Task {
            do {
                try await Cloud.shared.vote(ann.id, choice: i, name: p.fullName, group: p.group)
                Usage.shared.action("poll_vote", ann.id)
                Haptic.success()
            } catch {
                choice = old
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func setGoing(_ on: Bool) {
        busy = true; error = ""
        Haptic.tap()
        let p = app.profile
        Task {
            do {
                try await Cloud.shared.setGoing(ann.id, going: on, name: p.fullName, group: p.group)
                going = on
                if let fresh = try? await Cloud.shared.announcement(ann.id) {
                    withAnimation { ann = fresh }
                    AnnStore.shared.update(fresh)
                }
                Usage.shared.action(on ? "rsvp_go" : "rsvp_cancel", ann.id)
                Haptic.success()
            } catch {
                self.error = error.localizedDescription
                Haptic.error()
            }
            busy = false
        }
    }
}
