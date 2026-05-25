import SwiftUI

struct IntakeFormView: View {
    @State private var playerName: String = ""
    @State private var characterName: String = ""
    @State private var classKey: String = "druid"

    let onSubmit: (_ playerName: String, _ characterName: String, _ classKey: String) -> Void

    private var isReady: Bool {
        !playerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Player") {
                TextField("Name", text: $playerName)
                    .textInputAutocapitalization(.words)
                TextField("Character name (optional)", text: $characterName)
                    .textInputAutocapitalization(.words)
            }

            Section("Class") {
                ForEach(ClassChoice.all, id: \.key) { choice in
                    ClassPickerRow(
                        name: choice.name,
                        subtitle: choice.subtitle,
                        isSelected: classKey == choice.key
                    ) {
                        classKey = choice.key
                    }
                }
            }

            Section {
                Button {
                    onSubmit(playerName.trimmingCharacters(in: .whitespaces),
                             characterName.trimmingCharacters(in: .whitespaces),
                             classKey)
                } label: {
                    Text("Start capture")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReady)
            }
        }
        .navigationTitle("New player")
    }
}

private struct ClassChoice {
    let key: String
    let name: String
    let subtitle: String

    static let all: [ClassChoice] = [
        .init(key: "druid",     name: "Druid",     subtitle: "Listening before acting"),
        .init(key: "warrior",   name: "Warrior",   subtitle: "Courage in protecting others"),
        .init(key: "wizard",    name: "Wizard",    subtitle: "Curiosity and the patience to learn"),
        .init(key: "bard",      name: "Bard",      subtitle: "Telling your own story"),
        .init(key: "healer",    name: "Healer",    subtitle: "Empathy as strength"),
        .init(key: "trickster", name: "Trickster", subtitle: "The non-obvious path"),
    ]
}

private struct ClassPickerRow: View {
    let name: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
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
