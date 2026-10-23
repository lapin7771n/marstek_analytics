import SwiftUI

struct SettingsSheet: View {
    @Binding var settings: BatterySettings
    let checking: Bool
    let alertOn: Bool
    let outageAheadOn: Bool
    let alertDenied: Bool
    let outageGroup: OutageGroup?
    let save: () async -> Void
    let setAlert: (Bool) async -> Void
    let setOutageAhead: (Bool) async -> Void
    let saveGroup: (OutageGroup?) -> Void
    @State private var guide = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.50", text: $settings.host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .monospacedDigit()
                        .accessibilityLabel("Battery IP address")
                    FindBatteryRow(port: settings.port) { battery in
                        settings.host = battery.host
                        settings.retryHost = battery.takesRetry ? battery.host : nil
                        Task { await save() }
                    }
                    LabeledContent("Port") {
                        TextField("30000", value: $settings.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $settings.floorPct, in: 0...50) {
                        Text("Reserve ") + Text("\(settings.floorPct) %").foregroundStyle(.secondary)
                    }
                    Picker("Refresh", selection: $settings.chosenSpeed) {
                        Text("Fast (1 min)").tag(PollSpeed.fast)
                        Text("Medium (5 min)").tag(PollSpeed.medium)
                        Text("Infrequent (15 min)").tag(PollSpeed.infrequent)
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Battery IP")
                } footer: {
                    Text(settings.problem ?? String(localized: "The reserve is the charge the battery keeps back. EMPTY IN counts down to it."))
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(checking ? "Checking…" : "Save and check")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x08150F))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Palette.good.opacity(saveDisabled ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(saveDisabled)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Low-battery alert", isOn: Binding(get: { alertOn }, set: { on in Task { await setAlert(on) } }))
                    Toggle("Outage ahead", isOn: Binding(get: { outageAheadOn }, set: { on in Task { await setOutageAhead(on) } }))
                } header: {
                    Text("Alerts")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alertFooter)
                        if !alertDenied { Text("Warns 30 min before a YASNO outage the battery will not last through.") }
                    }
                }

                Section("Outage schedule") {
                    NavigationLink {
                        AddressScreen(group: outageGroup, onSave: saveGroup)
                    } label: {
                        LabeledContent("Address", value: outageGroup?.address ?? String(localized: "Not set"))
                    }
                }

                Section("Help") {
                    Button { guide = true } label: {
                        HStack {
                            Text("How to connect")
                            Spacer(minLength: 8)
                            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        DebugLogScreen()
                    } label: {
                        Hint(code: "LOGS", text: "Open the app's recent log and debug info to send with a bug report.")
                    }
                }

                Section("About") {
                    link("Support", AppLinks.support)
                    link("Privacy policy", AppLinks.privacy)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
            .sheet(isPresented: $guide) { GuideSheet() }
        }
    }

    private var saveDisabled: Bool {
        checking || settings.problem != nil
    }

    private var alertFooter: String {
        alertDenied
            ? String(localized: "Notifications are off. Turn them on for Battery ETA in Settings.")
            : String(localized: "Alerts once when the charge reaches the \(LowBattery.percent(settings.floorPct)) reserve, and once when less than 30 min is left. iOS checks about every 15–30 min, so an alert can come late.")
    }

    private func link(_ title: LocalizedStringKey, _ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}
