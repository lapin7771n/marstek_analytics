import SwiftUI
import WidgetKit

@main
struct BatteryWidgets: WidgetBundle {
    var body: some Widget {
        SpikeWidget()
    }
}

struct SpikeEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now, text: "··")
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        Task {
            let host = UserDefaults(suiteName: AppGroup.id)?.string(forKey: "host") ?? ""
            let text: String
            do { text = "\(try await MarstekClient(host: host, port: 30000).reading().socPct)%" } catch { text = "\(error)" }
            completion(Timeline(entries: [SpikeEntry(date: .now, text: text)], policy: .after(.now.addingTimeInterval(900))))
        }
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "spike", provider: SpikeProvider()) { entry in
            Text(entry.text).font(.caption).containerBackground(.black, for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}
