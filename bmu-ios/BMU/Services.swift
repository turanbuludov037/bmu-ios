import SwiftUI
import QuickLook

/// "Xidmətlər" tab-ı.
struct ServicesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink { LibraryView() } label: {
                        NavRow(icon: "books.vertical.fill", color: C.orange, title: t("Kitabxana", "Library"),
                               subtitle: t("Axtarış, sifariş, götürdüyün kitablar", "Search, order, your borrowed books"))
                    }.appear(0)
                    NavigationLink { OnlineServicesView() } label: {
                        NavRow(icon: "doc.badge.plus", color: C.indigo, title: t("Onlayn xidmətlər", "Online services"),
                               subtitle: t("Arayış, transkript, Forma №10 sifarişi", "Order a certificate, transcript, Form No. 10"))
                    }.appear(1)
                    NavigationLink { TuitionView() } label: {
                        NavRow(icon: "creditcard.fill", color: C.pink, title: t("Təhsil haqqı", "Tuition"),
                               subtitle: t("Borc, ödənişlər, tarixçə", "Debt, payments, history"))
                    }.appear(2)
                    NavigationLink { TurnstileView() } label: {
                        NavRow(icon: "door.left.hand.open", color: C.teal, title: t("Turniket", "Gate log"),
                               subtitle: t("Universitetə giriş-çıxış və statistika", "Entries, exits and statistics"))
                    }.appear(3)
                    NavigationLink { DocsView() } label: {
                        NavRow(icon: "folder.fill", color: C.purple, title: t("Sənədlər", "Documents"),
                               subtitle: t("Universitetin qaydaları, əsasnamələr, formalar", "University rules, regulations, forms"))
                    }.appear(4)
                    Link(destination: URL(string: "https://mail.google.com/a/std.beu.edu.az")!) {
                        NavRow(icon: "envelope.fill", color: C.rose, title: t("BMU Mail", "BMU Mail"),
                               subtitle: t("Universitet e-poçtunu aç", "Open your university e-mail"))
                    }.appear(5)
                    Link(destination: URL(string: "https://my.beu.edu.az")!) {
                        NavRow(icon: "safari.fill", color: C.navy, title: "my.beu.edu.az",
                               subtitle: t("Portalı brauzerdə aç", "Open the portal in the browser"))
                    }.appear(6)
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(t("Xidmətlər", "Services"))
        }
    }
}

// MARK: - Təhsil haqqı

struct TuitionView: View {
    @State private var key = 0

    var body: some View {
        ScrollView {
            AsyncContent(key: key, load: { try await Api.tuition() }) { data in
                VStack(alignment: .leading, spacing: 12) {
                    if let last = data.rows.last {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(t("Qalan məbləğ", "Remaining")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(last.remaining.isEmpty ? "0" : last.remaining).font(.system(size: 40, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText())
                            HStack(spacing: 10) {
                                Pill(text: last.year, icon: "calendar")
                                if !last.status.isEmpty { Pill(text: last.status, icon: "info.circle") }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .glassCard(cornerRadius: 26, tint: C.pink.opacity(0.14))
                        .appear(0)
                    }
                    ForEach(Array(data.rows.reversed().enumerated()), id: \.element.id) { i, r in
                        GlassSection(title: "\(r.year) · \(r.semester)", icon: "calendar") {
                            InfoRow(label: t("Təhsil haqqı", "Fee"), value: r.fee)
                            if !r.extra.isEmpty && r.extra != "0" { InfoRow(label: t("Əlavə", "Extra"), value: r.extra) }
                            InfoRow(label: t("Borc", "Debt"), value: r.debt)
                            InfoRow(label: t("Ümumi borc", "Total debt"), value: r.totalDebt)
                            InfoRow(label: t("Ödənilib", "Paid"), value: r.paid)
                            InfoRow(label: t("Qalıb", "Remaining"), value: r.remaining)
                            InfoRow(label: t("Status", "Status"), value: r.status)
                            InfoRow(label: t("Təhsil növü", "Study type"), value: r.kind)
                        }
                        .appear(i + 1)
                        .scrollFx()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Təhsil haqqı", "Tuition"))
        .refreshable { Haptic.soft(); key += 1 }
    }
}

// MARK: - Turniket

private struct GateStats {
    var days = 0
    var totalMin = 0
    var avgArrival: Int?
    var earliest: Int?
    var latest: Int?
    var byWeekday = [Int](repeating: 0, count: 7)   // dəqiqə, 0 = B.e.

    init(_ gates: [Gate]) {
        func time(_ s: String) -> Int? {
            guard let m = s.groups(#"(\d{1,2}):(\d{2})"#), let h = Int(m[1]), let mi = Int(m[2]) else { return nil }
            return h * 60 + mi
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        var arrivals: [Int] = []
        var daySet = Set<String>()
        for g in gates {
            guard let inT = time(g.inTime) else { continue }
            daySet.insert(g.date)
            arrivals.append(inT)
            guard let outT = time(g.outTime), outT > inT else { continue }
            totalMin += outT - inT
            for f in ["dd/MM/yyyy", "dd.MM.yyyy", "yyyy-MM-dd"] {
                df.dateFormat = f
                if let d = df.date(from: g.date.trimmed) { byWeekday[Day.weekdayIndex(d)] += outT - inT; break }
            }
        }
        days = daySet.count
        if !arrivals.isEmpty {
            avgArrival = arrivals.reduce(0, +) / arrivals.count
            earliest = arrivals.min()
            latest = arrivals.max()
        }
    }

    static func hm(_ m: Int?) -> String {
        guard let m else { return "—" }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

struct TurnstileView: View {
    @State private var range = 0
    @State private var key = 0

    private var ranges: [(String, Date, Date)] {
        let today = Day.startOfToday()
        let c = Day.cal
        let monthStart = c.date(from: c.dateComponents([.year, .month], from: today)) ?? today
        let prevStart = c.date(byAdding: .month, value: -1, to: monthStart) ?? today
        return [
            (t("Son 7 gün", "Last 7 days"), Day.add(-6, to: today), today),
            (t("Bu ay", "This month"), monthStart, today),
            (t("Keçən ay", "Last month"), prevStart, Day.add(-1, to: monthStart)),
            (t("Son 30 gün", "Last 30 days"), Day.add(-29, to: today), today)
        ]
    }

    var body: some View {
        let r = ranges[range]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $range) {
                    ForEach(0..<ranges.count, id: \.self) { i in Text(ranges[i].0).tag(i) }
                }
                .pickerStyle(.segmented)
                .onChange(of: range) { _, _ in Haptic.select() }

                AsyncContent(key: key * 10 + range, load: { try await Api.turnstile(from: r.1, to: r.2) }) { data in
                    content(data.gates, total: data.total)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Turniket", "Gate log"))
        .refreshable { Haptic.soft(); key += 1 }
    }

    @ViewBuilder
    private func content(_ gates: [Gate], total: String) -> some View {
        let st = GateStats(gates)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                stat(t("Gün", "Days"), "\(st.days)", "calendar")
                stat(t("Universitetdə", "On campus"), durationText(st.totalMin), "building.columns")
                stat(t("Orta gəliş", "Avg arrival"), GateStats.hm(st.avgArrival), "clock")
            }
            .appear(0)
            if st.totalMin > 0 {
                GlassSection(title: t("Həftənin günləri", "By weekday"), icon: "chart.bar.xaxis") {
                    let mx = max(st.byWeekday.max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(C.teal.gradient)
                                    .frame(height: max(4, CGFloat(st.byWeekday[i]) / CGFloat(mx) * 90))
                                Text(Day.weekdays[i]).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 112, alignment: .bottom)
                    Text(t("ən erkən \(GateStats.hm(st.earliest)) · ən gec \(GateStats.hm(st.latest))",
                           "earliest \(GateStats.hm(st.earliest)) · latest \(GateStats.hm(st.latest))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .appear(1)
            }
            if gates.isEmpty {
                EmptyCard(icon: "door.left.hand.closed", text: t("Bu aralıqda giriş qeydi yoxdur", "No entries in this period"))
            }
            ForEach(Array(gates.reversed().enumerated()), id: \.element.id) { i, g in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.date).font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(g.day).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(g.inTime, systemImage: "arrow.down.right.circle.fill").foregroundStyle(C.green)
                    Label(g.outTime, systemImage: "arrow.up.right.circle.fill").foregroundStyle(C.orange)
                }
                .font(.caption.monospacedDigit())
                .padding(14)
                .glassCard(cornerRadius: 18)
                .appear(i + 2)
                .scrollFx()
            }
            if !total.isEmpty { Text(total).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(C.teal)
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 18)
    }
}

// MARK: - Sənədlər

struct DocsView: View {
    var parent = "0"
    var title: String? = nil
    @State private var key = 0

    var body: some View {
        ScrollView {
            AsyncContent(key: key, load: { try await Api.docCategories(parent: parent) }) { cats in
                VStack(spacing: 10) {
                    if cats.isEmpty { EmptyCard(icon: "folder", text: t("Bu bölmədə sənəd yoxdur", "No documents here")) }
                    ForEach(Array(cats.enumerated()), id: \.element.id) { i, c in
                        if let sub = c.subId {
                            NavigationLink { DocsView(parent: sub, title: c.name) } label: {
                                NavRow(icon: "folder.fill", color: C.purple, title: c.name)
                            }
                            .buttonStyle(PressStyle()).appear(i)
                        } else if let cat = c.docsCat {
                            NavigationLink { DocListView(cat: cat, parent: c.parent, title: c.name) } label: {
                                NavRow(icon: "doc.on.doc.fill", color: C.indigo, title: c.name)
                            }
                            .buttonStyle(PressStyle()).appear(i)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(title ?? t("Sənədlər", "Documents"))
        .refreshable { key += 1 }
    }
}

struct DocListView: View {
    let cat: String
    let parent: String
    let title: String
    @State private var key = 0
    @State private var preview: URL?
    @State private var opening: UUID?
    @State private var error = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !error.isEmpty { ErrorCard(text: error) { error = "" } }
                AsyncContent(key: key, load: { try await Api.docs(cat: cat, parent: parent) }) { list in
                    VStack(spacing: 10) {
                        if list.items.isEmpty { EmptyCard(icon: "doc", text: t("Sənəd yoxdur", "No documents")) }
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { i, d in
                            VStack(alignment: .leading, spacing: 8) {
                                let name = d.cells.filter { !$0.isEmpty && Int($0) == nil }.max(by: { $0.count < $1.count }) ?? ""
                                Text(name).font(.subheadline.weight(.semibold))
                                let others = d.cells.filter { !$0.isEmpty && $0 != name && Int($0) == nil }
                                if !others.isEmpty { Text(others.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                HStack {
                                    ForEach(d.links) { l in
                                        Button {
                                            openDoc(l)
                                        } label: {
                                            HStack(spacing: 6) {
                                                if opening == l.id { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.doc.fill") }
                                                Text(l.title).lineLimit(1)
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                        .glassButton()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCard(cornerRadius: 20)
                            .appear(i)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { key += 1 }
        .quickLookPreview($preview)
    }

    private func openDoc(_ l: DocLink) {
        guard opening == nil else { return }
        Haptic.tap()
        opening = l.id
        Task {
            defer { opening = nil }
            do {
                let f = try await Api.file(l.target)
                if f.isHtml {
                    let full = l.target.hasPrefix("http") ? l.target : Portal.base + Api.libPath(l.target)
                    if let u = URL(string: full) { openURL(u) }
                    return
                }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docs", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(f.name.replacingOccurrences(of: "/", with: "_"))
                try f.data.write(to: url, options: .atomic)
                preview = url
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Onlayn xidmətlər

private struct Svc: Identifiable {
    let srv: Int
    let name: String, sub: String
    var id: Int { srv }
}

struct OnlineServicesView: View {
    @State private var tab = 0
    @State private var step = 0
    @State private var srv = 16
    @State private var lang = "AZ"
    @State private var refTyp = "16"
    @State private var place = ""
    @State private var busy = false
    @State private var error = ""
    @State private var notice = ""
    @State private var confirm: [KV] = []
    @State private var ordersKey = 0

    private var services: [Svc] {
        [Svc(srv: 16, name: t("Arayış", "Certificate"), sub: t("Tələbə haqqında arayış", "Proof of enrollment")),
         Svc(srv: 13, name: t("Transkript", "Transcript"), sub: t("Qiymət cədvəli", "Official grade report")),
         Svc(srv: 18, name: t("Forma №10", "Form No. 10"), sub: t("Hərbi komissarlıq üçün", "For the military commissariat"))]
    }

    private var params: [(String, String)] {
        switch srv {
        case 16: return [("lc", lang), ("tqdm_palace", place.trimmed), ("ref_typ", refTyp)]
        case 18: return [("lc", "AZ"), ("dm", "myself"), ("email", ""), ("addr", ""), ("amount", "0"), ("tqdm_palace", place.trimmed)]
        default: return [("lc", lang)]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $tab) {
                    Text(t("Sifariş ver", "New order")).tag(0)
                    Text(t("Sifarişlərim", "My orders")).tag(1)
                }
                .pickerStyle(.segmented)

                if !notice.isEmpty {
                    Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(C.green)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 18, tint: C.green.opacity(0.15))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if tab == 0 { orderFlow.transition(.opacity) } else { orders.transition(.opacity) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: tab)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: notice)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Onlayn xidmətlər", "Online services"))
        .refreshable { ordersKey += 1 }
    }

    @ViewBuilder
    private var orderFlow: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Hansı sənəd lazımdır?", "Which document do you need?")).font(.title3.weight(.bold))
                ForEach(services) { s in
                    Button {
                        Haptic.select(); srv = s.srv
                    } label: {
                        HStack(spacing: 14) {
                            IconBox(icon: "doc.text.fill", color: srv == s.srv ? C.btn : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                Text(s.sub).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: srv == s.srv ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(srv == s.srv ? C.indigo : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 20, tint: srv == s.srv ? C.indigo.opacity(0.12) : nil)
                    }
                    .buttonStyle(PressStyle())
                }
                Button { Haptic.tap(); error = ""; notice = ""; step = 1 } label: {
                    Text(t("Davam et", "Continue")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Text(services.first { $0.srv == srv }?.name ?? "").font(.title3.weight(.bold))
                if srv != 18 {
                    Picker(t("Dil", "Language"), selection: $lang) {
                        Text(t("Azərbaycanca", "Azerbaijani")).tag("AZ")
                        Text(t("İngiliscə", "English")).tag("EN")
                    }
                    .pickerStyle(.segmented)
                }
                if srv == 16 {
                    Picker(t("Növ", "Type"), selection: $refTyp) {
                        Text(t("Oxuduğuma dair", "Enrollment")).tag("16")
                        Text(t("Məzun arayışı", "Graduate")).tag("17")
                    }
                    .pickerStyle(.segmented)
                }
                if srv != 13 {
                    TextField(t("Təqdim ediləcək yer", "Where it will be submitted"), text: $place)
                        .padding(14).glassCard(cornerRadius: 16)
                    Text(srv == 18 ? t("Tədris Hissəsindən özün götürəcəksən · ödəniş 0 AZN", "Pick up in person at Academic Affairs · 0 AZN")
                                   : t("Yazdığın məlumat arayışda əks olunacaq — diqqətli yaz.", "What you write will appear on the certificate — check it."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(C.rose) }
                Button { next() } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(t("Davam et", "Continue")).font(.headline)
                    }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn).disabled(busy)
                Button(t("Geri", "Back")) { step = 0; error = "" }.glassButton()
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Məlumatlar doğrudurmu?", "Is everything correct?")).font(.title3.weight(.bold))
                GlassSection(title: services.first { $0.srv == srv }?.name ?? "", icon: "doc.text") {
                    if confirm.isEmpty { InfoRow(label: t("Dil", "Language"), value: lang) }
                    ForEach(confirm) { InfoRow(label: $0.key, value: $0.value) }
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(C.rose) }
                Button { send() } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(t("Təsdiqlə və göndər", "Confirm and send")).font(.headline)
                    }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn).disabled(busy)
                Button(t("Geri", "Back")) { step = 1; error = "" }.glassButton()
            }
        }
    }

    private var orders: some View {
        AsyncContent(key: ordersKey, load: { try await Api.onlineOrders() }) { list in
            VStack(spacing: 10) {
                if list.isEmpty { EmptyCard(icon: "tray", text: t("Sifariş yoxdur", "No orders")) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, o in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(o.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(o.status).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4).glassCapsule()
                        }
                        Text([o.date, o.place, o.lang].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        if !o.note.isEmpty { Text(o.note).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 20)
                    .appear(i)
                }
            }
        }
    }

    private func next() {
        let minLen = srv == 16 ? 6 : 5
        if srv != 13 && place.trimmed.count < minLen {
            error = t("Təqdim ediləcək yeri yazın (ən azı \(minLen) simvol)", "Enter where it will be submitted (at least \(minLen) characters)")
            Haptic.error()
            return
        }
        busy = true; error = ""
        Task {
            do {
                let html = try await Portal.shared.onlStep(srv: srv, action: "ContinueOrder", params)
                confirm = Parsers.onlineConfirm(html)
                step = 2
                Haptic.tap()
            } catch { self.error = error.localizedDescription; Haptic.error() }
            busy = false
        }
    }

    private func send() {
        busy = true; error = ""
        Task {
            do {
                _ = try await Portal.shared.onlStep(srv: srv, action: "ConfirmOrder", params)
                notice = t("Sifarişin göndərildi. Vəziyyətini \"Sifarişlərim\"-də izlə.", "Order sent. Track it under \"My orders\".")
                step = 0; place = ""; ordersKey += 1
                Haptic.success()
            } catch { self.error = error.localizedDescription; Haptic.error() }
            busy = false
        }
    }
}
