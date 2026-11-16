import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Prefs
    @State private var confirmLogout = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        let p = app.profile
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink { ProfileDetailsView() } label: {
                        VStack(spacing: 10) {
                            Avatar(image: app.photo, initials: p.initials, size: 96)
                            Text(p.fullName).font(.title2.weight(.bold)).multilineTextAlignment(.center).foregroundStyle(Color.primary)
                            Text("\(p.number) · \(p.group)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Text(t("Bütün məlumatlar", "All details")).font(.caption.weight(.semibold)).foregroundStyle(C.indigo)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .glassCard(cornerRadius: 28, tint: C.indigo.opacity(0.15))
                    }
                    .buttonStyle(PressStyle())
                    .appear(0)

                    SectionHeader(title: t("Hesab", "Account")).appear(1)
                    VStack(spacing: 10) {
                        NavigationLink { PasswordView() } label: {
                            NavRow(icon: "key.fill", color: C.orange, title: t("Parolu dəyiş", "Change password"), subtitle: t("Hesab təhlükəsizliyi", "Account security"))
                        }
                        NavigationLink { EnglishNameView() } label: {
                            NavRow(icon: "character.book.closed.fill", color: C.indigo, title: t("İngilis dilində ad", "Name in English"),
                                   subtitle: t("İngiliscə sənədlər üçün", "For documents in English"))
                        }
                        NavigationLink { ContactsView() } label: {
                            NavRow(icon: "phone.fill", color: C.green, title: t("Əlaqə məlumatlarım", "My contacts"), subtitle: t("Telefon və e-mail", "Phone and e-mail"))
                        }
                        NavigationLink { PhotoView() } label: {
                            NavRow(icon: "person.crop.square.fill", color: C.pink, title: t("Profil şəkli", "Profile photo"),
                                   subtitle: t("Tətbiqdə görünən şəkil", "Photo shown in the app"))
                        }
                    }
                    .buttonStyle(PressStyle())
                    .appear(2)

                    SettingsBlock().appear(3)

                    Button(role: .destructive) {
                        Haptic.tap(); confirmLogout = true
                    } label: {
                        Label(t("Çıxış", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .glassButton()
                    .tint(C.rose)
                    .appear(4)

                    Text("myBEU \(version)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(t("Profil", "Profile"))
            .confirmationDialog(t("Hesabdan çıxılsın?", "Sign out?"), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(t("Çıxış", "Sign out"), role: .destructive) { app.logout() }
                Button(t("Ləğv et", "Cancel"), role: .cancel) {}
            } message: {
                Text(t("Saxlanmış nömrə və şifrə bu iPhone-dan silinəcək.", "The saved number and password will be removed from this iPhone."))
            }
        }
    }
}

// MARK: - Tənzimləmələr

private struct SettingsBlock: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Prefs
    @State private var notifAllowed = true
    @State private var status = Updates.statusText()
    @State private var checking = false

    var body: some View {
        VStack(spacing: 14) {
            SectionHeader(title: t("Görünüş", "Appearance"))
            GlassSection(title: t("Tema", "Theme"), icon: "paintpalette.fill") {
                Picker("", selection: $prefs.theme) {
                    Label(t("Sistem", "System"), systemImage: "iphone").tag("system")
                    Label(t("İşıqlı", "Light"), systemImage: "sun.max.fill").tag("light")
                    Label(t("Qaranlıq", "Dark"), systemImage: "moon.fill").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.theme) { _, _ in Haptic.select() }
                Divider().padding(.vertical, 4)
                HStack {
                    Label(t("Dil", "Language"), systemImage: "globe").font(.subheadline)
                    Spacer()
                    Picker("", selection: $prefs.lang) {
                        Text("Azərbaycanca").tag("az")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.menu)
                }
                Toggle(isOn: $prefs.haptics) {
                    Label(t("Toxunuş titrəməsi", "Haptic feedback"), systemImage: "hand.tap.fill").font(.subheadline)
                }
                .tint(C.indigo)
            }

            SectionHeader(title: t("Bildirişlər", "Notifications"))
            GlassSection(title: t("Xəbərdarlıqlar", "Alerts"), icon: "bell.badge.fill") {
                if !notifAllowed {
                    Button {
                        Task { notifAllowed = await Notifier.requestPermission(); app.rescheduleReminders() }
                    } label: {
                        Label(t("Bildirişlərə icazə ver", "Allow notifications"), systemImage: "bell.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: true).tint(C.btn)
                }
                Toggle(isOn: $prefs.reminders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Dərs xatırlatması", "Class reminders")).font(.subheadline)
                        Text(t("Dərsdən əvvəl bildiriş", "A notification before each class")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(C.indigo)
                .onChange(of: prefs.reminders) { _, on in
                    Haptic.select()
                    Task {
                        let allowed = await Notifier.authorized()
                        if on && !allowed { notifAllowed = await Notifier.requestPermission() }
                        app.rescheduleReminders()
                    }
                }
                if prefs.reminders {
                    Stepper(value: $prefs.remindBefore, in: 5...60, step: 5) {
                        Text(t("\(prefs.remindBefore) dəqiqə əvvəl", "\(prefs.remindBefore) minutes before")).font(.subheadline)
                            .contentTransition(.numericText())
                    }
                    .onChange(of: prefs.remindBefore) { _, _ in Haptic.select(); app.rescheduleReminders() }
                }
                Divider().padding(.vertical, 4)
                Toggle(isOn: $prefs.updates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Qiymət və qaib bildirişi", "Grade & absence alerts")).font(.subheadline)
                        Text(t("Dəyişiklik olanda arxa planda xəbər verir", "Notifies you in the background when something changes"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(C.indigo)
                .onChange(of: prefs.updates) { _, on in
                    Haptic.select()
                    if on {
                        Task {
                            let allowed = await Notifier.authorized()
                            if !allowed { notifAllowed = await Notifier.requestPermission() }
                        }
                    }
                }
                if prefs.updates {
                    Text(status).font(.caption).foregroundStyle(.secondary).contentTransition(.opacity)
                    Button {
                        checking = true
                        Task {
                            await Updates.check()
                            status = Updates.statusText()
                            checking = false
                            Haptic.success()
                        }
                    } label: {
                        HStack {
                            if checking { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                            Text(checking ? t("Yoxlanır…", "Checking…") : t("İndi yoxla", "Check now"))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .glassButton()
                    .disabled(checking)
                }
            }

            SectionHeader(title: t("Təhlükəsizlik", "Security"))
            GlassSection(title: t("Tətbiq kilidi", "App lock"), icon: "lock.shield.fill") {
                Toggle(isOn: Binding(get: { prefs.lock }, set: { on in setLock(on) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("\(AppLock.biometryName) ilə kilid", "Lock with \(AppLock.biometryName)")).font(.subheadline)
                        Text(t("Tətbiq açılanda üzünü / parolu soruşur", "Asks for Face ID / passcode when opening"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(C.indigo)
                .disabled(!AppLock.available)
                if prefs.lock {
                    Picker(t("Arxa fondan qayıdanda", "After leaving the app"), selection: $prefs.lockAfter) {
                        Text(t("Dərhal", "Immediately")).tag(0)
                        Text(t("1 dəqiqə", "1 minute")).tag(60)
                        Text(t("5 dəqiqə", "5 minutes")).tag(300)
                        Text(t("15 dəqiqə", "15 minutes")).tag(900)
                    }
                    .font(.subheadline)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: prefs.reminders)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: prefs.updates)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: prefs.lock)
        .task {
            notifAllowed = await Notifier.authorized()
            status = Updates.statusText()
        }
    }

    private func setLock(_ on: Bool) {
        if !on { prefs.lock = false; Haptic.select(); return }
        Task {
            if await AppLock.shared.confirmEnable() { prefs.lock = true; Haptic.success() } else { Haptic.error() }
        }
    }
}

// MARK: - Bütün profil məlumatları

struct ProfileDetailsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        let p = app.profile
        ScrollView {
            VStack(spacing: 14) {
                Avatar(image: app.photo, initials: p.initials, size: 110).appear(0)
                GlassSection(title: t("Təhsil", "Study"), icon: "graduationcap.fill") {
                    InfoRow(label: t("Tələbə nömrəsi", "Student number"), value: p.number)
                    InfoRow(label: t("İxtisas", "Programme"), value: p.programLang.isEmpty ? p.program : "\(p.program) (\(p.programLang))")
                    InfoRow(label: t("Kurs", "Year"), value: p.course)
                    InfoRow(label: t("Qrup", "Group"), value: p.group)
                    InfoRow(label: t("Akademik məsləhətçi", "Academic advisor"), value: p.advisor)
                    InfoRow(label: t("Status", "Status"), value: p.status)
                    InfoRow(label: t("Qəbul balı", "Admission score"), value: p.score)
                }
                .appear(1)
                GlassSection(title: t("Ödəniş", "Payments"), icon: "creditcard.fill") {
                    InfoRow(label: t("Təhsil haqqı borcu", "Tuition debt"), value: p.tuitionDebt)
                    if !p.advance.isEmpty { InfoRow(label: t("Avans", "Advance"), value: p.advance) }
                    InfoRow(label: t("İllik təhsil haqqı", "Annual fee"), value: p.annualFee)
                    InfoRow(label: t("Ödəniş forması", "Payment type"), value: p.payForm)
                    InfoRow(label: t("Yataqxana borcu", "Dormitory debt"), value: p.dormDebt)
                }
                .appear(2)
                GlassSection(title: t("Şəxsi", "Personal"), icon: "person.fill") {
                    InfoRow(label: t("Doğum tarixi", "Date of birth"), value: p.birth)
                    InfoRow(label: "BMU Mail", value: p.email)
                    InfoRow(label: t("Qeydiyyat tarixi", "Registered"), value: p.regDate)
                }
                .appear(3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(p.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Parolu dəyiş

struct PasswordView: View {
    @EnvironmentObject private var app: AppState
    @State private var old = ""
    @State private var new = ""
    @State private var again = ""
    @State private var busy = false
    @State private var message = ""
    @State private var ok = false

    private var rules: [(String, Bool)] {
        [(t("Ən azı 8 simvol", "At least 8 characters"), new.count >= 8),
         (t("Ən azı 1 rəqəm", "At least 1 digit"), new.rangeOfCharacter(from: .decimalDigits) != nil),
         (t("Yalnız hərf, rəqəm və !@#$%^&*", "Only letters, digits and !@#$%^&*"), new.range(of: #"^[a-zA-Z0-9!@#$%^&*]+$"#, options: .regularExpression) != nil),
         (t("Təkrar eynidir", "Passwords match"), !again.isEmpty && new == again)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                IconBox(icon: "key.fill", color: C.orange, size: 64).appear(0)
                VStack(spacing: 10) {
                    secure(t("Hazırkı parol", "Current password"), $old)
                    secure(t("Yeni parol", "New password"), $new)
                    secure(t("Yeni parol (təkrar)", "New password (again)"), $again)
                }
                .appear(1)
                GlassSection(title: t("Tələblər", "Requirements"), icon: "checklist") {
                    ForEach(rules, id: \.0) { r in
                        Label(r.0, systemImage: r.1 ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(r.1 ? C.green : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: new)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: again)
                .appear(2)
                if !message.isEmpty {
                    Label(message, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(ok ? C.green : C.rose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(cornerRadius: 18, tint: (ok ? C.green : C.rose).opacity(0.12))
                        .transition(.scale.combined(with: .opacity))
                }
                Button { submit() } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? t("Gözləyin…", "Please wait…") : t("Parolu dəyiş", "Change password")).font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn).disabled(busy)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: message)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(t("Parolu dəyiş", "Change password"))
        .track("password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func secure(_ title: String, _ text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textContentType(.password)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .glassCard(cornerRadius: 16)
    }

    private func submit() {
        ok = false
        if old.isEmpty { message = t("Hazırkı parolu daxil edin", "Enter your current password"); Haptic.error(); return }
        if !Api.passwordValid(new) { message = t("Yeni parol tələblərə uyğun deyil", "The new password doesn't meet the requirements"); Haptic.error(); return }
        if new != again { message = t("Parollar eyni deyil", "Passwords don't match"); Haptic.error(); return }
        busy = true; message = ""
        Task {
            do {
                message = try await Api.changePassword(number: app.profile.number, old: old, new: new)
                ok = true
                old = ""; new = ""; again = ""
                Haptic.success()
            } catch {
                message = error.localizedDescription
                Haptic.error()
            }
            busy = false
        }
    }
}

// MARK: - İngilis dilində ad

struct EnglishNameView: View {
    @State private var name = ""
    @State private var surname = ""
    @State private var father = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var message = ""
    @State private var ok = false
    @State private var loadError = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(t("Ad və soyadın ingiliscə sənədlərdə (diplom, arayış) necə yazılacağını göstər.",
                       "Set how your name appears on English documents (diploma, certificates)."))
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if !loaded && loadError.isEmpty { LoadingStack(count: 3, height: 54) }
                if !loadError.isEmpty { ErrorCard(text: loadError) { Task { await load() } } }
                if loaded {
                    field(t("Ad", "Name"), $name).appear(0)
                    field(t("Soyad", "Surname"), $surname).appear(1)
                    field(t("Ata adı", "Father's name"), $father).appear(2)
                    if !message.isEmpty {
                        Label(message, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(ok ? C.green : C.rose)
                    }
                    Button { save() } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(t("Yadda saxla", "Save")).font(.headline)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .glassButton(prominent: true).tint(C.btn).disabled(busy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(t("İngilis dilində ad", "Name in English"))
        .track("engname")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load() } }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .glassCard(cornerRadius: 16)
        }
    }

    private func load() async {
        loadError = ""
        do {
            let r = try await Api.englishName()
            name = r.name; surname = r.surname; father = r.father
            withAnimation { loaded = true }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        if name.trimmed.isEmpty || surname.trimmed.isEmpty || father.trimmed.isEmpty {
            ok = false; message = t("Məlumatları tam daxil edin", "Fill in all fields"); Haptic.error(); return
        }
        busy = true; message = ""
        Task {
            do {
                message = try await Api.saveEnglishName(name: name.trimmed, surname: surname.trimmed, father: father.trimmed)
                ok = true; Haptic.success()
            } catch {
                message = error.localizedDescription; ok = false; Haptic.error()
            }
            busy = false
        }
    }
}

// MARK: - Əlaqə məlumatları (yalnız bu cihazda)

private struct ContactItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: String
    var value: String
}

struct ContactsView: View {
    @EnvironmentObject private var app: AppState
    @State private var items: [ContactItem] = []
    @State private var adding = false
    @State private var kind = "mobile"
    @State private var value = ""

    private var storeKey: String { "contacts_\(app.profile.number)" }

    private func label(_ k: String) -> String {
        switch k {
        case "email": return "E-mail"
        case "phone_father": return t("Telefon (ata)", "Phone (father)")
        case "phone_mother": return t("Telefon (ana)", "Phone (mother)")
        default: return t("Mobil (şəxsi)", "Mobile (personal)")
        }
    }

    private func icon(_ k: String) -> String { k == "email" ? "envelope.fill" : "phone.fill" }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !app.profile.email.isEmpty {
                    row(icon: "graduationcap.fill", title: "BMU Mail", value: app.profile.email, verified: true).appear(0)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                    row(icon: icon(c.kind), title: label(c.kind), value: c.value, verified: false)
                        .contextMenu {
                            Button(role: .destructive) { remove(c) } label: { Label(t("Sil", "Delete"), systemImage: "trash") }
                        }
                        .appear(i + 1)
                }
                if adding {
                    VStack(spacing: 10) {
                        Picker("", selection: $kind) {
                            Text(t("Mobil", "Mobile")).tag("mobile")
                            Text("E-mail").tag("email")
                            Text(t("Ata", "Father")).tag("phone_father")
                            Text(t("Ana", "Mother")).tag("phone_mother")
                        }
                        .pickerStyle(.segmented)
                        TextField(kind == "email" ? "ad@mail.com" : "+994 50 000 00 00", text: $value)
                            .keyboardType(kind == "email" ? .emailAddress : .phonePad)
                            .textInputAutocapitalization(.never)
                            .padding(14).glassCard(cornerRadius: 16)
                        HStack {
                            Button(t("Ləğv et", "Cancel")) { adding = false; value = "" }.glassButton()
                            Spacer()
                            Button(t("Yadda saxla", "Save")) { add() }.glassButton(prominent: true).tint(C.btn)
                                .disabled(value.trimmed.isEmpty)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    Button { Haptic.tap(); adding = true } label: {
                        Label(t("Yenisini əlavə et", "Add new"), systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .glassButton()
                }
                Text(t("Bu məlumatlar yalnız bu iPhone-da saxlanır. Silmək üçün sətrə uzun bas.",
                       "These are stored only on this iPhone. Long-press a row to delete."))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: adding)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: items)
        }
        .background(AppBackground())
        .navigationTitle(t("Əlaqə məlumatlarım", "My contacts"))
        .track("contacts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func row(icon: String, title: String, value: String, verified: Bool) -> some View {
        HStack(spacing: 14) {
            IconBox(icon: icon, color: verified ? C.indigo : C.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).textSelection(.enabled)
            }
            Spacer()
            if verified { Image(systemName: "checkmark.seal.fill").foregroundStyle(C.indigo) }
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: storeKey), let list = try? JSONDecoder().decode([ContactItem].self, from: d) else { return }
        items = list
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: storeKey) }
    }

    private func add() {
        items.append(ContactItem(kind: kind, value: value.trimmed))
        persist()
        value = ""; adding = false
        Haptic.success()
    }

    private func remove(_ c: ContactItem) {
        items.removeAll { $0.id == c.id }
        persist()
        Haptic.tap()
    }
}

// MARK: - Profil şəkli

struct PhotoView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Prefs
    @State private var pick: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Avatar(image: app.photo, initials: app.profile.initials, size: 180)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    .appear(0)
                Text(t("Seçdiyin şəkil yalnız bu tətbiqdə profil şəklin kimi görünür. Portaldakı rəsmi şəkil dəyişmir.",
                       "The photo you choose is shown only in this app. Your official portal photo doesn't change."))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                PhotosPicker(selection: $pick, matching: .images) {
                    Label(t("Şəkil seç", "Choose photo"), systemImage: "photo.on.rectangle.angled")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true).tint(C.btn)
                if prefs.customPhoto != nil {
                    Button(t("Portaldakı şəklə qayıt", "Use the portal photo")) {
                        withAnimation { prefs.customPhoto = nil }
                        Haptic.tap()
                    }
                    .glassButton()
                }
                if let img = app.photo {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview(t("Profil şəkli", "Profile photo"), image: Image(uiImage: img))) {
                        Label(t("Portal şəklini paylaş / saxla", "Share / save the portal photo"), systemImage: "square.and.arrow.up")
                    }
                    .glassButton()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(AppBackground())
        .navigationTitle(t("Profil şəkli", "Profile photo"))
        .track("photo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                let side: CGFloat = 512
                let scale = min(1, side / max(img.size.width, img.size.height))
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { prefs.customPhoto = small.jpegData(compressionQuality: 0.85) }
                Haptic.success()
            }
        }
    }
}
