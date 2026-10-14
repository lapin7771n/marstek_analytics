import Testing
@testable import BatteryETA

struct FormatTests {
    @Test(arguments: [
        (0.0, "0m"), (3.0 / 60, "3m"), (0.2, "10m"), (1.4244, "1h30"), (8.0427, "8h00"), (21.447, "21h"),
    ])
    func formats(hours: Double, text: String) {
        #expect(formatDuration(hours) == text)
    }
}
