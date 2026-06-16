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
            Section("Subscriptions") {
                LabeledContent("Claude plan, $/mo") {
                    TextField("price", value: $model.claudeMonthlyPriceUSD, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                LabeledContent("ChatGPT / Codex plan, $/mo") {
                    TextField("price", value: $model.codexMonthlyPriceUSD, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }

            Section("Billing") {
                Stepper(value: $model.billingAnchorDay, in: 1...28) {
                    LabeledContent("Billing day of month", value: "\(model.billingAnchorDay)")
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
                if let v = model.updateVersion {
                    LabeledContent("Latest", value: "\(v) available")
                }
                Button(model.isDownloadingUpdate ? "Downloading…" : "Check for Updates…") {
                    model.updateVersion == nil ? model.checkForUpdates() : model.downloadUpdate()
                }
                .disabled(model.isDownloadingUpdate)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 340)
    }
}
