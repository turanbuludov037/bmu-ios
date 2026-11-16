import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Prefs
    @State private var number = ""
    @State private var password = ""
    @State private var remember = true
    @State private var showPassword = false
    @State private var busy = false
    @State private var error = ""
    @FocusState private var focus: Field?

    private enum Field { case number, password }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 50)
                    LogoBadge(size: 92)
                    VStack(spacing: 6) {
                        Text("myBEU").font(.largeTitle.weight(.bold))
                        Text(t("my.beu.edu.az hesabınla daxil ol", "Sign in with your my.beu.edu.az account")).font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.text.rectangle").foregroundStyle(C.indigo).frame(width: 22)
                            TextField(t("Tələbə nömrəsi", "Student number"), text: $number)
                                .keyboardType(.numberPad)
                                .textContentType(.username)
                                .focused($focus, equals: .number)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        .glassCard(cornerRadius: 18)

                        HStack(spacing: 12) {
                            Image(systemName: "lock").foregroundStyle(C.indigo).frame(width: 22)
                            Group {
                                if showPassword {
                                    TextField(t("Şifrə", "Password"), text: $password)
                                } else {
                                    SecureField(t("Şifrə", "Password"), text: $password)
                                }
                            }
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 15)
                        .glassCard(cornerRadius: 18)

                        Toggle(isOn: $remember) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Məni xatırla", "Remember me")).font(.subheadline.weight(.semibold))
                                Text(t("Növbəti dəfə avtomatik daxil olur", "Signs you in automatically next time")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(C.indigo)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .glassCard(cornerRadius: 18)
                    }

                    if !error.isEmpty || !app.restoreError.isEmpty {
                        Label(error.isEmpty ? app.restoreError : error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(C.rose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? t("Daxil olunur…", "Signing in…") : t("Daxil ol", "Sign in")).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .glassButton(prominent: true)
                    .tint(C.btn)
                    .disabled(busy)

                    Label(t("Şifrən yalnız universitetin saytına göndərilir və yalnız bu iPhone-da saxlanır.", "Your password is sent only to the university site and stored only on this iPhone."), systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    HStack(spacing: 16) {
                        Link(t("Parolu unutmusan?", "Forgot password?"), destination: URL(string: "https://my.beu.edu.az/passwForgot")!)
                        Text("·").foregroundStyle(.secondary)
                        Button(prefs.lang == "az" ? "English" : "Azərbaycanca") {
                            Haptic.select()
                            prefs.lang = prefs.lang == "az" ? "en" : "az"
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { if number.isEmpty { number = app.savedNumber } }
    }

    private func submit() {
        guard !busy else { return }
        focus = nil
        error = ""
        busy = true
        let n = number.trimmed, p = password
        Task {
            do {
                try await app.login(n, p, remember: remember)
                AppLock.shared.locked = false          // indicə özü daxil oldu — kilid soruşulmasın
                Haptic.success()
                if remember { _ = await Notifier.requestPermission() }
            } catch {
                self.error = error.localizedDescription
                Haptic.error()
            }
            busy = false
        }
    }
}
