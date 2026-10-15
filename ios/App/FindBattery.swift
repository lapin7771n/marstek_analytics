import SwiftUI

struct FindBatteryRow: View {
    let port: Int
    let use: (String) -> Void
    @State private var finder = BatteryFinder()
    @State private var showing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            finder.start(Discovery.live(port: port))
            showing = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Find battery", systemImage: "magnifyingglass").foregroundStyle(Palette.good)
                Text("Looks for Marstek batteries on this Wi‑Fi. It asks each battery once, only when you tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showing, onDismiss: finder.stop) {
            FindBatterySheet(finder: finder) { host in
                showing = false
                use(host)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { finder.stop() }
        }
    }
}

struct FindBatterySheet: View {
    let finder: BatteryFinder
    let use: (String) -> Void
    @State private var picked: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Batteries on this Wi‑Fi").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(finder.found) { battery in
                    Button { picked = battery.host } label: { row(battery) }.buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
                status.padding(16)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Text("Not listed? Turn on Open API for the battery in the Marstek app, then search again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                finder.stop()
                if let chosen { use(chosen) }
            } label: {
                Text("Use this battery")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x08150F))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Palette.good.opacity(chosen == nil ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(chosen == nil)
        }
        .padding(16)
    }

    private var chosen: String? {
        picked ?? finder.found.first?.host
    }

    private func row(_ battery: FoundBattery) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: battery.model).font(.headline)
                Text(verbatim: battery.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if battery.host == chosen { Image(systemName: "checkmark").foregroundStyle(Palette.good) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var status: some View {
        if finder.searching {
            HStack(spacing: 8) { ProgressView(); Text("Searching…") }
        } else if finder.outcome == .noWifi {
            Text("Join the same Wi‑Fi as the battery, then tap Find battery.")
        } else if finder.outcome == .blocked {
            Text("Allow Local Network for Battery ETA, then tap Find battery again.")
        } else if finder.found.isEmpty && !finder.stopped {
            Text("No battery found.")
        }
    }
}
