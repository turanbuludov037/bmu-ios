import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
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
                    VStack(spacing: 10) {
                        Avatar(image: app.photo, initials: p.initials, size: 96)
                        Text(p.fullName).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        Text(p.number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard(cornerRadius: 28, tint: C.indigo.opacity(0.15))

                    card("Təhsil") {
                        InfoRow(label: "İxtisas", value: p.programLang.isEmpty ? p.program : "\(p.program) (\(p.programLang))")
                        InfoRow(label: "Kurs", value: p.course)
                        InfoRow(label: "Qrup", value: p.group)
                        InfoRow(label: "Akademik məsləhətçi", value: p.advisor)
                        InfoRow(label: "Status", value: p.status)
                        InfoRow(label: "Qəbul balı", value: p.score)
                    }

                    card("Ödəniş") {
                        InfoRow(label: "Təhsil haqqı borcu", value: p.tuitionDebt)
                        if !p.advance.isEmpty { InfoRow(label: "Avans", value: p.advance) }
                        InfoRow(label: "İllik təhsil haqqı", value: p.annualFee)
                        InfoRow(label: "Ödəniş forması", value: p.payForm)
                        InfoRow(label: "Yataqxana borcu", value: p.dormDebt)
                    }

                    card("Şəxsi") {
                        InfoRow(label: "Doğum tarixi", value: p.birth)
                        InfoRow(label: "BMU Mail", value: p.email)
                        InfoRow(label: "Qeydiyyat tarixi", value: p.regDate)
                    }

                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Label("Çıxış", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .glassButton()
                    .tint(C.rose)

                    Text("BMU Mobil \(version)").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Profil")
            .confirmationDialog("Hesabdan çıxılsın?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Çıxış", role: .destructive) { app.logout() }
                Button("Ləğv et", role: .cancel) {}
            } message: {
                Text("Saxlanmış nömrə və şifrə bu iPhone-dan silinəcək.")
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).padding(.bottom, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}
