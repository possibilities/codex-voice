import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Voice")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Hold Control-M anywhere on macOS to dictate into the focused app.")
                .foregroundStyle(.secondary)

            Text("The app will ask for Microphone and Accessibility permissions the first time you use it.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
