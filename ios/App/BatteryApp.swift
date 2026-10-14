import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsScreen()
                .preferredColorScheme(.dark)
                .fontDesign(.rounded)
                .tint(Palette.good)
        }
    }
}

struct SettingsScreen: View {
    private let store = Store()
    @State private var settings = Store().settings
    @State private var snapshot = Store().snapshot
    @State private var checking = false
    @Environment(\.openURL) private var openURL

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
                }
            }
            .navigationTitle("Battery ETA")
        }
        .task { await poll() }
        .onOpenURL { url in if url == AppLinks.localNetwork { openSettings() } }
    }

    private var saveDisabled: Bool {
        checking || settings.problem != nil
    }

    private func hint(_ code: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Palette.bad)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func openSettings() {
        openURL(URL(string: UIApplication.openSettingsURLString)!)
    }

    private func save() async {
        if settings.host != store.settings.host { store.snapshot = nil }
        store.settings = settings
        await refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh() async {
        guard !checking else { return }
        checking = true
        snapshot = await Refresher.refresh(store)
        checking = false
    }

    private func poll() async {
        while !Task.isCancelled {
            if store.settings.problem == nil { await refresh() }
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
