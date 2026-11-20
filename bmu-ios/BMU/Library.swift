import SwiftUI

struct LibraryView: View {
    @State private var tab = 0          // 0 axtarış · 1 sifarişlərim · 2 növbə · 3 kartım

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(0, t("Axtarış", "Search"), "magnifyingglass")
                        chip(1, t("Sifarişlərim", "My orders"), "bag")
                        chip(2, t("Növbə", "Queue"), "person.3.sequence")
                        chip(3, t("Kartım", "My card"), "person.text.rectangle")
                    }
                    .padding(.vertical, 2)
                }
                Group {
                    switch tab {
                    case 0: LibSearch()
                    case 1: LibRowsView(type: 4)
                    case 2: LibRowsView(type: 5)
                    default: LibRowsView(type: 6)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .id(tab)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(t("Kitabxana", "Library"))
        .track("library")
    }

    private func chip(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button {
            Haptic.select()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { tab = i }
        } label: {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tab == i ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background { if tab == i { Capsule().fill(C.orange.gradient) } }
                .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}

private struct LibSearch: View {
    @State private var type = 1
    @State private var advanced = false
    @State private var title = ""
    @State private var authors = ""
    @State private var publisher = ""
    @State private var isbn = ""
    @State private var year = ""
    @State private var busy = false
    @State private var error = ""
    @State private var result: (items: [LibBook], total: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $type) {
                Text(t("Kitab", "Books")).tag(1)
                Text(t("Jurnal", "Journals")).tag(2)
                Text(t("Elektron", "E-books")).tag(3)
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, v in if v != 1 { advanced = false }; result = nil }

            field("magnifyingglass", t("Kitabın adı", "Title"), $title)
            if type == 1 {
                Toggle(t("Ətraflı axtarış", "Advanced search"), isOn: $advanced.animation(.spring(response: 0.4, dampingFraction: 0.85)))
                    .tint(C.orange).font(.subheadline.weight(.medium)).padding(.horizontal, 4)
            }
            if advanced {
                field("person", t("Müəllif", "Author"), $authors)
                field("building.2", t("Nəşriyyat", "Publisher"), $publisher)
                field("barcode", "ISBN", $isbn)
                field("calendar", t("Nəşr ili", "Year"), $year)
            }
            Button { search() } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(t("Axtar", "Search")).font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .glassButton(prominent: true).tint(C.orange).disabled(busy)

            if !error.isEmpty { ErrorCard(text: error) { search() } }
            if let r = result {
                Text(t("\(r.total) nəticə tapıldı", "\(r.total) results")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(Array(r.items.enumerated()), id: \.element.id) { i, b in
                    NavigationLink { LibDetailView(book: b) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            IconBox(icon: type == 2 ? "newspaper.fill" : type == 3 ? "ipad" : "book.closed.fill", color: C.orange, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(3)
                                Text([b.author, b.publisher, b.year].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .glassCard(cornerRadius: 20)
                    }
                    .buttonStyle(PressStyle())
                    .appear(i)
                    .scrollFx()
                }
            }
        }
    }

    private func field(_ icon: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(C.orange).frame(width: 20)
            TextField(placeholder, text: text).submitLabel(.search).onSubmit(search)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .glassCard(cornerRadius: 16)
    }

    private func search() {
        guard !busy else { return }
        var fields: [(String, String)] = [("title", title)]
        if advanced {
            fields += [("authors", authors), ("publisher", publisher), ("isbn", isbn), ("pub_year", year), ("dewey", "")]
        }
        if fields.allSatisfy({ $0.1.trimmed.isEmpty }) { error = t("Axtarış üçün nəsə yazın", "Type something to search"); return }
        busy = true; error = ""
        Haptic.tap()
        Task {
            do {
                let r = try await Api.libSearch(type: type, fields: fields, advanced: advanced)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { result = r }
                Haptic.success()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

struct LibDetailView: View {
    let book: LibBook
    @State private var key = 0
    @State private var confirmInv: LibInv?
    @State private var note = ""
    @State private var ordering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    IconBox(icon: "book.closed.fill", color: C.orange, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.title3.weight(.bold))
                        Text([book.author, book.year].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 24, tint: C.orange.opacity(0.12))
                .appear(0)

                if !note.isEmpty {
                    Label(note, systemImage: "info.circle.fill").font(.subheadline)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 18, tint: C.indigo.opacity(0.12))
                }

                AsyncContent(key: key, load: { try await Api.libDetail(book.href) }) { d in
                    VStack(alignment: .leading, spacing: 12) {
                        if !d.fields.isEmpty {
                            GlassSection(title: t("Məlumat", "Details"), icon: "info.circle") {
                                ForEach(d.fields) { InfoRow(label: $0.key, value: $0.value) }
                            }
                        }
                        if !d.queueNote.isEmpty { Text(d.queueNote).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
                        GlassSection(title: t("Nüsxələr", "Copies"), icon: "square.stack.3d.up") {
                            if d.inventory.isEmpty { Text(t("Nüsxə məlumatı yoxdur", "No copy information")).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(d.inventory) { inv in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("№ \(inv.number)").font(.subheadline.weight(.semibold).monospacedDigit())
                                        Text([inv.status, inv.place, inv.returnDate].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if inv.orderForm != nil {
                                        Button(t("Sifariş", "Order")) { Haptic.tap(); confirmInv = inv }
                                            .confirmationDialog(t("Sifariş verilsin?", "Place an order?"),
                                                                isPresented: Binding(get: { confirmInv?.id == inv.id }, set: { if !$0 { confirmInv = nil } }),
                                                                titleVisibility: .visible) {
                                                Button(t("Sifariş ver", "Order")) { order() }
                                                Button(t("Ləğv et", "Cancel"), role: .cancel) { confirmInv = nil }
                                            } message: {
                                                Text(t("Sifariş 45 dəqiqə ərzində hazırlanır, 24 saat ərzində götürülməlidir.", "It will be ready within 45 minutes and must be picked up within 24 hours."))
                                            }
                                            .glassButton(prominent: true).tint(C.orange)
                                            .disabled(ordering)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(t("Material", "Item"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func order() {
        guard let inv = confirmInv, let form = inv.orderForm else { return }
        confirmInv = nil
        ordering = true
        Task {
            do {
                try await Api.libOrder(book.href, form: form)
                note = t("Sifariş sorğusu göndərildi. Vəziyyətini \"Sifarişlərim\"-də yoxla.", "Order request sent. Check \"My orders\".")
                Haptic.success()
                key += 1
            } catch {
                note = t("Sifariş göndərilmədi: ", "Order was not sent: ") + error.localizedDescription
                Haptic.error()
            }
            ordering = false
        }
    }
}

/// Sifarişlərim / Növbə / Kartım: portal cədvəlini kartlar şəklində göstərir.
private struct LibRowsView: View {
    let type: Int
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if type == 6 {
                Toggle(t("Qaytarılanları da göstər", "Show returned too"), isOn: $showAll).tint(C.orange)
                    .font(.subheadline.weight(.medium)).padding(.horizontal, 4)
            }
            AsyncContent(key: showAll ? 1 : 0, load: { try await Api.libRows(type: type, showAll: showAll) }) { d in
                VStack(spacing: 10) {
                    if d.rows.isEmpty { EmptyCard(icon: "tray", text: d.empty.isEmpty ? t("Qeyd yoxdur", "No records") : d.empty) }
                    ForEach(Array(d.rows.enumerated()), id: \.offset) { i, row in
                        let cells = Array(row.dropFirst()).filter { !$0.isEmpty }
                        let title = cells.max(by: { $0.count < $1.count }) ?? ""
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(3)
                            let rest = cells.filter { $0 != title }
                            if !rest.isEmpty {
                                Text(rest.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(cornerRadius: 18)
                        .appear(i)
                    }
                }
            }
        }
    }
}
