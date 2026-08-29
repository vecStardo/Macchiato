import AppKit
import SwiftUI

@MainActor
struct MenuView: View {
    @Environment(PowerManager.self) private var power

    var body: some View {
        VStack(spacing: 14) {
            header
            awakeToggle
            lidOptions
            statusArea
            lowBatteryNotice
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("MacchiatoBase")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Macchiato")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(power.isActive ? "Keeping this Mac awake" : "Normal sleep behavior")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var awakeToggle: some View {
        Button {
            guard !power.isChanging else { return }

            Task {
                await power.setActive(!power.isActive)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(power.isActive ? Color.brown.opacity(0.18) : Color.secondary.opacity(0.16))

                    Image(systemName: power.isActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(power.isActive ? Color.brown : Color.secondary)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep Awake")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text(power.isActive ? "Sleep is blocked" : "Prevent Mac sleep")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 6)

                TogglePill(isOn: power.isActive, isBusy: power.isChanging)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(power.isActive ? Color.brown.opacity(0.22) : Color.white.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(power.isActive ? 0.38 : 0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            .animation(.easeInOut(duration: 0.22), value: power.isActive)
        }
        .buttonStyle(.plain)
    }

    private var lidOptions: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("On lid close")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if power.isActive {
                    Label(power.isLidClosed ? "Lid closed" : "Lid open", systemImage: power.isLidClosed ? "laptopcomputer.and.arrow.down" : "laptopcomputer.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Picker("On lid close", selection: lidModeBinding) {
                ForEach(LidScreenMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.title)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(lidModeCaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
    }

    private var lidModeBinding: Binding<LidScreenMode> {
        Binding(
            get: { power.lidScreenMode },
            set: { power.lidScreenMode = $0 }
        )
    }

    private var lidModeCaption: LocalizedStringKey {
        power.lidScreenMode == .dimBrightness
            ? "Built-in screen dims to black while the lid is closed, restored on open."
            : "Built-in display sleeps while the lid is closed, wakes on open."
    }

    private var lowBatteryNotice: some View {
        Group {
            if power.stoppedDueToLowBattery {
                HStack(spacing: 8) {
                    Image(systemName: "battery.25%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)

                    Text("Battery low — Keep Awake turned off")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var batteryText: String? {
        guard let level = power.batteryLevel else { return nil }
        let key = power.isOnBatteryPower ? "Battery %lld%%" : "Battery %lld%% · Charging"
        return String.localizedStringWithFormat(NSLocalizedString(key, comment: "battery footer"), level)
    }

    private var statusText: LocalizedStringKey {
        if let lastError = power.lastError {
            return LocalizedStringKey(lastError)
        }
        return "Applying system sleep setting..."
    }

    private var statusArea: some View {
        HStack(spacing: 8) {
            Image(systemName: power.lastError == nil ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if needsHelperApproval {
                Button("Open Settings") {
                    power.openHelperApprovalSettings()
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 18)
        .opacity(showsStatus ? 1 : 0)
        .allowsHitTesting(showsStatus)
        .accessibilityHidden(!showsStatus)
    }

    private var showsStatus: Bool {
        power.isChanging || power.lastError != nil
    }

    private var needsHelperApproval: Bool {
        guard let lastError = power.lastError else {
            return false
        }

        return lastError == "Approve Macchiato Helper in System Settings, then try again."
            || lastError.contains("Approve the helper")
    }

    private var statusColor: Color {
        power.lastError == nil ? .secondary : .red
    }

    private var footer: some View {
        HStack {
            if let batteryText {
                Text(batteryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Menu bar utility")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                Task {
                    await power.disable()
                    if !power.isActive {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
    }
}

private struct TogglePill: View {
    let isOn: Bool
    let isBusy: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.brown : Color.secondary.opacity(0.22))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                )

            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .padding(3)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .overlay {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .frame(width: 52, height: 32)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isOn)
    }
}
