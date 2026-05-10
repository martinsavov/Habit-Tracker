import SwiftUI

struct SettingsView: View {
    @AppStorage("colorScheme") private var colorSchemePref: String = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    ThemeOptionRow(
                        label:    "Light",
                        icon:     "sun.max.fill",
                        iconColor: .orange,
                        selected: colorSchemePref == "light"
                    ) { colorSchemePref = "light" }

                    ThemeOptionRow(
                        label:    "Dark",
                        icon:     "moon.fill",
                        iconColor: .blue,
                        selected: colorSchemePref == "dark"
                    ) { colorSchemePref = "dark" }

                    ThemeOptionRow(
                        label:    "System Default",
                        icon:     "circle.lefthalf.filled",
                        iconColor: .secondary,
                        selected: colorSchemePref == "system"
                    ) { colorSchemePref = "system" }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ThemeOptionRow: View {
    let label:     String
    let icon:      String
    let iconColor: Color
    let selected:  Bool
    let onTap:     () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                Text(label)
                    .foregroundStyle(.primary)

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
