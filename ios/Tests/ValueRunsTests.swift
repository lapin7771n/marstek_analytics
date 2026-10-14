import Testing
@testable import BatteryETA

struct ValueRunsTests {
    @Test func splitsDigitsFromUnits() {
        #expect(valueRuns("6h20") == [Run(text: "6", digits: true), Run(text: "h", digits: false), Run(text: "20", digits: true)])
        #expect(valueRuns("82%") == [Run(text: "82", digits: true), Run(text: "%", digits: false)])
    }

    @Test func aWordIsOneRun() {
        #expect(valueRuns("FULL") == [Run(text: "FULL", digits: false)])
    }
}
