import SwiftUI

struct IntakeFormView: View {
    @Environment(\.themeKind) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var playerName: String = ""
    @State private var characterName: String = ""
    @State private var classKey: String = "druid"

    let onSubmit: (_ playerName: String, _ characterName: String, _ classKey: String) -> Void

    private var isReady: Bool {
        !playerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let p = theme.palette
        ZStack {
            ThemedBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock
                    nameSection
                    classSection
                    submitSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 140)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(p.accent)
                    .font(theme.bodyFont(15))
            }
        }
        .toolbarBackground(p.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    // MARK: - Title block

    @ViewBuilder
    private var titleBlock: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 6) {
            Text("CHARACTER SHEET")
                .font(theme.captionFont(11))
                .tracking(4)
                .foregroundStyle(p.accent)
            Text("Roll a Character")
                .font(theme.displayFont(36))
                .foregroundStyle(p.inkPrimary)
            Text("Choose a name and a class. The campaign already has a seat at the table.")
                .font(theme.bodyFont(15))
                .italic()
                .foregroundStyle(p.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private var nameSection: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel(text: "IDENTITY")
                ThemedField(title: "Your name", text: $playerName, autocap: true)
                ThemedField(title: "Character name", text: $characterName,
                            placeholder: "(optional — the hero's secret identity)",
                            autocap: true)
            }
        }
    }

    private var classSection: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(text: "CLASS")
                VStack(spacing: 8) {
                    ForEach(ClassChoice.all, id: \.key) { choice in
                        ClassPickerRow(
                            choice: choice,
                            isSelected: classKey == choice.key
                        ) { classKey = choice.key }
                    }
                }
            }
        }
    }

    private var submitSection: some View {
        VStack(spacing: 12) {
            ThemedPrimaryButton("Join the Party", systemImage: "sparkle", isEnabled: isReady) {
                onSubmit(playerName.trimmingCharacters(in: .whitespaces),
                         characterName.trimmingCharacters(in: .whitespaces),
                         classKey)
            }
            if !isReady {
                Text("Roll a name to seat them at the table.")
                    .font(theme.captionFont(12))
                    .foregroundStyle(theme.palette.inkSecondary)
            }
        }
        .padding(.top, 4)
    }

    private func sectionLabel(text: String) -> some View {
        Text(text)
            .font(theme.captionFont(11))
            .tracking(2.5)
            .foregroundStyle(theme.palette.accent)
    }
}

// MARK: - Themed field

private struct ThemedField: View {
    @Environment(\.themeKind) private var theme
    let title: String
    @Binding var text: String
    var placeholder: String? = nil
    var autocap: Bool = false

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(theme.captionFont(12))
                .tracking(1.5)
                .foregroundStyle(p.inkSecondary)
            TextField(placeholder ?? "", text: $text)
                .font(theme.bodyFont(18))
                .foregroundStyle(p.inkPrimary)
                .textInputAutocapitalization(autocap ? .words : .never)
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(p.paper.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(p.accent.opacity(0.7), lineWidth: 0.9)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - Class choices

struct ClassChoice {
    let key: String
    let name: String
    let subtitle: String
    let glyph: String

    static let all: [ClassChoice] = [
        .init(key: "druid",     name: "Druid",     subtitle: "Listening before acting",       glyph: "leaf.fill"),
        .init(key: "warrior",   name: "Warrior",   subtitle: "Courage in protecting others",   glyph: "shield.lefthalf.filled"),
        .init(key: "wizard",    name: "Wizard",    subtitle: "Curiosity and the patience to learn", glyph: "wand.and.stars"),
        .init(key: "bard",      name: "Bard",      subtitle: "Telling your own story",         glyph: "music.note"),
        .init(key: "healer",    name: "Healer",    subtitle: "Empathy as strength",            glyph: "heart.fill"),
        .init(key: "trickster", name: "Trickster", subtitle: "The non-obvious path",           glyph: "die.face.5.fill"),
    ]
}

private struct ClassPickerRow: View {
    @Environment(\.themeKind) private var theme
    let choice: ClassChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if isSelected {
                        RegularPolygon(sides: 6)
                            .fill(LinearGradient(colors: [p.accent, p.accent.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom))
                    } else {
                        RegularPolygon(sides: 6).fill(p.accent.opacity(0.12))
                    }
                    RegularPolygon(sides: 6).stroke(p.accent.opacity(0.5), lineWidth: 0.8)
                    Image(systemName: choice.glyph)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: 0x0E1822) : p.accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name)
                        .font(theme.headingFont(18))
                        .foregroundStyle(p.inkPrimary)
                    Text(choice.subtitle)
                        .font(theme.captionFont(12))
                        .foregroundStyle(p.inkSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? p.accent : p.inkSecondary.opacity(0.5))
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        IntakeFormView(onSubmit: { _, _, _ in })
    }
}
