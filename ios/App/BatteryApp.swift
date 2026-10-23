import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            HomeScreen()
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

struct HomeScreen: View {
    private let store = Store()
    @State private var settings = Store().settings
    @State private var snapshot = Store().snapshot
    @State private var history = Store().history
    @State private var day = Store().history.day(now: .now, latest: Store().snapshot?.reading)
    @State private var week = Store().history.week(now: .now)
    @State private var range = HomeRange.today
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
    @State private var showSettings = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        MediumFace(face: Face(snapshot, floorPct: settings.floorPct))
                            .frame(height: 158)
                            .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
                            .onTapGesture { if Face(snapshot, floorPct: settings.floorPct).blocked { openSettings() } }
                        if settings.problem != nil {
                            Button { showSettings = true } label: {
                                Text("Set up the battery")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(hex: 0x08150F))
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Palette.good, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
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
                            OutageRow(outage: outage, stale: face.stale, cut: cut)
                        }
                        Text("Uses the current load. The answer changes as the load changes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card()

                    TodayCard(day: day, week: week, range: $range)

                    if range == .today, !day.isEmpty {
                        TodayNumbers(day: day)
                            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 18))
                    } else if range == .week, week.contains(where: { $0.chargedWh > 0 || $0.usedWh > 0 }) {
                        TodayNumbers(week: week)
                            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 18))
                    }

                    if face.fixes {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Can't reach the battery").font(.system(size: 17, weight: .bold, design: .rounded))
                            Button(action: openSettings) {
                                HStack {
                                    Hint(code: "ALLOW LAN", text: "Tap to open Settings and turn on Local Network. If it is not there: Privacy & Security › Local Network.")
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hint(code: "NO LINK", text: "Join the battery's Wi‑Fi, and turn on Open API for the battery in the Marstek app.")
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                let enabled = !checking && Refresher.retryAllowed(snapshot, now: timeline.date)
                                Button { Task { await refresh(waiting: true) } } label: {
                                    Text("Try again")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(hex: 0x08150F))
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(Palette.good.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .disabled(!enabled)
                            }
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Battery ETA")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { guide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How to connect")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $guide, onDismiss: { if settings.host.isEmpty { showSettings = true } }) { GuideSheet() }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(
                    settings: $settings, checking: checking, alertOn: alertOn, alertDenied: alertDenied,
                    outageGroup: outageGroup, save: save, setAlert: setAlert, saveGroup: saveGroup
                )
            }
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

    private var cut: Int? {
        guard let r = snapshot?.reading, let powerBack else { return nil }
        return Outage.cut(r, floorPct: settings.floorPct, back: powerBack, now: .now)
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
        week = history.week(now: .now)
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

struct Hint: View {
    let code: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Palette.bad)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

private extension View {
    func card() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 18))
    }
}
