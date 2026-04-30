import AppKit
import SwiftUI

struct MenuView: View {
    @Environment(PowerManager.self) private var power

    var body: some View {
        VStack(spacing: 14) {
            header
            awakeToggle
            statusArea
            footer
        }
        .padding(16)
        .frame(width: 320)
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
            Task {
                await power.setActive(!power.isActive)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(power.isActive ? Color.brown.opacity(0.18) : Color.secondary.opacity(0.16))

                    Image(systemName: power.isActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(power.isActive ? Color.brown : Color.secondary)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep Awake")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(power.isActive ? "Lid-closed sleep is blocked" : "Click to prevent sleep")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                TogglePill(isOn: power.isActive, isBusy: power.isChanging)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(power.isActive ? Color.brown.opacity(0.22) : Color.white.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(power.isActive ? 0.38 : 0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(power.isChanging)
    }

    @ViewBuilder
    private var statusArea: some View {
        if power.isChanging || power.lastError != nil {
            HStack(spacing: 8) {
                Image(systemName: power.lastError == nil ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(power.lastError ?? "Applying system sleep setting...")
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
        }
    }

    private var needsHelperApproval: Bool {
        power.lastError == "Approve Macchiato Helper in System Settings, then try again."
    }

    private var statusColor: Color {
        power.lastError == nil ? .secondary : .red
    }

    private var footer: some View {
        HStack {
            Text("Menu bar utility")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

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
                .frame(width: 28, height: 28)
                .padding(3)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .overlay {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .frame(width: 56, height: 34)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isOn)
    }
}
