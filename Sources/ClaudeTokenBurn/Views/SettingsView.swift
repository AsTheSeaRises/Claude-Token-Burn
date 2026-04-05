import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    var onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                pollingSection
                notificationsSection
                displaySection
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") { onDone?() }
                    .keyboardShortcut(.defaultAction)
                    .padding(12)
            }
        }
        .frame(width: 360, height: 380)
    }

    private var pollingSection: some View {
        Section("Polling") {
            HStack {
                Text("Refresh Every")
                Slider(value: $store.settings.pollInterval, in: 30...300, step: 30)
                Text("\(Int(store.settings.pollInterval))s")
                    .frame(width: 36)
                    .monospacedDigit()
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notify when session % used reaches") {
            ForEach(store.settings.notificationThresholds.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Toggle("", isOn: enabledBinding(i)).labelsHidden()
                    TextField("%", value: thresholdBinding(i), format: .number)
                        .frame(width: 50)
                        .multilineTextAlignment(.trailing)
                    Text("% used").foregroundColor(.secondary)
                }
            }
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Toggle("Show Extra Usage", isOn: $store.settings.showExtraUsage)
            Toggle("Launch at Login", isOn: $store.settings.launchAtLogin)
                .onChange(of: store.settings.launchAtLogin) { enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
        }
    }

    private func enabledBinding(_ i: Int) -> Binding<Bool> {
        Binding(
            get: { i < store.settings.enabledThresholds.count ? store.settings.enabledThresholds[i] : false },
            set: { if i < store.settings.enabledThresholds.count { store.settings.enabledThresholds[i] = $0 } }
        )
    }

    private func thresholdBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { i < store.settings.notificationThresholds.count ? store.settings.notificationThresholds[i] : 0 },
            set: { if i < store.settings.notificationThresholds.count { store.settings.notificationThresholds[i] = $0 } }
        )
    }
}
