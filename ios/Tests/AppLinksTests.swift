import Foundation
import Testing
@testable import BatteryETA

struct AppLinksTests {
    @Test func linksPointAtTheLivePages() {
        #expect(AppLinks.privacy.absoluteString == "https://lapin7771n.github.io/marstek_analytics/privacy/")
        #expect(AppLinks.support.absoluteString == "https://lapin7771n.github.io/marstek_analytics/support/")
    }
}
