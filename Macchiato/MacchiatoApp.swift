import SwiftUI

@main
struct MacchiatoApp: App {
    @State private var power = PowerManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(power)
        } label: {
            Image(systemName: power.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.menu)
    }
}
