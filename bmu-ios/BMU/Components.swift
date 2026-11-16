import SwiftUI

/// Bölmə başlığı: "Bu gün" + kiçik alt yazı.
struct SectionHeader: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// Bir dərs: vaxt, rəngli zolaq, ad, kod və növ.
struct LessonRow: View {
    let lesson: Lesson
    var isToday = false

    private var color: Color {
        switch lesson.type {
        case "Laboratoriya": return C.orange
        case "Məşğələ": return C.green
        default: return C.indigo
        }
    }

    private var isNow: Bool {
        guard isToday else { return false }
        let n = Day.nowMinutes()
        return n >= Day.minutes(lesson.start) && n < Day.minutes(lesson.end)
    }

    private var isPast: Bool { isToday && Day.nowMinutes() >= Day.minutes(lesson.end) }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(lesson.start).font(.headline.monospacedDigit())
                Text(lesson.end).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 54)

            Capsule().fill(color.gradient).frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(lesson.code).font(.caption.weight(.medium))
                    Text("·").font(.caption)
                    Text(lesson.typeLabel).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isNow {
                Text(t("İndi", "Now")).font(.caption.weight(.bold)).foregroundStyle(C.onLime)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(C.lime))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: lesson.symbol).font(.body.weight(.semibold)).foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(14)
        .opacity(isPast ? 0.55 : 1)
        .glassCard(cornerRadius: 22, tint: isNow ? C.lime.opacity(0.35) : nil)
    }
}

/// Boş vəziyyət / məlumat kartı.
struct EmptyCard: View {
    let icon: String
    let text: String
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(C.indigo)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: bounce)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
        .onAppear { bounce += 1 }
    }
}

/// Xəta kartı + "Yenidən" düyməsi.
struct ErrorCard: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(C.rose)
            Button(t("Yenidən cəhd et", "Try again")) { Haptic.tap(); retry() }.glassButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22, tint: C.rose.opacity(0.12))
        .onAppear { Haptic.error() }
    }
}

/// Bal zolağı: dəyər / maksimum, istəyə görə hədd xətti. Açılanda dolaraq gəlir.
struct ScoreBar: View {
    let value: Double
    let max: Double
    var mark: Double? = nil
    var color: Color = C.indigo
    @State private var shown = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let f = Swift.min(Swift.max(value / max, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: shown ? Swift.max(w * f, 6) : 6)
                if let mark {
                    Rectangle().fill(Color.primary.opacity(0.45))
                        .frame(width: 2, height: 12)
                        .offset(x: w * Swift.min(mark / max, 1) - 1)
                }
            }
        }
        .frame(height: 8)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.1)) { shown = true } }
    }
}

/// Dairəvi irəliləyiş halqası.
struct Ring: View {
    let progress: Double
    var color: Color = C.indigo
    var width: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: width)
            Circle().trim(from: 0, to: Swift.min(Swift.max(progress, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: progress)
        }
    }
}

/// Hərf qiyməti nişanı (A … F).
struct LetterBadge: View {
    let letter: String

    static func color(_ letter: String) -> Color {
        switch letter {
        case "A", "B": return C.green
        case "C", "D": return C.indigo
        case "E": return C.orange
        default: return C.rose
        }
    }

    var body: some View {
        Text(letter)
            .font(.title3.weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Circle().fill(LetterBadge.color(letter).gradient))
    }
}

/// Semestr seçimi (şüşə menyu).
struct SemesterMenu: View {
    let semesters: [Semester]
    let selected: String
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(semesters) { s in
                Button {
                    Haptic.select()
                    onPick(s.value)
                } label: {
                    if s.value == selected { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                Text(semesters.first { $0.value == selected }?.label ?? t("Semestr seç", "Choose semester")).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .glassCard(cornerRadius: 20, interactive: true)
    }
}

/// Profil şəkli (öz seçdiyin → portal → baş hərflər).
struct Avatar: View {
    let image: UIImage?
    let initials: String
    var size: CGFloat = 64
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Group {
            if let d = prefs.customPhoto, let custom = UIImage(data: d) {
                Image(uiImage: custom).resizable().scaledToFill()
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(C.onLime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(C.lime)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
    }
}

/// Loqo: tünd dairə içində papaq.
struct LogoBadge: View {
    var size: CGFloat = 84

    var body: some View {
        Image(systemName: "graduationcap.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(C.lime)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: 0x1B2850)))
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color(hex: 0x1B2850).opacity(0.35), radius: 18, y: 8)
    }
}

/// Etiket + dəyər sətri.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

/// Başlıqlı şüşə kart.
struct GlassSection<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).foregroundStyle(C.indigo).symbolRenderingMode(.hierarchical) }
                Text(title).font(.headline)
            }
            .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

/// Rəngli ikon qutusu (menyu sətirləri və plitələr üçün).
struct IconBox: View {
    let icon: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.gradient))
    }
}

/// Menyu sətri: ikon + başlıq + alt yazı + ox. NavigationLink içində istifadə olunur.
struct NavRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String = ""

    var body: some View {
        HStack(spacing: 14) {
            IconBox(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 20)
    }
}

/// Ana səhifədəki kvadrat plitə (sürətli keçid).
struct Tile: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            IconBox(icon: icon, color: color, size: 44)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 20)
    }
}

/// Bir dəfə yükləyib göstərən ümumi qab: yüklənir → parıltı, xəta → "yenidən", uğur → məzmun.
struct AsyncContent<T, Content: View>: View {
    var key: Int = 0
    let load: () async throws -> T
    @ViewBuilder let content: (T) -> Content

    private enum Phase { case loading, failed(String), done(T) }
    @State private var phase: Phase = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading: LoadingStack()
            case .failed(let m): ErrorCard(text: m) { attempt += 1 }
            case .done(let v): content(v)
            }
        }
        .task(id: "\(key)-\(attempt)") {
            if case .done = phase {} else { phase = .loading }
            do {
                let v = try await load()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { phase = .done(v) }
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

/// Konfetti (ad günü).
struct Confetti: View {
    @State private var fall = false
    private let colors: [Color] = [C.lime, C.indigo, C.orange, C.pink, C.teal, C.purple]

    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach(0..<36, id: \.self) { i in
                    piece(i, size: g.size)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }

    private func piece(_ i: Int, size: CGSize) -> some View {
        let x: CGFloat = CGFloat((i * 53) % 100) / 100.0 * size.width
        let startY: CGFloat = -20.0 - CGFloat(i % 6) * 18.0
        let endY: CGFloat = size.height + 30.0
        let angle: Double = fall ? Double(i * 47 % 360) + 360.0 : 0.0
        let duration: Double = 1.6 + Double(i % 5) * 0.25
        let delay: Double = Double(i % 7) * 0.06
        return RoundedRectangle(cornerRadius: 2)
            .fill(colors[i % colors.count])
            .frame(width: 7, height: 11)
            .rotationEffect(.degrees(angle))
            .position(x: x, y: fall ? endY : startY)
            .animation(.easeIn(duration: duration).delay(delay), value: fall)
    }
}
