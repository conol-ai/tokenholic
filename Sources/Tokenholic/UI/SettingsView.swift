import SwiftUI

/// Standalone settings window (opened from the menubar popover's gear button).
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                planField("Claude plan", value: $model.claudeMonthlyPriceUSD)
                planField("ChatGPT / Codex plan", value: $model.codexMonthlyPriceUSD)
                planField("Gemini CLI plan", value: $model.geminiMonthlyPriceUSD)
            } header: {
                Text("Subscriptions")
            } footer: {
                Text("Your monthly price per tool, in USD. Set 0 for a tool you don't pay for.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Billing") {
                Stepper(value: $model.billingAnchorDay, in: 1...28) {
                    LabeledContent("Billing cycle resets on day", value: "\(model.billingAnchorDay)")
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                        } catch {
                            launchAtLogin = LoginItem.isEnabled // revert on failure
                        }
                        if newValue, LoginItem.requiresApproval {
                            LoginItem.openSystemSettings()
                        }
                    }
                if model.syncAvailable {
                    Toggle("Menu bar shows all-devices total", isOn: $model.menubarUsesCombined)
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: appVersion)
                if let latest = model.updateVersion {
                    LabeledContent("Latest", value: "\(latest) available")
                }
                Button(updateButtonTitle) {
                    if model.updateVersion == nil { model.checkForUpdates() }
                    else { model.downloadUpdate() }
                }
                .disabled(model.isDownloadingUpdate)
            }

            Section {
                Link(destination: URL(string: "https://google-gemini.github.io/gemini-cli/docs/cli/telemetry.html")!) {
                    Label("Enable Gemini CLI tracking", systemImage: "sparkles")
                }
            } header: {
                Text("About")
            } footer: {
                Text("Gemini CLI is tracked only when its local telemetry is enabled (off by default).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "https://github.com/conol-ai/tokenholic")!) {
                    Label("Star Tokenholic on GitHub", systemImage: "star")
                }
                Link(destination: URL(string: "https://tokenholic.app")!) {
                    Label("tokenholic.app", systemImage: "globe")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 500)
    }

    /// A "$/mo" plan row: label on the left, a right-aligned editable dollar amount.
    private func planField(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Text("$")
                TextField("", value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("/mo").foregroundStyle(.secondary)
            }
        }
    }

    private var updateButtonTitle: String {
        if model.isDownloadingUpdate { return "Downloading…" }
        if let v = model.updateVersion { return "Download \(v)" }
        return "Check for Updates…"
    }
}
