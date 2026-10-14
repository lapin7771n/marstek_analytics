import SwiftUI
import WidgetKit

@main
struct BatteryWidgets: WidgetBundle {
    var body: some Widget {
        RingWidget()
        EtaWidget()
        LockWidget()
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let face: Face
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, face: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let store = Store()
        let face = context.isPreview ? .sample : Face(store.snapshot, floorPct: store.settings.floorPct)
        completion(BatteryEntry(date: .now, face: face))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        Task {
            let snapshot = await SharedRefresh.shared.run { await Refresher.refresh(Store(), maxAge: Refresher.widgetMaxAge) }
            let entry = BatteryEntry(date: .now, face: Face(snapshot, floorPct: Store().settings.floorPct))
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct RingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ring", provider: BatteryProvider()) { entry in
            SmallFace(face: entry.face).containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Charge and power.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct EtaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "eta", provider: BatteryProvider()) { entry in
            MediumFace(face: entry.face).containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("Battery and ETA")
        .description("Charge, power and time until full or empty.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock", provider: BatteryProvider()) { entry in
            LockFace(face: entry.face).containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Charge on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockFace: View {
    @Environment(\.widgetFamily) private var family
    let face: Face

    var body: some View {
        if family == .accessoryCircular {
            CircularFace(face: face)
        } else {
            RectangularFace(face: face)
        }
    }
}
