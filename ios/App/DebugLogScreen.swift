import SwiftUI
import UIKit

struct DebugLogScreen: View {
    private let store = Store()
    @State private var log = Store().log
    @State private var copied = false

    var body: some View {
        Form {
            Section("Debug info") {
                ForEach(info, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(row.1).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }

            Section("Recent events") {
                if log.lines.isEmpty {
                    Text("No events yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DebugLog.stamp(line.time)).foregroundStyle(Palette.label)
                        Text(line.text)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    store.log = DebugLog()
                    log = DebugLog()
                }
                Button(copied ? "Copied" : "Copy") { copy() }
                    .fontWeight(.semibold)
            }
        }
        .task {
            while !Task.isCancelled {
                log = store.log
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var info: [(String, String)] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let settings = store.settings
        let snapshot = store.snapshot
        let reading = snapshot?.reading.map { "\(DebugLog.stamp($0.time)) · \($0.socPct) %, \(Int($0.acW.rounded())) W" }
        let state = settings.problem ?? Face(snapshot, floorPct: settings.floorPct).problem ?? String(localized: "No problems")
        return [
            (String(localized: "App"), "\(version) (\(build))"),
            ("iOS", UIDevice.current.systemVersion),
            (String(localized: "Device"), Self.model),
            (String(localized: "Battery IP"), settings.host.isEmpty ? "—" : settings.host),
            (String(localized: "Port"), "\(settings.port)"),
            (String(localized: "Reserve"), "\(settings.floorPct) %"),
            (String(localized: "Last check"), snapshot.map { DebugLog.stamp($0.checkedAt) } ?? "—"),
            (String(localized: "Last reading"), reading ?? "—"),
            (String(localized: "State"), state),
        ]
    }

    private static var model: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(sim) (Simulator)" }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private func copy() {
        UIPasteboard.general.string = store.log.text(info: info)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
