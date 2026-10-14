import SwiftUI
import WidgetKit

@main
struct BatteryApp: App {
    var body: some Scene {
        WindowGroup { SpikeScreen() }
    }
}

struct SpikeScreen: View {
    @AppStorage("host", store: UserDefaults(suiteName: AppGroup.id)) private var host = ""
    @State private var result = ""

    var body: some View {
        Form {
            TextField("Battery IP", text: $host)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Check") {
                Task {
                    do { result = "\(try await MarstekClient(host: host, port: 30000).reading())" } catch { result = "\(error)" }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            Text(result)
        }
    }
}
