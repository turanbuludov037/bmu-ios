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
                    Text(lesson.type).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isNow {
                Text("İndi").font(.caption.weight(.bold)).foregroundStyle(C.onLime)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(C.lime))
            } else {
                Image(systemName: lesson.symbol).font(.body.weight(.semibold)).foregroundStyle(color)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22, tint: isNow ? C.lime.opacity(0.35) : nil)
    }
}

/// Boş vəziyyət / məlumat kartı.
struct EmptyCard: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(C.indigo)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
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
            Button("Yenidən cəhd et", action: retry).glassButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22, tint: C.rose.opacity(0.12))
    }
}

/// Yükləmə göstəricisi (kartın içində).
struct LoadingCard: View {
    var text = "Yüklənir…"

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

/// Bal zolağı: dəyər / maksimum, istəyə görə hədd xətti (məs. giriş balı 34).
struct ScoreBar: View {
    let value: Double
    let max: Double
    var mark: Double? = nil
    var color: Color = C.indigo

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let f = Swift.min(Swift.max(value / max, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: Swift.max(w * f, 6))
                if let mark {
                    Rectangle().fill(Color.primary.opacity(0.45))
                        .frame(width: 2, height: 12)
                        .offset(x: w * Swift.min(mark / max, 1) - 1)
                }
            }
        }
        .frame(height: 8)
    }
}

/// Hərf qiyməti nişanı (A … F).
struct LetterBadge: View {
    let letter: String

    private var color: Color {
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
            .background(Circle().fill(color.gradient))
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
                    onPick(s.value)
                } label: {
                    if s.value == selected { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                Text(semesters.first { $0.value == selected }?.label ?? "Semestr seç").lineLimit(1)
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

/// Profil şəkli və ya baş hərflər.
struct Avatar: View {
    let image: UIImage?
    let initials: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image {
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

/// Loqo: şüşə dairə içində papaq.
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

/// Etiket + dəyər sətri (profil və detallar üçün).
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
