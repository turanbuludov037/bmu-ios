import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState
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
                        Text("BMU Mobil").font(.largeTitle.weight(.bold))
                        Text("my.beu.edu.az hesabınla daxil ol").font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.text.rectangle").foregroundStyle(C.indigo).frame(width: 22)
                            TextField("Tələbə nömrəsi", text: $number)
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
                                    TextField("Şifrə", text: $password)
                                } else {
                                    SecureField("Şifrə", text: $password)
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
                                Text("Məni xatırla").font(.subheadline.weight(.semibold))
                                Text("Növbəti dəfə avtomatik daxil olur").font(.caption).foregroundStyle(.secondary)
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
                            Text(busy ? "Daxil olunur…" : "Daxil ol").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .glassButton(prominent: true)
                    .tint(C.btn)
                    .disabled(busy)

                    Label("Şifrən yalnız universitetin saytına göndərilir və yalnız bu iPhone-da saxlanır.", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
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
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
