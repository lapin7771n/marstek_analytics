import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            SettingsScreen()
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(Palette.good)
        }
        .onChange(of: phase) { _, phase in
            if phase == .background, Store().alert.on { AlertTask.schedule() }
        }
        .backgroundTask(.appRefresh(AlertTask.id)) { await AlertTask.run() }
    }
}

struct SettingsScreen: View {
    private let store = Store()
    @State private var settings = Store().settings
    @State private var snapshot = Store().snapshot
    @State private var history = Store().history
    @State private var day = Store().history.day(now: .now, latest: Store().snapshot?.reading)
    @State private var checking = false
    @State private var alertOn = Store().alert.on
    @State private var alertDenied = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

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
                    FindBatteryRow(port: settings.port) { host in
                        settings.host = host
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

                Section("Now") {
                    MediumFace(face: Face(snapshot, floorPct: settings.floorPct))
                        .frame(height: 158)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .onTapGesture { if Face(snapshot, floorPct: settings.floorPct).blocked { openSettings() } }
                }

                Section {
                    TodayCard(day: day)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Today")
                } footer: {
                    Text("Built from readings the app and widgets already take. Dotted: no reading, the line joins the gap.")
                }

                if !day.isEmpty {
                    Section("Today in numbers") { TodayNumbers(day: day) }
                }

                Section {
                    Toggle("Low-battery alert", isOn: Binding(get: { alertOn }, set: { on in Task { await setAlert(on) } }))
                } header: {
                    Text("Alerts")
                } footer: {
                    Text(alertFooter)
                }

                Section("If it fails") {
                    Button(action: openSettings) {
                        HStack {
                            hint("ALLOW LAN", "Tap to open Settings and turn on Local Network. If it is not there: Privacy & Security › Local Network.")
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    hint("NO LINK", "Join the battery's Wi‑Fi, and turn on Open API for the battery in the Marstek app.")
                    NavigationLink {
                        DebugLogScreen()
                    } label: {
                        hint("LOGS", "Open the app's recent log and debug info to send with a bug report.")
                    }
                }

                Section("About") {
                    link("Support", AppLinks.support)
                    link("Privacy policy", AppLinks.privacy)
                }
            }
            .navigationTitle("Battery ETA")
        }
        // A background alert run wakes the app; the poll must not wake with it.
        .task(id: phase) { if phase == .active { await poll() } }
        .onOpenURL { url in if url == AppLinks.localNetwork { openSettings() } }
    }

    private var saveDisabled: Bool {
        checking || settings.problem != nil
    }

    private var alertFooter: String {
        alertDenied
            ? String(localized: "Notifications are off. Turn them on for Battery ETA in Settings.")
            : String(localized: "Alerts once when the charge reaches the \(LowBattery.percent(settings.floorPct)) reserve, and once when less than 30 min is left. iOS checks about every 15–30 min, so an alert can come late.")
    }

    private func setAlert(_ on: Bool) async {
        alertOn = on
        if on {
            alertOn = await AlertTask.turnOn()
            alertDenied = !alertOn
        } else {
            store.alert = AlertState()
            AlertTask.cancel()
            alertDenied = false
        }
    }

    private func hint(_ code: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Palette.bad)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
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

    private func openSettings() {
        openURL(URL(string: UIApplication.openSettingsURLString)!)
    }

    private func save() async {
        if settings.host != store.settings.host { store.snapshot = nil; store.history = History() }
        store.settings = settings
        store.log("Saved \(settings.host):\(settings.port)")
        await refresh(waiting: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh(waiting: Bool = false) async {
        guard !checking else { return }
        if waiting {
            await BatteryLine.shared.take()
        } else if await !BatteryLine.shared.claim() {
            return
        }
        checking = true
        snapshot = await Refresher.refresh(store)
        history = store.history
        day = history.day(now: .now, latest: snapshot?.reading)
        checking = false
        await BatteryLine.shared.release()
    }

    private func poll() async {
        while !Task.isCancelled {
            if store.settings.problem == nil { await refresh() }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
