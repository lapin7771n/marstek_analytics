import SwiftUI

struct GuideSheet: View {
    static func showsAtLaunch(_ settings: BatterySettings) -> Bool {
        settings.host.isEmpty
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    step(1, "In the Marstek app, open your battery and tap the gear icon at the top right.", "GuideGear")
                    step(2, "Under Wi‑Fi, write down the IP address.", "GuideIP")
                    step(3, "Scroll down and turn on Local API. Leave the port at 30000.", "GuideLocalAPI")
                    step(4, "Enter the IP here and tap Save and check.")
                    step(5, "When the app asks to find devices on your local network, tap Allow.")
                    Text("This device and the battery must be on the same Wi‑Fi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("How to connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey, _ image: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x08150F))
                .frame(width: 26, height: 26)
                .background(Palette.good, in: Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(text).fixedSize(horizontal: false, vertical: true)
                if let image {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
