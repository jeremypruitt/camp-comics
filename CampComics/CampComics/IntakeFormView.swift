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
                ClassPickerRow(name: "Druid", subtitle: "Listening before acting", isSelected: classKey == "druid") {
                    classKey = "druid"
                }
                Text("More classes land in a later slice — only Druid is wired up for now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
