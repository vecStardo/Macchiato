import AppKit
import SwiftUI

struct MenuView: View {
    @Environment(PowerManager.self) private var power

    var body: some View {
        Toggle(
            "Keep Mac Awake",
            isOn: Binding(
                get: { power.isActive },
                set: { isOn in
                    Task {
                        await power.setActive(isOn)
                    }
                }
            )
        )
        .disabled(power.isChanging)

        if power.isChanging {
            Text("Applying...")
        }

        if let lastError = power.lastError {
            Text(lastError)
        }

        Divider()

        Button("Quit Macchiato") {
            Task {
                await power.disable()
                if !power.isActive {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .keyboardShortcut("q")
    }
}
