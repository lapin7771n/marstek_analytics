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
    @State private var powerBack = Store().powerBack
    @State private var fromSchedule = Store().powerBackFromSchedule
    @State private var outageGroup = Store().outageGroup
    @State private var schedule = Store().schedule
    @State private var checking = false
    @State private var alertOn = Store().alert.on
    @State private var alertDenied = false
    @State private var reloadAfterCheck = false
    @State private var ticking = false
    @State private var guide = GuideSheet.showsAtLaunch(Store().settings)
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
                    FindBatteryRow(port: settings.port) { battery in
                        settings.host = battery.host
                        settings.gentleHost = battery.resetsUnderLoad ? battery.host : nil
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

                Section("Now") {
                    MediumFace(face: Face(snapshot, floorPct: settings.floorPct))
                        .frame(height: 158)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .onTapGesture { if Face(snapshot, floorPct: settings.floorPct).blocked { openSettings() } }
                }

                Section {
                    NavigationLink {
                        AddressScreen(group: outageGroup, onSave: saveGroup)
                    } label: {
                        LabeledContent("Address", value: outageGroup?.address ?? String(localized: "Not set"))
                    }
                    LabeledContent("Grid returns") {
                        if let back = powerBack, back > .now {
                            HStack(spacing: 6) {
                                Menu {
                                    if Calendar.current.isDateInToday(back) || Outage.moved(back, tomorrow: false, now: .now) != back {
                                        Button("Today") { setPowerBack(Outage.moved(back, tomorrow: false, now: .now)) }
                                    }
                                    Button("Tomorrow") { setPowerBack(Outage.moved(back, tomorrow: true, now: .now)) }
                                    if !fromSchedule {
                                        if offersSchedule { Button("Use YASNO") { useSchedule() } }
                                        Button("Clear", role: .destructive) { setPowerBack(nil) }
                                    }
                                } label: {
                                    Text(Calendar.current.isDateInToday(back) ? "Today" : "Tomorrow")
                                        .padding(.horizontal, 11).frame(height: 34)
                                        .background(Color(hex: 0x2C2C2E), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .foregroundStyle(.white)
                                DatePicker("Time", selection: backTime, displayedComponents: .hourAndMinute).labelsHidden()
                            }
                        } else {
                            Button("Set") { setPowerBack(Calendar.current.nextDate(after: .now.addingTimeInterval(3600), matching: DateComponents(minute: 0), matchingPolicy: .nextTime)) }
                        }
                    }
                    if let outageGroup {
                        ScheduleNote(group: outageGroup, state: schedule, now: .now)
                    }
                    if let outage = face.outage {
                        OutageRow(outage: outage, stale: face.stale)
                    }
                } header: {
                    Text("Power back at")
                } footer: {
                    Text("Uses the current load. The answer changes as the load changes.")
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
            .toolbar {
                Button { guide = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("How to connect")
            }
            .sheet(isPresented: $guide) { GuideSheet() }
        }
        // A background alert run wakes the app; the poll must not wake with it.
        .task(id: phase) { if phase == .active { await poll() } }
        .task(id: phase == .active ? outageGroup?.key : nil) { if phase == .active { await pollSchedule() } }
        .onOpenURL { url in if url == AppLinks.localNetwork { openSettings() } }
    }

    private var face: Face {
        Face(snapshot, floorPct: settings.floorPct, powerBack: powerBack)
    }

    private var backTime: Binding<Date> {
        Binding(get: { powerBack ?? .now }, set: { setPowerBack(Outage.retimed(powerBack, to: $0, now: .now)) })
    }

    private func setPowerBack(_ date: Date?) {
        powerBack = date
        fromSchedule = false
        store.powerBack = date
        store.powerBackFromSchedule = false
        reloadEta()
    }

    private var offersSchedule: Bool {
        guard let days = schedule?.days, schedule?.key == outageGroup?.key else { return false }
        if case .off = Schedule.answer(days, now: .now) { return true }
        return false
    }

    private func saveGroup(_ group: OutageGroup?) {
        outageGroup = group
        store.outageGroup = group
    }

    private func useSchedule() {
        powerBack = nil
        fromSchedule = false
        store.powerBack = nil
        store.powerBackFromSchedule = false
        reloadEta()
        Task { await tickSchedule() }
    }

    private func tickSchedule() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        let changed = await ScheduleFeed.tick(store)
        schedule = store.schedule
        guard changed else { return }
        powerBack = store.powerBack
        fromSchedule = store.powerBackFromSchedule
        reloadEta()
    }

    private func pollSchedule() async {
        while !Task.isCancelled {
            await tickSchedule()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func reloadEta() {
        if !checking, store.settings.problem != nil || Refresher.widgetCanReuse(store.snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: "eta")
        } else {
            reloadAfterCheck = true
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
        checking = true
        defer { checking = false }
        if waiting {
            do { try await BatteryLine.shared.take() } catch { return }
        } else if await !BatteryLine.shared.claim() {
            return
        }
        snapshot = await Refresher.refresh(store)
        history = store.history
        day = history.day(now: .now, latest: snapshot?.reading)
        await BatteryLine.shared.release()
        checking = false
        if reloadAfterCheck {
            reloadAfterCheck = false
            WidgetCenter.shared.reloadTimelines(ofKind: "eta")
        }
    }

    // Due a fixed interval after the last request, so a newly chosen interval applies at once.
    private func poll() async {
        var tried = Date.distantPast
        while !Task.isCancelled {
            let now = Date.now
            let checked = store.snapshot.map(\.checkedAt).flatMap { $0 <= now ? $0 : nil } ?? .distantPast
            let due = max(tried, checked) + TimeInterval(store.settings.pollInterval.components.seconds)
            if now >= due {
                tried = now
                if store.settings.problem == nil { await refresh() }
            } else {
                try? await Task.sleep(for: .seconds(min(due.timeIntervalSince(now), 5)))
            }
        }
    }
}
